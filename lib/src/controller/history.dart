part of 'node_editor_controller.dart';

/// The undo stack, and the transactions that collapse a drag into one step.
///
/// History is kept as whole [NodeGraph] snapshots rather than as a log of
/// inverse operations. The graph is immutable and structurally shared, so a
/// snapshot costs a pointer, and there is no class of bug where an undo step
/// fails to invert the edit that produced it.
class NodeEditorHistory {
  NodeEditorHistory(this._controller, {required this.limit});

  final NodeEditorController _controller;

  /// How many undo steps to retain.
  final int limit;

  final List<NodeGraph> _undoStack = <NodeGraph>[];
  final List<NodeGraph> _redoStack = <NodeGraph>[];

  int _depth = 0;
  NodeGraph? _baseline;

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  /// Whether an edit made now would fold into an open transaction.
  bool get inTransaction => _depth > 0;

  /// Groups every edit until the matching [commitTransaction] into a single
  /// undo step. Used for drags, which would otherwise push one entry a frame.
  void beginTransaction() {
    if (_depth == 0) _baseline = _controller._graph;
    _depth++;
  }

  void commitTransaction() {
    if (_depth == 0) return;
    _depth--;
    if (_depth > 0) return;
    final baseline = _baseline;
    _baseline = null;
    if (baseline != null && baseline != _controller._graph) {
      _push(baseline);
      _controller._notify();
    }
  }

  /// Ends the transaction and restores the graph as it was when it began.
  void cancelTransaction() {
    if (_depth == 0) return;
    _depth = 0;
    final baseline = _baseline;
    _baseline = null;
    if (baseline != null && baseline != _controller._graph) {
      _controller._graph = baseline;
      _afterJump();
    }
  }

  void undo() {
    if (_undoStack.isEmpty) return;
    _redoStack.add(_controller._graph);
    _controller._graph = _undoStack.removeLast();
    _afterJump();
  }

  void redo() {
    if (_redoStack.isEmpty) return;
    _undoStack.add(_controller._graph);
    _controller._graph = _redoStack.removeLast();
    _afterJump();
  }

  void clear() {
    _undoStack.clear();
    _redoStack.clear();
    _controller._notify();
  }

  /// Drops both stacks without notifying, for a load that is about to notify
  /// on its own account.
  void _reset() {
    _undoStack.clear();
    _redoStack.clear();
  }

  void _push(NodeGraph snapshot) {
    _undoStack.add(snapshot);
    if (_undoStack.length > limit) _undoStack.removeAt(0);
    _redoStack.clear();
  }

  void _afterJump() {
    // Stepping through the history moves the ground under an open run of
    // typing: the next keystroke has to record, or it would overwrite the
    // step the user just came back to.
    _controller._commentBeingTyped = null;
    _controller._revision++;
    _controller.layout._reindexAll();
    _controller.selection._prune();
    _controller._notify();
  }
}
