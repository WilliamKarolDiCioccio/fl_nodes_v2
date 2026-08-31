part of 'node_editor_controller.dart';

/// A detached piece of a graph: nodes, the wires and frames between them, and
/// where it was taken from.
///
/// Node positions are stored relative to the fragment's own top-left, which is
/// what makes a fragment portable between documents. [origin] remembers the
/// scene position it was cut from, so a keyboard paste can land beside the
/// original instead of at the world origin.
@immutable
class GraphFragment {
  const GraphFragment({required this.graph, required this.origin});

  /// The copied nodes, their internal connections and any group entirely
  /// inside the selection, positioned relative to the fragment's top-left
  /// corner.
  final NodeGraph graph;

  /// Where the fragment's top-left sat in the document it came from.
  final Offset origin;

  bool get isEmpty => graph.nodes.isEmpty;
  bool get isNotEmpty => !isEmpty;
}

/// Copy, cut, paste and duplicate over the selection.
///
/// The buffer is in-process, so copy and paste are synchronous and a duplicate
/// never has to wait on a platform channel. When the controller was given a
/// [NodeGraphCodec], every copy is *also* written to the system clipboard as
/// JSON, which is what carries a selection between two editors or across a
/// restart. Without a codec the package never touches `flutter/services`.
class NodeEditorClipboard {
  NodeEditorClipboard(this._controller, {NodeGraphCodec? codec})
    : _codec = codec;

  /// How far each successive paste is offset from the last.
  static const Offset pasteNudge = Offset(32, 32);

  /// Marks a document on the system clipboard as one of ours.
  static const String fragmentKey = 'clipboard';

  /// Where [GraphFragment.origin] is carried in a document's metadata.
  static const String originKey = 'origin';

  final NodeEditorController _controller;
  final NodeGraphCodec? _codec;

  GraphFragment? _buffer;
  int _pasteCount = 0;

  /// What was last copied, or null if nothing has been.
  GraphFragment? get buffer => _buffer;

  bool get canPaste => _buffer?.isNotEmpty ?? false;

  /// Whether copies also reach the system clipboard.
  bool get mirrorsToSystem => _codec != null;

  /// Copies the selected nodes and the wires between them.
  ///
  /// Returns false — and leaves any existing buffer alone — when no node is
  /// selected. A selected *connection* is not a copy on its own: a wire with
  /// nothing on either end is not something that can be pasted anywhere.
  bool copy() {
    final fragment = _fragmentOf(_controller.selection.nodeIdsWithGroups);
    if (fragment == null) return false;
    _buffer = fragment;
    _pasteCount = 0;
    _writeSystem(fragment);
    return true;
  }

  /// Copies the selection and then deletes it, as a single undo step.
  bool cut() {
    if (!copy()) return false;
    _controller.selection.deleteSelected();
    return true;
  }

  /// Pastes the buffer and selects the result.
  ///
  /// Returns the ids of the nodes that actually landed. A prototype resolves
  /// the pasted nodes on the way in and is free to prune one, so this is the
  /// honest answer rather than the ids that were attempted.
  ///
  /// With no [scenePosition] each paste steps further from the original, so
  /// holding Ctrl+V cascades instead of stacking copies on one spot.
  Set<String> paste({Offset? scenePosition}) {
    final fragment = _buffer;
    if (fragment == null || fragment.isEmpty) return const <String>{};
    return _paste(fragment, scenePosition: scenePosition, step: ++_pasteCount);
  }

  /// Copies the selection straight back into the document, without disturbing
  /// the buffer or the system clipboard.
  Set<String> duplicate({Offset offset = pasteNudge}) {
    final fragment = _fragmentOf(_controller.selection.nodeIdsWithGroups);
    if (fragment == null) return const <String>{};
    return _paste(fragment, scenePosition: fragment.origin + offset);
  }

  /// Pastes whatever the system clipboard holds.
  ///
  /// Text that is not one of our documents — another app's, or no JSON at all
  /// — falls back to the in-process buffer when [fallbackToBuffer] is set, so
  /// a host can bind this to Ctrl+V and get sensible behaviour whether or not
  /// a codec was configured. A document that *is* ours but cannot be read
  /// throws [GraphDocumentException] rather than being silently ignored.
  Future<Set<String>> pasteFromSystem({
    Offset? scenePosition,
    bool fallbackToBuffer = true,
  }) async {
    final fragment = await _readSystem();
    if (fragment == null) {
      return fallbackToBuffer
          ? paste(scenePosition: scenePosition)
          : const <String>{};
    }
    _buffer = fragment;
    _pasteCount = 0;
    return _paste(fragment, scenePosition: scenePosition, step: ++_pasteCount);
  }

  /// Empties the buffer. The system clipboard is left alone.
  void clear() {
    _buffer = null;
    _pasteCount = 0;
  }

  // ---------------------------------------------------------------- copying

