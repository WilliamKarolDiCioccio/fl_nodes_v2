part of 'node_editor_controller.dart';

/// Where a node got to in the current or most recent run.
enum NodeRunState { idle, running, done, failed, cancelled }

/// Something the runner noticed that is worth saying out loud but is not an
/// error.
enum GraphRunIssue {
  /// Nothing to start from: every node with control outputs also has a
  /// control input wired to it.
  noEntryPoint,

  /// A node with no executor and more than one control output. The runner
  /// refuses to guess which one the flow takes, so it takes none.
  ambiguousFlow,

  /// Several wires arrive at one data input. The first by connection id wins;
  /// [NodeExecutionContext.inputs] sees all of them.
  multipleInputs,

  /// A data input reads from a node that is part of the control flow and has
  /// not run yet, so there is nothing to read.
  producerNotRun,

  /// A node ran more than once, because more than one control pulse reached
  /// it. Expected inside a loop; usually a surprise after a fan-out.
  reentered,
}

/// One remark about a run.
@immutable
class GraphRunDiagnostic {
  const GraphRunDiagnostic({
    required this.issue,
    required this.message,
    this.nodeId,
    this.portId,
  });

  final GraphRunIssue issue;
  final String message;
  final String? nodeId;
  final String? portId;

  @override
  String toString() {
    final where = nodeId == null
        ? ''
        : ' (${portId == null ? nodeId : '$nodeId.$portId'})';
    return '${issue.name}: $message$where';
  }
}

/// A run that could not continue.
class GraphRunException implements Exception {
  const GraphRunException(this.message, {this.nodeIds = const <String>[]});

  final String message;

  /// The nodes the failure is about — the members of a cycle, or the nodes
  /// that consumed the step budget.
  final List<String> nodeIds;

  @override
  String toString() => 'GraphRunException: $message';
}

/// What one execution of the graph did.
@immutable
class GraphRun {
  const GraphRun({
    required this.trace,
    required this.states,
    required this.runCounts,
    required this.values,
    required this.diagnostics,
    required this.steps,
    required this.elapsed,
    required this.cancelled,
    required this.timedOut,
    this.error,
    this.failedNodeId,
    this.stackTrace,
  });

  /// Node ids in the order they ran. A node appears once per turn it took.
  final List<String> trace;

  final Map<String, NodeRunState> states;

  /// How many turns each node took.
  final Map<String, int> runCounts;

  /// Every value produced, keyed by the **output port that produced it**.
  ///
  /// Keyed by source rather than destination so that a value is written once
  /// however many wires carry it, and so an output nothing is wired to still
  /// shows up here — which is what makes this useful to look at.
  final Map<PortRef, Object?> values;

  final List<GraphRunDiagnostic> diagnostics;

  /// Node executions, pure data evaluations included.
  final int steps;
  final Duration elapsed;

  final bool cancelled;
  final bool timedOut;

  final Object? error;
  final String? failedNodeId;
  final StackTrace? stackTrace;

  bool get succeeded => error == null && !cancelled;

  Object? valueAt(PortRef ref) => values[ref];

  @override
  String toString() =>
      'GraphRun(${succeeded
          ? 'ok'
          : cancelled
          ? 'cancelled'
          : 'failed'}, '
      '$steps steps, ${elapsed.inMilliseconds}ms)';
}

/// Runs the graph.
///
/// Execution reads the document and never writes to it: no node moves, the
/// revision does not change, nothing lands in the undo history and the project
/// does not become dirty. Runtime values live in the run, not on the ports —
/// which is the one place this design has to differ from an editor whose model
/// is mutable, and the reason a run is immune to edits made while it is in
/// flight.
class NodeEditorRunner {
  NodeEditorRunner(this._controller);

  /// Node executions between yields to the event loop.
  ///
  /// A fully synchronous graph would otherwise hold the isolate for the whole
  /// run, which drops frames and makes [cancel] unobservable.
  static const int yieldEvery = 64;

  final NodeEditorController _controller;

  _RunState? _current;
  GraphRun? _last;

  bool get isRunning => _current != null;

