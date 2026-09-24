import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fl_nodes_v2/fl_nodes_v2.dart';

/// A drag held against the edge of the canvas scrolls it, so a target off
/// screen can be reached without letting go to zoom out. Wires and nodes
/// both; and the drag keeps up with the camera, so what is held stays under
/// the pointer while the canvas moves beneath it — exactly, unless snapping
/// is on, where the node advances a cell at a time and slips under the
/// pointer between them.
void main() {
  final NodeEditorTheme theme = NodeEditorTheme.dark();

  final NodePrototypeRegistry prototypes = NodePrototypeRegistry(
    const <NodePrototype>[
      NodePrototype(
        type: 'step',
        label: 'Step',
        ports: <PortFamily>[
          StaticPortFamily(
            id: 'io',
            ports: <NodePort>[
              NodePort.input(id: 'in'),
              NodePort.output(id: 'out'),
            ],
          ),
        ],
      ),
    ],
  );

  const Size canvas = Size(800, 600);

  /// Boots the editor at a known size with `a` on screen and `b` well past
  /// the right edge, where only a scroll can bring it into view.
  Future<NodeEditorController> boot(
    WidgetTester tester, {
    EdgeScrollConfig? edgeScroll = const EdgeScrollConfig(),
  }) async {
    final controller = NodeEditorController(
      graph: NodeGraph(
        nodes: <GraphNode>[
          GraphNode(
            id: 'a',
            type: 'step',
            position: const Offset(100, 100),
            width: 160,
            height: 90,
          ),
          GraphNode(
            id: 'b',
            type: 'step',
            position: const Offset(1200, 100),
            width: 160,
            height: 90,
          ),
        ],
      ),
      prototypes: prototypes,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox.fromSize(
              size: canvas,
              child: NodeEditor(
                controller: controller,
                theme: theme,
                edgeScroll: edgeScroll,
                nodeBuilder: (context, graphNode, state) =>
                    const ColoredBox(color: Color(0xFF2A2E38)),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  Offset canvasOrigin(WidgetTester tester) =>
      tester.getTopLeft(find.byType(NodeEditor));

  Offset screenPoint(
    WidgetTester tester,
    NodeEditorController controller,
    Offset scenePoint,
  ) => canvasOrigin(tester) + controller.camera.viewport.toScreen(scenePoint);

  /// Presses at [from] and walks the pointer to [to] in a few steps, leaving
  /// the button held.
  Future<TestGesture> dragTo(
    WidgetTester tester,
    Offset from,
    Offset to,
  ) async {
    final gesture = await tester.startGesture(
      from,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 16));
    for (var step = 1; step <= 4; step++) {
      await gesture.moveTo(Offset.lerp(from, to, step / 4)!);
      await tester.pump(const Duration(milliseconds: 16));
    }
    return gesture;
  }

  /// Lets the ticker run for [frames] frames with the pointer where it is.
  Future<void> hold(WidgetTester tester, int frames) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  /// A point [inset] pixels in from the right edge of the canvas, at the
  /// height of node `a`.
  Offset nearRightEdge(WidgetTester tester, double inset) =>
      canvasOrigin(tester) + Offset(canvas.width - inset, 145);

  group('EdgeScrollConfig.velocityAt', () {
    const config = EdgeScrollConfig(margin: 40, speed: 600);
    const size = Size(800, 600);

    test('is zero anywhere inside the margins', () {
      expect(config.velocityAt(const Offset(400, 300), size), Offset.zero);
      expect(config.velocityAt(const Offset(40, 40), size), Offset.zero);
      expect(config.velocityAt(const Offset(760, 560), size), Offset.zero);
    });

    test('points at the near edge and ramps up toward it', () {
      expect(
        config.velocityAt(const Offset(20, 300), size),
        const Offset(-300, 0),
        reason: 'halfway into the left margin pulls at half speed',
      );
      expect(
        config.velocityAt(const Offset(0, 300), size),
        const Offset(-600, 0),
      );
      expect(
        config.velocityAt(const Offset(790, 300), size),
        const Offset(450, 0),
      );
      expect(
        config.velocityAt(const Offset(400, 10), size),
        const Offset(0, -450),
      );
      expect(
        config.velocityAt(const Offset(400, 600), size),
        const Offset(0, 600),
      );
    });

    test('holds full speed past the edge', () {
      expect(
        config.velocityAt(const Offset(-500, 300), size),
        const Offset(-600, 0),
        reason: 'a drag that has left the window keeps scrolling',
      );
      expect(
        config.velocityAt(const Offset(2000, 1000), size),
        const Offset(600, 600),
      );
    });

    test('a corner pulls on both axes', () {
      expect(
        config.velocityAt(const Offset(0, 0), size),
        const Offset(-600, -600),
      );
    });

    test('is zero with no speed or no canvas', () {
      expect(
        const EdgeScrollConfig(speed: 0).velocityAt(const Offset(0, 0), size),
        Offset.zero,
      );
      expect(config.velocityAt(const Offset(0, 0), Size.zero), Offset.zero);
    });
  });

  testWidgets('a node held against the edge scrolls the canvas and keeps '
      'moving with it', (tester) async {
    final controller = await boot(tester);
    final start = screenPoint(tester, controller, const Offset(180, 145));

    final gesture = await dragTo(tester, start, nearRightEdge(tester, 10));
    final offsetBefore = controller.camera.viewport.offset;
    final nodeBefore = controller.graph.nodes['a']!.position;

    await hold(tester, 10);

    final offsetAfter = controller.camera.viewport.offset;
    expect(
      offsetAfter.dx,
      lessThan(offsetBefore.dx),
      reason: 'the content moves left to reveal what lies to the right',
    );
    expect(
      offsetAfter.dy,
      offsetBefore.dy,
      reason: 'no vertical pull mid-height',
    );

    final nodeAfter = controller.graph.nodes['a']!.position;
    expect(
      nodeAfter.dx,
      greaterThan(nodeBefore.dx),
      reason:
          'the pointer has not moved but the scene under it has, and '
          'the node stays under the pointer',
    );
    // Scene units: the camera moved by `offset` screen pixels at scale 1,
    // and the node went the other way by the same amount.
    expect(
      nodeAfter.dx - nodeBefore.dx,
      moreOrLessEquals(offsetBefore.dx - offsetAfter.dx, epsilon: 0.01),
    );

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('a snapped node keeps scrolling: a no-op frame is not a stop', (
    tester,
  ) async {
    final controller = await boot(tester);
    controller.snapToGrid = true;
    final start = screenPoint(tester, controller, const Offset(180, 145));

    final gesture = await dragTo(tester, start, nearRightEdge(tester, 10));
    final offsetBefore = controller.camera.viewport.offset;
    final nodeBefore = controller.graph.nodes['a']!.position;

    await hold(tester, 20);

    expect(
      controller.camera.viewport.offset.dx,
      lessThan(offsetBefore.dx),
      reason:
          'most frames of a snapped drag move the node nowhere, and a frame '
          'that changes nothing must not be read as the drag being over',
    );
    final nodeAfter = controller.graph.nodes['a']!.position;
    expect(nodeAfter.dx, greaterThan(nodeBefore.dx));
    expect(
      nodeAfter.dx % theme.gridSpacing,
      0,
      reason: 'and it advances in whole cells rather than trailing the camera',
    );

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('a wire held against the edge reaches a node that was off '
      'screen', (tester) async {
    final controller = await boot(tester);
    final from = screenPoint(
      tester,
      controller,
      controller.layout.portPosition(const PortRef('a', 'out'))!,
    );
    // Past the edge: full speed, the way a pointer dragged out of the window
    // arrives.
    final gesture = await dragTo(tester, from, nearRightEdge(tester, -20));

    // `b` sits at x 1200..1360 in scene space and the pointer at screen x
    // 820, so the camera has to come back by roughly 400 px before the
    // pointer is over the card — and would carry it past again if held on,
    // exactly as a real drag does. Hold until it arrives, within a bound.
    String? under() => controller.layout
        .nodeAt(
          controller.camera.viewport.toScene(
            nearRightEdge(tester, -20) - canvasOrigin(tester),
          ),
        )
        ?.id;
    for (var frame = 0; frame < 120 && under() != 'b'; frame++) {
      await hold(tester, 1);
    }
    expect(
      under(),
      'b',
      reason: 'the canvas scrolled until the far node came under the pointer',
    );

    await gesture.up();
    await tester.pumpAndSettle();

    expect(
      controller.graph.connections.values.map(
        (c) => (c.from.nodeId, c.to.nodeId),
      ),
      contains(('a', 'b')),
      reason: 'the wire landed on the node the scroll brought into reach',
    );
  });

  testWidgets('the scroll stops when the pointer leaves the margin', (
    tester,
  ) async {
    final controller = await boot(tester);
    final start = screenPoint(tester, controller, const Offset(180, 145));

    final gesture = await dragTo(tester, start, nearRightEdge(tester, 10));
    await hold(tester, 5);
    expect(controller.camera.viewport.offset, isNot(Offset.zero));

    await gesture.moveTo(canvasOrigin(tester) + const Offset(400, 300));
    await tester.pump(const Duration(milliseconds: 16));
    final parked = controller.camera.viewport.offset;
    await hold(tester, 10);
    expect(controller.camera.viewport.offset, parked);

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('the scroll stops when the drag ends', (tester) async {
    final controller = await boot(tester);
    final start = screenPoint(tester, controller, const Offset(180, 145));

    final gesture = await dragTo(tester, start, nearRightEdge(tester, 10));
    await hold(tester, 5);
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 16));

    final released = controller.camera.viewport.offset;
    await hold(tester, 10);
    expect(
      controller.camera.viewport.offset,
      released,
      reason: 'nothing is being held, so nothing is pulling',
    );
  });

  testWidgets('Escape cancels a wire and its scroll with it', (tester) async {
    final controller = await boot(tester);
    final from = screenPoint(
      tester,
      controller,
      controller.layout.portPosition(const PortRef('a', 'out'))!,
    );
    final gesture = await dragTo(tester, from, nearRightEdge(tester, 10));
    await hold(tester, 5);
    expect(controller.camera.viewport.offset, isNot(Offset.zero));

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 16));
    final cancelled = controller.camera.viewport.offset;

    // The button is still down and the pointer still at the edge.
    await gesture.moveBy(const Offset(0, 1));
    await hold(tester, 10);
    expect(
      controller.camera.viewport.offset,
      cancelled,
      reason: 'a cancelled wire must not leave the camera drifting',
    );

    await gesture.up();
    await tester.pumpAndSettle();
    expect(controller.graph.connections, isEmpty);
  });

  testWidgets('off with edgeScroll: null', (tester) async {
    final controller = await boot(tester, edgeScroll: null);
    final start = screenPoint(tester, controller, const Offset(180, 145));

    final gesture = await dragTo(tester, start, nearRightEdge(tester, 10));
    await hold(tester, 10);
    expect(controller.camera.viewport.offset, Offset.zero);

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('a waypoint handle held against the edge scrolls too', (
    tester,
  ) async {
    final controller = await boot(tester);
    final id = controller.connect(
      const PortRef('a', 'out'),
      const PortRef('b', 'in'),
    )!;
    controller.setConnectionWaypoints(id, const <Offset>[Offset(400, 145)]);
    await tester.pumpAndSettle();

    final handle = screenPoint(tester, controller, const Offset(400, 145));
    final gesture = await dragTo(tester, handle, nearRightEdge(tester, 10));
    final before = controller.graph.connections[id]!.waypoints.single;
    await hold(tester, 10);

    expect(controller.camera.viewport.offset.dx, lessThan(0));
    expect(
      controller.graph.connections[id]!.waypoints.single.dx,
      greaterThan(before.dx),
      reason: 'the handle stays under a pointer the scene moved beneath',
    );

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('a group dragged by its handle scrolls too', (tester) async {
    final controller = await boot(tester);
    controller.selection.selectNodes(<String>['a']);
    controller.groupSelection();
    controller.selection.clear();
    await tester.pumpAndSettle();

    final handle = tester.getCenter(find.byIcon(Icons.drag_indicator));
    final gesture = await dragTo(tester, handle, nearRightEdge(tester, 10));
    final before = controller.graph.nodes['a']!.position;
    await hold(tester, 10);

    expect(controller.camera.viewport.offset.dx, lessThan(0));
    expect(controller.graph.nodes['a']!.position.dx, greaterThan(before.dx));

    await gesture.up();
    await tester.pumpAndSettle();
  });
}
