import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show EdgeInsets;
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../collections/spatial_hash_grid.dart';
import 'graph_edit.dart';
import '../geometry/node_geometry.dart';
import '../geometry/viewport_transform.dart';
import '../model/graph_node.dart';
import '../model/node_comment.dart';
import '../model/node_connection.dart';
import '../model/node_graph.dart';
import '../model/node_group.dart';
import '../model/node_port.dart';
import '../model/port_ref.dart';
import '../prototype/node_execution.dart';
import '../prototype/node_prototype_registry.dart';
import '../serialization/document_exceptions.dart';
import '../serialization/graph_document.dart';
import '../serialization/node_graph_codec.dart';

part 'camera.dart';
part 'clipboard.dart';
part 'history.dart';
part 'layout.dart';
part 'project.dart';
part 'runner.dart';
part 'selection.dart';

/// Decides whether an output port may be wired to an input port.
typedef ConnectionValidator =
    bool Function(NodeGraph graph, PortRef from, PortRef to);

/// The single source of truth for a [NodeEditor].
///
/// Owns the immutable [graph] and every edit made to it. The rest — the undo
/// [history], the [selection], the [camera] and the sizes and spatial index in
/// [layout] — lives in subsystems that share this library, so they reach the
/// graph directly without any of that machinery becoming public API.
///
/// Widgets never mutate the graph themselves; they call in here, and a new
/// snapshot is swapped in and announced.
class NodeEditorController extends ChangeNotifier {
  NodeEditorController({
    NodeGraph? graph,
    ViewportTransform viewport = ViewportTransform.identity,
    int historyLimit = 50,
    ConnectionValidator? connectionValidator,
    NodePrototypeRegistry? prototypes,
    NodeGraphCodec? codec,
    this.allowSelfConnections = false,
    double spatialCellSize = 512,
  }) : _graph = graph ?? NodeGraph.empty,
       _validator = connectionValidator,
       _prototypes = prototypes ?? NodePrototypeRegistry.empty {
    history = NodeEditorHistory(this, limit: historyLimit);
    selection = NodeEditorSelection(this);
    camera = NodeEditorCamera(this, viewport);
    layout = NodeEditorLayout(this, cellSize: spatialCellSize);
    clipboard = NodeEditorClipboard(this, codec: codec);
    project = NodeEditorProject(this, codec: codec);
    runner = NodeEditorRunner(this);

    // A document arrives holding only what was authored or loaded; its ports
    // are the prototypes' to derive.
    if (_prototypes.isNotEmpty) {
      _graph = _prototypes.resolveAll(_graph).graph;
    }
    layout._reindexAll();
    // The document as constructed is the baseline, so `project.isDirty`
    // answers "has the user changed anything" rather than "was this ever
    // written", which no controller can know.
    project._savedGraph = _graph;
  }

  /// Undo, redo and transactions.
  late final NodeEditorHistory history;

  /// What the user has selected.
  late final NodeEditorSelection selection;

  /// Pan, zoom and framing.
  late final NodeEditorCamera camera;

  /// Node sizes, the spatial index, and picking.
  late final NodeEditorLayout layout;

  /// Copy, cut, paste and duplicate.
  late final NodeEditorClipboard clipboard;

  /// The open document: saving, loading and the dirty flag.
  late final NodeEditorProject project;

  /// Running the graph.
  late final NodeEditorRunner runner;

  /// Whether a node may be wired back to itself.
  final bool allowSelfConnections;

  final ConnectionValidator? _validator;

  NodePrototypeRegistry _prototypes;

  NodeGraph _graph;

  int _idSeed = 0;

  int _revision = 0;

  /// The note the app user is currently typing into, if any. See
  /// [setCommentText].
  String? _commentBeingTyped;

