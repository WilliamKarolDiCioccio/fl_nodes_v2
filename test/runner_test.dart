import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fl_nodes_v2/fl_nodes_v2.dart';

void main() {
  const control = PortKind.control;

  NodePort controlIn([String id = 'in']) =>
      NodePort.input(id: id, kind: control);
  NodePort controlOut([String id = 'out']) =>
      NodePort.output(id: id, kind: control);

  GraphNode node(String id, String type, List<NodePort> ports) => GraphNode(
    id: id,
    type: type,
    position: Offset.zero,
    width: 100,
    height: 50,
    ports: ports,
  );

  NodeConnection wire(
    String id,
    String fromNode,
    String fromPort,
    String toNode,
    String toPort,
  ) => NodeConnection(
    id: id,
    from: PortRef(fromNode, fromPort),
    to: PortRef(toNode, toPort),
  );

  /// A node that flows straight through, recording that it ran.
  NodePrototype step(
    String type, {
    NodeExecutor? onExecute,
    bool pure = true,
  }) => NodePrototype(type: type, onExecute: onExecute, pure: pure);

  NodeEditorController controllerWith(
    List<GraphNode> nodes,
    List<NodeConnection> connections,
    List<NodePrototype> prototypes, {
    bool allowSelfConnections = false,
  }) {
    final controller = NodeEditorController(
      graph: NodeGraph(nodes: nodes, connections: connections),
      prototypes: NodePrototypeRegistry(prototypes),
      allowSelfConnections: allowSelfConnections,
    );
    addTearDown(controller.dispose);
    return controller;
  }

  group('control flow', () {
    test('a chain runs in order', () async {
      final controller = controllerWith(
        <GraphNode>[
          node('a', 'pass', <NodePort>[controlOut()]),
          node('b', 'pass', <NodePort>[controlIn(), controlOut()]),
          node('c', 'pass', <NodePort>[controlIn()]),
        ],
        <NodeConnection>[
          wire('1', 'a', 'out', 'b', 'in'),
          wire('2', 'b', 'out', 'c', 'in'),
        ],
        <NodePrototype>[step('pass')],
      );

      final run = await controller.runner.run();

      expect(run.succeeded, isTrue);
      expect(run.trace, <String>['a', 'b', 'c']);
      expect(
        controller.runner.stateOf('c'),
        NodeRunState.done,
        reason: 'the state survives the run, for a UI to paint',
      );
    });

    test('a node with no executor passes the flow through', () async {
      final controller = controllerWith(
        <GraphNode>[
          node('a', 'pass', <NodePort>[controlOut()]),
          node('b', 'unknown', <NodePort>[controlIn(), controlOut()]),
          node('c', 'pass', <NodePort>[controlIn()]),
        ],
        <NodeConnection>[
          wire('1', 'a', 'out', 'b', 'in'),
          wire('2', 'b', 'out', 'c', 'in'),
        ],
        <NodePrototype>[step('pass')],
      );

      final run = await controller.runner.run();

      expect(
        run.trace,
        <String>['a', 'b', 'c'],
        reason: 'a node with no prototype at all still hands the flow on',
      );
    });

    test('two control outputs and no executor stops, and says why', () async {
      final controller = controllerWith(
        <GraphNode>[
          node('a', 'fork', <NodePort>[controlOut('l'), controlOut('r')]),
          node('l', 'pass', <NodePort>[controlIn()]),
          node('r', 'pass', <NodePort>[controlIn()]),
        ],
        <NodeConnection>[
          wire('1', 'a', 'l', 'l', 'in'),
          wire('2', 'a', 'r', 'r', 'in'),
        ],
        <NodePrototype>[step('pass')],
      );

      final run = await controller.runner.run();

      expect(run.trace, <String>['a']);
      expect(
        run.diagnostics.map((d) => d.issue),
        contains(GraphRunIssue.ambiguousFlow),
        reason: 'guessing a branch would silently turn an if/else into a fork',
      );
    });

    test('branches run depth first', () async {
      final controller = controllerWith(
        <GraphNode>[
          node('fork', 'fork', <NodePort>[controlOut('l'), controlOut('r')]),
          node('l1', 'pass', <NodePort>[controlIn(), controlOut()]),
          node('l2', 'pass', <NodePort>[controlIn()]),
          node('r1', 'pass', <NodePort>[controlIn()]),
        ],
        <NodeConnection>[
          wire('1', 'fork', 'l', 'l1', 'in'),
          wire('2', 'fork', 'r', 'r1', 'in'),
          wire('3', 'l1', 'out', 'l2', 'in'),
        ],
        <NodePrototype>[
          step('pass'),
          step('fork', onExecute: (c) async => c.flowAll(<String>['l', 'r'])),
        ],
      );

      final run = await controller.runner.run();

      expect(
        run.trace,
        <String>['fork', 'l1', 'l2', 'r1'],
        reason:
            'a branch runs to its end before its sibling starts; breadth '
            'first would interleave l1, r1, l2',
      );
    });

    test('a fan-out into a shared node runs it twice', () async {
      final controller = controllerWith(
        <GraphNode>[
          node('fork', 'fork', <NodePort>[controlOut('l'), controlOut('r')]),
          node('join', 'pass', <NodePort>[controlIn()]),
        ],
        <NodeConnection>[
          wire('1', 'fork', 'l', 'join', 'in'),
          wire('2', 'fork', 'r', 'join', 'in'),
        ],
        <NodePrototype>[
          step('pass'),
          step('fork', onExecute: (c) async => c.flowAll(<String>['l', 'r'])),
        ],
      );

      final run = await controller.runner.run();

      expect(
        run.trace,
        <String>['fork', 'join', 'join'],
        reason: 'control flow is a pulse: one turn per token, no implicit join',
      );
      expect(run.runCounts['join'], 2);
      expect(
        run.diagnostics.map((d) => d.issue),
        contains(GraphRunIssue.reentered),
      );
    });

    test('a condition takes one branch and the other never runs', () async {
      final controller = controllerWith(
        <GraphNode>[
          node('pick', 'pick', <NodePort>[controlOut('yes'), controlOut('no')]),
          node('yes', 'pass', <NodePort>[controlIn()]),
          node('no', 'pass', <NodePort>[controlIn()]),
        ],
        <NodeConnection>[
          wire('1', 'pick', 'yes', 'yes', 'in'),
          wire('2', 'pick', 'no', 'no', 'in'),
        ],
        <NodePrototype>[
          step('pass'),
          step('pick', onExecute: (c) async => c.flow('yes')),
        ],
      );

      final run = await controller.runner.run();

      expect(run.trace, <String>['pick', 'yes']);
      expect(controller.runner.stateOf('no'), NodeRunState.idle);
    });

    test('a node is told which control input the flow arrived on', () async {
      final seen = <String?>[];
      final controller = controllerWith(
        <GraphNode>[
          node('head', 'pick', <NodePort>[
            controlOut('left'),
            controlOut('right'),
          ]),
          node('both', 'watch', <NodePort>[controlIn('a'), controlIn('b')]),
        ],
        <NodeConnection>[
          wire('1', 'head', 'left', 'both', 'a'),
          wire('2', 'head', 'right', 'both', 'b'),
        ],
        <NodePrototype>[
          step(
            'pick',
            onExecute: (c) async => c.flowAll(<String>['left', 'right']),
          ),
          step('watch', onExecute: (c) async => seen.add(c.enteredVia)),
        ],
      );

      await controller.runner.run();

      expect(
        seen,
        <String?>['a', 'b'],
        reason:
            "a loop's continue and break are one node doing opposite things, "
            'so which wire arrived is the only thing that can tell them apart',
      );
    });

    test('a root and a pulled node arrived through nothing', () async {
      String? atRoot;
      String? atPulled;
      final controller = controllerWith(
        <GraphNode>[
          node('root', 'root', <NodePort>[controlOut()]),
          node('value', 'value', <NodePort>[NodePort.output(id: 'v')]),
          node('sink', 'sink', <NodePort>[
            controlIn(),
            NodePort.input(id: 'v'),
          ]),
        ],
        <NodeConnection>[
          wire('1', 'root', 'out', 'sink', 'in'),
          wire('2', 'value', 'v', 'sink', 'v'),
        ],
        <NodePrototype>[
          step(
            'root',
            onExecute: (c) async {
              atRoot = c.enteredVia;
              c.flow('out');
            },
          ),
          step(
            'value',
            onExecute: (c) async {
              atPulled = c.enteredVia;
              c.emit('v', 1);
            },
          ),
          step('sink'),
        ],
      );

      await controller.runner.run();

      expect(atRoot, isNull, reason: 'nothing flowed into the start of a run');
      expect(
        atPulled,
        isNull,
        reason:
            'a pulled node was asked what it holds, not sent anywhere; naming '
            'the port that wanted it would read as a control arrival',
      );
    });
  });

  group('data flow', () {
    /// `value` emits a field; `sink` records what reached it.
    List<NodePrototype> valueAndSink({int? evaluations, bool pure = true}) {
      var count = 0;
      return <NodePrototype>[
        NodePrototype(
          type: 'value',
          pure: pure,
          onExecute: (context) async {
            count++;
            if (evaluations != null) {
              // The closure is how a test observes re-evaluation.
              context.state['n'] = count;
            }
            context.emit('out', context.fieldOr<String>('text', ''));
          },
        ),
        step('sink'),
      ];
    }

    test('a pure data node is pulled by its consumer', () async {
      final controller = controllerWith(
        <GraphNode>[
          GraphNode(
            id: 'v',
            type: 'value',
            position: Offset.zero,
            data: const <String, Object?>{'text': 'hello'},
            ports: const <NodePort>[NodePort.output(id: 'out')],
          ),
          node('s', 'sink', <NodePort>[
            controlOut(),
            const NodePort.input(id: 'value'),
          ]),
        ],
        <NodeConnection>[wire('1', 'v', 'out', 's', 'value')],
        valueAndSink(),
      );

      final run = await controller.runner.run();

      expect(run.trace, <String>['v', 's'], reason: 'the pull comes first');
      expect(run.valueAt(const PortRef('v', 'out')), 'hello');
    });

    test('an unwired data input reads as absent, not as null', () async {
      String? seen;
      var had = true;
      final controller = controllerWith(
        <GraphNode>[
          node('s', 'sink', <NodePort>[
            controlOut(),
            const NodePort.input(id: 'value'),
          ]),
        ],
        const <NodeConnection>[],
        <NodePrototype>[
          NodePrototype(
            type: 'sink',
            onExecute: (context) async {
              had = context.hasInput('value');
              seen =
                  context.input<String>('value') ??
                  context.fieldOr<String>('fallback', 'from the field');
            },
          ),
        ],
      );

      await controller.runner.run();

      expect(had, isFalse);
      expect(seen, 'from the field');
    });

    test('two wires into one input take the lower connection id', () async {
      Object? seen;
      List<Object?> all = const <Object?>[];
      final controller = controllerWith(
        <GraphNode>[
          GraphNode(
            id: 'a',
            type: 'value',
            position: Offset.zero,
            data: const <String, Object?>{'text': 'first'},
            ports: const <NodePort>[NodePort.output(id: 'out')],
          ),
          GraphNode(
            id: 'b',
            type: 'value',
            position: Offset.zero,
            data: const <String, Object?>{'text': 'second'},
            ports: const <NodePort>[NodePort.output(id: 'out')],
          ),
          node('s', 'sink', <NodePort>[
            controlOut(),
            const NodePort.input(id: 'value'),
          ]),
        ],
        <NodeConnection>[
          wire('c2', 'b', 'out', 's', 'value'),
          wire('c1', 'a', 'out', 's', 'value'),
        ],
        <NodePrototype>[
          ...valueAndSink(),
          NodePrototype(
            type: 'sink',
            onExecute: (context) async {
              seen = context.input<String>('value');
              all = context.inputs('value');
            },
          ),
        ],
      );

      final run = await controller.runner.run();

      expect(
        seen,
        'first',
        reason:
            'c1 sorts before c2, so the answer does not depend on which '
            'wire was drawn first',
      );
      expect(all, <Object?>['first', 'second']);
      expect(
        run.diagnostics.map((d) => d.issue),
        contains(GraphRunIssue.multipleInputs),
      );
    });

    test('a data cycle fails, naming the path', () async {
      final controller = controllerWith(
        <GraphNode>[
          node('a', 'value', <NodePort>[
            const NodePort.input(id: 'in'),
            const NodePort.output(id: 'out'),
          ]),
          node('b', 'value', <NodePort>[
            const NodePort.input(id: 'in'),
            const NodePort.output(id: 'out'),
          ]),
          node('s', 'sink', <NodePort>[
            controlOut(),
            const NodePort.input(id: 'value'),
          ]),
        ],
        <NodeConnection>[
          wire('1', 'a', 'out', 'b', 'in'),
          wire('2', 'b', 'out', 'a', 'in'),
          wire('3', 'a', 'out', 's', 'value'),
        ],
        <NodePrototype>[...valueAndSink()],
      );

      final run = await controller.runner.run();

      expect(run.succeeded, isFalse);
      final error = run.error! as GraphRunException;
      expect(error.nodeIds, containsAll(<String>['a', 'b']));
    });

    test('a pure data diamond is not mistaken for a cycle', () async {
      var evaluations = 0;
      final controller = controllerWith(
        <GraphNode>[
          node('x', 'root', <NodePort>[const NodePort.output(id: 'out')]),
          node('y', 'mid', <NodePort>[
            const NodePort.input(id: 'in'),
            const NodePort.output(id: 'out'),
          ]),
          node('w', 'mid', <NodePort>[
            const NodePort.input(id: 'in'),
            const NodePort.output(id: 'out'),
          ]),
          node('s', 'sink', <NodePort>[
            controlOut(),
            const NodePort.input(id: 'l'),
            const NodePort.input(id: 'r'),
          ]),
        ],
        <NodeConnection>[
          wire('1', 'x', 'out', 'y', 'in'),
          wire('2', 'x', 'out', 'w', 'in'),
          wire('3', 'y', 'out', 's', 'l'),
          wire('4', 'w', 'out', 's', 'r'),
        ],
        <NodePrototype>[
          NodePrototype(
            type: 'root',
            onExecute: (context) async {
              evaluations++;
              context.emit('out', 1);
            },
          ),
          NodePrototype(
            type: 'mid',
            onExecute: (context) async =>
                context.emit('out', context.inputOr<int>('in', 0) + 1),
          ),
          step('sink'),
        ],
      );

      final run = await controller.runner.run();

      expect(run.succeeded, isTrue);
      expect(run.valueAt(const PortRef('y', 'out')), 2);
      expect(
        evaluations,
        1,
        reason:
            'reached twice in one pull, evaluated once — the memo is what '
            'keeps a data diamond from going exponential',
      );
    });

    test('an impure data node is evaluated on every pull', () async {
      var evaluations = 0;
      final controller = controllerWith(
        <GraphNode>[
          node('n', 'now', <NodePort>[const NodePort.output(id: 'out')]),
          node('a', 'sink', <NodePort>[
            controlOut(),
            const NodePort.input(id: 'value'),
          ]),
          node('b', 'sink', <NodePort>[
            controlIn(),
            const NodePort.input(id: 'value'),
          ]),
        ],
        <NodeConnection>[
          wire('1', 'n', 'out', 'a', 'value'),
          wire('2', 'n', 'out', 'b', 'value'),
          wire('3', 'a', 'out', 'b', 'in'),
        ],
        <NodePrototype>[
          NodePrototype(
            type: 'now',
            pure: false,
            onExecute: (context) async => context.emit('out', ++evaluations),
          ),
          step('sink'),
        ],
      );

      await controller.runner.run();

      expect(
        evaluations,
        2,
        reason: 'pure: false is what a node that reads the world sets',
      );
    });

    test(
      'a data node re-evaluates when something it reads is rewritten',
      () async {
        var doubles = 0;
        final controller = controllerWith(
          <GraphNode>[
            node('loop', 'loop', <NodePort>[
              controlIn(),
              controlOut('body'),
              const NodePort.output(id: 'i'),
            ]),
            node('twice', 'twice', <NodePort>[
              const NodePort.input(id: 'in'),
              const NodePort.output(id: 'out'),
            ]),
            node('body', 'body', <NodePort>[
              controlIn(),
              controlOut(),
              const NodePort.input(id: 'value'),
            ]),
          ],
          <NodeConnection>[
            wire('1', 'loop', 'body', 'body', 'in'),
            wire('2', 'loop', 'i', 'twice', 'in'),
            wire('3', 'twice', 'out', 'body', 'value'),
            wire('4', 'body', 'out', 'loop', 'in'),
          ],
          <NodePrototype>[
            NodePrototype(
              type: 'loop',
              onExecute: (context) async {
                final i = (context.state['i'] as int? ?? 0) + 1;
                context.state['i'] = i;
                context.emit('i', i);
                if (i <= 3) context.flow('body');
              },
            ),
            NodePrototype(
              type: 'twice',
              onExecute: (context) async {
                doubles++;
                context.emit('out', context.inputOr<int>('in', 0) * 2);
              },
            ),
            step('body'),
          ],
        );

        // The loop is a closed control cycle, so it has to be named as the
        // starting point; nothing about it looks like an entry.
        final run = await controller.runner.run(from: <String>['loop']);

        expect(run.succeeded, isTrue);
        expect(
          doubles,
          3,
          reason:
              'the memo is invalid once loop.i is rewritten, so the doubler '
              'runs again on each iteration rather than serving a stale 2',
        );
        expect(run.valueAt(const PortRef('twice', 'out')), 6);
      },
    );

    test('a read from a control node that has not run says so', () async {
      final controller = controllerWith(
        <GraphNode>[
          node('a', 'sink', <NodePort>[
            controlOut(),
            const NodePort.input(id: 'value'),
          ]),
          node('b', 'later', <NodePort>[
            controlIn(),
            const NodePort.output(id: 'out'),
          ]),
        ],
        <NodeConnection>[
          wire('1', 'a', 'out', 'b', 'in'),
          wire('2', 'b', 'out', 'a', 'value'),
        ],
        <NodePrototype>[
          step('sink'),
          step('later', onExecute: (c) async => c.emit('out', 'late')),
        ],
      );

      final run = await controller.runner.run();

      expect(
        run.diagnostics.map((d) => d.issue),
        contains(GraphRunIssue.producerNotRun),
        reason:
            'silently reading null from a node that runs later is the '
            'kind of thing nobody ever works out on their own',
      );
    });
  });

  group('bounds and failure', () {
    test('a loop with a counter ends by itself', () async {
      final controller = controllerWith(
        <GraphNode>[
          node('loop', 'loop', <NodePort>[controlIn(), controlOut()]),
        ],
        const <NodeConnection>[],
        <NodePrototype>[
          NodePrototype(
            type: 'loop',
            onExecute: (context) async {
              final n = (context.state['n'] as int? ?? 0) + 1;
              context.state['n'] = n;
              if (n < 3) context.flow('out');
            },
          ),
        ],
        allowSelfConnections: true,
      );
      controller.connect(
        const PortRef('loop', 'out'),
        const PortRef('loop', 'in'),
      );

      final run = await controller.runner.run(from: <String>['loop']);

      expect(run.runCounts['loop'], 3);
      expect(run.succeeded, isTrue);
    });

    test('a runaway loop stops at the budget and names the busiest', () async {
      final controller = controllerWith(
        <GraphNode>[
          node('a', 'pass', <NodePort>[controlIn(), controlOut()]),
          node('b', 'pass', <NodePort>[controlIn(), controlOut()]),
        ],
        <NodeConnection>[
          wire('1', 'a', 'out', 'b', 'in'),
          wire('2', 'b', 'out', 'a', 'in'),
        ],
        <NodePrototype>[step('pass')],
      );

      final run = await controller.runner.run(
        from: <String>['a'],
        maxSteps: 20,
      );

      expect(run.succeeded, isFalse);
      final error = run.error! as GraphRunException;
      expect(error.message, contains('budget'));
      expect(error.nodeIds.join(' '), contains('a x'));
    });

    test('a graph that is only a cycle reports no entry point', () async {
      final controller = controllerWith(
        <GraphNode>[
          node('a', 'pass', <NodePort>[controlIn(), controlOut()]),
          node('b', 'pass', <NodePort>[controlIn(), controlOut()]),
        ],
        <NodeConnection>[
          wire('1', 'a', 'out', 'b', 'in'),
          wire('2', 'b', 'out', 'a', 'in'),
        ],
        <NodePrototype>[step('pass')],
      );

      final run = await controller.runner.run();

      expect(run.trace, isEmpty);
      expect(
        run.diagnostics.single.issue,
        GraphRunIssue.noEntryPoint,
        reason: 'an empty trace with no explanation looks like a broken button',
      );
    });

    test('a graph with no control ports evaluates its data sinks', () async {
      final controller = controllerWith(
        <GraphNode>[
          GraphNode(
            id: 'v',
            type: 'value',
            position: Offset.zero,
            data: const <String, Object?>{'text': 'x'},
            ports: const <NodePort>[NodePort.output(id: 'out')],
          ),
          node('u', 'upper', <NodePort>[
            const NodePort.input(id: 'in'),
            const NodePort.output(id: 'out'),
          ]),
        ],
        <NodeConnection>[wire('1', 'v', 'out', 'u', 'in')],
        <NodePrototype>[
          NodePrototype(
            type: 'value',
            onExecute: (c) async =>
                c.emit('out', c.fieldOr<String>('text', '')),
          ),
          NodePrototype(
            type: 'upper',
            onExecute: (c) async =>
                c.emit('out', c.inputOr<String>('in', '').toUpperCase()),
          ),
        ],
      );

      final run = await controller.runner.run();

      expect(run.valueAt(const PortRef('u', 'out')), 'X');
    });

    test('an executor that throws stops the run and names the node', () async {
      final controller = controllerWith(
        <GraphNode>[
          node('a', 'ok', <NodePort>[controlOut()]),
          node('b', 'bad', <NodePort>[controlIn(), controlOut()]),
          node('c', 'ok', <NodePort>[controlIn()]),
        ],
        <NodeConnection>[
          wire('1', 'a', 'out', 'b', 'in'),
          wire('2', 'b', 'out', 'c', 'in'),
        ],
        <NodePrototype>[
          step('ok'),
          step('bad', onExecute: (c) async => throw StateError('nope')),
        ],
      );

      final run = await controller.runner.run();

      expect(run.succeeded, isFalse);
      expect(run.failedNodeId, 'b');
      expect(run.error, isA<StateError>());
      expect(run.stackTrace, isNotNull);
      expect(run.trace, <String>['a'], reason: 'c never got its turn');
      expect(controller.runner.stateOf('b'), NodeRunState.failed);
    });

    test('emitting on a port that is not a data output throws', () async {
      final controller = controllerWith(
        <GraphNode>[
          node('a', 'bad', <NodePort>[controlOut()]),
        ],
        const <NodeConnection>[],
        <NodePrototype>[step('bad', onExecute: (c) async => c.emit('out', 1))],
      );

      final run = await controller.runner.run();

      expect(run.error, isA<ArgumentError>());
      expect(
        run.error.toString(),
        contains('out'),
        reason:
            'a mistyped port id that quietly did nothing would be the '
            'worst kind of bug to chase',
      );
    });

    test('a context kept past its turn refuses to write', () async {
      NodeExecutionContext? stashed;
      final controller = controllerWith(
        <GraphNode>[
          node('a', 'keep', <NodePort>[const NodePort.output(id: 'out')]),
          node('s', 'sink', <NodePort>[
            controlOut(),
            const NodePort.input(id: 'value'),
          ]),
        ],
        <NodeConnection>[wire('1', 'a', 'out', 's', 'value')],
        <NodePrototype>[
          step('keep', onExecute: (c) async => stashed = c),
          step('sink'),
        ],
      );

      await controller.runner.run();

      expect(
        () => stashed!.emit('out', 'too late'),
        throwsStateError,
        reason:
            'an unawaited future inside an executor would otherwise '
            "scribble into a later node's inputs",
      );
    });
  });

  group('the run itself', () {
    test('a second run while one is in flight is refused', () async {
      final gate = Completer<void>();
      final controller = controllerWith(
        <GraphNode>[
          node('a', 'slow', <NodePort>[controlOut()]),
        ],
        const <NodeConnection>[],
        <NodePrototype>[step('slow', onExecute: (c) async => gate.future)],
      );

      final first = controller.runner.run();
      expect(controller.runner.isRunning, isTrue);
      expect(controller.runner.run, throwsStateError);

      gate.complete();
      await first;
      expect(controller.runner.isRunning, isFalse);
    });

    test('cancel stops the run and comes back as a result', () async {
      final gate = Completer<void>();
      final controller = controllerWith(
        <GraphNode>[
          node('a', 'slow', <NodePort>[controlOut()]),
          node('b', 'pass', <NodePort>[controlIn()]),
        ],
        <NodeConnection>[wire('1', 'a', 'out', 'b', 'in')],
        <NodePrototype>[
          step('slow', onExecute: (c) async => gate.future),
          step('pass'),
        ],
      );

      final running = controller.runner.run();
      controller.runner.cancel();
      gate.complete();
      final run = await running;

      expect(run.cancelled, isTrue);
      expect(run.succeeded, isFalse);
      expect(run.error, isNull, reason: 'cancelling is not a failure');
      expect(
        run.trace,
        isEmpty,
        reason: 'the turn it was waiting on is dropped',
      );

      controller.runner.cancel();
    });

    test('running does not touch the document', () async {
      final controller = controllerWith(
        <GraphNode>[
          node('a', 'pass', <NodePort>[controlOut()]),
          node('b', 'pass', <NodePort>[controlIn()]),
        ],
        <NodeConnection>[wire('1', 'a', 'out', 'b', 'in')],
        <NodePrototype>[step('pass')],
      );
      final graph = controller.graph;
      final revision = controller.revision;

      await controller.runner.run();

      expect(identical(controller.graph, graph), isTrue);
      expect(controller.revision, revision);
      expect(controller.history.canUndo, isFalse);
      expect(
        controller.project.isDirty,
        isFalse,
        reason: 'a run is not an edit, and nothing about it belongs in a file',
      );
    });

    test('from runs exactly what it names', () async {
      final controller = controllerWith(
        <GraphNode>[
          node('a', 'pass', <NodePort>[controlOut()]),
          node('b', 'pass', <NodePort>[controlIn(), controlOut()]),
          node('c', 'pass', <NodePort>[controlIn()]),
        ],
        <NodeConnection>[
          wire('1', 'a', 'out', 'b', 'in'),
          wire('2', 'b', 'out', 'c', 'in'),
        ],
        <NodePrototype>[step('pass')],
      );

      final run = await controller.runner.run(from: <String>['b']);

      expect(run.trace, <String>['b', 'c']);
    });
  });
}
