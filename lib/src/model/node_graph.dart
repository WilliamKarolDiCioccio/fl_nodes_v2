import 'dart:ui';

import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'graph_node.dart';
import 'node_comment.dart';
import 'node_connection.dart';
import 'node_group.dart';
import 'port_ref.dart';

/// An immutable snapshot of the whole graph.
///
/// Every mutation returns a new [NodeGraph], which is what makes undo/redo a
/// matter of keeping a list of these around. Node maps are copied on write;
/// the node-to-connection index is only rebuilt when the connections actually
/// change, so dragging a node stays cheap even on a dense graph.
@immutable
class NodeGraph {
  factory NodeGraph({
    Iterable<GraphNode> nodes = const <GraphNode>[],
    Iterable<NodeConnection> connections = const <NodeConnection>[],
    Iterable<NodeGroup> groups = const <NodeGroup>[],
  }) {
    final nodeMap = <String, GraphNode>{
      for (final node in nodes) node.id: node,
    };
    return NodeGraph._(
      _seal(nodeMap),
      _seal(<String, NodeConnection>{
        for (final connection in connections) connection.id: connection,
      }),
      // Authored membership is not trusted: a group naming a node the graph
      // does not have would leave a frame stretched around nothing, and every
      // reader of it would have to guard.
      _seal(_prunedGroups(groups, nodeMap.keys.toSet())),
      null,
    );
  }

  const NodeGraph._(
    this.nodes,
    this.connections,
    this.groups,
    this._indexOrNull,
  );

  /// Drops ids no longer present, and the groups that empty out as a result.
  static Map<String, NodeGroup> _prunedGroups(
    Iterable<NodeGroup> groups,
    Set<String> live,
  ) {
    final result = <String, NodeGroup>{};
    for (final group in groups) {
      final kept = <String>{
        for (final id in group.nodeIds)
          if (live.contains(id)) id,
      };
      if (kept.isEmpty) continue;
      result[group.id] = kept.length == group.nodeIds.length
          ? group
          : group.withNodes(kept);
    }
    return result;
  }

  static final NodeGraph empty = NodeGraph();

  final Map<String, GraphNode> nodes;
  final Map<String, NodeConnection> connections;

  /// The frames drawn behind sets of nodes. Every member id is guaranteed to
  /// name a node this graph holds, and no group is empty.
  final Map<String, NodeGroup> groups;

  final Map<String, List<NodeConnection>>? _indexOrNull;

  /// Wraps rather than copies.
  ///
  /// `Map.unmodifiable` duplicates its argument, which meant every edit copied
  /// the node map twice — once to apply the change and once to seal it. The
  /// backing map is private and never handed out, so a view is enough.
  static Map<K, V> _seal<K, V>(Map<K, V> source) =>
      UnmodifiableMapView<K, V>(source);

  Map<String, List<NodeConnection>> get _index {
    final cached = _indexOrNull;
    if (cached != null) return cached;
    return _buildIndex(connections);
  }

  static Map<String, List<NodeConnection>> _buildIndex(
    Map<String, NodeConnection> connections,
  ) {
    final index = <String, List<NodeConnection>>{};
    for (final connection in connections.values) {
      (index[connection.from.nodeId] ??= <NodeConnection>[]).add(connection);
      if (connection.to.nodeId != connection.from.nodeId) {
        (index[connection.to.nodeId] ??= <NodeConnection>[]).add(connection);
      }
    }
    return index;
  }

  GraphNode? node(String id) => nodes[id];

  NodeConnection? connection(String id) => connections[id];

  NodeGroup? group(String id) => groups[id];

  /// The group [nodeId] belongs to, or null. Membership is exclusive, so there
  /// is never more than one.
  NodeGroup? groupOf(String nodeId) {
    for (final group in groups.values) {
      if (group.contains(nodeId)) return group;
    }
    return null;
  }

  /// All connections with an endpoint on [nodeId].
  List<NodeConnection> connectionsOf(String nodeId) =>
      _index[nodeId] ?? const <NodeConnection>[];

  /// All connections landing on a specific port.
  Iterable<NodeConnection> connectionsAt(PortRef port) =>
      connectionsOf(port.nodeId).where((c) => c.touchesPort(port));

  bool get isEmpty => nodes.isEmpty;
  bool get isNotEmpty => nodes.isNotEmpty;

  /// The notes on the canvas, in insertion order.
  Iterable<GraphNode> get comments => nodes.values.where(NodeComment.isComment);

  /// Every node that is not a note — what a host usually means by "the graph".
  ///
  /// [nodes] holds both, because a comment is a node in every way the canvas
  /// cares about. This is the seam for the places that care about the other
  /// way: running the graph, counting it, exporting it.
  Iterable<GraphNode> get contentNodes =>
      nodes.values.where((node) => !NodeComment.isComment(node));

  NodeGraph _withNodes(Map<String, GraphNode> next) =>
      NodeGraph._(_seal(next), connections, groups, _index);

  NodeGraph _withConnections(Map<String, NodeConnection> next) =>
      NodeGraph._(nodes, _seal(next), groups, _buildIndex(next));