  /// Asked before every edit this controller makes. Returning false abandons
  /// it, leaving the graph exactly as it was.
  ///
  /// **Undo and redo do not pass through here.** They restore a graph the
  /// guard already saw on the way in, so asking again would be asking about a
  /// decision already taken — and a host that refused a delete would then be
  /// unable to redo one it had allowed. A host that must know about *every*
  /// way a node can leave the graph watches [onEdit] and listens for the
  /// jump as well.
  GraphEditGuard? guard;

  /// Told after every edit that landed, with what it touched.
  GraphEditListener? onEdit;

  /// Bumped whenever node geometry or the graph itself changes.
  ///
  /// Consumers that cache derived geometry — the connection path cache, say —
  /// use this as their invalidation key. Camera changes deliberately do not
  /// bump it: scene-space geometry survives panning and zooming.
  int get revision => _revision;

  NodeGraph get graph => _graph;

  /// [ChangeNotifier.notifyListeners] is `@protected`, and a subsystem is not
  /// a subclass however closely it collaborates. This is the door they use.
  void _notify() => notifyListeners();

  // ------------------------------------------------------------ prototypes

  /// The prototypes nodes are normalised against.
  NodePrototypeRegistry get prototypes => _prototypes;

  /// Swaps the registry and re-normalises the whole document.
  ///
  /// Deliberately settable, where [ConnectionValidator] is fixed at
  /// construction: editing a family builder and hot-reloading has to reach the
  /// nodes that already exist, or the shapes on screen quietly stop matching
  /// the rules that produced them.
  set prototypes(NodePrototypeRegistry value) {
    if (identical(_prototypes, value)) return;
    _prototypes = value;
    revalidate();
    // The registry also decides which links may be retitled, and that shows on
    // the canvas, so refresh even when no node's shape changed.
    _revision++;
    notifyListeners();
  }

  /// Re-derives the shape of [ids], or of every node when null.
  ///
  /// Outside the history by default: this repairs the document to match the
  /// prototypes, which is not an edit the user made.
  void revalidate({Iterable<String>? ids, bool recordHistory = false}) {
    if (_prototypes.isEmpty) return;
    final outcome = ids == null
        ? _prototypes.resolveAll(_graph)
        : _prototypes.resolve(_graph, seeds: ids);
    _mutate(
      outcome.graph,
      const GraphEdit(kind: GraphEditKind.replace),
      record: recordHistory,
      touchedNodes: null,
    );
  }

  // ------------------------------------------------------------- mutation

  /// Swaps in [next] and records an undo step unless a transaction is open.
  ///
  /// [touchedNodes] lists the nodes whose geometry changed, so the spatial
  /// index can be patched instead of rebuilt; null means "rebuild it all",
  /// which is what undo, redo and whole-document loads need.
  ///
  /// [resolve] lists the nodes whose *shape* may need re-deriving from their
  /// prototype. The two axes are independent: dragging changes geometry and
  /// nothing else, wiring changes shape and nothing else — which is what keeps
  /// the resolver off the drag path entirely.
  void _mutate(
    NodeGraph next,
    GraphEdit edit, {
    bool record = true,
    Iterable<String>? touchedNodes = const <String>[],
    Iterable<String> resolve = const <String>[],
  }) {
    // Before anything is computed: a refused edit must cost nothing and, more
    // to the point, must not have resolved prototypes against a graph that is
    // then thrown away.
    if (guard?.call(edit) == false) return;
    var settled = next;
    Set<String>? reshaped;
    if (resolve.isNotEmpty && _prototypes.isNotEmpty) {
      final outcome = _prototypes.resolve(next, seeds: resolve);
      settled = outcome.graph;
      if (outcome.changed.isNotEmpty) reshaped = outcome.changed;
    }
    // Compare the settled graph, not the caller's. An edit that contradicts a
    // prototype resolves straight back to the graph we already have, and that
    // has to be a real no-op rather than an undo entry that changes nothing.
    if (settled == _graph) return;
    // Any edit that lands ends the current run of typing, so the next
    // keystroke opens a new undo step rather than folding into one that has
    // had an unrelated change in the middle of it. `setCommentText` re-arms
    // it afterwards, and is the only caller that ever does.
    _commentBeingTyped = null;
    if (record && !history.inTransaction) history._push(_graph);
    _graph = settled;
    _revision++;
    if (touchedNodes == null) {
      layout._reindexAll();
    } else if (reshaped == null) {
      layout._reindexNodes(touchedNodes);
    } else {
      // A resolution that changed a declared height moved the node's bounds,
      // and a stale index breaks nodeAt and nodesIn without saying so.
      layout._reindexNodes(<String>{...touchedNodes, ...reshaped});
    }
    selection._prune();
    notifyListeners();
    onEdit?.call(edit);
  }

