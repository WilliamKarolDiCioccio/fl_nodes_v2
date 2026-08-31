part of 'node_editor_controller.dart';

/// The selected nodes and connections.
///
/// Selection is deliberately outside the undo history: it is where the user is
/// looking, not something they authored, and an undo that moved the selection
/// around would fight the edit it was meant to reverse.
class NodeEditorSelection {
  NodeEditorSelection(this._controller);

  final NodeEditorController _controller;

  final Set<String> _nodeIds = <String>{};
  final Set<String> _connectionIds = <String>{};
  final Set<String> _groupIds = <String>{};

  Set<String>? _nodesSnapshot;
  Set<String>? _connectionsSnapshot;
  Set<String>? _groupsSnapshot;

  int _revision = 0;

  /// The selected nodes, as an immutable snapshot.
  ///
  /// Deliberately not a live view over the internal set: a view would keep
  /// changing under a caller that held on to it, which silently defeats any
  /// before/after comparison — a painter's `shouldRepaint`, for one.
  /// The snapshot is cached, so repeated reads cost nothing between changes.
  Set<String> get nodeIds =>
      _nodesSnapshot ??= Set<String>.unmodifiable(_nodeIds);

  /// The selected connections, as an immutable snapshot. See [nodeIds].
  Set<String> get connectionIds =>
      _connectionsSnapshot ??= Set<String>.unmodifiable(_connectionIds);

  /// The selected groups, as an immutable snapshot. See [nodeIds].
  ///
  /// Deliberately separate from [nodeIds]: selecting a group is selecting the
  /// frame, not painting five nodes blue. What acts on the contents —
  /// deleting, cutting, dragging — expands through [nodeIdsWithGroups], and
  /// nothing else has to.
  Set<String> get groupIds =>
      _groupsSnapshot ??= Set<String>.unmodifiable(_groupIds);

  /// The selected nodes, plus every member of every selected group.
  ///
  /// What "delete the selection" and "copy the selection" actually mean once
  /// a frame can be part of it.
  Set<String> get nodeIdsWithGroups {
    if (_groupIds.isEmpty) return nodeIds;
    return <String>{
      ..._nodeIds,
      for (final id in _groupIds) ...?_controller._graph.groups[id]?.nodeIds,
    };
  }

  /// Bumped whenever the selection changes.
  ///
  /// Gives painters an O(1) invalidation key, instead of comparing sets that
  /// may be large.
  int get revision => _revision;

  bool get isEmpty =>
      _nodeIds.isEmpty && _connectionIds.isEmpty && _groupIds.isEmpty;
  bool get isNotEmpty => !isEmpty;

  bool containsNode(String id) => _nodeIds.contains(id);
  bool containsConnection(String id) => _connectionIds.contains(id);
  bool containsGroup(String id) => _groupIds.contains(id);

  void selectNode(String id, {bool additive = false}) =>
      selectNodes(<String>[id], additive: additive);

  void selectNodes(Iterable<String> ids, {bool additive = false}) {
    final next = <String>{
      if (additive) ..._nodeIds,
      for (final id in ids)
        if (_controller._graph.nodes[id]?.selectable ?? false) id,
    };
    _apply(
      next,
      additive ? _connectionIds : const <String>{},
      additive ? _groupIds : const <String>{},
    );
  }

  void toggleNode(String id) {
    final next = Set<String>.of(_nodeIds);
    if (!next.remove(id) &&
        (_controller._graph.nodes[id]?.selectable ?? false)) {
      next.add(id);
    }
    _apply(next, _connectionIds, _groupIds);
  }

  void selectConnection(String id, {bool additive = false}) {
    if (!_controller._graph.connections.containsKey(id)) return;
    _apply(additive ? _nodeIds : const <String>{}, <String>{
      if (additive) ..._connectionIds,
      id,
    }, additive ? _groupIds : const <String>{});
  }

  void selectGroup(String id, {bool additive = false}) {
    if (!_controller._graph.groups.containsKey(id)) return;
    _apply(
      additive ? _nodeIds : const <String>{},
      additive ? _connectionIds : const <String>{},
      <String>{if (additive) ..._groupIds, id},
    );
  }

  void toggleGroup(String id) {
    final next = Set<String>.of(_groupIds);
    if (!next.remove(id) && _controller._graph.groups.containsKey(id)) {
      next.add(id);
    }
    _apply(_nodeIds, _connectionIds, next);
  }

  /// Every selectable node — deliberately not the groups.
  ///
  /// Selecting the frames as well would change nothing a user can see and
  /// would make the next `Del` delete each group's contents twice over, once
  /// through the nodes and once through the frame.
  void selectAll() => _apply(
    _controller._graph.nodes.values
        .where((node) => node.selectable)
        .map((node) => node.id)
        .toSet(),
    const <String>{},
    const <String>{},
  );

  void clear() => _apply(const <String>{}, const <String>{}, const <String>{});

  /// Selects every selectable node intersecting [rect] in scene coordinates.
  void selectInRect(Rect rect, {bool additive = false}) =>
      selectNodes(_controller.layout.nodeIdsIn(rect), additive: additive);

  /// Deletes everything selected as a single undo step.
  ///
  /// A selected group takes its contents with it. Deleting the frame and
  /// leaving the nodes is what "disband" means, and it has its own command;
  /// `Del` on a frame is asked for when the whole branch is unwanted.
  void deleteSelected() {
    if (isEmpty) return;
    _controller.history.beginTransaction();
    _controller.removeConnections(_connectionIds.toList());
    _controller.removeNodes(nodeIdsWithGroups.toList());
    // Removing every member empties the frames, and an empty group is pruned
    // by the graph — but a frame whose members were already gone would not be,
    // so say it outright.
    _controller.disbandGroups(_groupIds.toList());
    _controller.history.commitTransaction();
    clear();
  }

  void _apply(
    Set<String> nodeIds,
    Set<String> connectionIds,
    Set<String> groupIds,
  ) {
    if (setEquals(nodeIds, _nodeIds) &&
        setEquals(connectionIds, _connectionIds) &&
        setEquals(groupIds, _groupIds)) {
      return;
    }
    // Copied before anything is cleared. "Keep what you had" is expressed by
    // passing the live set straight back in, and clearing that set before
    // reading it empties it — which is how ctrl-clicking a node used to drop
    // the connection selection on the floor.
    final nextNodes = Set<String>.of(nodeIds);
    final nextConnections = Set<String>.of(connectionIds);
    final nextGroups = Set<String>.of(groupIds);
    _nodeIds
      ..clear()
      ..addAll(nextNodes);
    _connectionIds
      ..clear()
      ..addAll(nextConnections);
    _groupIds
      ..clear()
      ..addAll(nextGroups);
    _invalidate();
    _controller._notify();
  }

  /// Drops ids the graph no longer holds. Called after every mutation.
  void _prune() {
    final nodes = _nodeIds.length;
    final connections = _connectionIds.length;
    final groups = _groupIds.length;
    _nodeIds.removeWhere((id) => !_controller._graph.nodes.containsKey(id));
    _connectionIds.removeWhere(
      (id) => !_controller._graph.connections.containsKey(id),
    );
    _groupIds.removeWhere((id) => !_controller._graph.groups.containsKey(id));
    if (_nodeIds.length != nodes ||
        _connectionIds.length != connections ||
        _groupIds.length != groups) {
      _invalidate();
    }
  }

  void _invalidate() {
    _nodesSnapshot = null;
    _connectionsSnapshot = null;
    _groupsSnapshot = null;
    _revision++;
  }
}
