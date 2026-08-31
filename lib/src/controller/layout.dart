part of 'node_editor_controller.dart';

/// Where things are: node sizes, the spatial index built from them, and every
/// query that answers "what is at this point".
///
/// The index is kept in step with each mutation rather than rebuilt, so a
/// viewport query costs the area asked for rather than the size of the graph.
/// Hover picking runs on every mouse move and is the reason this exists.
class NodeEditorLayout {
  NodeEditorLayout(this._controller, {required double cellSize})
    : _index = SpatialHashGrid(cellSize: cellSize);

  final NodeEditorController _controller;

  final SpatialHashGrid _index;

  /// Content sizes reported by laid-out node widgets, for auto-height nodes.
  /// Deliberately outside the history: it is a measurement, not a document
  /// edit.
  final Map<String, Size> _measuredSizes = <String, Size>{};

  /// The resolved size of [node]: its declared height, the height measured
  /// from its built content, or a fallback on the very first frame.
  Size sizeOf(GraphNode node) {
    final declared = node.height;
    if (declared != null) return Size(node.width, declared);
    final measured = _measuredSizes[node.id];
    return Size(node.width, measured?.height ?? GraphNode.fallbackHeight);
  }

  /// True while an auto-height node has yet to report a measured size.
  ///
  /// Callers that depend on accurate extents — framing the view, exporting an
  /// image — should wait for this to go false rather than trust the fallback.
  bool get hasUnmeasuredNodes => _controller._graph.nodes.values.any(
    (node) => node.hasIntrinsicHeight && !_measuredSizes.containsKey(node.id),
  );

  /// Called by node widgets once their content has been laid out.
  void reportMeasuredSize(String nodeId, Size size) {
    if (_measuredSizes[nodeId] == size) return;
    _measuredSizes[nodeId] = size;
    if (!(_controller._graph.nodes[nodeId]?.hasIntrinsicHeight ?? false)) {
      return;
    }
    _controller._revision++;
    _reindexNodes(<String>[nodeId]);
    _controller._notify();
  }

  /// Nodes in paint order: selected ones last so they float above the rest.
  List<GraphNode> get nodesInPaintOrder =>
      _inPaintOrder(_controller._graph.nodes.values.toList(growable: false));

  /// Nodes overlapping [sceneRect], in paint order.
  ///
  /// Backed by the spatial index, so a viewport query costs the area asked for
  /// rather than the size of the graph — and only the survivors get sorted.
  List<GraphNode> nodesIn(Rect sceneRect) => _inPaintOrder(<GraphNode>[
    for (final id in _index.queryRect(sceneRect))
      if (_controller._graph.nodes[id] case final GraphNode node) node,
  ]);

  /// Ids of selectable nodes whose bounds overlap [sceneRect].
  ///
  /// The raw query behind [NodeEditorSelection.selectInRect], for callers that
  /// need to combine the result with a selection of their own — a rubber band
  /// that adds to what was already selected, say.
  Set<String> nodeIdsIn(Rect sceneRect) => <String>{
    for (final id in _index.queryRect(sceneRect))
      if (_controller._graph.nodes[id]?.selectable ?? false) id,
  };

  /// The topmost node containing [scenePoint], matching paint order.
  GraphNode? nodeAt(Offset scenePoint) {
    GraphNode? best;
    for (final id in _index.queryPoint(scenePoint)) {
      final node = _controller._graph.nodes[id];
      if (node == null) continue;
      if (best == null || _paintRank(node) >= _paintRank(best)) best = node;
    }
    return best;
  }

  /// Node bounds as the spatial index currently sees them.
  Rect? boundsOf(String nodeId) => _index.rectOf(nodeId);

  /// The frame [group] draws, or null once every member is gone.
  ///
  /// Read off the spatial index, which already holds each node's rect at the
  /// size it was last measured at — so a frame can never disagree with the
  /// nodes it is drawn around.
  Rect? boundsOfGroup(NodeGroup group) =>
      NodeGraph.groupBounds(group, _index.rectOf);

  /// Groups whose frame overlaps [sceneRect], each with its frame.
  ///
  /// Not backed by the spatial index: a group has no entry of its own there,
  /// and there are rarely enough of them for that to matter. A frame can
  /// overlap the viewport while none of its members do — two nodes either side
  /// of the screen — so this is asked independently of the node cull.
  List<(NodeGroup, Rect)> groupsIn(Rect sceneRect) => <(NodeGroup, Rect)>[
    for (final group in _controller._graph.groups.values)
      if (boundsOfGroup(group) case final Rect frame)
        if (frame.overlaps(sceneRect)) (group, frame),
  ];

  /// Reference count held by the spatial index, for diagnostics.
  int get cellReferences => _index.cellReferences;

  /// The port nearest [scenePoint] within [radius], or null.
  ///
  /// Only nodes whose bounds are near the point are considered, so this stays
  /// cheap enough to run on every pointer move during a connection drag.
  PortRef? portAt(Offset scenePoint, {required double radius}) {
    PortRef? best;
    var bestDistance = double.infinity;

    final probe = Rect.fromCircle(center: scenePoint, radius: radius);
    for (final id in _index.queryRect(probe)) {
      final node = _controller._graph.nodes[id];
      if (node == null) continue;
      final size = sizeOf(node);
      for (final port in node.ports) {
        final distance =
            (NodeGeometry.portPosition(node, port, size) - scenePoint).distance;
        if (distance <= radius && distance < bestDistance) {
          bestDistance = distance;
          best = PortRef(node.id, port.id);
        }
      }
    }
    return best;
  }

  /// Scene-space centre of a port, or null if the port no longer exists.
  Offset? portPosition(PortRef ref) {
    final node = _controller._graph.nodes[ref.nodeId];
    if (node == null) return null;
    final port = node.portById(ref.portId);
    if (port == null) return null;
    return NodeGeometry.portPosition(node, port, sizeOf(node));
  }

  void _reindexAll() {
    _index.rebuild(<String, Rect>{
      for (final node in _controller._graph.nodes.values)
        node.id: node.rect(sizeOf(node)),
    });
  }

  void _reindexNodes(Iterable<String> ids) {
    for (final id in ids) {
      final node = _controller._graph.nodes[id];
      if (node == null) {
        _index.remove(id);
      } else {
        _index.put(id, node.rect(sizeOf(node)));
      }
    }
  }

  void _forgetMeasurements(Iterable<String> ids) {
    for (final id in ids) {
      _measuredSizes.remove(id);
    }
  }

  List<GraphNode> _inPaintOrder(List<GraphNode> nodes) {
    nodes.sort((a, b) => _paintRank(a) - _paintRank(b));
    return nodes;
  }

  int _paintRank(GraphNode node) =>
      _controller.selection.containsNode(node.id) ? 1 : 0;
}
