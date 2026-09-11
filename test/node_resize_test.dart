import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fl_nodes_v2/fl_nodes_v2.dart';

/// Dragging a node's right edge changes its width — and only its width.
///
/// A prototype opts in with `resizable`; the floor is its `defaultWidth` and
/// the strip along the right edge is `NodeView.resizeGripWidth` wide. The
/// gesture is the node's own pan recogniser deciding what a press meant from
/// where it landed, so nothing here contests the arena.
void main() {
  final NodePrototypeRegistry prototypes = NodePrototypeRegistry(
    const <NodePrototype>[
      NodePrototype(
        type: 'card',
        label: 'Card',
        defaultWidth: 200,
        resizable: true,
        maxWidth: 400,
        ports: <PortFamily>[
          StaticPortFamily(
            id: 'io',
            ports: <NodePort>[
              NodePort.input(id: 'in', anchor: Offset(0, 0.5)),
              NodePort.output(id: 'out', anchor: Offset(1, 0.5)),
            ],
          ),
        ],
      ),
      NodePrototype(type: 'fixed', label: 'Fixed', defaultWidth: 200),
    ],
  );

  Future<NodeEditorController> boot(
    WidgetTester tester, {
    String type = 'card',
    double snap = 0,
  }) async {
    final controller = NodeEditorController(prototypes: prototypes);
    addTearDown(controller.dispose);
    controller.addNode(
      prototypes.instantiate(type, id: 'a', position: const Offset(100, 100)),
    );
    controller.history.clear();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 800,
              height: 600,
              child: NodeEditor(
                controller: controller,
                theme: NodeEditorTheme.dark().copyWith(snapToGrid: snap),
                nodeBuilder: (context, node, state) => const SizedBox(
                  height: 120,
                  child: ColoredBox(color: Color(0xFF2A2E38)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  Offset screen(WidgetTester tester, NodeEditorController c, Offset scene) =>
      tester.getTopLeft(find.byType(NodeEditor)) +
      c.camera.viewport.toScreen(scene);

  /// A mouse drag from [from] by [by], in scene units.
  Future<void> drag(
    WidgetTester tester,
    NodeEditorController controller,
    Offset from,
    Offset by,
  ) async {
    final gesture = await tester.startGesture(
      screen(tester, controller, from),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveBy(by);
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('dragging the right edge widens the node, in one undo step', (
    tester,
  ) async {
    final controller = await boot(tester);
    final node = controller.graph.node('a')!;
    expect(node.width, 200);

    // Two pixels inside the right edge, in the grip.
    await drag(tester, controller, const Offset(298, 160), const Offset(60, 0));

    final widened = controller.graph.node('a')!;
    expect(widened.width, 260);
    expect(widened.position, const Offset(100, 100), reason: 'not moved');
    expect(
      controller.layout.portPosition(const PortRef('a', 'out'))!.dx,
      360,
      reason: 'the output handle follows the edge — anchors are fractions',
    );

    controller.history.undo();
    expect(controller.graph.node('a')!.width, 200, reason: 'one step back');
    expect(controller.history.canUndo, isFalse);
  });

  testWidgets('a press off the grip still moves the node', (tester) async {
    final controller = await boot(tester);

    await drag(tester, controller, const Offset(200, 160), const Offset(60, 0));

    final moved = controller.graph.node('a')!;
    expect(moved.position, const Offset(160, 100));
    expect(moved.width, 200);
  });

  testWidgets('the width is clamped to the prototype', (tester) async {
    final controller = await boot(tester);

    await drag(
      tester,
      controller,
      const Offset(298, 160),
      const Offset(-150, 0),
    );
    expect(
      controller.graph.node('a')!.width,
      200,
      reason: 'no narrower than the width it was designed at',
    );

    await drag(
      tester,
      controller,
      const Offset(298, 160),
      const Offset(900, 0),
    );
    expect(controller.graph.node('a')!.width, 400, reason: 'nor past maxWidth');
  });

  testWidgets('the width snaps to the grid the positions snap to', (
    tester,
  ) async {
    final controller = await boot(tester, snap: 20);

    await drag(tester, controller, const Offset(298, 160), const Offset(53, 0));
    expect(controller.graph.node('a')!.width, 260);
  });

  testWidgets('a prototype that did not opt in has no grip', (tester) async {
    final controller = await boot(tester, type: 'fixed');

    await drag(tester, controller, const Offset(298, 160), const Offset(60, 0));

    final node = controller.graph.node('a')!;
    expect(node.width, 200);
    expect(node.position, const Offset(160, 100), reason: 'the edge drags');
  });

  testWidgets('the grip shows a resize cursor', (tester) async {
    final controller = await boot(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);

    await mouse.moveTo(screen(tester, controller, const Offset(298, 160)));
    await tester.pump();
    expect(
      RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
      SystemMouseCursors.resizeLeftRight,
    );

    await mouse.moveTo(screen(tester, controller, const Offset(200, 160)));
    await tester.pump();
    expect(
      RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
      SystemMouseCursors.grab,
    );
  });
}