  /// Builds a fragment from [ids], or null when none of them exist.
  GraphFragment? _fragmentOf(Set<String> ids) {
    final graph = _controller._graph;
    final nodes = <GraphNode>[
      for (final id in ids)
        if (graph.nodes[id] case final GraphNode node) node,
    ];
    if (nodes.isEmpty) return null;

    final origin = _topLeftOf(nodes);
    return GraphFragment(
      graph: NodeGraph(
        nodes: <GraphNode>[
          for (final node in nodes)
            node.copyWith(position: node.position - origin),
        ],
        // Only wires with both ends in the selection come along. A connection
        // to a node that was left behind is not part of what was copied, and
        // reattaching it on paste would silently rewire the document.
        connections: <NodeConnection>[
          for (final connection in graph.connections.values)
            if (ids.contains(connection.from.nodeId) &&
                ids.contains(connection.to.nodeId))
              connection,
        ],
        // And only frames whose every member came along. Copying half a group
        // and pasting it would frame a set the user never drew a box around.
        groups: <NodeGroup>[
          for (final group in graph.groups.values)
            if (group.nodeIds.every(ids.contains)) group,
        ],
      ),
      origin: origin,
    );
  }

  static Offset _topLeftOf(Iterable<GraphNode> nodes) {
    var left = double.infinity;
    var top = double.infinity;
    for (final node in nodes) {
      left = math.min(left, node.position.dx);
      top = math.min(top, node.position.dy);
    }
    return Offset(left, top);
  }

  // --------------------------------------------------------------- pasting

  Set<String> _paste(
    GraphFragment fragment, {
    Offset? scenePosition,
    int step = 1,
  }) {
    final base =
        scenePosition ?? fragment.origin + pasteNudge * step.toDouble();

    // Fresh ids for everything. Port ids are node-local, so they ride along
    // unchanged and the remapped endpoints still find them.
    final ids = <String, String>{
      for (final id in fragment.graph.nodes.keys)
        id: _controller.nextId('node'),
    };

    var next = _controller._graph.putNodes(<GraphNode>[
      for (final node in fragment.graph.nodes.values)
        node.copyWith(id: ids[node.id], position: base + node.position),
    ]);
    for (final group in fragment.graph.groups.values) {
      next = next.putGroup(
        group.copyWith(
          id: _controller.nextId('group'),
          nodeIds: <String>{for (final id in group.nodeIds) ids[id]!},
        ),
      );
    }
    for (final connection in fragment.graph.connections.values) {
      next = next.putConnection(
        connection.copyWith(
          id: _controller.nextId('connection'),
          from: PortRef(ids[connection.from.nodeId]!, connection.from.portId),
          to: PortRef(ids[connection.to.nodeId]!, connection.to.portId),
        ),
      );
    }

    final pasted = ids.values.toList(growable: false);
    // One mutation, so one undo step — and one resolution pass, which is what
    // gives a pasted node its prototype-owned ports back. A family derived
    // from link state resolves against the wires that came along, so a node
    // copied without them legitimately arrives smaller than it left.
    _controller._mutate(next, touchedNodes: pasted, resolve: pasted);

    final survivors = <String>{
      for (final id in pasted)
        if (_controller._graph.nodes.containsKey(id)) id,
    };
    _controller.selection.selectNodes(survivors);
    return survivors;
  }

  // ------------------------------------------------------- system clipboard

  void _writeSystem(GraphFragment fragment) {
    final codec = _codec;
    if (codec == null) return;
    final json = codec.encode(
      GraphDocument(
        graph: fragment.graph,
        meta: <String, Object?>{
          fragmentKey: true,
          originKey: <double>[fragment.origin.dx, fragment.origin.dy],
        },
      ),
    );
    // Deliberately not awaited: a copy is not allowed to make the caller
    // asynchronous, and a platform channel that refuses the write leaves the
    // in-process buffer — the one paste actually reads — perfectly good.
    Clipboard.setData(ClipboardData(text: jsonEncode(json))).ignore();
  }

  Future<GraphFragment?> _readSystem() async {
    final codec = _codec;
    if (codec == null) return null;

    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    if (text == null || text.isEmpty) return null;

    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      return null;
    }
    // Anything without a version is somebody else's text, not a document of
    // ours that happens to be broken — and the difference decides whether the
    // caller sees an exception or a quiet fallback.
    if (decoded is! Map) return null;
    final json = Map<String, Object?>.from(decoded);
    if (!json.containsKey('version')) return null;

    final document = codec.decode(json);
    if (document.graph.nodes.isEmpty) return null;

    // A fragment of ours is already relative and says where it came from; a
    // whole document saved by the host is neither, so rebase it and take its
    // own top-left as the origin.
    final topLeft = _topLeftOf(document.graph.nodes.values);
    return GraphFragment(
      graph: NodeGraph(
        nodes: <GraphNode>[
          for (final node in document.graph.nodes.values)
            node.copyWith(position: node.position - topLeft),
        ],
        connections: document.graph.connections.values.toList(growable: false),
      ),
      origin: _originIn(document.meta) ?? topLeft,
    );
  }

  static Offset? _originIn(Map<String, Object?> meta) {
    final origin = meta[originKey];
    if (origin is! List || origin.length != 2) return null;
    final dx = origin[0];
    final dy = origin[1];
    if (dx is! num || dy is! num) return null;
    return Offset(dx.toDouble(), dy.toDouble());
  }
}
