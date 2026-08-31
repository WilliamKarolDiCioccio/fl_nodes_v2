import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fl_nodes_v2/fl_nodes_v2.dart';

/// The half of the menu behaviour that only exists once a menu is on screen:
/// what right-clicking hits, what it selects on the way, and that the editor
/// gets its keyboard back afterwards.
void main() {
  final NodeEditorTheme theme = NodeEditorTheme.dark();

  GraphNode node(String id, Offset position, {String type = 'plain'}) =>
      GraphNode(
        id: id,
        type: type,
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
    NodeGraph? graph,
    NodePrototypeRegistry? prototypes,
    NodeEditorMenus? menus = const NodeEditorMenus(),
    void Function(GraphNode node, Offset globalPosition)? onNodeSecondaryTap,
  }) async {
    final controller = NodeEditorController(
      graph:
          graph ??
          NodeGraph(
            nodes: <GraphNode>[
              node('a', const Offset(100, 100)),
              node('b', const Offset(420, 100)),
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
            onNodeSecondaryTap: onNodeSecondaryTap,
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

  /// A real right-click: mouse kind, secondary button, press and release.
  Future<void> rightClick(WidgetTester tester, Offset at) async {
    final gesture = await tester.startGesture(
      at,
      buttons: kSecondaryButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.up();
    await tester.pumpAndSettle();
  }

  Future<void> tapMenuItem(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  testWidgets('right-clicking a node opens the node menu', (tester) async {
    final controller = await boot(tester);

    await rightClick(
      tester,
      screenPoint(tester, controller, const Offset(180, 145)),
    );

    expect(find.text('Cut'), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    expect(
      find.text('Center view'),
      findsNothing,
      reason: 'the node menu, not the canvas one',
    );
  });

  testWidgets('right-clicking an unselected node selects it', (tester) async {
    final controller = await boot(tester);

    await rightClick(
      tester,
      screenPoint(tester, controller, const Offset(180, 145)),
    );

    expect(controller.selection.nodeIds, <String>{'a'});
  });

  testWidgets('right-clicking inside a multi-selection keeps it', (
    tester,
  ) async {
    final controller = await boot(tester);
    controller.selection.selectAll();
    await tester.pumpAndSettle();

    await rightClick(
      tester,
      screenPoint(tester, controller, const Offset(180, 145)),
    );
    await tapMenuItem(tester, 'Delete');

    expect(
      controller.graph.nodes,
      isEmpty,
      reason:
          'Delete on one of a selection deletes the selection, which is '
          'what having selected them meant',
    );
  });

  testWidgets('Delete removes the node in one undo step', (tester) async {
    final controller = await boot(tester);

    await rightClick(
      tester,
      screenPoint(tester, controller, const Offset(180, 145)),
    );
    await tapMenuItem(tester, 'Delete');

    expect(controller.graph.nodes.keys, <String>['b']);
    controller.history.undo();
    expect(controller.graph.nodes.keys, <String>['a', 'b']);
  });

  testWidgets('right-clicking a port offers to cut its links', (tester) async {
    final controller = await boot(tester);
    controller.connect(const PortRef('a', 'out'), const PortRef('b', 'in'));
    await tester.pumpAndSettle();

    await rightClick(
      tester,
      screenPoint(
        tester,
        controller,
        controller.layout.portPosition(const PortRef('a', 'out'))!,
      ),
    );
    expect(find.text('Cut link'), findsOneWidget);
    await tapMenuItem(tester, 'Cut link');

    expect(controller.graph.connections, isEmpty);
    expect(
      controller.graph.nodes,
      hasLength(2),
      reason: 'cutting links takes the wires and leaves the nodes',
    );
  });

  testWidgets('right-clicking a wire offers to follow it', (tester) async {
    final controller = await boot(tester);
    controller.connect(const PortRef('a', 'out'), const PortRef('b', 'in'));
    await tester.pumpAndSettle();

    final from = controller.layout.portPosition(const PortRef('a', 'out'))!;
    final to = controller.layout.portPosition(const PortRef('b', 'in'))!;
    await rightClick(tester, screenPoint(tester, controller, (from + to) / 2));

    expect(find.text('Go to source'), findsOneWidget);
    await tapMenuItem(tester, 'Go to destination');

    expect(controller.selection.nodeIds, <String>{'b'});
    expect(
      controller.camera.viewport.offset,
      isNot(Offset.zero),
      reason: 'following a wire moves the camera to the far end',
    );
  });

  testWidgets('right-clicking empty canvas opens the canvas menu', (
    tester,
  ) async {
    final controller = await boot(tester);

    await rightClick(
      tester,
      screenPoint(tester, controller, const Offset(60, 420)),
    );

    expect(find.text('Center view'), findsOneWidget);
    expect(find.text('Reset zoom'), findsOneWidget);
    expect(find.text('Project'), findsOneWidget);
  });

  testWidgets('Paste lands where the menu was opened', (tester) async {
    final controller = await boot(tester);
    controller.selection.selectNode('a');
    controller.clipboard.copy();
    await tester.pumpAndSettle();

    const dropPoint = Offset(300, 400);
    await rightClick(tester, screenPoint(tester, controller, dropPoint));
    await tapMenuItem(tester, 'Paste');

    final pasted = controller.graph.nodes.values.where(
      (graphNode) => graphNode.id != 'a' && graphNode.id != 'b',
    );
    expect(pasted, hasLength(1));
    expect(
      pasted.single.position,
      dropPoint,
      reason:
          'pasting from a menu lands at the click, not at the cascade '
          'offset a keyboard paste uses',
    );
  });

  testWidgets('Create adds a node of the chosen type at the click', (
    tester,
  ) async {
    final controller = await boot(
      tester,
      graph: NodeGraph(nodes: <GraphNode>[node('a', const Offset(100, 100))]),
      prototypes: NodePrototypeRegistry(const <NodePrototype>[
        NodePrototype(type: 'note', label: 'Note'),
      ]),
    );

    const at = Offset(320, 430);
    await rightClick(tester, screenPoint(tester, controller, at));
    await tapMenuItem(tester, 'Create');
    await tapMenuItem(tester, 'Note');

    final created = controller.graph.nodes.values.singleWhere(
      (graphNode) => graphNode.type == 'note',
    );
    expect(created.position, at);
    expect(controller.selection.nodeIds, <String>{created.id});
  });

  testWidgets('a host callback suppresses the built-in node menu', (
    tester,
  ) async {
    var calls = 0;
    final controller = await boot(
      tester,
      onNodeSecondaryTap: (_, _) => calls++,
    );

    await rightClick(
      tester,
      screenPoint(tester, controller, const Offset(180, 145)),
    );

    expect(calls, 1);
    expect(find.text('Cut'), findsNothing);
  });

  testWidgets('contextMenus: null opens nothing anywhere', (tester) async {
    final controller = await boot(tester, menus: null);

    await rightClick(
      tester,
      screenPoint(tester, controller, const Offset(60, 420)),
    );
    expect(find.text('Center view'), findsNothing);

    await rightClick(
      tester,
      screenPoint(tester, controller, const Offset(180, 145)),
    );
    expect(find.text('Cut'), findsNothing);
  });

  testWidgets('clicking the canvas closes an open menu', (tester) async {
    final controller = await boot(tester);

    await rightClick(
      tester,
      screenPoint(tester, controller, const Offset(60, 420)),
    );
    expect(find.text('Center view'), findsOneWidget);

    await tester.tapAt(screenPoint(tester, controller, const Offset(300, 480)));
    await tester.pumpAndSettle();

    expect(
      find.text('Center view'),
      findsNothing,
      reason:
          'the menu anchors to the click point, not to the canvas — an '
          'anchor the size of the canvas makes every tap an inside tap, and '
          'then only Escape can dismiss it',
    );
  });

  testWidgets(
    'the click that dismisses a menu does not also reach the canvas',
    (tester) async {
      final controller = await boot(tester);
      controller.selection.selectNode('a');
      await tester.pumpAndSettle();

      await rightClick(
        tester,
        screenPoint(tester, controller, const Offset(60, 420)),
      );
      await tester.tapAt(
        screenPoint(tester, controller, const Offset(300, 480)),
      );
      await tester.pumpAndSettle();

      expect(
        controller.selection.nodeIds,
        <String>{'a'},
        reason:
            'that click was spent dismissing; letting it clear the '
            'selection too would move things out from under the menu',
      );
    },
  );

  testWidgets('the menu opens under the keyboard', (tester) async {
    final controller = await boot(tester);

    await rightClick(
      tester,
      screenPoint(tester, controller, const Offset(60, 420)),
    );

    expect(
      FocusManager.instance.primaryFocus?.context?.widget,
      isA<Focus>(),
      reason:
          'a menu anchored to a point has no button to focus, so the '
          'anchor focuses itself and hands off to its first item',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byWidget(FocusManager.instance.primaryFocus!.context!.widget),
        matching: find.text('Reset zoom'),
      ),
      findsOneWidget,
      reason:
          'the arrow keys walk the menu, which they cannot do while the '
          'canvas still holds focus',
    );
  });

  testWidgets('a menu still closes on Escape', (tester) async {
    final controller = await boot(tester);

    await rightClick(
      tester,
      screenPoint(tester, controller, const Offset(60, 420)),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.text('Center view'), findsNothing);
  });

  testWidgets('the canvas gets its keyboard back when a menu closes', (
    tester,
  ) async {
    final controller = await boot(tester);

    await rightClick(
      tester,
      screenPoint(tester, controller, const Offset(60, 420)),
    );
    // Dismiss without choosing anything.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    controller.selection.selectNode('a');
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pumpAndSettle();

    expect(
      controller.graph.nodes.keys,
      <String>['b'],
      reason:
          'shortcuts are gated on the canvas holding focus, and the menu '
          'took it away — this is the regression onClose exists to stop',
    );
  });
}
