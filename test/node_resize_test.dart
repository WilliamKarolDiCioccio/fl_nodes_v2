import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fl_nodes_v2/fl_nodes_v2.dart';
import 'package:fl_nodes_v2/src/widgets/corner_grip.dart';
import 'package:fl_nodes_v2/src/widgets/node_view.dart';

/// Dragging a node's bottom-right corner resizes it.
///
/// A prototype opts in with `resizable`; the width's floor is its
/// `defaultWidth`, the height's floor is whatever the node already is, and
/// the corner is `NodeView.resizeGripSize` square — the minimap's grip. The
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
        maxHeight: 300,
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

    // A few pixels inside the bottom-right corner, in the grip.
    await drag(tester, controller, const Offset(296, 216), const Offset(60, 0));

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

  testWidgets('dragging the corner down adds room below the rows', (
    tester,
  ) async {
    final controller = await boot(tester);
    final before = controller.layout.portPosition(const PortRef('a', 'out'))!;
    expect(controller.layout.sizeOf(controller.graph.node('a')!).height, 120);

    await drag(tester, controller, const Offset(296, 216), const Offset(0, 80));

    final stretched = controller.graph.node('a')!;
    expect(stretched.minHeight, 200, reason: 'a floor, not a height');
    expect(stretched.height, isNull, reason: 'its content still decides');
    expect(controller.layout.sizeOf(stretched).height, 200);
    expect(
      tester.getSize(find.byType(NodeView)).height,
      200,
      reason: 'and the box on screen is the stretched one',
    );

    // Back up past where it started: the floor goes, rather than staying as
    // a number that happens to equal the natural height.
    await drag(
      tester,
      controller,
      const Offset(296, 296),
      const Offset(0, -120),
    );
    expect(controller.graph.node('a')!.minHeight, isNull);
    expect(controller.layout.sizeOf(controller.graph.node('a')!).height, 120);
    expect(
      controller.layout.portPosition(const PortRef('a', 'out')),
      before,
      reason: 'nothing about the ports was ever touched',
    );
  });

  testWidgets('a declared height keeps its handles on their rows when '
      'stretched', (tester) async {
    final controller = NodeEditorController(
      prototypes: NodePrototypeRegistry(const <NodePrototype>[
        NodePrototype(
          type: 'fixed',
          resizable: true,
          defaultWidth: 200,
          ports: <PortFamily>[
            StaticPortFamily(
              id: 'io',
              ports: <NodePort>[
                NodePort.output(id: 'out', anchor: Offset(1, 0.75)),
              ],
            ),
          ],
        ),
      ]),
    );
    addTearDown(controller.dispose);
    controller.addNode(
      GraphNode(
        id: 'a',
        type: 'fixed',
        position: const Offset(100, 100),
        width: 200,
        height: 100,
      ),
    );
    controller.updateNode('a', (node) => node.withMinHeight(300));

    expect(controller.layout.sizeOf(controller.graph.node('a')!).height, 300);
    expect(
      controller.layout.portPosition(const PortRef('a', 'out')),
      const Offset(300, 175),
      reason:
          'a fraction of the declared height, not of the box: the row the '
          'wire was landed on has not moved, only the room below it has',
    );
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
      const Offset(296, 216),
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
      const Offset(296, 216),
      const Offset(900, 0),
    );
    expect(controller.graph.node('a')!.width, 400, reason: 'nor past maxWidth');
  });

  testWidgets('the width snaps to the grid the positions snap to', (
    tester,
  ) async {
    final controller = await boot(tester, snap: 20);

    await drag(
      tester,
      controller,
      const Offset(296, 216),
      const Offset(53, 47),
    );
    expect(controller.graph.node('a')!.width, 260);
    expect(controller.graph.node('a')!.minHeight, 160);
  });

  testWidgets('a prototype that did not opt in has no grip', (tester) async {
    final controller = await boot(tester, type: 'fixed');

    await drag(tester, controller, const Offset(296, 216), const Offset(60, 0));

    final node = controller.graph.node('a')!;
    expect(node.width, 200);
    expect(node.position, const Offset(160, 100), reason: 'the edge drags');
  });

  testWidgets('the grip shows a resize cursor', (tester) async {
    final controller = await boot(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);

    await mouse.moveTo(screen(tester, controller, const Offset(296, 216)));
    await tester.pump();
    expect(
      RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
      SystemMouseCursors.resizeUpLeftDownRight,
    );
    expect(
      find.byType(CornerGrip),
      findsOneWidget,
      reason: 'the minimap\'s grip, drawn while the node is under the pointer',
    );

    await mouse.moveTo(screen(tester, controller, const Offset(200, 160)));
    await tester.pump();
    expect(
      RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
      SystemMouseCursors.grab,
    );
  });

  test('the floor travels in the document, and only once it is set', () {
    NodeGraph graph(double? floor) => NodeGraph(
      nodes: <GraphNode>[
        GraphNode(
          id: 'a',
          position: Offset.zero,
          height: 100,
          minHeight: floor,
        ),
      ],
    );
    const codec = NodeGraphCodec();

    final plain = codec.encode(GraphDocument(graph: graph(null)));
    expect(jsonEncode(plain), isNot(contains('minHeight')));
    expect(codec.decode(plain).graph.node('a')!.minHeight, isNull);

    final stretched = codec.encode(GraphDocument(graph: graph(240)));
    expect(jsonEncode(stretched), contains('minHeight'));
    expect(codec.decode(stretched).graph.node('a')!.minHeight, 240);
  });
}
