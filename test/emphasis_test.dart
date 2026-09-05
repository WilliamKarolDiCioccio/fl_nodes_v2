import 'package:fl_nodes_v2/fl_nodes_v2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const Color _red = Color(0xFFFF0000);
const Color _blue = Color(0xFF0000FF);

void main() {
  GraphNode node(String id, {Offset position = Offset.zero}) => GraphNode(
    id: id,
    position: position,
    width: 100,
    height: 50,
    ports: const <NodePort>[
      NodePort.input(id: 'in'),
      NodePort.output(id: 'out'),
    ],
  );

  NodeEditorController controllerWith(
    List<GraphNode> nodes, {
    List<NodeConnection> connections = const <NodeConnection>[],
  }) {
    final created = NodeEditorController(
      graph: NodeGraph(nodes: nodes, connections: connections),
    );
    addTearDown(created.dispose);
    return created;
  }

  group('the focus is a value, and changing it is not an edit', () {
    test('assigning notifies once and moves the revision', () {
      final controller = controllerWith(<GraphNode>[node('a')]);
      var notifications = 0;
      controller.addListener(() => notifications++);
      final before = controller.emphasis.revision;

      controller.emphasis.value = const GraphEmphasis(
        nodes: <String, Color?>{'a': _red},
      );

      expect(notifications, 1);
      expect(controller.emphasis.revision, greaterThan(before));
    });

    test('an equal focus notifies nobody', () {
      final controller = controllerWith(<GraphNode>[node('a')]);
      controller.emphasis.value = const GraphEmphasis(
        nodes: <String, Color?>{'a': _red},
      );

      var notifications = 0;
      controller.addListener(() => notifications++);
      final revision = controller.emphasis.revision;

      // A host that recomputes the same answer on every tick must cost no
      // repaint, or a focus becomes a per-frame expense.
      controller.emphasis.value = const GraphEmphasis(
        nodes: <String, Color?>{'a': _red},
      );

      expect(notifications, 0);
      expect(controller.emphasis.revision, revision);
    });

    test('it records no history and dirties no document', () {
      final controller = controllerWith(<GraphNode>[node('a')]);
      controller.emphasis.value = const GraphEmphasis(
        nodes: <String, Color?>{'a': _red},
      );

      expect(
        controller.history.canUndo,
        isFalse,
        reason:
            'a focus is where the user is looking, not something they '
            'authored — an undo that cleared it would fight the edit it was '
            'meant to reverse',
      );
      expect(controller.project.isDirty, isFalse);
    });

    test('a guard that refuses everything cannot refuse a focus', () {
      final controller = controllerWith(<GraphNode>[node('a')])
        ..guard = (_) => false;

      controller.emphasis.value = const GraphEmphasis(
        nodes: <String, Color?>{'a': _red},
      );

      expect(
        controller.emphasis.lifts('a'),
        isTrue,
        reason:
            'a read-only canvas is exactly where a focus is most wanted, '
            'and it never goes through _mutate',
      );
    });

    test(
      'the lifted snapshot is the same instance until the focus changes',
      () {
        final controller = controllerWith(<GraphNode>[node('a')]);
        controller.emphasis.value = const GraphEmphasis(
          nodes: <String, Color?>{'a': _red},
        );

        final first = controller.emphasis.lifted;
        expect(identical(controller.emphasis.lifted, first), isTrue);

        controller.emphasis.value = const GraphEmphasis(
          nodes: <String, Color?>{'a': _blue},
        );
        expect(identical(controller.emphasis.lifted, first), isFalse);
      },
    );
  });

  group('a focus follows the graph', () {
    test('deleting a lifted node takes its halo with it', () {
      final controller = controllerWith(<GraphNode>[node('a'), node('b')]);
      controller.emphasis.value = const GraphEmphasis(
        nodes: <String, Color?>{'a': _red, 'b': _blue},
      );

      controller.removeNodes(<String>['a']);

      expect(controller.emphasis.value.nodes.keys, <String>['b']);
      expect(
        controller.emphasis.lifts('a'),
        isFalse,
        reason:
            'nothing else would drop it: a focus is not in the document, '
            'so the halo would be painted around nothing',
      );
    });

    test('an undo that removes a lifted node prunes it too', () {
      final controller = controllerWith(<GraphNode>[node('a')]);
      controller.addNode(node('b', position: const Offset(200, 0)));
      controller.emphasis.value = const GraphEmphasis(
        nodes: <String, Color?>{'a': _red, 'b': _blue},
      );

      controller.history.undo();

      expect(
        controller.emphasis.value.nodes.keys,
        <String>['a'],
        reason:
            'undo does not pass through _mutate, so the prune has to be '
            'on the jump as well',
      );
    });

    test('removing a connection drops its tint', () {
      final controller = controllerWith(
        <GraphNode>[node('a'), node('b', position: const Offset(200, 0))],
        connections: <NodeConnection>[
          const NodeConnection(
            id: 'wire',
            from: PortRef('a', 'out'),
            to: PortRef('b', 'in'),
          ),
        ],
      );
      controller.emphasis.value = const GraphEmphasis(
        connections: <String, Color?>{'wire': _red},
      );

      controller.removeConnections(<String>['wire']);

      expect(controller.emphasis.value.connections, isEmpty);
    });

    test('an edit that touches nothing lifted leaves the revision alone', () {
      final controller = controllerWith(<GraphNode>[node('a'), node('b')]);
      controller.emphasis.value = const GraphEmphasis(
        nodes: <String, Color?>{'a': _red},
      );
      final revision = controller.emphasis.revision;

      controller.moveNodes(<String, Offset>{'b': const Offset(10, 10)});

      expect(controller.emphasis.revision, revision);
    });
  });

  group('a focus decides paint order, and picking agrees with it', () {
    test('a lifted node is painted last', () {
      final controller = controllerWith(<GraphNode>[node('a'), node('b')]);
      controller.emphasis.value = const GraphEmphasis(
        nodes: <String, Color?>{'a': _red},
      );

      expect(controller.layout.nodesInPaintOrder.last.id, 'a');
    });

    test('two overlapping nodes: the lifted one takes the click', () {
      final controller = controllerWith(<GraphNode>[
        node('under'),
        node('over'),
      ]);
      controller.emphasis.value = const GraphEmphasis(
        nodes: <String, Color?>{'under': _red},
      );

      expect(controller.layout.nodeAt(const Offset(50, 25))?.id, 'under');
    });

    test('a selected node does not float above the scrim', () {
      final controller = controllerWith(<GraphNode>[
        node('lit'),
        node('picked'),
      ]);
      controller.emphasis.value = const GraphEmphasis(
        nodes: <String, Color?>{'lit': _red},
      );
      controller.selection.selectNode('picked');

      expect(
        controller.layout.nodesInPaintOrder.last.id,
        'lit',
        reason:
            'a focus wins outright — a union of the two would let one '
            'stray click undo the whole effect',
      );
      expect(controller.layout.nodeAt(const Offset(50, 25))?.id, 'lit');
    });

    test('with no focus the selection ranks as it always did', () {
      final controller = controllerWith(<GraphNode>[node('a'), node('b')]);
      controller.selection.selectNode('a');

      expect(controller.layout.nodesInPaintOrder.last.id, 'a');
    });
  });

  group('a handle under the scrim is neither drawn nor grabbable', () {
    test('portAt refuses a dimmed node', () {
      final controller = controllerWith(<GraphNode>[
        node('lit'),
        node('dim', position: const Offset(300, 0)),
      ]);
      final handle = controller.layout.portPosition(
        const PortRef('dim', 'out'),
      )!;
      expect(controller.layout.portAt(handle, radius: 11), isNotNull);

      controller.emphasis.value = const GraphEmphasis(
        nodes: <String, Color?>{'lit': _red},
      );

      expect(
        controller.layout.portAt(handle, radius: 11),
        isNull,
        reason:
            'one condition gates drawing and hitting alike — an invisible '
            'dot that still starts a wire is worse than one plainly absent',
      );
      expect(
        controller.layout.portAt(
          controller.layout.portPosition(const PortRef('lit', 'out'))!,
          radius: 11,
        ),
        isNotNull,
      );
    });

    test('clearing the focus gives every handle back', () {
      final controller = controllerWith(<GraphNode>[
        node('lit'),
        node('dim', position: const Offset(300, 0)),
      ]);
      controller.emphasis.value = const GraphEmphasis(
        nodes: <String, Color?>{'lit': _red},
      );
      controller.emphasis.clear();

      expect(
        controller.layout.portAt(
          controller.layout.portPosition(const PortRef('dim', 'out'))!,
          radius: 11,
        ),
        isNotNull,
      );
    });
  });

  group('GraphEmphasis is a value', () {
    test('equal maps compare equal whatever order they were built in', () {
      const a = GraphEmphasis(
        nodes: <String, Color?>{'x': _red, 'y': null},
        connections: <String, Color?>{'w': _blue},
      );
      const b = GraphEmphasis(
        nodes: <String, Color?>{'y': null, 'x': _red},
        connections: <String, Color?>{'w': _blue},
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('a different tint is a different focus', () {
      expect(
        const GraphEmphasis(nodes: <String, Color?>{'x': _red}),
        isNot(const GraphEmphasis(nodes: <String, Color?>{'x': _blue})),
      );
    });

    test('nodes and connections are independent', () {
      // The shape the app needs: a helper node the flow merely passes through
      // stays dimmed while the wires either side of it are lifted, so the run
      // reads as continuous across a card that is not part of it.
      const focus = GraphEmphasis(
        nodes: <String, Color?>{'prose': _red},
        connections: <String, Color?>{'in': _red, 'out': _red},
      );
      expect(focus.nodes.containsKey('helper'), isFalse);
      expect(focus.connections.length, 2);
      expect(focus.isNotEmpty, isTrue);
    });

    test('none is empty', () {
      expect(GraphEmphasis.none.isEmpty, isTrue);
    });
  });

  group('the layer is only there when it is wanted', () {
    final NodeEditorTheme theme = NodeEditorTheme.dark();

    Future<NodeEditorController> boot(WidgetTester tester) async {
      final controller = NodeEditorController(
        graph: NodeGraph(
          nodes: <GraphNode>[
            node('a', position: const Offset(200, 200)),
            node('b', position: const Offset(500, 200)),
          ],
          connections: <NodeConnection>[
            const NodeConnection(
              id: 'wire',
              from: PortRef('a', 'out'),
              to: PortRef('b', 'in'),
            ),
          ],
        ),
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NodeEditor(
              controller: controller,
              theme: theme,
              nodeBuilder: (context, graphNode, state) =>
                  const ColoredBox(color: Color(0xFF2A2E38)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return controller;
    }

    Finder emphasisLayer() => find.byWidgetPredicate(
      (widget) => widget is CustomPaint && widget.painter is EmphasisPainter,
    );

    testWidgets('no focus, no layer at all', (tester) async {
      await boot(tester);
      expect(
        emphasisLayer(),
        findsNothing,
        reason:
            'the whole feature has to cost nothing until somebody asks '
            'for it',
      );
    });

    testWidgets('a focus adds exactly one layer, and clearing takes it away', (
      tester,
    ) async {
      final controller = await boot(tester);

      controller.emphasis.value = const GraphEmphasis(
        nodes: <String, Color?>{'a': _red},
        connections: <String, Color?>{'wire': _red},
      );
      await tester.pumpAndSettle();
      expect(emphasisLayer(), findsOneWidget);

      controller.emphasis.clear();
      await tester.pumpAndSettle();
      expect(emphasisLayer(), findsNothing);
    });

    testWidgets('the editor is not rebuilt by its host to show one', (
      tester,
    ) async {
      // The whole reason the focus lives on the controller: the editor already
      // listens, so a host never has to hand it a fresh nodeBuilder — which is
      // the one thing this package asks a host not to do.
      var builds = 0;
      final controller = NodeEditorController(
        graph: NodeGraph(nodes: <GraphNode>[node('a')]),
      );
      addTearDown(controller.dispose);
      Widget builder(BuildContext context, GraphNode node, NodeRenderState _) {
        builds++;
        return const ColoredBox(color: Color(0xFF2A2E38));
      }

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NodeEditor(
              controller: controller,
              theme: theme,
              nodeBuilder: builder,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final before = builds;

      controller.emphasis.value = const GraphEmphasis(
        nodes: <String, Color?>{'a': _red},
      );
      await tester.pumpAndSettle();

      expect(
        builds,
        before,
        reason:
            'a halo is painted behind the card, so the card itself has '
            'nothing to say about it',
      );
    });
  });
}