  NodeGraph _withGroups(Map<String, NodeGroup> next) =>
      NodeGraph._(nodes, connections, _seal(next), _index);

  /// Adds or replaces [group], taking its members out of any other.
  ///
  /// Exclusivity is enforced here rather than asked of the caller: two frames
  /// claiming one node is a state with no sensible rendering, and the only
  /// honest answer to "which group is this in" would be "it depends".
  NodeGraph putGroup(NodeGroup group) {
    final members = <String>{
      for (final id in group.nodeIds)
        if (nodes.containsKey(id)) id,
    };
    if (members.isEmpty) return removeGroups(<String>[group.id]);

    final next = <String, NodeGroup>{};
    for (final other in groups.values) {
      if (other.id == group.id) continue;
      final kept = other.nodeIds.difference(members);
      if (kept.isEmpty) continue;
      next[other.id] = kept.length == other.nodeIds.length
          ? other
          : other.withNodes(kept);
    }
    next[group.id] = group.withNodes(members);
    return _withGroups(next);
  }

  /// Removes the groups, leaving their members on the canvas.
  NodeGraph removeGroups(Iterable<String> ids) {
    final doomed = ids.toSet();
    if (doomed.isEmpty || !doomed.any(groups.containsKey)) return this;
    return _withGroups(
      Map<String, NodeGroup>.of(groups)
        ..removeWhere((id, _) => doomed.contains(id)),
    );
  }

  /// Adds or replaces [node].
  NodeGraph putNode(GraphNode node) =>
      _withNodes(Map<String, GraphNode>.of(nodes)..[node.id] = node);

  /// Adds or replaces several nodes in one copy.
  NodeGraph putNodes(Iterable<GraphNode> updated) {
    if (updated.isEmpty) return this;
    final next = Map<String, GraphNode>.of(nodes);
    for (final node in updated) {
      next[node.id] = node;
    }
    return _withNodes(next);
  }

  /// Removes [ids] along with every connection attached to them.
  NodeGraph removeNodes(Iterable<String> ids) {
    final doomed = ids.toSet();
    if (doomed.isEmpty) return this;
    final nextNodes = Map<String, GraphNode>.of(nodes)
      ..removeWhere((id, _) => doomed.contains(id));
    final nextConnections = Map<String, NodeConnection>.of(connections)
      ..removeWhere(
        (_, c) =>
            doomed.contains(c.from.nodeId) || doomed.contains(c.to.nodeId),
      );
    return NodeGraph._(
      _seal(nextNodes),
      _seal(nextConnections),
      // A group whose last member just went is a frame around nothing.
      _seal(_prunedGroups(groups.values, nextNodes.keys.toSet())),
      _buildIndex(nextConnections),
    );
  }

  NodeGraph putConnection(NodeConnection connection) => _withConnections(
    Map<String, NodeConnection>.of(connections)..[connection.id] = connection,
  );

  NodeGraph removeConnections(Iterable<String> ids) {
    final doomed = ids.toSet();
    if (doomed.isEmpty) return this;
    return _withConnections(
      Map<String, NodeConnection>.of(connections)
        ..removeWhere((id, _) => doomed.contains(id)),
    );
  }

  /// Bounding box of every node, using [sizeOf] to resolve node extents.
  ///
  /// Group frames are included: they reach [NodeGroup.padding] beyond their
  /// members, so framing the content without them clips the frames.
  ///
  /// Returns null for an empty graph.
  Rect? contentBounds(Size Function(GraphNode node) sizeOf) {
    Rect? bounds;
    final rects = <String, Rect>{};
    for (final node in nodes.values) {
      final rect = node.rect(sizeOf(node));
      rects[node.id] = rect;
      bounds = bounds == null ? rect : bounds.expandToInclude(rect);
    }
    for (final group in groups.values) {
      final frame = groupBounds(group, (id) => rects[id]);
      if (frame != null) bounds = bounds!.expandToInclude(frame);
    }
    return bounds;
  }

  /// The frame [group] draws: its members' bounding box, padded.
  ///
  /// Takes a lookup rather than the rects themselves so the one caller that
  /// has them already does not build a second map, and the ones that do not
  /// can answer from the spatial index.
  static Rect? groupBounds(NodeGroup group, Rect? Function(String id) rectOf) {
    Rect? bounds;
    for (final id in group.nodeIds) {
      final rect = rectOf(id);
      if (rect == null) continue;
      bounds = bounds == null ? rect : bounds.expandToInclude(rect);
    }
    if (bounds == null) return null;
    return Rect.fromLTRB(
      bounds.left - NodeGroup.padding.left,
      bounds.top - NodeGroup.padding.top,
      bounds.right + NodeGroup.padding.right,
      bounds.bottom + NodeGroup.padding.bottom,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NodeGraph &&
          mapEquals(other.nodes, nodes) &&
          mapEquals(other.connections, connections) &&
          mapEquals(other.groups, groups);

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(nodes.values),
    Object.hashAllUnordered(connections.values),
    Object.hashAllUnordered(groups.values),
  );

  @override
  String toString() =>
      'NodeGraph(${nodes.length} nodes, ${connections.length} connections, '
      '${groups.length} groups)';
}