  /// The most recent completed run, or null if none has finished.
  GraphRun? get lastRun => _last;

  NodeRunState stateOf(String nodeId) =>
      _current?.states[nodeId] ?? _last?.states[nodeId] ?? NodeRunState.idle;

  /// Asks the current run to stop. A no-op when nothing is running.
  ///
  /// Nothing can interrupt a future from outside, so a run stops as soon as
  /// the executor it is waiting on returns. An executor that expects to be
  /// long should watch [NodeExecutionContext.isCancelled].
  void cancel() {
    final run = _current;
    if (run == null) return;
    run.cancelled = true;
  }

  /// Runs the graph and reports what happened.
  ///
  /// [from] names the nodes to start at, bypassing the search for entry
  /// points entirely — which is how a single node gets run on its own.
  /// [maxSteps] bounds the whole run, so a control loop that never ends is
  /// reported instead of hanging the app.
  ///
  /// Throws [StateError] if a run is already in flight; an exception thrown by
  /// an executor is *not* rethrown, it comes back on [GraphRun.error].
  Future<GraphRun> run({
    Iterable<String>? from,
    int maxSteps = 1024,
    Duration? timeout,
  }) async {
    if (_current != null) {
      throw StateError(
        'A run is already in flight. Await it, or call cancel() first.',
      );
    }
    final watch = Stopwatch()..start();
    final run = _RunState(
      graph: _controller._graph,
      prototypes: _controller._prototypes,
      maxSteps: maxSteps,
      deadline: timeout == null ? null : DateTime.now().add(timeout),
      onStateChanged: _controller._notify,
    );
    _current = run;
    _controller._notify();
    try {
      await _execute(run, from);
    } finally {
      watch.stop();
      _current = null;
    }
    final result = GraphRun(
      trace: List<String>.unmodifiable(run.trace),
      states: Map<String, NodeRunState>.unmodifiable(run.states),
      runCounts: Map<String, int>.unmodifiable(run.runCounts),
      values: Map<PortRef, Object?>.unmodifiable(run.values),
      diagnostics: List<GraphRunDiagnostic>.unmodifiable(run.diagnostics),
      steps: run.steps,
      elapsed: watch.elapsed,
      cancelled: run.cancelled,
      timedOut: run.timedOut,
      error: run.error,
      failedNodeId: run.failedNodeId,
      stackTrace: run.stackTrace,
    );
    _last = result;
    _controller._notify();
    return result;
  }

  // --------------------------------------------------------------- driving