  /// Replaces the whole document, e.g. after loading from disk.
  ///
  /// [normalise] re-derives every node's shape from its prototype, which is
  /// what lets a document persist only its field values and get its ports back.
  void replaceGraph(
    NodeGraph graph, {
    bool recordHistory = true,
    bool normalise = true,
  }) {
    _mutate(
      graph,
      GraphEdit(kind: GraphEditKind.replace, nodeIds: graph.nodes.keys.toSet()),
      record: recordHistory,
      touchedNodes: null,
      resolve: normalise
          ? graph.nodes.keys.toList(growable: false)
          : const <String>[],
    );
    if (!recordHistory) history._reset();
  }

  /// Adds [node], deriving its shape if a prototype claims its type.
  ///
  /// Resolution doubles as instantiation: a node added with no ports at all
  /// comes back with the ones its prototype says it should have, so there is
  /// no separate "create from prototype" call to remember.
  void addNode(GraphNode node) => _mutate(
    _graph.putNode(node),
    GraphEdit(kind: GraphEditKind.addNodes, nodeIds: <String>{node.id}),
    touchedNodes: <String>[node.id],
    resolve: <String>[node.id],
  );

  void addNodes(Iterable<GraphNode> nodes) {
    final ids = nodes.map((node) => node.id).toList(growable: false);
    _mutate(
      _graph.putNodes(nodes),
      GraphEdit(kind: GraphEditKind.addNodes, nodeIds: ids.toSet()),
      touchedNodes: ids,
      resolve: ids,
    );
  }

  /// Rewrites a single node through [update]. No-op if the node is gone.
  void updateNode(String id, GraphNode Function(GraphNode node) update) {
    final node = _graph.nodes[id];
    if (node == null) return;
    _mutate(
      _graph.putNode(update(node)),
      GraphEdit(kind: GraphEditKind.updateNodes, nodeIds: <String>{id}),
      touchedNodes: <String>[id],
      resolve: <String>[id],
    );
  }

  void removeNodes(Iterable<String> ids) {
    final doomed = ids.toSet();
    if (doomed.isEmpty) return;
    // Collected before the removal: deleting the node that consumed a variadic
    // exit has to let the node at the other end shrink again.
    final neighbours = <String>{};
    if (_prototypes.isNotEmpty) {
      for (final id in doomed) {
        for (final connection in _graph.connectionsOf(id)) {
          if (!doomed.contains(connection.from.nodeId)) {
            neighbours.add(connection.from.nodeId);
          }
          if (!doomed.contains(connection.to.nodeId)) {
            neighbours.add(connection.to.nodeId);
          }
        }
      }
    }
    layout._forgetMeasurements(doomed);
    _mutate(
      _graph.removeNodes(doomed),
      GraphEdit(kind: GraphEditKind.removeNodes, nodeIds: doomed),
      touchedNodes: doomed,
      resolve: neighbours,
    );
  }

