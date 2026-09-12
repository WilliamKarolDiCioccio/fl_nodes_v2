part of 'node_editor_controller.dart';

/// Told about a run as it happens. See [NodeEditorRunner.onEvent].
typedef GraphRunListener = void Function(GraphRunEvent event);

/// One thing the runner did.
///
/// A sealed hierarchy rather than a string: which lines a log is made of, and
/// what each says, is the host's decision, the way the arrangement of a graph
/// is the host's under `applyLayout`. What the package supplies is the facts a
/// host cannot get for itself — what ran, in what order, what was on the wires.
///
/// Every event carries the run it belongs to, its position in that run, and
/// how long after the run started it happened. `at` is read from the run's own
/// stopwatch, so two events from one run can be compared and two from
/// different runs cannot.
sealed class GraphRunEvent {
  const GraphRunEvent({
    required this.runId,
    required this.sequence,
    required this.at,
  });

  /// Which run this belongs to. Climbs by one per run of one runner.
  final int runId;

  /// Where this sits among the run's events, from zero.
  final int sequence;

  final Duration at;
}

/// The run has worked out where to start, and is about to.
final class RunStarted extends GraphRunEvent {
  const RunStarted({
    required super.runId,
    required super.sequence,
    required super.at,
    required this.roots,
    required this.pullOnly,
  });

  /// The nodes the run begins at, in the order it will take them.
  final List<String> roots;

  /// True when there is no control flow to follow, and the run is evaluating
  /// data sinks instead.
  final bool pullOnly;
}

/// A node is about to take a turn.
final class NodeStarted extends GraphRunEvent {
  const NodeStarted({
    required super.runId,
    required super.sequence,
    required super.at,
    required this.nodeId,
    required this.step,
    required this.enteredVia,
    required this.pulled,
    required this.inputs,
  });

  final String nodeId;

  /// How many turns this node has already taken in this run. Non-zero means
  /// the flow came back around.
  final int step;

  /// The control input the flow arrived on, or null when it did not arrive.
  final String? enteredVia;

  /// True when the node is being evaluated because something downstream
  /// asked what it holds, rather than because the flow reached it.
  final bool pulled;

  /// What is on every wire into this node's data inputs, one entry per wire.
  final List<GraphTraceValue> inputs;
}

/// A node's turn is over, one way or another.
final class NodeFinished extends GraphRunEvent {
  const NodeFinished({
    required super.runId,
    required super.sequence,
    required super.at,
    required this.nodeId,
    required this.step,
    required this.outcome,
    required this.outputs,
    required this.flowed,
    required this.elapsed,
    this.error,
    this.stackTrace,
  });

  final String nodeId;
  final int step;

  /// [NodeRunState.done], [NodeRunState.failed] or [NodeRunState.cancelled];
  /// never the other two.
  final NodeRunState outcome;

  /// What the node published, one entry per data output it wrote. Empty
  /// unless [outcome] is [NodeRunState.done]: a cancelled turn's writes are
  /// never published, so they are never reported either.
  final List<GraphTraceValue> outputs;

  /// The control outputs the flow leaves through, in the order it will.
  final List<String> flowed;

  /// How long the turn took, executor included.
  final Duration elapsed;

  /// What the executor threw, when [outcome] is [NodeRunState.failed].
  final Object? error;
  final StackTrace? stackTrace;
}

/// A pure data node was read and did not need to run, because nothing it
/// reads has changed since it last did.
///
/// Reported so that a value arriving at a consumer can always be traced to
/// the turn that produced it, even when that turn was several reads ago.
final class MemoHit extends GraphRunEvent {
  const MemoHit({
    required super.runId,
    required super.sequence,
    required super.at,
    required this.nodeId,
  });

  final String nodeId;
}

/// The run made a remark. The same one is never made twice about the same
/// port, which is the rule [GraphRun.diagnostics] already follows.
final class DiagnosticRaised extends GraphRunEvent {
  const DiagnosticRaised({
    required super.runId,
    required super.sequence,
    required super.at,
    required this.diagnostic,
  });

  final GraphRunDiagnostic diagnostic;
}

/// An executor said something through [NodeExecutionContext.log].
final class LogEmitted extends GraphRunEvent {
  const LogEmitted({
    required super.runId,
    required super.sequence,
    required super.at,
    required this.entry,
  });

  final GraphLogEntry entry;
}

/// The run is over, and this is what it did — the same object [NodeEditorRunner.run]
/// returns.
final class RunFinished extends GraphRunEvent {
  const RunFinished({
    required super.runId,
    required super.sequence,
    required super.at,
    required this.run,
  });

  final GraphRun run;
}

/// A value on a wire, as the trace saw it.
@immutable
class GraphTraceValue {
  const GraphTraceValue({
    required this.from,
    required this.dataType,
    required this.payload,
    this.to,
  });

  /// The output that produced the value.
  final PortRef from;

  /// The input it was read on. Null on an output that was written, whether or
  /// not anything is wired to it.
  final PortRef? to;

  /// [NodePort.dataType] of [from]: the tag the host gave the port, and never
  /// anything derived from the value's Dart type, which a shipped build
  /// renames.
  final String? dataType;

  final GraphPayload payload;

  @override
  String toString() =>
      'GraphTraceValue(${from.nodeId}.${from.portId}'
      '${to == null ? '' : ' -> ${to!.nodeId}.${to!.portId}'}'
      '${dataType == null ? '' : ' : $dataType'} = $payload)';
}

/// What a [GraphTraceValue] carries, and whether it carries it at all.
sealed class GraphPayload {
  const GraphPayload();
}

/// The value itself. Null is a value a node is entitled to emit, so a null
/// here is a null on the wire and not an absence.
final class PresentPayload extends GraphPayload {
  const PresentPayload(this.value);

  final Object? value;

  @override
  String toString() => '$value';
}

/// There is a value, and [NodeEditorRunner.tracePayloads] said not to carry it.
final class WithheldPayload extends GraphPayload {
  const WithheldPayload();

  @override
  String toString() => '<withheld>';
}

/// The wire exists and nothing has been written on it yet — the producer has
/// not run, or ran and did not emit on that port.
final class AbsentPayload extends GraphPayload {
  const AbsentPayload();

  @override
  String toString() => '<absent>';
}

/// Collects events into a list.
///
/// The ten lines every host and every test would otherwise write, and nothing
/// more: it is a fixture, not a sink. Assign it directly —
/// `runner.onEvent = recorder.call` — and read [events] when the run is done.
class GraphRunRecorder {
  final List<GraphRunEvent> events = <GraphRunEvent>[];

  void call(GraphRunEvent event) => events.add(event);

  void clear() => events.clear();

  /// The events of one kind, in order.
  Iterable<T> whereType<T extends GraphRunEvent>() => events.whereType<T>();
}