  Future<void> _execute(_RunState run, Iterable<String>? from) async {
    final roots = run.rootsFor(from);
    if (roots.isEmpty) return;

    if (run.pullOnly) {
      // No control flow anywhere: evaluate the data sinks, which is the only
      // thing a pure data graph can usefully mean.
      for (final id in roots) {
        if (run.stopped) break;
        await _pull(run, id, <String>[]);
        if (run.error != null) break;
      }
      return;
    }

    // The port a node is entered through travels with it. A node with two
    // control inputs has no other way to tell them apart, and some cannot be
    // written without it — a loop's `continue` and `break` are one node doing
    // opposite things. A root arrives through nothing, hence the null.
    final stack = <_Arrival>[
      for (final id in roots.reversed) (nodeId: id, via: null),
    ];
    while (stack.isNotEmpty) {
      if (run.stopped) break;
      final arrival = stack.removeLast();
      final flowed = await _step(run, arrival.nodeId, arrival.via);
      if (run.error != null || run.stopped) break;

      // Depth first: the first port flowed is the first one taken, so a branch
      // runs to its end before its sibling starts. Pushed in reverse for that.
      final next = <_Arrival>[];
      for (final portId in flowed) {
        for (final connection
            in run.outgoing[PortRef(arrival.nodeId, portId)] ??
                const <NodeConnection>[]) {
          next.add((nodeId: connection.to.nodeId, via: connection.to.portId));
        }
      }
      for (var i = next.length - 1; i >= 0; i--) {
        stack.add(next[i]);
      }
      if (run.steps % yieldEvery == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }
  }

  /// Runs one control node: pulls what it reads, invokes it, reports what it
  /// flowed.
  Future<List<String>> _step(_RunState run, String nodeId, String? via) async {
    final plan = run.plans[nodeId];
    if (plan == null) return const <String>[];

    await _pullInputs(run, plan, <String>[]);
    if (run.error != null || run.stopped) return const <String>[];

    final step = await _invoke(run, plan, via);
    if (step == null) return const <String>[];

    run.trace.add(nodeId);
    final count = (run.runCounts[nodeId] ?? 0) + 1;
    run.runCounts[nodeId] = count;
    if (count == 2) {
      run.diagnose(
        GraphRunIssue.reentered,
        'ran again because a second control pulse reached it',
        nodeId: nodeId,
      );
    }
    return step.flowed;
  }

  /// Makes sure every data input of [plan] has whatever it is going to have.
  Future<void> _pullInputs(
    _RunState run,
    _NodePlan plan,
    List<String> pulling,
  ) async {
    for (final portId in plan.dataInputs) {
      final incoming =
          run.incoming[PortRef(plan.node.id, portId)] ??
          const <NodeConnection>[];
      if (incoming.isEmpty) continue;
      if (incoming.length > 1) {
        run.diagnose(
          GraphRunIssue.multipleInputs,
          '${incoming.length} wires arrive here; the first by connection id '
          'is what input() returns',
          nodeId: plan.node.id,
          portId: portId,
        );
      }
      for (final connection in incoming) {
        await _pullFrom(run, connection.from, pulling);
        if (run.error != null || run.stopped) return;
      }
    }
  }

  /// Ensures the value on [source] is as fresh as it can be.
  Future<void> _pullFrom(
    _RunState run,
    PortRef source,
    List<String> pulling,
  ) async {
    final plan = run.plans[source.nodeId];
    if (plan == null) return;

    if (!plan.isPureData) {
      // It belongs to the control flow, so it produces its value when the flow
      // reaches it — not on demand, which would run it out of order.
      if ((run.runCounts[source.nodeId] ?? 0) == 0) {
        run.diagnose(
          GraphRunIssue.producerNotRun,
          'reads ${source.nodeId}.${source.portId}, which has not run yet',
          nodeId: source.nodeId,
          portId: source.portId,
        );
      }
      return;
    }
    if (run.memoValid(plan)) return;
    await _pull(run, source.nodeId, pulling);
  }

  /// Evaluates a pure data node, and whatever it reads, first.
  Future<void> _pull(_RunState run, String nodeId, List<String> pulling) async {
    if (pulling.contains(nodeId)) {
      run.fail(
        GraphRunException(
          'data flows in a circle: ${<String>[...pulling, nodeId].join(' -> ')}',
          nodeIds: <String>[...pulling, nodeId],
        ),
        nodeId: nodeId,
      );
      return;
    }
    final plan = run.plans[nodeId];
    if (plan == null) return;

    pulling.add(nodeId);
    await _pullInputs(run, plan, pulling);
    pulling.removeLast();
    if (run.error != null || run.stopped) return;

    // Null, and not a guess: nothing flowed into this node. It is being
    // evaluated because something downstream asked what it holds.
    final step = await _invoke(run, plan, null);
    if (step == null) return;
    // Traced like any other turn: `steps` and `runCounts` count a pull, and a
    // trace that quietly left them out would disagree with both.
    run.trace.add(nodeId);
    run.runCounts[nodeId] = (run.runCounts[nodeId] ?? 0) + 1;
    if (plan.pure) run.evaluatedAt[nodeId] = run.stamp;
  }

  /// Gives [plan] its turn. Null means it did not get one, or did not survive.
  Future<_Step?> _invoke(
    _RunState run,
    _NodePlan plan,
    String? enteredVia,
  ) async {
    if (run.steps >= run.maxSteps) {
      run.fail(
        GraphRunException(
          'the run passed its budget of ${run.maxSteps} steps; the busiest '
          'nodes were ${run.busiest().join(', ')}',
          nodeIds: run.busiest(),
        ),
      );
      return null;
    }
    run.steps++;
    run.setState(plan.node.id, NodeRunState.running);

    final step = _Step(run, plan, run.runCounts[plan.node.id] ?? 0, enteredVia);
    try {
      final executor = plan.executor;
      if (executor != null) {
        await executor(NodeExecutionContext(step));
      } else if (plan.controlOutputs.length == 1) {
        // No executor is not "does nothing": an ordinary pass-through node
        // hands the flow straight on.
        step.scheduleFlow(plan.controlOutputs.single);
      } else if (plan.controlOutputs.length > 1) {
        run.diagnose(
          GraphRunIssue.ambiguousFlow,
          'has ${plan.controlOutputs.length} control outputs and no executor '
          'to choose between them, so the flow stops here',
          nodeId: plan.node.id,
        );
      }
    } catch (error, stackTrace) {
      step.close();
      run.setState(plan.node.id, NodeRunState.failed);
      run.fail(error, nodeId: plan.node.id, stackTrace: stackTrace);
      return null;
    }
    step.close();

    // Checked before anything the step recorded is applied, so a run that was
    // cancelled mid-await does not publish the values of the node it was
    // waiting on.
    if (run.stopped) {
      run.setState(plan.node.id, NodeRunState.cancelled);
      return null;
    }
    run.commit(step, bumpStamp: !plan.isPureData);
    run.setState(plan.node.id, NodeRunState.done);
    return step;
  }
}

// ---------------------------------------------------------------- internals

/// A node waiting its turn, and the control input that sent it there.
typedef _Arrival = ({String nodeId, String? via});

/// Everything about one node that the run needs, worked out once.
///
/// The rule is *no plan cached between runs*, not *no index within one*: every
/// edge lookup would otherwise walk `connectionsOf`, which is node-keyed and
/// undirected, and every port lookup would be a linear scan.
class _NodePlan {
  _NodePlan({
    required this.node,
    required this.controlInputs,
    required this.controlOutputs,
    required this.dataInputs,
    required this.dataOutputs,
    required this.executor,
    required this.pure,
  });

