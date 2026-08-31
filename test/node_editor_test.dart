import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fl_nodes_v2/fl_nodes_v2.dart';

void main() {
  GraphNode node(
    String id, {
    required Offset position,
    double? height = 60,
    List<NodePort> ports = const <NodePort>[
      NodePort.input(id: 'in'),
      NodePort.output(id: 'out'),
    ],
  }) => GraphNode(
    id: id,
    position: position,
    width: 140,
    height: height,
    ports: ports,
  );

  Widget harness(
    NodeEditorController controller, {
    NodeWidgetBuilder? nodeBuilder,
    Size size = const Size(800, 600),
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: NodeEditor(
              controller: controller,
              theme: NodeEditorTheme.dark(),
              nodeBuilder:
                  nodeBuilder ??
                  (context, graphNode, state) => ColoredBox(
                    key: ValueKey<String>('body_${graphNode.id}'),
                    color: state.isSelected
                        ? const Color(0xFF335599)
                        : const Color(0xFF2A2E38),
                  ),
            ),
          ),
        ),
      ),
    );
  }

  /// Where a port handle sits on screen.
  ///
  /// Handles are painted rather than built, so there is no widget to find:
  /// this asks the same geometry the painter draws from and the picker reads.
  Offset portPoint(
    WidgetTester tester,
    NodeEditorController controller,
    String nodeId,
    String portId,
  ) {
    final scene = controller.layout.portPosition(PortRef(nodeId, portId));
    expect(scene, isNotNull, reason: 'no port $nodeId.$portId to aim at');
    return tester.getTopLeft(find.byType(NodeEditor)) +
        controller.camera.viewport.toScreen(scene!);
  }

  /// Whether a port exists *and* can be picked where it is drawn — the
  /// painted equivalent of finding its handle in the tree.
  bool portIsLive(
    NodeEditorController controller,
    String nodeId,
    String portId,
  ) {
    final ref = PortRef(nodeId, portId);
    final scene = controller.layout.portPosition(ref);
    if (scene == null) return false;
    return controller.layout.portAt(
          scene,
          radius: NodeEditorTheme.dark().portHitRadius,
        ) ==
        ref;
  }

  testWidgets('renders a node body per node', (tester) async {
    final controller = NodeEditorController(
      graph: NodeGraph(
        nodes: <GraphNode>[
          node('a', position: const Offset(60, 60)),
          node('b', position: const Offset(400, 200)),
        ],
      ),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(harness(controller));

    expect(find.byKey(const ValueKey<String>('body_a')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('body_b')), findsOneWidget);
  });

  testWidgets('places a node body at its scene position', (tester) async {
    final controller = NodeEditorController(
      graph: NodeGraph(
        nodes: <GraphNode>[node('a', position: const Offset(60, 90))],
      ),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(harness(controller));

    expect(
      tester.getTopLeft(find.byKey(const ValueKey<String>('body_a'))),
      const Offset(60, 90),
    );
  });

  testWidgets('tapping a node selects it, tapping the canvas clears', (
    tester,
  ) async {
    final controller = NodeEditorController(
      graph: NodeGraph(
        nodes: <GraphNode>[node('a', position: const Offset(60, 60))],
      ),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(harness(controller));

    await tester.tap(find.byKey(const ValueKey<String>('body_a')));
    await tester.pump();
    expect(controller.selection.nodeIds, <String>{'a'});

    await tester.tapAt(const Offset(600, 500));
    await tester.pump();
    expect(controller.selection.nodeIds, isEmpty);
  });

  testWidgets('dragging a node body moves it', (tester) async {
    final controller = NodeEditorController(
      graph: NodeGraph(
        nodes: <GraphNode>[node('a', position: const Offset(60, 60))],
      ),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(harness(controller));
    await tester.drag(
      find.byKey(const ValueKey<String>('body_a')),
      const Offset(50, 30),
    );
    await tester.pump();

    expect(controller.graph.node('a')!.position, const Offset(110, 90));
    expect(
      controller.history.canUndo,
      isTrue,
      reason: 'drag should be one undo step',
    );

    controller.history.undo();
    expect(controller.graph.node('a')!.position, const Offset(60, 60));
  });

  testWidgets('a node drag scales with the viewport zoom', (tester) async {
    final controller = NodeEditorController(
      graph: NodeGraph(
        nodes: <GraphNode>[node('a', position: const Offset(60, 60))],
      ),
      viewport: const ViewportTransform(scale: 2),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(harness(controller));
    // 100 screen pixels at 2x is 50 scene units.
    await tester.drag(
      find.byKey(const ValueKey<String>('body_a')),
      const Offset(100, 0),
    );
    await tester.pump();

    expect(controller.graph.node('a')!.position, const Offset(110, 60));
  });

  testWidgets('dragging between ports creates a connection', (tester) async {
    final controller = NodeEditorController(
      graph: NodeGraph(
        nodes: <GraphNode>[
          node('a', position: const Offset(60, 60)),
          node('b', position: const Offset(400, 200)),
        ],
      ),
    );
    addTearDown(controller.dispose);
    NodeConnection? created;

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
                theme: NodeEditorTheme.dark(),
                onConnectionCreated: (connection) => created = connection,
                nodeBuilder: (context, graphNode, state) => ColoredBox(
                  key: ValueKey<String>('body_${graphNode.id}'),
                  color: const Color(0xFF2A2E38),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final start = portPoint(tester, controller, 'a', 'out');
    final end = portPoint(tester, controller, 'b', 'in');
    await tester.dragFrom(start, end - start);
    await tester.pump();

    expect(controller.graph.connections, hasLength(1));
    expect(created, isNotNull);
    expect(created!.from, const PortRef('a', 'out'));
    expect(created!.to, const PortRef('b', 'in'));
  });

  testWidgets('an output-to-output drag creates nothing', (tester) async {
    final controller = NodeEditorController(
      graph: NodeGraph(
        nodes: <GraphNode>[
          node('a', position: const Offset(60, 60)),
          node('b', position: const Offset(400, 200)),
        ],
      ),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(harness(controller));

    final start = portPoint(tester, controller, 'a', 'out');
    final end = portPoint(tester, controller, 'b', 'out');
    await tester.dragFrom(start, end - start);
    await tester.pump();

    expect(controller.graph.connections, isEmpty);
  });

  testWidgets('a wire dropped on empty canvas reports its source', (
    tester,
  ) async {
    final controller = NodeEditorController(
      graph: NodeGraph(
        nodes: <GraphNode>[node('a', position: const Offset(60, 60))],
      ),
    );
    addTearDown(controller.dispose);
    PortRef? droppedSource;
    Offset? droppedAt;

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
                theme: NodeEditorTheme.dark(),
                onConnectionDropped: (source, scenePosition) {
                  droppedSource = source;
                  droppedAt = scenePosition;
                },
                nodeBuilder: (context, graphNode, state) => ColoredBox(
                  key: ValueKey<String>('body_${graphNode.id}'),
                  color: const Color(0xFF2A2E38),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.dragFrom(
      portPoint(tester, controller, 'a', 'out'),
      const Offset(300, 250),
    );
    await tester.pump();

    expect(droppedSource, const PortRef('a', 'out'));
    expect(droppedAt, isNotNull);
    expect(controller.graph.connections, isEmpty);
  });

  testWidgets('dropping a wire on a node body wires its first free port', (
    tester,
  ) async {
    final controller = NodeEditorController(
      graph: NodeGraph(
        nodes: <GraphNode>[
          node('a', position: const Offset(60, 60)),
          node('b', position: const Offset(400, 200)),
        ],
      ),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(harness(controller));

    await tester.dragFrom(
      portPoint(tester, controller, 'a', 'out'),
      tester.getCenter(find.byKey(const ValueKey<String>('body_b'))) -
          portPoint(tester, controller, 'a', 'out'),
    );
    await tester.pump();

    expect(
      controller.graph.connections.values.single.to,
      const PortRef('b', 'in'),
    );
  });

  testWidgets('clicking a connection curve selects it', (tester) async {
    final controller = NodeEditorController(
      graph: NodeGraph(
        nodes: <GraphNode>[
          node('a', position: const Offset(60, 200)),
          node('b', position: const Offset(400, 200)),
        ],
        connections: const <NodeConnection>[
          NodeConnection(
            id: 'c1',
            from: PortRef('a', 'out'),
            to: PortRef('b', 'in'),
          ),
        ],
      ),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(harness(controller));

    // Both ports sit at y = 230, so the curve runs flat between them.
    await tester.tapAt(const Offset(330, 230));
    await tester.pump();

    expect(controller.selection.connectionIds, <String>{'c1'});
  });

  testWidgets('auto-height nodes report their measured size', (tester) async {
    final controller = NodeEditorController(
      graph: NodeGraph(
        nodes: <GraphNode>[
          node('a', position: const Offset(60, 60), height: null),
        ],
      ),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      harness(
        controller,
        nodeBuilder: (context, graphNode, state) => SizedBox(
          height: 123,
          child: ColoredBox(
            key: ValueKey<String>('body_${graphNode.id}'),
            color: const Color(0xFF2A2E38),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      controller.layout.sizeOf(controller.graph.node('a')!),
      const Size(140, 123),
    );
    // The output port follows the measured height to the node's mid-point.
    expect(portPoint(tester, controller, 'a', 'out'), const Offset(200, 121.5));
  });

  testWidgets('nodes outside the viewport are culled', (tester) async {
    final controller = NodeEditorController(
      graph: NodeGraph(
        nodes: <GraphNode>[
          node('near', position: const Offset(60, 60)),
          node('far', position: const Offset(5000, 5000)),
        ],
      ),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(harness(controller));

    expect(find.byKey(const ValueKey<String>('body_near')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('body_far')), findsNothing);

    controller.camera.centerOnNode('far', const Size(800, 600));
    await tester.pump();

    expect(find.byKey(const ValueKey<String>('body_far')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('body_near')), findsNothing);
  });

  testWidgets('panned-to nodes stay draggable', (tester) async {
    final controller = NodeEditorController(
      graph: NodeGraph(
        nodes: <GraphNode>[node('a', position: const Offset(2000, 1500))],
      ),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(harness(controller));
    controller.camera.centerOnNode('a', const Size(800, 600));
    await tester.pump();

    await tester.drag(
      find.byKey(const ValueKey<String>('body_a')),
      const Offset(20, 20),
    );
    await tester.pump();

    expect(controller.graph.node('a')!.position, const Offset(2020, 1520));
  });

  testWidgets('scrolling zooms around the pointer', (tester) async {
    final controller = NodeEditorController(
      graph: NodeGraph(
        nodes: <GraphNode>[node('a', position: const Offset(60, 60))],
      ),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(harness(controller));

    const focal = Offset(400, 300);
    final before = controller.camera.viewport.toScene(focal);

    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(focal));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, -120)));
    await tester.pump();

    final after = controller.camera.viewport.toScene(focal);
    expect(controller.camera.viewport.scale, greaterThan(1.0));
    expect(after.dx, closeTo(before.dx, 0.001));
    expect(after.dy, closeTo(before.dy, 0.001));
  });

  testWidgets('an unselected node drags immediately, selecting as it goes', (
    tester,
  ) async {
    final controller = NodeEditorController(
      graph: NodeGraph(
        nodes: <GraphNode>[
          node('a', position: const Offset(60, 60)),
          node('other', position: const Offset(400, 400)),
        ],
      ),
    );
    addTearDown(controller.dispose);
    controller.selection.selectNode('other');

    await tester.pumpWidget(harness(controller));

    // Frames are pumped between moves on purpose. Sending a whole drag without
    // them hides anything that breaks when the tree rebuilds mid-gesture, which
    // is exactly what selecting the node does: it reorders paint order.
    final gesture = await tester.startGesture(const Offset(130, 90));
    await tester.pump();
    for (var i = 0; i < 5; i++) {
      await gesture.moveBy(const Offset(20, 10));
      await tester.pump();
    }
    await gesture.up();
    await tester.pump();

    expect(controller.graph.node('a')!.position, const Offset(160, 110));
    expect(controller.selection.nodeIds, <String>{'a'});
    expect(controller.history.canUndo, isTrue);
  });

  testWidgets('node body state survives the selection reorder', (tester) async {
    final controller = NodeEditorController(
      graph: NodeGraph(
        nodes: <GraphNode>[
          node('a', position: const Offset(60, 60)),
          node('b', position: const Offset(400, 60)),
        ],
      ),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      harness(
        controller,
        nodeBuilder: (context, graphNode, state) =>
            _Counter(key: ValueKey<String>('counter_${graphNode.id}')),
      ),
    );

    await tester.tap(find.byKey(const ValueKey<String>('counter_a')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('counter_a')));
    await tester.pump();
    expect(find.text('a:2'), findsOneWidget);

    // Selecting 'b' pushes it above 'a' in the stack.
    controller.selection.selectNode('b');
    await tester.pump();

    expect(
      find.text('a:2'),
      findsOneWidget,
      reason: 'reordering must not rebuild node bodies from scratch',
    );
  });

  testWidgets('dragging one of several selected nodes moves them all', (
    tester,
  ) async {
    final controller = NodeEditorController(
      graph: NodeGraph(
        nodes: <GraphNode>[
          node('a', position: const Offset(60, 60)),
          node('b', position: const Offset(300, 60)),
        ],
      ),
    );
    addTearDown(controller.dispose);
    controller.selection.selectNodes(<String>['a', 'b']);

    await tester.pumpWidget(harness(controller));

    final gesture = await tester.startGesture(const Offset(130, 90));
    await tester.pump();
    for (var i = 0; i < 3; i++) {
      await gesture.moveBy(const Offset(10, 20));
      await tester.pump();
    }
    await gesture.up();
    await tester.pump();

    expect(controller.graph.node('a')!.position, const Offset(90, 120));
    expect(controller.graph.node('b')!.position, const Offset(330, 120));
  });

  testWidgets('a mouse drag on empty canvas sweeps a selection', (
    tester,
  ) async {
    final controller = NodeEditorController(
      graph: NodeGraph(
        nodes: <GraphNode>[
          node('a', position: const Offset(60, 60)),
          node('b', position: const Offset(500, 400)),
        ],
      ),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(harness(controller));
    await tester.dragFrom(
      const Offset(40, 40),
      const Offset(260, 200),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();

    expect(controller.selection.nodeIds, <String>{'a'});
    expect(
      controller.camera.viewport.offset,
      Offset.zero,
      reason: 'must not pan',
    );
  });

  testWidgets('the sweep updates the selection as it moves', (tester) async {
    final controller = NodeEditorController(
      graph: NodeGraph(
        nodes: <GraphNode>[
          node('a', position: const Offset(60, 60)),
          node('b', position: const Offset(300, 60)),
        ],
      ),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(harness(controller));

    final gesture = await tester.startGesture(
      const Offset(40, 40),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();

    await gesture.moveTo(const Offset(220, 160));
    await tester.pump();
    expect(controller.selection.nodeIds, <String>{'a'});

    await gesture.moveTo(const Offset(460, 160));
    await tester.pump();
    expect(controller.selection.nodeIds, <String>{'a', 'b'});

    // Shrinking the rectangle deselects again.
    await gesture.moveTo(const Offset(220, 160));
    await tester.pump();
    expect(controller.selection.nodeIds, <String>{'a'});

    await gesture.up();
    await tester.pump();
    expect(controller.selection.nodeIds, <String>{'a'});
  });

  testWidgets('shift adds the swept nodes to the existing selection', (
    tester,
  ) async {
    final controller = NodeEditorController(
      graph: NodeGraph(
        nodes: <GraphNode>[
          node('a', position: const Offset(60, 60)),
          node('b', position: const Offset(500, 400)),
        ],
      ),
    );
    addTearDown(controller.dispose);
    controller.selection.selectNode('b');

    await tester.pumpWidget(harness(controller));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.dragFrom(
      const Offset(40, 40),
      const Offset(260, 200),
      kind: PointerDeviceKind.mouse,
    );
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();

    expect(controller.selection.nodeIds, <String>{'a', 'b'});
  });

  testWidgets('a touch drag pans instead of selecting', (tester) async {
    final controller = NodeEditorController(
      graph: NodeGraph(
        nodes: <GraphNode>[node('a', position: const Offset(60, 60))],
      ),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(harness(controller));
    await tester.dragFrom(const Offset(600, 480), const Offset(-90, -40));
    await tester.pump();

    expect(controller.selection.nodeIds, isEmpty);
    expect(controller.camera.viewport.offset.dx, lessThan(-40));
  });

  testWidgets('a click on empty canvas does not sweep', (tester) async {
    final controller = NodeEditorController(
      graph: NodeGraph(
        nodes: <GraphNode>[node('a', position: const Offset(60, 60))],
      ),
    );
    addTearDown(controller.dispose);
    controller.selection.selectNode('a');

    await tester.pumpWidget(harness(controller));

    // A press that wanders a pixel is still a click, not a sweep.
    final gesture = await tester.startGesture(
      const Offset(600, 480),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await gesture.moveBy(const Offset(1, 1));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(controller.selection.nodeIds, isEmpty, reason: 'click clears');
    expect(controller.camera.viewport.offset, Offset.zero);
  });

  testWidgets('escape abandons a sweep and restores the selection', (
    tester,
  ) async {
    final controller = NodeEditorController(
      graph: NodeGraph(
        nodes: <GraphNode>[
          node('a', position: const Offset(60, 60)),
          node('b', position: const Offset(500, 400)),
        ],
      ),
    );
    addTearDown(controller.dispose);
    controller.selection.selectNode('b');

    await tester.pumpWidget(harness(controller));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    final gesture = await tester.startGesture(
      const Offset(40, 40),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await gesture.moveTo(const Offset(220, 160));
    await tester.pump();
    expect(controller.selection.nodeIds, <String>{'a', 'b'});

    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(controller.selection.nodeIds, <String>{'b'});

    await gesture.up();
    await tester.pump();
  });

  testWidgets('delete removes the selection', (tester) async {
    final controller = NodeEditorController(
      graph: NodeGraph(
        nodes: <GraphNode>[node('a', position: const Offset(60, 60))],
      ),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(harness(controller));
    await tester.tap(find.byKey(const ValueKey<String>('body_a')));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pump();

    expect(controller.graph.nodes, isEmpty);
  });

  testWidgets('a port spawned by a prototype is live in the tree', (
    tester,
  ) async {
    final controller = NodeEditorController(
      graph: NodeGraph(
        nodes: <GraphNode>[
          GraphNode(
            id: 'r',
            type: 'fanout',
            position: const Offset(60, 60),
            width: 120,
            height: 80,
          ),
          GraphNode(
            id: 'b',
            position: const Offset(360, 60),
            width: 120,
            height: 80,
            ports: const <NodePort>[NodePort.input(id: 'in')],
          ),
        ],
      ),
      prototypes: NodePrototypeRegistry(<NodePrototype>[
        NodePrototype(
          type: 'fanout',
          ports: <PortFamily>[
            DynamicPortFamily(
              id: 'exits',
              build: PortFamilies.variadic(
                idPrefix: 'out_',
                create: (index) => NodePort.output(id: 'out_$index'),
              ),
            ),
          ],
        ),
      ]),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(harness(controller));
    expect(portIsLive(controller, 'r', 'out_0'), isTrue);
    expect(portIsLive(controller, 'r', 'out_1'), isFalse);

    // Wiring the only free exit has to grow the family and put a real,
    // hit-testable handle on screen — not just a port in the model.
    final start = portPoint(tester, controller, 'r', 'out_0');
    final end = portPoint(tester, controller, 'b', 'in');
    await tester.dragFrom(start, end - start);
    await tester.pump();

    expect(controller.graph.connections, hasLength(1));
    expect(portIsLive(controller, 'r', 'out_1'), isTrue);

    // The fresh handle is usable straight away, not only after a reload.
    final tail = portPoint(tester, controller, 'r', 'out_1');
    await tester.dragFrom(
      tail,
      portPoint(tester, controller, 'b', 'in') - tail,
    );
    await tester.pump();

    expect(portIsLive(controller, 'r', 'out_2'), isTrue);
  });
}

/// A node body that holds state, for checking the tree is not rebuilt under it.
class _Counter extends StatefulWidget {
  const _Counter({super.key});

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int _taps = 0;

  @override
  Widget build(BuildContext context) {
    final label = (widget.key! as ValueKey<String>).value.split('_').last;
    return GestureDetector(
      onTap: () => setState(() => _taps++),
      child: ColoredBox(
        color: const Color(0xFF2A2E38),
        child: Center(
          child: Text('$label:$_taps', textDirection: TextDirection.ltr),
        ),
      ),
    );
  }
}
