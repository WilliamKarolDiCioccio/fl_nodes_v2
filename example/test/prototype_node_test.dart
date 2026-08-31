import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fl_nodes_v2/fl_nodes_v2.dart';
import 'package:fl_nodes_v2_example/main.dart';

void main() {
  Future<NodeEditorController> boot(WidgetTester tester) async {
    await tester.pumpWidget(const NodeEditorDemoApp());
    await tester.pumpAndSettle();
    return tester.widget<NodeEditor>(find.byType(NodeEditor)).controller;
  }

  /// The format node's template field, which is the first of its text fields —
  /// the rest are the per-argument literals it generates.
  /// The greeting node's template field, which is the first of its text
  /// fields — the rest are the per-argument literals it generates.
  ///
  /// Scoped to that node: the demo has a second format node feeding it, and
  /// the first `FormatNodeBody` in the tree is not necessarily this one.
  final Finder formatField = find
      .descendant(
        of: find.byKey(const ValueKey<String>('greeting')),
        matching: find.byType(TextField),
      )
      .first;

  /// Where a port handle sits on screen.
  ///
  /// Handles are painted rather than built, so there is no widget to find:
  /// this reads the geometry the painter draws from and the picker uses.
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

  /// Whether a port exists *and* can be picked where it is drawn.
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

  /// Puts [scenePoint] in the middle of the canvas at full zoom.
  ///
  /// Centring on a node is not enough for a caption on a long wire, whose
  /// midpoint can sit well outside either end's card.
  Future<void> focusOnPoint(
    WidgetTester tester,
    NodeEditorController controller,
    Offset scenePoint, {
    double scale = 1,
  }) async {
    final state = tester.state<NodeEditorState>(find.byType(NodeEditor));
    final size = state.viewportSize;
    controller.camera.viewport = ViewportTransform(
      offset: Offset(size.width / 2, size.height / 2) - scenePoint * scale,
      scale: scale,
    );
    await tester.pumpAndSettle();
  }

  List<String> inputsOf(NodeEditorController controller, String id) => <String>[
    for (final port in controller.graph.node(id)!.ports)
      if (port.isInput) port.id,
  ];

  testWidgets('typing a placeholder grows the node and its ports', (
    tester,
  ) async {
    final controller = await boot(tester);
    expect(inputsOf(controller, 'greeting'), <String>['arg_0', 'arg_1']);
    final before = controller.layout.boundsOf('greeting')!.height;

    await tester.tap(formatField);
    await tester.pumpAndSettle();
    await tester.enterText(formatField, 'Hello, {0}. {1}! From {2}.');
    await tester.pumpAndSettle();

    expect(inputsOf(controller, 'greeting'), <String>[
      'arg_0',
      'arg_1',
      'arg_2',
    ]);
    expect(
      portIsLive(controller, 'greeting', 'arg_2'),
      isTrue,
      reason: 'the new port has to be aimable at, not just a model entry',
    );
    expect(
      controller.layout.boundsOf('greeting')!.height,
      greaterThan(before),
      reason: 'the declared height follows the argument count',
    );
  });

  testWidgets('the whole edit undoes in one step', (tester) async {
    final controller = await boot(tester);
    final original = controller.graph.node('greeting')!.data['format'];

    await tester.tap(formatField);
    await tester.pumpAndSettle();
    for (final value in <String>['A {0}', 'A {0} {1}', 'A {0} {1} {2}']) {
      await tester.enterText(formatField, value);
      await tester.pump();
    }
    // The transaction commits when the field gives up focus.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    expect(inputsOf(controller, 'greeting'), hasLength(3));

    controller.history.undo();
    await tester.pumpAndSettle();

    expect(controller.graph.node('greeting')!.data['format'], original);
    expect(
      inputsOf(controller, 'greeting'),
      <String>['arg_0', 'arg_1'],
      reason: 'the ports come back with the string that produced them',
    );
  });

  testWidgets(
    'losing a placeholder takes its wire with it, and undo restores both',
    (tester) async {
      final controller = await boot(tester);
      expect(controller.graph.connections.containsKey('c11'), isTrue);

      await tester.tap(formatField);
      await tester.pumpAndSettle();
      await tester.enterText(formatField, 'no placeholders here');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();

      expect(inputsOf(controller, 'greeting'), isEmpty);
      expect(
        controller.graph.connections.containsKey('c11'),
        isFalse,
        reason: 'the wire landed on a port that no longer exists',
      );

      controller.history.undo();
      await tester.pumpAndSettle();

      expect(inputsOf(controller, 'greeting'), <String>['arg_0', 'arg_1']);
      expect(
        controller.graph.connections.containsKey('c11'),
        isTrue,
        reason: 'port and wire went together, so they come back together',
      );
    },
  );

  testWidgets('wiring the free exit spawns another', (tester) async {
    final controller = await boot(tester);
    List<String> exits() => <String>[
      for (final port in controller.graph.node('route')!.ports)
        if (port.isOutput) port.id,
    ];
    expect(exits(), <String>['exit_0', 'exit_1']);

    // Close enough that the handles are big and far enough apart to hit.
    await focusOnPoint(tester, controller, const Offset(1700, 380), scale: 0.8);

    // exit_1 is the free one; wiring it must grow a fresh exit_2. The target
    // is a control input — an exit is control flow, and the editor refuses to
    // put it on a data port.
    final start = portPoint(tester, controller, 'route', 'exit_1');
    final end = portPoint(tester, controller, 'deliver', 'in');
    await tester.dragFrom(start, end - start);
    await tester.pumpAndSettle();

    expect(
      controller.graph
          .connectionsAt(const PortRef('route', 'exit_1'))
          .map((connection) => connection.to),
      <PortRef>[const PortRef('deliver', 'in')],
      reason:
          'asserting the endpoint, not just that an exit appeared: a drop '
          'on empty canvas spawns a node and wires it, which would grow one '
          'too',
    );
    expect(exits(), <String>['exit_0', 'exit_1', 'exit_2']);
    expect(portIsLive(controller, 'route', 'exit_2'), isTrue);
  });

  /// Brings [nodeId] into view at full zoom.
  ///
  /// The demo opens framed on the whole graph, which in a test-sized viewport
  /// is below the zoom at which captions are drawn at all — and a caption that
  /// is not drawn is deliberately not tappable either.
  Future<void> focusOn(
    WidgetTester tester,
    NodeEditorController controller,
    String nodeId,
  ) async {
    final state = tester.state<NodeEditorState>(find.byType(NodeEditor));
    controller.camera.setScale(1);
    controller.camera.centerOnNode(nodeId, state.viewportSize);
    await tester.pumpAndSettle();
  }

  Future<void> tapCaption(
    WidgetTester tester,
    NodeEditorController controller,
    String connectionId,
  ) async {
    final state = tester.state<NodeEditorState>(find.byType(NodeEditor));
    final anchor = state.connectionLayout[connectionId]!.labelAnchor;
    expect(
      anchor,
      isNotNull,
      reason: 'a captionable link is anchored even before it has a caption',
    );
    // toScreen is relative to the canvas, which sits below the toolbar.
    final origin = tester.getTopLeft(find.byType(NodeEditor));
    await tester.tapAt(origin + controller.camera.viewport.toScreen(anchor!));
    await tester.pumpAndSettle();
  }

  final Finder dialogField = find.descendant(
    of: find.byType(AlertDialog),
    matching: find.byType(TextField),
  );

  testWidgets('a branch link can be renamed by tapping its caption', (
    tester,
  ) async {
    final controller = await boot(tester);
    expect(controller.graph.connection('c3')!.label, 'High');
    await focusOn(tester, controller, 'score');

    await tapCaption(tester, controller, 'c3');

    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.enterText(dialogField, 'Hot lead');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(controller.graph.connection('c3')!.label, 'Hot lead');

    controller.history.undo();
    await tester.pumpAndSettle();
    expect(controller.graph.connection('c3')!.label, 'High');
  });

  testWidgets('a fan-out caption is derived, not stored or editable', (
    tester,
  ) async {
    final controller = await boot(tester);

    final state = tester.state<NodeEditorState>(find.byType(NodeEditor));
    expect(
      state.connectionLayout['c9']!.caption,
      'Out 0',
      reason: 'the caption comes from the port the wire leaves',
    );
    expect(
      controller.graph.connection('c9')!.label,
      isNull,
      reason: 'a derived caption is worked out, never written down',
    );

    // Tapping it selects the link rather than offering an editor: a derived
    // caption and a user-owned one are exclusive by construction.
    final anchor = state.connectionLayout['c9']!.labelAnchor!;
    await focusOnPoint(tester, controller, anchor);
    final origin = tester.getTopLeft(find.byType(NodeEditor));
    await tester.tapAt(origin + controller.camera.viewport.toScreen(anchor));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(controller.selection.connectionIds, contains('c9'));
  });

  testWidgets('a plain workflow link is not captionable', (tester) async {
    final controller = await boot(tester);
    final state = tester.state<NodeEditorState>(find.byType(NodeEditor));

    expect(
      controller.prototypes.allowsLabelEditing(
        controller.graph.connection('c1')!,
      ),
      isFalse,
      reason: 'only branching links opted in',
    );
    expect(
      state.connectionLayout['c1']!.labelAnchor,
      isNull,
      reason: 'nothing is drawn for it, so nothing can be aimed at',
    );
  });
}
