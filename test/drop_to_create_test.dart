import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fl_nodes_v2/fl_nodes_v2.dart';

/// A wire let go over nothing. Off by default it is the host's hook, exactly
/// as before; on, it is the Create menu at the drop point. Never both — one
/// gesture must not be able to produce two nodes.
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

  Future<NodeEditorController> boot(
    WidgetTester tester, {
    required NodeEditorMenus? menus,
    void Function(PortRef source, Offset scenePosition)? onConnectionDropped,
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
        ],
      ),
      prototypes: prototypes,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NodeEditor(
            controller: controller,
            theme: theme,
            contextMenus: menus,
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

  /// Drags the wire out of `a.out` and lets it go over empty canvas.
  Future<void> dropWire(
    WidgetTester tester,
    NodeEditorController controller,
    Offset sceneTarget,
  ) async {
    final from = screenPoint(
      tester,
      controller,
      controller.layout.portPosition(const PortRef('a', 'out'))!,
    );
    final to = screenPoint(tester, controller, sceneTarget);
    final gesture = await tester.startGesture(
      from,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 16));
    for (var step = 1; step <= 4; step++) {
      await gesture.moveTo(Offset.lerp(from, to, step / 4)!);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('off by default: the host hook fires and nothing is made', (
    tester,
  ) async {
    PortRef? droppedFrom;
    Offset? droppedAt;
    final controller = await boot(
      tester,
      menus: const NodeEditorMenus(),
      onConnectionDropped: (source, at) {
        droppedFrom = source;
        droppedAt = at;
      },
    );

    await dropWire(tester, controller, const Offset(420, 400));

    expect(droppedFrom, const PortRef('a', 'out'));
    expect(droppedAt, isNotNull);
    expect(controller.graph.nodes, hasLength(1));
    expect(find.text('Step'), findsNothing);
  });

  testWidgets('on: the menu opens and the host hook does not fire', (
    tester,
  ) async {
    var dropped = 0;
    final controller = await boot(
      tester,
      menus: const NodeEditorMenus(createOnDrop: true),
      onConnectionDropped: (_, _) => dropped++,
    );

    await dropWire(tester, controller, const Offset(420, 400));

    expect(find.text('Step'), findsOneWidget);
    expect(
      dropped,
      0,
      reason:
          'the menu replaces the hook rather than joining it, or one '
          'gesture would make two nodes',
    );
    expect(controller.graph.nodes, hasLength(1));
  });

  testWidgets('choosing an entry creates the node wired up, in one step', (
    tester,
  ) async {
    final controller = await boot(
      tester,
      menus: const NodeEditorMenus(createOnDrop: true),
    );

    await dropWire(tester, controller, const Offset(420, 400));
    await tester.tap(find.text('Step'));
    await tester.pumpAndSettle();

    expect(controller.graph.nodes, hasLength(2));
    expect(controller.graph.connections, hasLength(1));

    final wire = controller.graph.connections.values.single;
    expect(wire.from, const PortRef('a', 'out'));
    expect(
      wire.to.portId,
      'in',
      reason: 'the first port the source is allowed to land on',
    );

    controller.history.undo();
    expect(
      controller.graph.nodes,
      hasLength(1),
      reason:
          'the node and its wire go back together — half a dropped '
          'connection is not a state worth stopping at',
    );
    expect(controller.graph.connections, isEmpty);
  });

  testWidgets('dismissing the menu leaves the graph alone', (tester) async {
    final controller = await boot(
      tester,
      menus: const NodeEditorMenus(createOnDrop: true),
    );

    await dropWire(tester, controller, const Offset(420, 400));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(controller.graph.nodes, hasLength(1));
    expect(controller.graph.connections, isEmpty);
    expect(controller.history.canUndo, isFalse);
  });
}