  /// Moves nodes to absolute scene positions, snapping when [snap] is set.
  void moveNodes(Map<String, Offset> positions, {double snap = 0}) {
    if (positions.isEmpty) return;
    final updated = <GraphNode>[];
    positions.forEach((id, position) {
      final node = _graph.nodes[id];
      if (node == null || !node.draggable) return;
      final target = snap > 0 ? _snap(position, snap) : position;
      if (node.position != target) updated.add(node.copyWith(position: target));
    });
    _mutate(
      _graph.putNodes(updated),
      GraphEdit(
        kind: GraphEditKind.moveNodes,
        nodeIds: <String>{for (final node in updated) node.id},
      ),
      touchedNodes: updated.map((node) => node.id).toList(growable: false),
    );
  }

  void translateNodes(Iterable<String> ids, Offset delta, {double snap = 0}) {
    moveNodes(<String, Offset>{
      for (final id in ids)
        if (_graph.nodes[id] != null) id: _graph.nodes[id]!.position + delta,
    }, snap: snap);
  }

  static Offset _snap(Offset value, double grid) => Offset(
    (value.dx / grid).roundToDouble() * grid,
    (value.dy / grid).roundToDouble() * grid,
  );

  // ---------------------------------------------------------------- groups

  /// Frames the current selection, or widens the frame already in it.
  ///
  /// This is one command rather than two because it is bound to one keystroke,
  /// and which of the two the user meant is never ambiguous:
  ///
  /// * nodes only, none of them grouped — a new group around them;
  /// * one group plus ungrouped nodes — that group, widened to take them;
  /// * one group alone — nothing to add, so nothing happens.
  ///
  /// Returns the group's id, or null when the selection cannot be framed:
  /// nothing selected, more than one group in it, or a node that belongs to a
  /// group other than the one selected. **Moving a node between groups is
  /// deliberately not offered** — disband the old frame first. Silently
  /// stealing members would make one keystroke rewrite a group the user was
  /// not looking at.
  String? groupSelection() {
    final loose = selection.nodeIds.where(_graph.nodes.containsKey).toSet();
    final targets = selection.groupIds
        .map((id) => _graph.groups[id])
        .nonNulls
        .toList(growable: false);
    if (targets.length > 1) return null;

    final target = targets.isEmpty ? null : targets.single;
    for (final id in loose) {
      final owner = _graph.groupOf(id);
      if (owner != null && owner.id != target?.id) return null;
    }

    if (target == null) {
      if (loose.isEmpty) return null;
      final group = NodeGroup(id: nextId('group'), nodeIds: loose);
      _mutate(
        _graph.putGroup(group),
        GraphEdit(
          kind: GraphEditKind.group,
          nodeIds: loose,
          groupIds: <String>{group.id},
        ),
        touchedNodes: const <String>[],
      );
      selection.selectGroup(group.id);
      return group.id;
    }

    final widened = <String>{...target.nodeIds, ...loose};
    if (widened.length == target.nodeIds.length) return target.id;
    _mutate(
      _graph.putGroup(target.withNodes(widened)),
      GraphEdit(
        kind: GraphEditKind.group,
        nodeIds: widened,
        groupIds: <String>{target.id},
      ),
      touchedNodes: const <String>[],
    );
    selection.selectGroup(target.id);
    return target.id;
  }

  /// Takes the frames away and leaves their nodes where they are.
  ///
  /// The only operation on a group that is not also an operation on its
  /// contents. Deleting a selected frame takes the nodes with it — see
  /// [NodeEditorSelection.deleteSelected].
  void disbandGroups(Iterable<String> ids) => _mutate(
    _graph.removeGroups(ids),
    GraphEdit(kind: GraphEditKind.group, groupIds: ids.toSet()),
    touchedNodes: const <String>[],
  );

  void renameGroup(String id, String name) {
    final group = _graph.groups[id];
    if (group == null) return;
    final trimmed = name.trim();
    final next = trimmed.isEmpty ? NodeGroup.defaultName : trimmed;
    if (group.name == next) return;
    _mutate(
      _graph.putGroup(group.copyWith(name: next)),
      GraphEdit(kind: GraphEditKind.group, groupIds: <String>{id}),
      touchedNodes: const <String>[],
    );
  }