  final GraphNode node;
  final List<String> controlInputs;
  final List<String> controlOutputs;
  final List<String> dataInputs;
  final List<String> dataOutputs;
  final NodeExecutor? executor;
  final bool pure;

  /// Whether this node sits outside the flow entirely.
  ///
  /// Declares no control ports — never "has none connected", which would make
  /// a node's nature depend on wiring elsewhere in the document, so the same
  /// node would be pulled on demand in one run and not in the next.
  bool get isPureData => controlInputs.isEmpty && controlOutputs.isEmpty;
}

class _RunState {
  _RunState({
    required this.graph,
    required NodePrototypeRegistry prototypes,
    required this.maxSteps,
    required this.deadline,
    required this.onStateChanged,
  }) {
    for (final node in graph.nodes.values) {
      final controlIn = <String>[];
      final controlOut = <String>[];
      final dataIn = <String>[];
      final dataOut = <String>[];
      for (final port in node.ports) {
        ports[PortRef(node.id, port.id)] = port;
        if (port.kind == PortKind.control) {
          (port.isOutput ? controlOut : controlIn).add(port.id);
        } else {
          (port.isOutput ? dataOut : dataIn).add(port.id);
        }
      }
      final prototype = prototypes[node.type];
      plans[node.id] = _NodePlan(
        node: node,
        controlInputs: controlIn,
        controlOutputs: controlOut,
        dataInputs: dataIn,
        dataOutputs: dataOut,
        // Resolved now, so a registry swapped mid-run cannot change the
        // executor between two turns of the same loop.
        executor: prototype?.onExecute,
        pure: prototype?.pure ?? true,
      );
    }
    // Built from the connection map rather than from connectionsOf, whose
    // index holds a self-connection once and would lose its incoming half.
    for (final connection in graph.connections.values) {
      (outgoing[connection.from] ??= <NodeConnection>[]).add(connection);
      (incoming[connection.to] ??= <NodeConnection>[]).add(connection);
    }
    // Ordered by connection id, so fan-out is a property of the document and
    // not of the order the wires happened to be drawn.
    for (final list in outgoing.values) {
      list.sort((a, b) => a.id.compareTo(b.id));
    }
    for (final list in incoming.values) {
      list.sort((a, b) => a.id.compareTo(b.id));
    }
  }

