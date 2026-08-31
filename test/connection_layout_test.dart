import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fl_nodes_v2/fl_nodes_v2.dart';

void main() {
  GraphNode node(String id, Offset position) => GraphNode(
    id: id,
    position: position,
    width: 140,
    height: 60,
    ports: const <NodePort>[
      NodePort.input(id: 'in'),
      NodePort.output(id: 'out'),
    ],
  );

  NodeEditorController wired() => NodeEditorController(
    graph: NodeGraph(
      nodes: <GraphNode>[
        node('a', const Offset(60, 60)),
        node('b', const Offset(400, 200)),
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

  test('sync rebuilds only when the graph revision moves', () {
    final controller = wired();
    addTearDown(controller.dispose);
    final layout = ConnectionLayout();

    layout.sync(controller);
    expect(layout.rebuildCount, 1);
    expect(layout.length, 1);

    layout.sync(controller);
    expect(layout.rebuildCount, 1, reason: 'nothing changed');

    controller.moveNodes(<String, Offset>{'a': const Offset(80, 60)});
    layout.sync(controller);
    expect(layout.rebuildCount, 2);
  });

  /// Three nodes in a chain plus an unrelated pair, so "only the curves whose
  /// ends moved" has something to be wrong about.
  NodeEditorController chain() => NodeEditorController(
    graph: NodeGraph(
      nodes: <GraphNode>[
        node('a', const Offset(60, 60)),
        node('b', const Offset(400, 60)),
        node('c', const Offset(740, 60)),
        node('x', const Offset(60, 400)),
        node('y', const Offset(400, 400)),
      ],
      connections: const <NodeConnection>[
        NodeConnection(
          id: 'ab',
          from: PortRef('a', 'out'),
          to: PortRef('b', 'in'),
        ),
        NodeConnection(
          id: 'bc',
          from: PortRef('b', 'out'),
          to: PortRef('c', 'in'),
        ),
        NodeConnection(
          id: 'xy',
          from: PortRef('x', 'out'),
          to: PortRef('y', 'in'),
        ),
      ],
    ),
  );

  group('a pass only rebuilds the curves that moved', () {
    test('moving one node rebuilds only the curves attached to it', () {
      final controller = chain();
      addTearDown(controller.dispose);
      final layout = ConnectionLayout()..sync(controller);
      expect(layout.pathBuildCount, 3);

      final untouched = layout['xy']!;
      controller.moveNodes(<String, Offset>{'b': const Offset(400, 120)});
      layout.sync(controller);

      expect(
        layout.pathBuildCount,
        5,
        reason: "'b' is an end of two curves, and of no others",
      );
      expect(
        identical(layout['xy'], untouched),
        isTrue,
        reason: 'a curve nothing touched keeps the object it had, path and all',
      );
    });

    test('a node moved and moved back still costs nothing extra', () {
      final controller = chain();
      addTearDown(controller.dispose);
      final layout = ConnectionLayout()..sync(controller);

      controller.moveNodes(<String, Offset>{'a': const Offset(60, 61)});
      layout.sync(controller);
      final built = layout.pathBuildCount;

      // A no-op mutation still bumps the revision; the endpoints decide.
      controller.moveNodes(<String, Offset>{'a': const Offset(60, 61)});
      layout.sync(controller);

      expect(layout.pathBuildCount, built);
    });

    test('adding and removing a wire touches only that wire', () {
      final controller = chain();
      addTearDown(controller.dispose);
      final layout = ConnectionLayout()..sync(controller);
      final built = layout.pathBuildCount;

      final id = controller.connect(
        const PortRef('a', 'out'),
        const PortRef('y', 'in'),
      );
      layout.sync(controller);
      expect(layout.pathBuildCount, built + 1);
      expect(layout.length, 4);

      controller.removeConnections(<String>[id!]);
      layout.sync(controller);
      expect(layout.pathBuildCount, built + 1, reason: 'nothing to build');
      expect(layout.length, 3);
      expect(layout[id], isNull);
    });

    test('a connection to a deleted node stops being drawn and picked', () {
      final controller = chain();
      addTearDown(controller.dispose);
      final layout = ConnectionLayout()..sync(controller);

      controller.removeNodes(<String>['c']);
      layout.sync(controller);

      expect(layout['bc'], isNull);
      expect(
        layout.idsIn(const Rect.fromLTWH(0, 0, 4000, 4000)),
        isNot(contains('bc')),
      );
    });

    test('changing the curvature rebuilds every curve', () {
      final controller = chain();
      addTearDown(controller.dispose);
      final layout = ConnectionLayout()..sync(controller);
      final built = layout.pathBuildCount;

      layout.curvature = layout.curvature + 0.1;
      layout.sync(controller);

      expect(layout.pathBuildCount, built + 3);
    });
  });

  test('paths are in scene space, so hit tests survive a zoom', () {
    final controller = wired();
    addTearDown(controller.dispose);
    final layout = ConnectionLayout()..sync(controller);

    final geometry = layout['c1']!;
    // The output port of 'a' sits on its right edge, at its vertical centre.
    expect(geometry.bounds.contains(const Offset(200, 90)), isTrue);

    controller.camera.setScale(3);
    layout.sync(controller);
    expect(layout.rebuildCount, 1, reason: 'zoom must not invalidate geometry');
  });

  test('hitTest picks the nearest curve within tolerance', () {
    final controller = wired();
    addTearDown(controller.dispose);
    final layout = ConnectionLayout()..sync(controller);

    final onCurve = ConnectionPath.midpoint(layout['c1']!.path)!;
    expect(layout.hitTest(onCurve, tolerance: 6), 'c1');
    expect(
      layout.hitTest(onCurve + const Offset(0, 200), tolerance: 6),
      isNull,
    );
  });

  test('a dropped connection leaves the cache', () {
    final controller = wired();
    addTearDown(controller.dispose);
    final layout = ConnectionLayout()..sync(controller);
    expect(layout.length, 1);

    controller.removeNodes(<String>['b']);
    layout.sync(controller);

    expect(layout.length, 0);
    expect(layout['c1'], isNull);
  });

  testWidgets('panning and zooming do not rebuild connection paths', (
    tester,
  ) async {
    final controller = wired();
    addTearDown(controller.dispose);
    final editorKey = GlobalKey<NodeEditorState>();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NodeEditor(
            key: editorKey,
            controller: controller,
            theme: NodeEditorTheme.dark(),
            nodeBuilder: (context, graphNode, state) =>
                const ColoredBox(color: Color(0xFF2A2E38)),
          ),
        ),
      ),
    );

    final layout = editorKey.currentState!.connectionLayout;
    final baseline = layout.rebuildCount;
    expect(baseline, greaterThan(0));

    for (var i = 0; i < 12; i++) {
      controller.camera.panBy(const Offset(17, 9));
      controller.camera.zoomBy(1.05);
      await tester.pump();
    }

    expect(
      layout.rebuildCount,
      baseline,
      reason: 'viewport changes must not invalidate scene-space paths',
    );
  });

  testWidgets('moving a node does rebuild them', (tester) async {
    final controller = wired();
    addTearDown(controller.dispose);
    final editorKey = GlobalKey<NodeEditorState>();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NodeEditor(
            key: editorKey,
            controller: controller,
            theme: NodeEditorTheme.dark(),
            nodeBuilder: (context, graphNode, state) =>
                const ColoredBox(color: Color(0xFF2A2E38)),
          ),
        ),
      ),
    );

    final layout = editorKey.currentState!.connectionLayout;
    final baseline = layout.rebuildCount;

    controller.moveNodes(<String, Offset>{'a': const Offset(70, 60)});
    await tester.pump();

    expect(layout.rebuildCount, baseline + 1);
  });
}
