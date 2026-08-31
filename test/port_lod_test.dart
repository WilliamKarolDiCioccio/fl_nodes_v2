import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fl_nodes_v2/fl_nodes_v2.dart';

/// Handles are painted, so hiding them when they get too small is a condition
/// inside one painter rather than widgets coming and going. These pin the rule
/// that comes with that: drawn and grabbable are the same threshold, so there
/// is never an invisible dot that still starts a wire.
void main() {
  final NodeEditorTheme theme = NodeEditorTheme.dark();

  GraphNode node(String id, Offset position) => GraphNode(
    id: id,
    position: position,
    width: 160,
    height: 90,
    ports: const <NodePort>[
      NodePort.input(id: 'in'),
      NodePort.output(id: 'out'),
    ],
  );

  NodeEditorController pair() => NodeEditorController(
    graph: NodeGraph(
      nodes: <GraphNode>[
        node('a', const Offset(200, 200)),
        node('b', const Offset(600, 200)),
      ],
    ),
  );

  Future<NodeEditorController> boot(WidgetTester tester, double scale) async {
    final controller = pair();
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
    controller.camera.setScale(scale);
    await tester.pumpAndSettle();
    return controller;
  }

  Offset screenPortPoint(
    WidgetTester tester,
    NodeEditorController controller,
    PortRef ref,
  ) =>
      tester.getTopLeft(find.byType(NodeEditor)) +
      controller.camera.viewport.toScreen(controller.layout.portPosition(ref)!);

  Future<void> dragBetweenPorts(
    WidgetTester tester,
    NodeEditorController controller,
  ) async {
    final start = screenPortPoint(
      tester,
      controller,
      const PortRef('a', 'out'),
    );
    final end = screenPortPoint(tester, controller, const PortRef('b', 'in'));
    await tester.dragFrom(start, end - start);
    await tester.pumpAndSettle();
  }

  testWidgets('a handle wires up at a zoom where it is drawn', (tester) async {
    final controller = await boot(tester, 1);

    await dragBetweenPorts(tester, controller);

    expect(controller.graph.connections, hasLength(1));
  });

  testWidgets('below the threshold a handle is neither drawn nor grabbable', (
    tester,
  ) async {
    final controller = await boot(tester, theme.portMinScale / 2);

    await dragBetweenPorts(tester, controller);

    expect(
      controller.graph.connections,
      isEmpty,
      reason:
          'the whole target is a pixel across here; a dot nobody can see must '
          'not quietly start a wire either',
    );
  });

  testWidgets('the press falls through to the node underneath instead', (
    tester,
  ) async {
    final controller = await boot(tester, theme.portMinScale / 2);
    final before = controller.graph.node('a')!.position;

    // Just inside the right edge, where 'a.out' is drawn when there is room
    // to draw it. A point exactly on the edge is outside the box.
    final start =
        screenPortPoint(tester, controller, const PortRef('a', 'out')) -
        const Offset(4, 0);
    await tester.dragFrom(start, const Offset(40, 30));
    await tester.pumpAndSettle();

    expect(
      controller.graph.node('a')!.position,
      isNot(before),
      reason: 'with no handle to grab, dragging the node is what is left',
    );
  });

  testWidgets('the threshold is a repaint, not a rebuild', (tester) async {
    var bodyBuilds = 0;
    final controller = pair();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NodeEditor(
            controller: controller,
            theme: theme,
            nodeBuilder: (context, graphNode, state) {
              bodyBuilds++;
              return const ColoredBox(color: Color(0xFF2A2E38));
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    bodyBuilds = 0;
    // Straight across the threshold in both directions.
    for (final scale in <double>[
      theme.portMinScale * 1.1,
      theme.portMinScale * 0.9,
      theme.portMinScale * 1.1,
    ]) {
      controller.camera.setScale(scale);
      await tester.pumpAndSettle();
    }

    expect(
      bodyBuilds,
      0,
      reason:
          'this is the whole point of painting handles: crossing the level of '
          'detail threshold must not touch the widget tree, or it stutters '
          'exactly where the user is already moving',
    );
  });
}