  final NodeGraph graph;
  final int maxSteps;
  final DateTime? deadline;
  final VoidCallback onStateChanged;

  final Map<PortRef, NodePort> ports = <PortRef, NodePort>{};
  final Map<PortRef, List<NodeConnection>> outgoing =
      <PortRef, List<NodeConnection>>{};
  final Map<PortRef, List<NodeConnection>> incoming =
      <PortRef, List<NodeConnection>>{};
  final Map<String, _NodePlan> plans = <String, _NodePlan>{};

  final Map<PortRef, Object?> values = <PortRef, Object?>{};
  final Map<PortRef, int> writtenAt = <PortRef, int>{};
  final Map<String, int> evaluatedAt = <String, int>{};
  final Map<String, int> runCounts = <String, int>{};
  final Map<String, Map<String, Object?>> scratch =
      <String, Map<String, Object?>>{};
  final Map<String, NodeRunState> states = <String, NodeRunState>{};
  final List<String> trace = <String>[];
  final List<GraphRunDiagnostic> diagnostics = <GraphRunDiagnostic>[];
  final Set<String> _said = <String>{};

  /// Bumped once per control-node turn. A pure data node's memo is good while
  /// nothing it reads has been written since it last ran.
  int stamp = 0;
  int steps = 0;
  bool cancelled = false;
  bool timedOut = false;
  bool pullOnly = false;

  Object? error;
  String? failedNodeId;
  StackTrace? stackTrace;

  bool get stopped {
    if (cancelled) return true;
    final by = deadline;
    if (by != null && DateTime.now().isAfter(by)) {
      timedOut = true;
      cancelled = true;
      return true;
    }
    return false;
  }

  Map<String, Object?> scratchFor(String nodeId) =>
      scratch[nodeId] ??= <String, Object?>{};

  void setState(String nodeId, NodeRunState state) {
    if (states[nodeId] == state) return;
    states[nodeId] = state;
    onStateChanged();
  }

  void fail(Object error, {String? nodeId, StackTrace? stackTrace}) {
    if (this.error != null) return;
    this.error = error;
    failedNodeId = nodeId;
    this.stackTrace = stackTrace;
  }

  void diagnose(
    GraphRunIssue issue,
    String message, {
    String? nodeId,
    String? portId,
  }) {
    // The same remark about the same port, once. A node inside a loop would
    // otherwise report it on every turn.
    if (!_said.add('${issue.name}:$nodeId:$portId')) return;
    diagnostics.add(
      GraphRunDiagnostic(
        issue: issue,
        message: message,
        nodeId: nodeId,
        portId: portId,
      ),
    );
  }

  /// The nodes that took the most turns, for a budget-exceeded report.
  List<String> busiest() {
    final ids = runCounts.keys.toList()
      ..sort((a, b) => runCounts[b]!.compareTo(runCounts[a]!));
    return <String>[for (final id in ids.take(3)) '$id x${runCounts[id]}'];
  }

  bool memoValid(_NodePlan plan) {
    if (!plan.pure) return false;
    final at = evaluatedAt[plan.node.id];
    if (at == null) return false;
    for (final portId in plan.dataInputs) {
      for (final connection
          in incoming[PortRef(plan.node.id, portId)] ??
              const <NodeConnection>[]) {
        if ((writtenAt[connection.from] ?? 0) > at) return false;
      }
    }
    return true;
  }

  void commit(_Step step, {required bool bumpStamp}) {
    if (bumpStamp) stamp++;
    step.writes.forEach((ref, value) {
      values[ref] = value;
      writtenAt[ref] = stamp;
    });
  }

