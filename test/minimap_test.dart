import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fl_nodes_v2/fl_nodes_v2.dart';
// Deliberately not exported: a host reaches the panel through
// `NodeEditor.minimap`, and only these tests need the type itself.
import 'package:fl_nodes_v2/src/minimap/minimap_palette.dart';
import 'package:fl_nodes_v2/src/minimap/minimap_panel.dart';

void main() {
  // --------------------------------------------------------------- factories

  GraphNode node(String id, Offset position, {String type = 'default'}) =>
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

  NodeGraph threeNodes() => NodeGraph(
    nodes: <GraphNode>[
      node('a', Offset.zero),
      node('b', const Offset(200, 0)),
      node('c', const Offset(400, 120)),
    ],
  );

  NodeEditorController boot({NodeGraph? graph}) {
    final controller = NodeEditorController(graph: graph ?? threeNodes());
    addTearDown(controller.dispose);
    return controller;
  }

  Widget harness(
    NodeEditorController controller, {
    MinimapConfig? minimap = const MinimapConfig(),
    MinimapController? minimapController,
    Size size = const Size(800, 600),
  }) => MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: NodeEditor(
            controller: controller,
            theme: NodeEditorTheme.dark(),
            minimap: minimap,
            minimapController: minimapController,
            nodeBuilder: (context, graphNode, state) =>
                const ColoredBox(color: Color(0xFF2A2E38)),
          ),
        ),
      ),
    ),
  );

  final panelFinder = find.byKey(const ValueKey<String>('minimap'));
  final mapFinder = find.byWidgetPredicate(
    (widget) => widget is CustomPaint && widget.painter is MinimapPainter,
  );

  MinimapPanelState panelState(WidgetTester tester) =>
      tester.state<MinimapPanelState>(find.byType(MinimapPanel));

  /// The panel as it is actually laid out, which is what the clamp and the
  /// alignment default both end up expressed in.
  Rect panelRect(WidgetTester tester) {
    final editor = tester.getTopLeft(find.byType(NodeEditor));
    final box = tester.getRect(
      find.byKey(const ValueKey<String>('minimap.frame')),
    );
    return box.shift(-editor);
  }

  // ============================================================ the arithmetic

  group('MinimapProjection.fit', () {
    const map = Size(240, 160);

    test('frames the whole content when nothing caps it', () {
      const content = Rect.fromLTWH(0, 0, 2000, 1000);
      final projection = MinimapProjection.fit(
        contentBounds: content,
        mapSize: map,
        maxScale: 1,
      );

      final drawn = projection.sceneRectToMap(content);
      expect(
        (Offset.zero & map).inflate(0.01).contains(drawn.topLeft) &&
            (Offset.zero & map).inflate(0.01).contains(drawn.bottomRight),
        isTrue,
        reason: 'fitting means everything lands inside the panel',
      );
      expect(drawn.center.dx, closeTo(map.width / 2, 0.01));
      expect(drawn.center.dy, closeTo(map.height / 2, 0.01));
    });

    test('the zoom cap stops a small graph filling the map', () {
      // Three nodes in a corner: fitting alone would blow them up to fill the
      // panel and say nothing about the shape of the document.
      const content = Rect.fromLTWH(0, 0, 200, 100);
      final projection = MinimapProjection.fit(
        contentBounds: content,
        mapSize: map,
        maxScale: 0.2,
      );

      expect(projection.scale, 0.2);
      expect(
        projection.sceneRectToMap(content).width,
        closeTo(40, 0.01),
        reason: '200 scene units at the capped scale, not the panel width',
      );
    });

    test('the cap can never push content off the map', () {
      const content = Rect.fromLTWH(-500, -500, 40, 30);
      final projection = MinimapProjection.fit(
        contentBounds: content,
        mapSize: map,
        maxScale: 0.05,
      );
      final drawn = projection.sceneRectToMap(content);

      expect((Offset.zero & map).contains(drawn.topLeft), isTrue);
      expect((Offset.zero & map).contains(drawn.bottomRight), isTrue);
      expect(
        drawn.center,
        const Offset(120, 80),
        reason:
            'the cap only ever makes the drawing smaller than fitting, so the '
            'content stays centred with slack on both axes',
      );
    });

    test('an empty graph frames nothing', () {
      final projection = MinimapProjection.fit(
        contentBounds: null,
        mapSize: map,
        maxScale: 0.2,
      );
      expect(projection.content, isNull);
      expect(projection, MinimapProjection.empty);
    });

    test('a map with no room in it frames nothing', () {
      final projection = MinimapProjection.fit(
        contentBounds: const Rect.fromLTWH(0, 0, 100, 100),
        mapSize: Size.zero,
        maxScale: 0.2,
      );
      expect(
        projection.content,
        isNull,
        reason: 'a zero-sized panel must not divide by zero on the way to it',
      );
    });

    test('a content rect with no extent still projects', () {
      final projection = MinimapProjection.fit(
        contentBounds: Rect.zero,
        mapSize: map,
        maxScale: 0.2,
      );
      expect(projection.scale, 0.2);
    });
  });

  // ================================================================= the shade

  group('minimapShadeBands', () {
    const map = Rect.fromLTWH(0, 0, 100, 80);

    double area(Iterable<Rect> rects) =>
        rects.fold(0, (sum, r) => sum + r.width * r.height);

    test('the bands tile the map around the viewport and never overlap', () {
      const viewport = Rect.fromLTWH(20, 15, 40, 30);
      final bands = minimapShadeBands(map, viewport);

      expect(
        area(bands) + viewport.width * viewport.height,
        closeTo(map.width * map.height, 0.001),
        reason: 'the complement plus the hole is the whole map',
      );
      for (var i = 0; i < bands.length; i++) {
        for (var j = i + 1; j < bands.length; j++) {
          expect(
            bands[i].intersect(bands[j]).isEmpty,
            isTrue,
            reason:
                'the wash is translucent, so two bands over one pixel '
                'composite twice and show as a darker seam',
          );
        }
        expect(bands[i].intersect(viewport).isEmpty, isTrue);
      }
    });

    test('a viewport flush against an edge leaves no empty bands', () {
      final bands = minimapShadeBands(map, const Rect.fromLTWH(0, 0, 40, 80));
      expect(bands.length, 1);
      expect(bands.single, const Rect.fromLTRB(40, 0, 100, 80));
    });

    test('a viewport covering the map leaves nothing washed', () {
      expect(minimapShadeBands(map, map), isEmpty);
    });

    test('a viewport entirely off the map washes all of it', () {
      final bands = minimapShadeBands(
        map,
        const Rect.fromLTWH(500, 500, 10, 10),
      );
      expect(bands, <Rect>[map]);
    });
  });

  // ================================================================= the colour

  group('minimapNodeColor', () {
    const selected = Color(0xFF00FF00);
    const comment = Color(0xFF888888);
    const neutral = Color(0xFF111111);
    const hosted = Color(0xFFFF0000);

    Color colorOf(
      GraphNode target, {
      required NodeGraph graph,
      bool isSelected = false,
      MinimapNodeColor? override,
    }) => minimapNodeColor(
      target,
      graph: graph,
      selected: selected,
      comment: comment,
      neutral: neutral,
      isSelected: isSelected,
      override: override,
    );

    test('a node with nothing to say about it takes the neutral', () {
      final graph = threeNodes();
      expect(colorOf(graph.nodes['a']!, graph: graph), neutral);
    });

    test('a node in a group takes the group colour', () {
      var graph = threeNodes();
      graph = graph.putGroup(
        const NodeGroup(
          id: 'g',
          nodeIds: <String>{'a'},
          color: Color(0xFF5B8DEF),
        ),
      );
      expect(colorOf(graph.nodes['a']!, graph: graph), const Color(0xFF5B8DEF));
      expect(colorOf(graph.nodes['b']!, graph: graph), neutral);
    });

    test('a note takes the note grey', () {
      final comment = NodeComment.create(id: 'n', position: Offset.zero);
      final graph = NodeGraph(nodes: <GraphNode>[comment]);
      expect(colorOf(comment, graph: graph), const Color(0xFF888888));
    });

    test('the selection outranks the host, which outranks the group', () {
      var graph = threeNodes();
      graph = graph.putGroup(
        const NodeGroup(
          id: 'g',
          nodeIds: <String>{'a'},
          color: Color(0xFF5B8DEF),
        ),
      );
      final target = graph.nodes['a']!;
      Color? host(GraphNode _) => hosted;

      expect(
        colorOf(target, graph: graph, override: host),
        hosted,
        reason: 'a host colouring by its own node vocabulary wins the group',
      );
      expect(
        colorOf(target, graph: graph, override: host, isSelected: true),
        selected,
        reason:
            'or a selected node is indistinguishable from an unselected one '
            'of the same type, on the panel whose job is telling you where '
            'you are',
      );
    });
  });

  // ============================================================= the controller

  group('MinimapController', () {
    test('notifies once, and only on a real change', () {
      final minimap = MinimapController();
      addTearDown(minimap.dispose);
      var notifications = 0;
      minimap.addListener(() => notifications++);

      minimap.maxScale = 0.4;
      expect(notifications, 1);
      minimap.maxScale = 0.4;
      expect(notifications, 1, reason: 'the same value is not a change');
      minimap.toggleMinimised();
      expect(notifications, 2);
    });

    test('a zoom cap is kept inside sane limits', () {
      final minimap = MinimapController(maxScale: 40);
      addTearDown(minimap.dispose);
      expect(minimap.maxScale, 1.0);

      minimap.maxScale = double.nan;
      expect(minimap.maxScale, MinimapController.defaultMaxScale);
    });
  });

  // ================================================================== the panel

  testWidgets('there is no panel unless the host asks for one', (tester) async {
    final controller = boot();
    await tester.pumpWidget(harness(controller, minimap: null));
    expect(panelFinder, findsNothing);

    await tester.pumpWidget(harness(controller));
    expect(panelFinder, findsOneWidget);
    expect(mapFinder, findsOneWidget);
  });

  testWidgets('the panel starts where the config aligns it', (tester) async {
    await tester.pumpWidget(harness(boot()));

    expect(
      panelRect(tester),
      const Rect.fromLTWH(544, 424, 240, 160),
      reason: 'bottom-right of an 800x600 canvas, inside a 16px margin',
    );
  });

  testWidgets('the close button minimises rather than closing', (tester) async {
    final minimap = MinimapController();
    addTearDown(minimap.dispose);
    await tester.pumpWidget(harness(boot(), minimapController: minimap));

    await tester.tap(find.byTooltip('Minimise'));
    await tester.pumpAndSettle();

    expect(minimap.minimised, isTrue);
    expect(
      panelFinder,
      findsOneWidget,
      reason:
          'folding is not closing: the bar stays, and it is the only way '
          'back',
    );
    expect(mapFinder, findsNothing);
    expect(panelRect(tester).height, MinimapController.barHeight);

    await tester.tap(find.byTooltip('Restore'));
    await tester.pumpAndSettle();
    expect(minimap.minimised, isFalse);
    expect(mapFinder, findsOneWidget);
  });

  testWidgets('the bar buttons sit against the right edge, whatever the '
      'width', (tester) async {
    final minimap = MinimapController()..size = const Size(320, 200);
    addTearDown(minimap.dispose);
    await tester.pumpWidget(harness(boot(), minimapController: minimap));

    final frame = tester.getRect(
      find.byKey(const ValueKey<String>('minimap.frame')),
    );
    final fold = tester.getRect(find.byIcon(Icons.close));
    final gear = tester.getRect(find.byIcon(Icons.settings));
    final grip = tester.getRect(find.byIcon(Icons.drag_indicator));

    expect(
      frame.right - fold.right,
      lessThan(8),
      reason:
          'a Flexible title beside a Spacer split the free width between '
          'them, and the half the title did not fill sat as a gap before the '
          'spacer — the buttons floated a third of the way in from the edge',
    );
    expect(
      frame.right - fold.right,
      moreOrLessEquals(grip.left - frame.left, epsilon: 1),
      reason: 'the same inset the grip keeps from the left',
    );
    expect(gear.right, lessThanOrEqualTo(fold.left));
    expect(
      gear.center.dy,
      moreOrLessEquals(fold.center.dy, epsilon: 0.5),
      reason: 'on one line',
    );
  });

  testWidgets('dragging the bar moves the panel and never the camera', (
    tester,
  ) async {
    final controller = boot();
    final minimap = MinimapController();
    addTearDown(minimap.dispose);
    await tester.pumpWidget(harness(controller, minimapController: minimap));

    final before = controller.camera.viewport;
    final start = panelRect(tester).topLeft;

    final gesture = await tester.startGesture(
      tester.getCenter(find.byIcon(Icons.drag_indicator)),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(-100, -60));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(minimap.position, start + const Offset(-100, -60));
    expect(
      controller.camera.viewport,
      before,
      reason: 'the minimap is a readout: the drag belongs to the panel',
    );
  });

  testWidgets('a drag across the map body moves nothing at all', (
    tester,
  ) async {
    final controller = boot();
    await tester.pumpWidget(harness(controller));
    final before = controller.camera.viewport;

    final gesture = await tester.startGesture(
      tester.getCenter(mapFinder),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(40, 30));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(controller.camera.viewport, before);
    expect(
      controller.selection.nodeIds,
      isEmpty,
      reason: 'the panel is opaque, so the marquee never sees the press',
    );
  });

  testWidgets('the grip resizes from the top-left and clamps', (tester) async {
    final minimap = MinimapController();
    addTearDown(minimap.dispose);
    await tester.pumpWidget(harness(boot(), minimapController: minimap));

    // Placed by hand first: an *unplaced* panel is anchored to its corner by
    // the config's alignment, so shrinking it there legitimately moves its
    // top-left. What the grip must not do is move a panel somebody put
    // somewhere.
    minimap.position = const Offset(300, 200);
    await tester.pump();

    final origin = panelRect(tester).topLeft;
    final gesture = await tester.startGesture(
      panelRect(tester).bottomRight -
          const Offset(6, 6) +
          tester.getTopLeft(find.byType(NodeEditor)),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(-60, -30));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(minimap.size, const Size(180, 130));
    expect(
      panelRect(tester).topLeft,
      origin,
      reason: 'the grip is anchored at the top-left, so the panel stays put',
    );

    // And it stops at the config's ceiling rather than growing without bound.
    final wide = await tester.startGesture(
      panelRect(tester).bottomRight -
          const Offset(6, 6) +
          tester.getTopLeft(find.byType(NodeEditor)),
      kind: PointerDeviceKind.mouse,
    );
    await wide.moveBy(const Offset(2000, 2000));
    await tester.pump();
    await wide.up();
    await tester.pumpAndSettle();

    expect(minimap.size, const Size(480, 360));
  });

  testWidgets('the gear writes the same size field the grip does', (
    tester,
  ) async {
    final minimap = MinimapController();
    addTearDown(minimap.dispose);
    await tester.pumpWidget(harness(boot(), minimapController: minimap));

    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Size'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Large'));
    await tester.pumpAndSettle();

    expect(minimap.size, const Size(360, 240));
  });

  testWidgets('closing the gear hands focus back to the canvas', (
    tester,
  ) async {
    final controller = boot();
    await tester.pumpWidget(harness(controller));

    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    controller.selection.selectNode('a');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pumpAndSettle();

    expect(
      controller.graph.nodes.containsKey('a'),
      isFalse,
      reason:
          'a shortcut reaching the wrong widget is worse than one reaching '
          'nothing, which is why canvas_focus_test.dart exists',
    );
  });

  testWidgets('scrolling over the panel does not zoom the canvas', (
    tester,
  ) async {
    final controller = boot();
    await tester.pumpWidget(harness(controller));
    final before = controller.camera.viewport.scale;

    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    final overPanel = tester.getCenter(mapFinder);
    pointer.hover(overPanel);
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, -120)));
    await tester.pump();

    expect(controller.camera.viewport.scale, before);

    // And the same scroll on bare canvas still zooms, so the guard is a guard
    // and not a break.
    final overCanvas =
        tester.getTopLeft(find.byType(NodeEditor)) + const Offset(40, 40);
    pointer.hover(overCanvas);
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, -120)));
    await tester.pump();

    expect(controller.camera.viewport.scale, greaterThan(before));
  });

  testWidgets('hovering the panel does not pick a port beneath it', (
    tester,
  ) async {
    final cursors = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.mouseCursor,
      (call) async {
        if (call.method == 'activateSystemCursor') {
          cursors.add(
            (call.arguments as Map<Object?, Object?>)['kind']! as String,
          );
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.mouseCursor,
        null,
      ),
    );

    final controller = boot();
    await tester.pumpWidget(harness(controller));

    // Put a port exactly under the middle of the panel.
    final editorOrigin = tester.getTopLeft(find.byType(NodeEditor));
    final target = tester.getCenter(mapFinder) - editorOrigin;
    final scene = controller.camera.viewport.toScene(target);
    controller.moveNodes(<String, Offset>{'a': scene - const Offset(0, 45)});
    await tester.pump();
    expect(
      controller.layout.portAt(scene, radius: 12),
      isNotNull,
      reason: 'the test is worthless unless there is a port to mis-pick',
    );

    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(target + editorOrigin));
    await tester.pump();

    expect(
      cursors,
      isNot(contains('precise')),
      reason:
          'an opaque MouseRegion stops siblings, not ancestors, so the canvas '
          'goes on hover-picking under the panel unless it is told not to',
    );
  });

  testWidgets('a viewport that shrank clamps the panel without moving it', (
    tester,
  ) async {
    final minimap = MinimapController();
    addTearDown(minimap.dispose);
    final controller = boot();
    await tester.pumpWidget(harness(controller, minimapController: minimap));

    // Place it explicitly, so the clamp has something of its own to chew on.
    minimap.position = const Offset(500, 400);
    await tester.pump();

    await tester.pumpWidget(
      harness(
        controller,
        minimapController: minimap,
        size: const Size(400, 300),
      ),
    );
    await tester.pump();

    expect(
      panelRect(tester),
      const Rect.fromLTWH(160, 140, 240, 160),
      reason: 'clamped into the smaller canvas',
    );
    expect(
      minimap.position,
      const Offset(500, 400),
      reason:
          'the clamp is a read, so widening the window again puts the panel '
          'back where it was put',
    );
  });

  testWidgets('a host-supplied controller outlives the editor', (tester) async {
    final minimap = MinimapController();
    addTearDown(minimap.dispose);
    await tester.pumpWidget(harness(boot(), minimapController: minimap));
    await tester.pumpWidget(const SizedBox.shrink());

    expect(
      () => minimap.minimised = true,
      returnsNormally,
      reason: 'the editor disposes only the controller it made itself',
    );
  });

  testWidgets('the map washes over what the canvas is not showing', (
    tester,
  ) async {
    final controller = boot();
    await tester.pumpWidget(harness(controller));

    // Zoomed well in and centred, so the viewport is strictly inside the
    // content and all four bands exist.
    controller.camera.setScale(5);
    controller.camera.centerOnContent(const Size(800, 600));
    await tester.pump();

    expect(
      mapFinder,
      paints
        // The panel's own background, before anything is drawn on it.
        ..rect(color: MinimapPalette.onDark.surface)
        ..rect(color: MinimapPalette.onDark.shade)
        ..rect(color: MinimapPalette.onDark.shade)
        ..rect(color: MinimapPalette.onDark.shade)
        ..rect(color: MinimapPalette.onDark.shade)
        ..rect(
          color: MinimapPalette.onDark.viewportBorder,
          style: PaintingStyle.stroke,
        ),
      reason:
          'four bands around the hole, then the marker over them — anything '
          'fewer means a band was dropped and part of the map is lying about '
          'being on screen',
    );
  });

  testWidgets('a viewport covering everything washes nothing', (tester) async {
    final controller = boot();
    await tester.pumpWidget(harness(controller));
    controller.camera.setScale(0.2);
    controller.camera.centerOnContent(const Size(800, 600));
    await tester.pump();

    expect(
      mapFinder,
      isNot(
        paints
          ..rect(color: MinimapPalette.onDark.surface)
          ..rect(color: MinimapPalette.onDark.shade),
      ),
      reason: 'there is nothing off screen to grey out',
    );
  });

  testWidgets('panning rebuilds no minimap geometry', (tester) async {
    final controller = boot();
    await tester.pumpWidget(harness(controller));
    await tester.pumpAndSettle();

    final before = panelState(tester).debugSceneSyncs;
    for (var i = 0; i < 20; i++) {
      controller.camera.panBy(const Offset(3, 2));
      await tester.pump();
    }

    expect(
      panelState(tester).debugSceneSyncs,
      before,
      reason:
          'revision moves for edits and not for the camera, so a scroll tick '
          'recomputes the projection and nothing else',
    );

    controller.translateNodes(<String>['a'], const Offset(10, 0));
    await tester.pump();
    expect(panelState(tester).debugSceneSyncs, before + 1);
  });
}