  /// Recolours a frame, or returns it to the neutral grey when null.
  void setGroupColor(String id, Color? color) {
    final group = _graph.groups[id];
    if (group == null || group.color == color) return;
    _mutate(
      _graph.putGroup(group.withColor(color)),
      GraphEdit(kind: GraphEditKind.group, groupIds: <String>{id}),
      touchedNodes: const <String>[],
    );
  }

  // -------------------------------------------------------------- comments

  /// Adds a note at [position] and returns its id.
  ///
  /// Notes are ordinary nodes of a reserved type — see [NodeComment] — so
  /// this is [addNode] with the shape filled in, and everything downstream of
  /// it (undo, the marquee, the clipboard, the document) needs no cases for
  /// them.
  String addComment({
    required Offset position,
    String text = '',
    double width = NodeComment.defaultWidth,
  }) {
    final id = nextId('comment');
    addNode(
      NodeComment.create(id: id, position: position, text: text, width: width),
    );
    return id;
  }

  /// Rewrites a note's text, folding a run of edits into one undo step.
  ///
  /// A keystroke is an edit like any other, and one undo entry per character
  /// makes `Ctrl+Z` useless for anything else. Only the first change of a run
  /// records; the rest overwrite it in place. A run ends at
  /// [endCommentEdit] — which the note calls when it loses focus — or as soon
  /// as any other edit is made, so an undo can never step back past something
  /// that happened while the caret was elsewhere.
  ///
  /// No-op for an id that is not a note's, so a host cannot use this to write
  /// a `text` field onto one of its own nodes.
  void setCommentText(String id, String text) {
    final node = _graph.nodes[id];
    if (node == null || !NodeComment.isComment(node)) return;
    final next = NodeComment.withText(node, text);
    if (identical(next, node)) return;

    final continuing = _commentBeingTyped == id;
    _mutate(
      _graph.putNode(next),
      GraphEdit(kind: GraphEditKind.comment, nodeIds: <String>{id}),
      record: !continuing,
      touchedNodes: <String>[id],
    );
    _commentBeingTyped = id;
  }

  /// Ends the current run of [setCommentText] edits.
  void endCommentEdit() => _commentBeingTyped = null;

  /// Recaptions a connection, or takes its caption off when [label] is null.
  ///
  /// A plain graph edit: it goes through the history like any other, so a
  /// retitled link undoes with `Ctrl+Z`.
  void setConnectionLabel(String id, String? label) {
    final connection = _graph.connections[id];
    if (connection == null) return;
    final trimmed = (label == null || label.isEmpty) ? null : label;
    if (connection.label == trimmed) return;
    _mutate(
      _graph.putConnection(connection.withLabel(trimmed)),
      GraphEdit(
        kind: GraphEditKind.labelConnection,
        nodeIds: <String>{connection.from.nodeId, connection.to.nodeId},
        connectionIds: <String>{id},
      ),
    );
  }

  void removeConnections(Iterable<String> ids) {
    final doomed = ids.toList(growable: false);
    final endpoints = <String>{};
    if (_prototypes.isNotEmpty) {
      for (final id in doomed) {
        final connection = _graph.connection(id);
        if (connection == null) continue;
        endpoints
          ..add(connection.from.nodeId)
          ..add(connection.to.nodeId);
      }
    }
    _mutate(
      _graph.removeConnections(doomed),
      GraphEdit(
        kind: GraphEditKind.disconnect,
        nodeIds: endpoints,
        connectionIds: doomed.toSet(),
      ),
      resolve: endpoints,
    );
  }

  /// Whether [a] and [b] could be wired together, in either drag order.
  bool canConnect(PortRef a, PortRef b) => _normalize(a, b) != null;