  List<String> rootsFor(Iterable<String>? from) {
    if (from != null) {
      final explicit = <String>[
        for (final id in from)
          if (plans.containsKey(id)) id,
      ];
      // Naming a data node explicitly means "work out what it produces".
      pullOnly =
          explicit.isNotEmpty && explicit.every((id) => plans[id]!.isPureData);
      return explicit;
    }

    final entries = <String>[
      for (final plan in plans.values)
        if (plan.controlOutputs.isNotEmpty && !_hasWiredControlInput(plan))
          plan.node.id,
    ]..sort();
    if (entries.isNotEmpty) return entries;

    // Falling back on an empty entry set rather than on "the document has no
    // control ports": one stray control port would otherwise take a graph that
    // is mostly data and leave it doing nothing at all.
    final sinks = <String>[
      for (final plan in plans.values)
        if (plan.isPureData &&
            plan.dataOutputs.isNotEmpty &&
            !_hasWiredDataOutput(plan))
          plan.node.id,
    ]..sort();
    if (sinks.isNotEmpty) {
      pullOnly = true;
      if (plans.values.any((plan) => !plan.isPureData)) {
        diagnose(
          GraphRunIssue.noEntryPoint,
          'no node can start the flow, so the data sinks were evaluated and '
          'the control half did not run',
        );
      }
      return sinks;
    }

    if (plans.isNotEmpty) {
      diagnose(
        GraphRunIssue.noEntryPoint,
        'nothing to start from: every node with a control output already has '
        'one wired to its input',
      );
    }
    return const <String>[];
  }

  bool _hasWiredControlInput(_NodePlan plan) => plan.controlInputs.any(
    (portId) =>
        (incoming[PortRef(plan.node.id, portId)] ?? const []).isNotEmpty,
  );

  bool _hasWiredDataOutput(_NodePlan plan) => plan.dataOutputs.any(
    (portId) =>
        (outgoing[PortRef(plan.node.id, portId)] ?? const []).isNotEmpty,
  );
}

/// One node's turn. The state a [NodeExecutionContext] reads and writes.
class _Step implements NodeExecutionStep {
  _Step(this._run, this._plan, this.step, this.enteredVia);

  final _RunState _run;
  final _NodePlan _plan;

  @override
  final int step;

  @override
  final String? enteredVia;

  /// Buffered until the turn survives, so a run cancelled mid-await does not
  /// publish the values of the node it was waiting on.
  final Map<PortRef, Object?> writes = <PortRef, Object?>{};
  final List<String> flowed = <String>[];

  bool _open = true;
  void close() => _open = false;

  @override
  NodeGraph get graph => _run.graph;

  @override
  GraphNode get node => _plan.node;

  @override
  bool get isCancelled => _run.stopped;

  @override
  bool get isOpen => _open;

  @override
  Map<String, Object?> get state => _run.scratchFor(_plan.node.id);

  @override
  bool hasInput(String portId) => readInput(portId).isNotEmpty;

  @override
  List<Object?> readInput(String portId) {
    final wires =
        _run.incoming[PortRef(_plan.node.id, portId)] ??
        const <NodeConnection>[];
    return <Object?>[
      for (final wire in wires)
        if (_run.values.containsKey(wire.from)) _run.values[wire.from],
    ];
  }

  @override
  void writeOutput(String portId, Object? value) {
    _require(portId, PortKind.data, 'emit');
    writes[PortRef(_plan.node.id, portId)] = value;
  }

  @override
  void scheduleFlow(String portId) {
    _require(portId, PortKind.control, 'flow');
    if (!flowed.contains(portId)) flowed.add(portId);
  }

  void _require(String portId, PortKind kind, String what) {
    final port = _run.ports[PortRef(_plan.node.id, portId)];
    if (port == null) {
      throw ArgumentError.value(
        portId,
        'portId',
        '${_plan.node.id} has no port to $what from',
      );
    }
    if (port.kind != kind || port.isInput) {
      throw ArgumentError.value(
        portId,
        'portId',
        '$what needs a ${kind.name} output; ${_plan.node.id}.$portId is a '
            '${port.kind.name} ${port.direction.name}',
      );
    }
  }
}
