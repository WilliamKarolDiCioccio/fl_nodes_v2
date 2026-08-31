import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fl_nodes_v2/fl_nodes_v2.dart';

/// Neither the canvas scale recogniser nor a node's pan recogniser filters by
/// button, so every drag path had to be told that the secondary button is for
/// menus. These pin the three things a right-press used to do by accident —
/// and, just as important, that the left button still does all three.
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

  Future<NodeEditorController> boot(
    WidgetTester tester, {
    void Function(PortRef source, Offset scenePosition)? onConnectionDropped,
  }) async {
    final controller = NodeEditorController(
      graph: NodeGraph(
        nodes: <GraphNode>[
          node('a', const Offset(120, 120)),
          node('b', const Offset(420, 120)),
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
            onConnectionDropped: onConnectionDropped,
            nodeBuilder: (context, graphNode, state) =>
                const ColoredBox(color: Color(0xFF2A2E38)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  Offset screenPoint(
    WidgetTester tester,
    NodeEditorController controller,
    Offset scenePoint,
  ) =>
      tester.getTopLeft(find.byType(NodeEditor)) +
      controller.camera.viewport.toScreen(scenePoint);

  Offset portPoint(
    WidgetTester tester,
    NodeEditorController controller,
    PortRef ref,
  ) => screenPoint(tester, controller, controller.layout.portPosition(ref)!);

  /// A press, a travel and a release, all on one button.
  Future<void> dragWith(
    WidgetTester tester,
    Offset from,
    Offset to, {
    required int buttons,
  }) async {
    // Mouse, not the default touch: a touch drag always pans by design, so a
    // touch gesture could never tell the two buttons apart in the first place.
    final gesture = await tester.startGesture(
      from,
      buttons: buttons,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 16));
    // Several steps, not one jump: the scale recogniser has to win the arena
    // before it reports a start, and the marquee has a slop threshold.
    for (var step = 1; step <= 4; step++) {
      await gesture.moveTo(Offset.lerp(from, to, step / 4)!);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('right-dragging off a port creates no wire', (tester) async {
    var dropped = 0;
    final controller = await boot(
      tester,
      onConnectionDropped: (_, _) => dropped++,
    );

    await dragWith(
      tester,
      portPoint(tester, controller, const PortRef('a', 'out')),
      portPoint(tester, controller, const PortRef('b', 'in')),
      buttons: kSecondaryButton,
    );

    expect(controller.graph.connections, isEmpty);
    expect(
      dropped,
      0,
      reason:
          'a right-press must not start a wire at all, so there is no '
          'in-flight connection left to drop',
    );
  });

  testWidgets('left-dragging off a port still creates a wire', (tester) async {
    final controller = await boot(tester);

    await dragWith(
      tester,
      portPoint(tester, controller, const PortRef('a', 'out')),
      portPoint(tester, controller, const PortRef('b', 'in')),
      buttons: kPrimaryButton,
    );

    expect(controller.graph.connections, hasLength(1));
  });

  testWidgets('right-dragging the canvas sweeps no marquee', (tester) async {
    final controller = await boot(tester);

    await dragWith(
      tester,
      screenPoint(tester, controller, const Offset(60, 400)),
      screenPoint(tester, controller, const Offset(640, 430)),
      buttons: kSecondaryButton,
    );

    expect(controller.selection.nodeIds, isEmpty);
  });

  testWidgets('right-dragging the canvas does not pan it', (tester) async {
    final controller = await boot(tester);
    final before = controller.camera.viewport.offset;

    await dragWith(
      tester,
      screenPoint(tester, controller, const Offset(60, 400)),
      screenPoint(tester, controller, const Offset(640, 430)),
      buttons: kSecondaryButton,
    );

    expect(
      controller.camera.viewport.offset,
      before,
      reason:
          'a blocked press must not fall through to the pan branch, which '
          'is what leaving it in the neutral state would have done',
    );
  });

  testWidgets('left-dragging the canvas still sweeps a marquee', (
    tester,
  ) async {
    final controller = await boot(tester);

    await dragWith(
      tester,
      screenPoint(tester, controller, const Offset(60, 60)),
      screenPoint(tester, controller, const Offset(640, 430)),
      buttons: kPrimaryButton,
    );

    expect(controller.selection.nodeIds, <String>{'a', 'b'});
  });

  testWidgets('right-dragging a node neither moves it nor records history', (
    tester,
  ) async {
    final controller = await boot(tester);
    final before = controller.graph.nodes['a']!.position;

    await dragWith(
      tester,
      screenPoint(tester, controller, const Offset(200, 165)),
      screenPoint(tester, controller, const Offset(320, 260)),
      buttons: kSecondaryButton,
    );

    expect(controller.graph.nodes['a']!.position, before);
    expect(
      controller.history.canUndo,
      isFalse,
      reason: 'the drag opened no transaction, so there is nothing to undo',
    );
  });

  testWidgets('left-dragging a node still moves it', (tester) async {
    final controller = await boot(tester);
    final before = controller.graph.nodes['a']!.position;

    await dragWith(
      tester,
      screenPoint(tester, controller, const Offset(200, 165)),
      screenPoint(tester, controller, const Offset(320, 260)),
      buttons: kPrimaryButton,
    );

    expect(controller.graph.nodes['a']!.position, isNot(before));
    expect(controller.history.canUndo, isTrue);
  });
}
