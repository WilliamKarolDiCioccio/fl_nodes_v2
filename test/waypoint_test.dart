import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fl_nodes_v2/fl_nodes_v2.dart';

/// Waypoints: points a wire is routed *through*, placed on the wire by the
/// user, with the bezier control points solved from them. They are the
/// wire's own — one optional key, undone with the wire, carried with it,
/// dropped with it — and never a thing selected on its own.
void main() {
  GraphNode node(String id, {Offset position = Offset.zero}) => GraphNode(
    id: id,
    type: 'step',
    position: position,
    width: 100,
    height: 50,
    ports: const <NodePort>[
      NodePort.input(id: 'in'),
      NodePort.output(id: 'out'),
    ],
  );

  const wire = NodeConnection(
    id: 'ab',
    from: PortRef('a', 'out'),
    to: PortRef('b', 'in'),
  );

  NodeEditorController boot({List<Offset> waypoints = const <Offset>[]}) {
    final controller = NodeEditorController(
      graph: NodeGraph(
        nodes: <GraphNode>[
          node('a'),
          node('b', position: const Offset(400, 200)),
        ],
        connections: <NodeConnection>[wire.copyWith(waypoints: waypoints)],
      ),
    );
    addTearDown(controller.dispose);
    return controller;
  }

  /// Distance from [point] to the nearest sample of [path].
  double offBy(Path path, Offset point) =>
      ConnectionPath.distanceTo(path, point, step: 1);

  group('ConnectionPath through waypoints', () {
    const from = Offset(100, 100);
    const to = Offset(500, 300);

    test('no waypoints is the very same curve as before', () {
      final segments = ConnectionPath.segments(from, to);
      final arm = ConnectionPath.controlArm(from, to);
      expect(segments, hasLength(1));
      expect(segments.single.c1, from + Offset(arm, 0));
      expect(segments.single.c2, to + Offset(-arm, 0));
      expect(
        ConnectionPath.build(from, to).getBounds(),
        ConnectionPath.build(from, to, via: const <Offset>[]).getBounds(),
      );
    });

    test('the wire passes through every waypoint, in order', () {
      const via = <Offset>[Offset(200, 260), Offset(380, 40)];
      final path = ConnectionPath.build(from, to, via: via);

      for (final point in via) {
        expect(offBy(path, point), lessThan(1.0));
      }
      final segments = ConnectionPath.segments(from, to, via: via);
      expect(segments.map((s) => s.start), <Offset>[from, ...via]);
      expect(segments.map((s) => s.end), <Offset>[...via, to]);
    });

    test('the join at a waypoint is smooth', () {
      const via = <Offset>[Offset(300, 260)];
      final segments = ConnectionPath.segments(from, to, via: via);
      final w = via.single;
      // The arm arriving and the arm leaving point the same way: the wire
      // does not kink at the handle.
      final arriving = w - segments[0].c2;
      final leaving = segments[1].c1 - w;
      final cross = arriving.dx * leaving.dy - arriving.dy * leaving.dx;
      expect(cross.abs(), lessThan(1e-6));
      expect(
        arriving.dx * leaving.dx + arriving.dy * leaving.dy,
        greaterThan(0),
      );
    });

    test('the ends still leave and arrive along their port normals', () {
      const via = <Offset>[Offset(300, 260)];
      final segments = ConnectionPath.segments(from, to, via: via);
      expect(segments.first.c1.dy, from.dy);
      expect(segments.first.c1.dx, greaterThan(from.dx));
      expect(segments.last.c2.dy, to.dy);
      expect(segments.last.c2.dx, lessThan(to.dx));
    });

    test('a waypoint that doubles straight back does not produce NaN', () {
      const via = <Offset>[
        Offset(300, 200),
        Offset(200, 150),
        Offset(300, 200),
      ];
      final segments = ConnectionPath.segments(from, to, via: via);
      for (final segment in segments) {
        for (final point in <Offset>[segment.c1, segment.c2]) {
          expect(point.dx.isNaN || point.dy.isNaN, isFalse);
        }
      }
    });

    test('nearestOnRoute says which segment, and lands on the curve', () {
      const via = <Offset>[Offset(300, 260)];
      final path = ConnectionPath.build(from, to, via: via);

      final early = ConnectionPath.nearestOnRoute(
        const Offset(180, 140),
        from: from,
        to: to,
        via: via,
      );
      expect(early.index, 0, reason: 'before the waypoint');
      expect(offBy(path, early.position), lessThan(1.0));

      final late = ConnectionPath.nearestOnRoute(
        const Offset(420, 300),
        from: from,
        to: to,
        via: via,
      );
      expect(late.index, 1, reason: 'after the waypoint');
      expect(offBy(path, late.position), lessThan(1.0));
      expect(late.distance, lessThan((const Offset(420, 300) - to).distance));
    });
  });

  group('routing a connection', () {
    test('is an edit: undone, reported, refusable', () {
      final controller = boot();
      final edits = <GraphEdit>[];
      controller.onEdit = edits.add;

      controller.setConnectionWaypoints('ab', const <Offset>[Offset(200, 50)]);
      expect(controller.graph.connections['ab']!.waypoints, const <Offset>[
        Offset(200, 50),
      ]);
      expect(edits.single.kind, GraphEditKind.routeConnection);
      expect(edits.single.connectionIds, <String>{'ab'});
      expect(edits.single.nodeIds, <String>{'a', 'b'});

      controller.history.undo();
      expect(controller.graph.connections['ab']!.waypoints, isEmpty);

      controller.guard = (_) => false;
      controller.setConnectionWaypoints('ab', const <Offset>[Offset(1, 1)]);
      expect(controller.graph.connections['ab']!.waypoints, isEmpty);
    });

    test('an equal list is not an edit', () {
      final controller = boot(waypoints: const <Offset>[Offset(200, 50)]);
      final revision = controller.revision;
      controller.setConnectionWaypoints('ab', const <Offset>[Offset(200, 50)]);
      expect(controller.revision, revision);
      expect(controller.history.canUndo, isFalse);
    });

    test('insert keeps the run in order and clamps the index', () {
      final controller = boot(waypoints: const <Offset>[Offset(200, 50)]);
      controller.insertWaypoint('ab', 1, const Offset(300, 150));
      controller.insertWaypoint('ab', 0, const Offset(150, 20));
      controller.insertWaypoint('ab', 99, const Offset(390, 190));
      expect(controller.graph.connections['ab']!.waypoints, const <Offset>[
        Offset(150, 20),
        Offset(200, 50),
        Offset(300, 150),
        Offset(390, 190),
      ]);
    });

    test('move takes the point as given; remove ignores an index it has not '
        'got', () {
      final controller = boot(waypoints: const <Offset>[Offset(200, 50)]);
      controller.snapToGrid = true;
      controller.reportGridStep(10);
      controller.moveWaypoint('ab', 0, const Offset(213, 58));
      expect(
        controller.graph.connections['ab']!.waypoints,
        const <Offset>[Offset(213, 58)],
        reason:
            'the grid does not reach a waypoint through the controller: where '
            'a handle belongs depends on the connection style, which only the '
            'editor can see',
      );
      controller.moveWaypoint('ab', 3, Offset.zero);
      controller.removeWaypoint('ab', 3);
      expect(controller.graph.connections['ab']!.waypoints, const <Offset>[
        Offset(213, 58),
      ]);
      controller.removeWaypoint('ab', 0);
      expect(controller.graph.connections['ab']!.waypoints, isEmpty);
    });

    test('a wire carried whole by a move takes its route along', () {
      final controller = boot(waypoints: const <Offset>[Offset(200, 50)]);
      controller.translateNodes(<String>['a', 'b'], const Offset(30, -20));
      expect(controller.graph.connections['ab']!.waypoints, const <Offset>[
        Offset(230, 30),
      ]);
    });

    test('a wire with one end moving keeps its route where it was', () {
      final controller = boot(waypoints: const <Offset>[Offset(200, 50)]);
      controller.translateNodes(<String>['b'], const Offset(30, -20));
      expect(controller.graph.connections['ab']!.waypoints, const <Offset>[
        Offset(200, 50),
      ]);
    });

    test('an arrangement retires the routes of the wires it moved', () {
      final controller = boot(waypoints: const <Offset>[Offset(200, 50)]);
      final moved = controller.applyLayout(
        (graph, _) => <String, Offset>{'b': const Offset(600, 0)},
      );
      expect(moved, isTrue);
      expect(controller.graph.connections['ab']!.waypoints, isEmpty);
      controller.history.undo();
      expect(
        controller.graph.connections['ab']!.waypoints,
        const <Offset>[Offset(200, 50)],
        reason: 'one step takes back the move and the route together',
      );
    });

    test('a copy pastes with its route in the same shape', () {
      final controller = boot(waypoints: const <Offset>[Offset(200, 50)]);
      controller.selection.selectNodes(<String>['a', 'b']);
      expect(controller.clipboard.copy(), isTrue);
      final pasted = controller.clipboard.paste(
        scenePosition: const Offset(1000, 1000),
      );
      expect(pasted, hasLength(2));

      final copy = controller.graph.connections.values.firstWhere(
        (c) => c.id != 'ab',
      );
      final copiedA = controller.graph.nodes[copy.from.nodeId]!;
      // The fragment's origin was `a` at (0, 0), so the route sits at the
      // same offset from the pasted `a` as it did from the original.
      expect(copy.waypoints.single - copiedA.position, const Offset(200, 50));
    });
  });

  group('on disk', () {
    const codec = NodeGraphCodec();

    test('round-trips, and is written only when there is one', () {
      final routed = boot(waypoints: const <Offset>[Offset(200, 50)]);
      final json = codec.encode(GraphDocument(graph: routed.graph));
      final connections = json['connections'] as List<Object?>;
      final entry = connections.single as Map<String, Object?>;
      expect(entry['waypoints'], <Object?>[
        <Object?>[200.0, 50.0],
      ]);
      expect(
        codec.decode(json).graph.connections['ab']!.waypoints,
        const <Offset>[Offset(200, 50)],
      );

      final plain = boot();
      final plainJson = codec.encode(GraphDocument(graph: plain.graph));
      final plainEntry =
          (plainJson['connections'] as List<Object?>).single
              as Map<String, Object?>;
      expect(
        plainEntry.containsKey('waypoints'),
        isFalse,
        reason: 'an older build reads the wire and never sees the key',
      );
      expect(
        codec.decode(plainJson).graph.connections['ab']!.waypoints,
        isEmpty,
      );
    });
  });

  group('ConnectionLayout', () {
    test('a moved handle rebuilds the curve although no end moved', () {
      final controller = boot(waypoints: const <Offset>[Offset(200, 50)]);
      final layout = ConnectionLayout()..sync(controller);
      final before = layout.pathBuildCount;
      expect(offBy(layout['ab']!.path, const Offset(200, 50)), lessThan(1.0));

      controller.moveWaypoint('ab', 0, const Offset(250, 300));
      layout.sync(controller);

      expect(layout.pathBuildCount, before + 1);
      expect(offBy(layout['ab']!.path, const Offset(250, 300)), lessThan(1.0));
      expect(
        layout.hitTest(const Offset(250, 300), tolerance: 4),
        'ab',
        reason: 'picking follows the curve as drawn',
      );
    });
  });

  group('on the canvas', () {
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

    Future<NodeEditorController> pump(
      WidgetTester tester, {
      List<Offset> waypoints = const <Offset>[],
    }) async {
      final controller = NodeEditorController(
        graph: NodeGraph(
          nodes: <GraphNode>[
            node('a', position: const Offset(100, 100)),
            node('b', position: const Offset(500, 300)),
          ],
          connections: <NodeConnection>[wire.copyWith(waypoints: waypoints)],
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

    Future<void> doubleClick(WidgetTester tester, Offset at) async {
      await tester.tapAt(at);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(at);
      await tester.pumpAndSettle();
    }

    /// Where the wire runs, from the editor's own cache.
    Path drawnPath(WidgetTester tester) => tester
        .state<NodeEditorState>(find.byType(NodeEditor))
        .connectionLayout['ab']!
        .path;

    testWidgets('double-clicking a wire adds a waypoint on the curve', (
      tester,
    ) async {
      final controller = await pump(tester);
      final before = drawnPath(tester);
      // Somewhere along the wire: its midpoint, which the cache knows.
      final mid = ConnectionPath.midpoint(before)!;
      // Aim a few pixels off it, inside the hit tolerance.
      final aim = mid + const Offset(0, 4);

      await doubleClick(tester, screenPoint(tester, controller, aim));

      final waypoints = controller.graph.connections['ab']!.waypoints;
      expect(waypoints, hasLength(1));
      expect(
        offBy(before, waypoints.single),
        lessThan(1.0),
        reason: 'the point goes on the curve, not under the pointer',
      );
      expect(controller.selection.connectionIds, <String>{'ab'});
    });

    testWidgets('a single click on a wire adds nothing', (tester) async {
      final controller = await pump(tester);
      final mid = ConnectionPath.midpoint(drawnPath(tester))!;
      await tester.tapAt(screenPoint(tester, controller, mid));
      await tester.pumpAndSettle();
      expect(controller.graph.connections['ab']!.waypoints, isEmpty);
      expect(controller.selection.connectionIds, <String>{'ab'});
    });

    testWidgets('dragging a handle routes the wire, in one undo step', (
      tester,
    ) async {
      final controller = await pump(
        tester,
        waypoints: const <Offset>[Offset(300, 100)],
      );
      final from = screenPoint(tester, controller, const Offset(300, 100));
      final to = screenPoint(tester, controller, const Offset(330, 260));

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

      expect(controller.graph.connections['ab']!.waypoints, const <Offset>[
        Offset(330, 260),
      ]);
      expect(controller.graph.nodes['a']!.position, const Offset(100, 100));
      expect(
        controller.selection.connectionIds,
        <String>{'ab'},
        reason: 'the wire the handle belongs to is lit',
      );
      expect(
        offBy(drawnPath(tester), const Offset(330, 260)),
        lessThan(1.0),
        reason: 'the drawn wire follows the handle',
      );

      controller.history.undo();
      expect(
        controller.graph.connections['ab']!.waypoints,
        const <Offset>[Offset(300, 100)],
        reason: 'the whole drag is one step',
      );
      expect(controller.history.canUndo, isFalse);
    });

    testWidgets('double-clicking a handle removes it', (tester) async {
      final controller = await pump(
        tester,
        waypoints: const <Offset>[Offset(300, 100), Offset(350, 250)],
      );
      await doubleClick(
        tester,
        screenPoint(tester, controller, const Offset(300, 100)),
      );
      expect(controller.graph.connections['ab']!.waypoints, const <Offset>[
        Offset(350, 250),
      ]);
    });

    testWidgets('right-clicking a handle offers to remove it', (tester) async {
      final controller = await pump(
        tester,
        waypoints: const <Offset>[Offset(300, 100)],
      );
      await tester.tapAt(
        screenPoint(tester, controller, const Offset(300, 100)),
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();

      expect(find.text('Remove waypoint'), findsOneWidget);
      await tester.tap(find.text('Remove waypoint'));
      await tester.pumpAndSettle();
      expect(controller.graph.connections['ab']!.waypoints, isEmpty);
    });

    testWidgets('a handle is not a place to start a wire from', (tester) async {
      final controller = await pump(
        tester,
        waypoints: const <Offset>[Offset(300, 100)],
      );
      final from = screenPoint(tester, controller, const Offset(300, 100));
      // Drop onto node b's body, where a wire would have landed.
      final to = screenPoint(tester, controller, const Offset(550, 320));
      final gesture = await tester.startGesture(
        from,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.moveTo(to);
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(controller.graph.connections, hasLength(1));
      expect(controller.graph.connections['ab']!.waypoints, const <Offset>[
        Offset(550, 320),
      ]);
    });
  });
}
