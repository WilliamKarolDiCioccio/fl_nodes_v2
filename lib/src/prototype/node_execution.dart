import '../model/graph_node.dart';
import '../model/node_graph.dart';

/// What a node does when the flow reaches it.
///
/// Returning a future is what lets a node await real work — a request, a
/// file, a frame — without the runner having to know about any of it.
typedef NodeExecutor = Future<void> Function(NodeExecutionContext context);

/// One node's turn, from the runner's side.
///
/// Implemented by the runner and deliberately not exported: it exists so
/// [NodeExecutionContext] can be a thin, typed façade over state that lives in
/// the run, rather than the run's state leaking into the prototype layer.
abstract class NodeExecutionStep {
  NodeGraph get graph;
  GraphNode get node;

  /// How many times this node has already run in this pass, starting at zero.
  int get step;

  bool get isCancelled;

  /// False once the runner has moved on. See [NodeExecutionContext.emit].
  bool get isOpen;

  bool hasInput(String portId);
  List<Object?> readInput(String portId);
  void writeOutput(String portId, Object? value);
  void scheduleFlow(String portId);

  Map<String, Object?> get state;
}

/// Everything a [NodeExecutor] is given, and everything it can do.
///
/// One object rather than a handful of positional maps and callbacks, matching
/// the other prototype hooks. It reaches the graph and the node but never the
/// controller: writing to the document from inside a run is not something to
/// stumble into, and execution is supposed to leave the document alone.
class NodeExecutionContext {
  const NodeExecutionContext(this._step);

  final NodeExecutionStep _step;

  /// The graph as it was when the run began.
  ///
  /// A snapshot, so an edit made while the run is in flight cannot change what
  /// it is running.
  NodeGraph get graph => _step.graph;

  GraphNode get node => _step.node;
  String get nodeId => _step.node.id;

  /// How many times this node has already run in this pass, starting at zero.
  ///
  /// Non-zero means the flow has come back around — a loop.
  int get step => _step.step;

  /// True once the run has been asked to stop.
  ///
  /// A long executor should check this between pieces of work; nothing can
  /// interrupt a future from outside, so a run is only as responsive to
  /// [NodeEditorRunner.cancel] as its slowest executor chooses to be.
  bool get isCancelled => _step.isCancelled;

  // ----------------------------------------------------------------- fields

  /// The node's stored values, which is exactly `node.data`.
  Map<String, Object?> get fields => _step.node.data;

  T? field<T>(String key) {
    final value = _step.node.data[key];
    return value is T ? value : null;
  }

  T fieldOr<T>(String key, T fallback) => field<T>(key) ?? fallback;

  // ----------------------------------------------------------------- inputs

  /// Whether a value reached [portId].
  ///
  /// Distinct from a null value, which a node is perfectly entitled to emit.
  bool hasInput(String portId) => _step.hasInput(portId);

  /// The value delivered to a data input, or null.
  ///
  /// With several wires into one input this is the first by connection id, and
  /// the run records a diagnostic saying so. [inputs] returns all of them.
  T? input<T>(String portId) {
    final values = _step.readInput(portId);
    if (values.isEmpty) return null;
    final value = values.first;
    return value is T ? value : null;
  }

  T inputOr<T>(String portId, T fallback) => input<T>(portId) ?? fallback;

  /// Every value delivered to [portId], in connection id order.
  List<Object?> inputs(String portId) => _step.readInput(portId);

  // ---------------------------------------------------------------- outputs

  /// Publishes a value on a data output, for whatever is wired to it.
  ///
  /// Throws if [portId] is not a data output of this node — a mistyped port id
  /// that quietly did nothing would be the worst kind of bug to chase — and
  /// throws once this node's turn is over, which catches an executor that kept
  /// the context and wrote from a future it never awaited.
  void emit(String portId, Object? value) {
    _requireOpen('emit');
    _step.writeOutput(portId, value);
  }

  /// Sends the flow out of a control output.
  ///
  /// Calling it twice on the same port in one turn is the same as calling it
  /// once. Throws on a port that is not a control output of this node, and
  /// after this node's turn is over.
  void flow(String portId) {
    _requireOpen('flow');
    _step.scheduleFlow(portId);
  }

  void flowAll(Iterable<String> portIds) {
    for (final portId in portIds) {
      flow(portId);
    }
  }

  // ------------------------------------------------------------------ state

  /// Scratch space that survives from one turn of this node to the next,
  /// within a single run.
  ///
  /// This is what a loop counts in, and what a node that waits for several
  /// incoming branches counts tokens in — the runner has no join of its own.
  /// It starts empty on every run.
  Map<String, Object?> get state => _step.state;

  void _requireOpen(String what) {
    if (_step.isOpen) return;
    throw StateError(
      'NodeExecutionContext.$what was called after ${_step.node.id} finished '
      'its turn. A context is only valid until its executor returns; hold the '
      'values you need instead of the context.',
    );
  }
}