  /// Wires two ports together, accepting the drag in either direction.
  ///
  /// Returns the new connection's id, or null when the pair is invalid.
  String? connect(
    PortRef a,
    PortRef b, {
    String? id,
    String? type,
    String? label,
    Color? color,
    Object? data,
  }) {
    final pair = _normalize(a, b);
    if (pair == null) return null;
    final connection = NodeConnection(
      id: id ?? nextId('connection'),
      from: pair.$1,
      to: pair.$2,
      // The originating port decides what kind of link it emits, unless the
      // caller says otherwise.
      type: type ?? _portOf(pair.$1)?.linkType ?? 'default',
      label: label,
      color: color,
      data: data,
    );
    _mutate(
      _graph.putConnection(connection),
      GraphEdit(
        kind: GraphEditKind.connect,
        nodeIds: <String>{pair.$1.nodeId, pair.$2.nodeId},
        connectionIds: <String>{connection.id},
      ),
      resolve: <String>{pair.$1.nodeId, pair.$2.nodeId},
    );
    // Wiring a port can change the shape of the node it belongs to, and a
    // prototype is free to resolve that port away again. Report what actually
    // survived rather than an id the caller would dereference to nothing.
    return _graph.connections.containsKey(connection.id) ? connection.id : null;
  }

  /// Orders a candidate pair as (output, input) and validates it.
  (PortRef, PortRef)? _normalize(PortRef a, PortRef b) {
    final portA = _portOf(a);
    final portB = _portOf(b);
    if (portA == null || portB == null) return null;
    if (portA.direction == portB.direction) return null;

    final (from, to) = portA.isOutput ? (a, b) : (b, a);
    if (!allowSelfConnections && from.nodeId == to.nodeId) return null;

    final validator = _validator ?? defaultConnectionValidator;
    if (!validator(_graph, from, to)) return null;
    return (from, to);
  }

  NodePort? _portOf(PortRef ref) =>
      _graph.nodes[ref.nodeId]?.portById(ref.portId);

  /// Rejects duplicates, respects each port's [NodePort.maxConnections], and
  /// refuses a pair whose [portsCompatible] says they do not belong together.
  static bool defaultConnectionValidator(
    NodeGraph graph,
    PortRef from,
    PortRef to,
  ) {
    for (final existing in graph.connectionsOf(from.nodeId)) {
      if (existing.from == from && existing.to == to) return false;
    }
    final source = graph.nodes[from.nodeId]?.portById(from.portId);
    final target = graph.nodes[to.nodeId]?.portById(to.portId);
    if (source == null || target == null) return false;
    if (!portsCompatible(source, target)) return false;
    return !_isPortFull(graph, from) && !_isPortFull(graph, to);
  }

  /// Whether two ports carry the same thing.
  ///
  /// A control pin and a data pin never join: one decides what runs next, the
  /// other moves a value, and a wire between them means nothing to the runner.
  /// Types match when they are equal or when either side declares none — an
  /// untyped port is a wildcard, which is what keeps a graph written before
  /// types existed entirely legal.
  ///
  /// Exposed because a host that supplies its own [ConnectionValidator]
  /// replaces [defaultConnectionValidator] wholesale, and would otherwise lose
  /// this along with the duplicate and capacity checks.
  static bool portsCompatible(NodePort from, NodePort to) {
    if (from.kind != to.kind) return false;
    if (from.dataType == null || to.dataType == null) return true;
    return from.dataType == to.dataType;
  }

  static bool _isPortFull(NodeGraph graph, PortRef ref) {
    final limit = graph.nodes[ref.nodeId]?.portById(ref.portId)?.maxConnections;
    if (limit == null) return false;
    return graph.connectionsAt(ref).length >= limit;
  }

  /// Generates ids of the form `prefix_0`, `prefix_1`, ... unique within this
  /// controller's lifetime.
  String nextId(String prefix) {
    var candidate = '${prefix}_${_idSeed++}';
    while (_graph.nodes.containsKey(candidate) ||
        _graph.connections.containsKey(candidate)) {
      candidate = '${prefix}_${_idSeed++}';
    }
    return candidate;
  }
}
