part of 'node_editor_controller.dart';

/// The current [GraphEmphasis], and the bookkeeping around changing it.
///
/// Beside [NodeEditorSelection] rather than inside the graph, and for the same
/// three reasons it is: no undo entry, nothing written to a document, and no
/// trip through `_mutate`. Assigning a focus is not an edit.
///
/// It lives on the controller rather than on the widget because paint order
/// and hit order have to agree. [NodeEditorLayout.nodeAt] and
/// [NodeEditorLayout.nodesInPaintOrder] rank through one function, and a focus
/// that reordered what is drawn without reordering what is clicked would put
/// the topmost card and the one a press lands on in different places.
class NodeEditorEmphasis {
  NodeEditorEmphasis(this._controller);

  final NodeEditorController _controller;

  GraphEmphasis _value = GraphEmphasis.none;

  Set<String>? _liftedSnapshot;

  int _revision = 0;

  GraphEmphasis get value => _value;

  /// Bumped whenever the focus changes.
  ///
  /// Painters key on this rather than comparing maps, exactly as they do with
  /// [NodeEditorSelection.revision].
  int get revision => _revision;

  bool get isEmpty => _value.isEmpty;
  bool get isNotEmpty => _value.isNotEmpty;

  /// The lifted node ids, as a cached immutable snapshot.
  ///
  /// Cached for the reason [NodeEditorSelection.nodeIds] is: it is read once
  /// per paint-order sort and once per pointer move, and a fresh set each time
  /// would allocate on every hover.
  Set<String> get lifted =>
      _liftedSnapshot ??= Set<String>.unmodifiable(_value.nodes.keys);

  bool lifts(String nodeId) => _value.nodes.containsKey(nodeId);

  /// Replaces the focus wholesale.
  ///
  /// Wholesale rather than incremental because a focus is an *answer* — every
  /// route between these two nodes — and merging two answers describes nothing.
  /// An equal value is a no-op, so a host that recomputes the same focus on
  /// every tick costs no repaint.
  set value(GraphEmphasis next) {
    if (next == _value) return;
    _value = next;
    _invalidate();
    _controller._notify();
  }

  void clear() => value = GraphEmphasis.none;

  /// Drops ids the graph no longer holds. Called after every mutation.
  ///
  /// Nothing else would: a focus is not in the document, so deleting a lifted
  /// node would otherwise leave a halo painted around nothing and a scrim held
  /// open by an id that is gone.
  void _prune() {
    if (_value.isEmpty) return;
    final nodes = <String, Color?>{
      for (final entry in _value.nodes.entries)
        if (_controller._graph.nodes.containsKey(entry.key))
          entry.key: entry.value,
    };
    final connections = <String, Color?>{
      for (final entry in _value.connections.entries)
        if (_controller._graph.connections.containsKey(entry.key))
          entry.key: entry.value,
    };
    if (nodes.length == _value.nodes.length &&
        connections.length == _value.connections.length) {
      return;
    }
    _value = GraphEmphasis(
      nodes: nodes,
      connections: connections,
      scrim: _value.scrim,
    );
    _invalidate();
  }

  void _invalidate() {
    _liftedSnapshot = null;
    _revision++;
  }
}
