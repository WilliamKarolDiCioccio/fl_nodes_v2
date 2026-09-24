import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fl_nodes_v2/fl_nodes_v2.dart';

/// Wires drawn in right angles: `ConnectionStyle.orthogonal`, one choice for
/// the whole canvas. The route is a handful of templates ranked by corners
/// and length and never doubling back; a waypoint is a corner; and the
/// curved default is untouched by any of it.
void main() {
  const right = Offset(1, 0);

  /// Every leg of [route] is horizontal or vertical.
  void expectAxisAligned(List<Offset> route) {
    for (var i = 1; i < route.length; i++) {
      final leg = route[i] - route[i - 1];
      expect(
        leg.dx == 0 || leg.dy == 0,
        isTrue,
        reason: 'leg $i of $route is diagonal',
      );
      expect(leg, isNot(Offset.zero), reason: 'leg $i of $route is empty');
    }
  }

  /// No two consecutive legs of [route] point opposite ways.
  void expectNoUTurn(List<Offset> route) {
    for (var i = 2; i < route.length; i++) {
      final a = route[i - 1] - route[i - 2];
      final b = route[i] - route[i - 1];
      expect(
        a.dx * b.dx + a.dy * b.dy,
        isNot(lessThan(0)),
        reason: 'legs ${i - 1} and $i of $route double back',
      );
    }
  }

  group('OrthogonalRoute.legs', () {
    test(
      'facing ports with the target ahead take the Z through the middle',
      () {
        final route = OrthogonalRoute.legs(
          start: const Offset(100, 100),
          end: const Offset(500, 300),
          startDirection: right,
          endDirection: right,
          stub: 24,
        );
        // Stub ends at 124 and 476; the vertical leg sits halfway between.
        expect(route, const <Offset>[
          Offset(100, 100),
          Offset(300, 100),
          Offset(300, 300),
          Offset(500, 300),
        ]);
      },
    );

    test('a target behind the source on its own row goes round by a lane', () {
      final route = OrthogonalRoute.legs(
        start: const Offset(500, 200),
        end: const Offset(100, 200),
        startDirection: right,
        endDirection: right,
        stub: 24,
      );
      expectAxisAligned(route);
      expectNoUTurn(route);
      expect(route, hasLength(6));
      expect(
        route[2].dy,
        isNot(200),
        reason: 'the lane is off the row the wire would otherwise fold on',
      );
    });

    test('facing ports on one row join with a single straight leg', () {
      final route = OrthogonalRoute.legs(
        start: const Offset(100, 100),
        end: const Offset(500, 100),
        startDirection: right,
        endDirection: right,
        stub: 24,
      );
      expect(route, const <Offset>[Offset(100, 100), Offset(500, 100)]);
    });

    test('a target behind the source goes round by a lane, never back', () {
      final route = OrthogonalRoute.legs(
        start: const Offset(500, 100),
        end: const Offset(100, 300),
        startDirection: right,
        endDirection: right,
        stub: 24,
      );
      expectAxisAligned(route);
      expectNoUTurn(route);
      expect(route.first, const Offset(500, 100));
      expect(route.last, const Offset(100, 300));
      expect(
        route[1],
        const Offset(524, 100),
        reason: 'the wire still leaves the port along its normal',
      );
      expect(
        route[route.length - 2],
        const Offset(76, 300),
        reason: 'and still arrives along the other one',
      );
      expect(route, hasLength(6), reason: 'out, down, back, down, in');
    });

    test('two ports on the same side go out past the further one', () {
      final route = OrthogonalRoute.legs(
        start: const Offset(100, 100),
        end: const Offset(300, 300),
        startDirection: right,
        endDirection: -right,
        stub: 24,
      );
      expectAxisAligned(route);
      expectNoUTurn(route);
      final furthest = route.map((p) => p.dx).reduce((a, b) => a > b ? a : b);
      expect(furthest, 324, reason: 'the vertical leg sits beyond both stubs');
    });

    test('never doubles back and stays axis-aligned, whatever the ends', () {
      const directions = <Offset>[
        Offset(1, 0),
        Offset(-1, 0),
        Offset(0, 1),
        Offset(0, -1),
      ];
      const start = Offset(200, 200);
      for (final startDirection in directions) {
        for (final endDirection in directions) {
          for (var dx = -300; dx <= 300; dx += 100) {
            for (var dy = -300; dy <= 300; dy += 100) {
              // A wire from a point to itself is not a route; two ports
              // never share a position.
              if (dx == 0 && dy == 0) continue;
              final route = OrthogonalRoute.legs(
                start: start,
                end: start + Offset(dx.toDouble(), dy.toDouble()),
                startDirection: startDirection,
                endDirection: endDirection,
                stub: 24,
              );
              expectAxisAligned(route);
              expectNoUTurn(route);
              expect(route.first, start);
              expect(route.last, start + Offset(dx.toDouble(), dy.toDouble()));
            }
          }
        }
      }
    });

    test('a free start turns across the axis it arrived on', () {
      final route = OrthogonalRoute.legs(
        start: const Offset(300, 100),
        end: const Offset(500, 300),
        incomingAxis: right,
        stub: 24,
      );
      expect(route, const <Offset>[
        Offset(300, 100),
        Offset(300, 300),
        Offset(500, 300),
      ], reason: 'the corner is at the waypoint, not somewhere after it');
    });
  });

  group('ConnectionPath, orthogonal', () {
    const from = Offset(100, 100);
    const to = Offset(500, 300);

    test('the wire is one contour through every waypoint', () {
      const via = <Offset>[Offset(300, 100), Offset(300, 250)];
      final path = ConnectionPath.build(
        from,
        to,
        via: via,
        style: ConnectionStyle.orthogonal,
      );
      expect(path.computeMetrics().length, 1);
      for (final point in via) {
        expect(
          ConnectionPath.distanceTo(path, point, step: 1),
          // An arc of radius r cuts its corner by r(√2 − 1).
          lessThan(8 * 0.4143 + 0.1),
          reason: 'a corner rounded with radius 8 still passes near $point',
        );
      }
    });

    test(
      'spans hand the incoming axis forward so each waypoint is a corner',
      () {
        const via = <Offset>[Offset(300, 100)];
        final spans = ConnectionPath.orthogonalSpans(from, to, via: via);
        expect(spans, hasLength(2));
        expect(spans.first.corners.last, via.single);
        final leaving = spans.last.corners[1] - spans.last.corners[0];
        expect(
          leaving.dx,
          0,
          reason: 'arrived horizontally, leaves vertically',
        );
      },
    );

    test('the default style is still the very same cubic', () {
      final plain = ConnectionPath.build(from, to);
      final explicit = ConnectionPath.build(
        from,
        to,
        style: ConnectionStyle.curved,
      );
      expect(explicit.getBounds(), plain.getBounds());
      expect(
        ConnectionPath.segments(from, to).single.c1,
        from + Offset(ConnectionPath.controlArm(from, to), 0),
      );
    });

    test(
      'roundedPolyline keeps inside its corners and shrinks on short legs',
      () {
        const corners = <Offset>[
          Offset(0, 0),
          Offset(100, 0),
          Offset(100, 6),
          Offset(200, 6),
        ];
        final path = ConnectionPath.roundedPolyline(corners, radius: 8);
        final bounds = path.getBounds();
        expect(bounds.left, 0);
        expect(bounds.right, 200);
        expect(bounds.top, 0);
        expect(bounds.bottom, 6, reason: 'an arc never bulges past a corner');
        expect(
          ConnectionPath.distanceTo(path, const Offset(100, 3), step: 0.5),
          lessThan(0.5),
          reason:
              'a six-pixel leg between two arcs of radius three is still '
              'the leg',
        );
      },
    );

    test('nearestOnRoute says which span, in right angles too', () {
      const via = <Offset>[Offset(300, 100)];
      final late = ConnectionPath.nearestOnRoute(
        const Offset(310, 250),
        from: from,
        to: to,
        via: via,
        style: ConnectionStyle.orthogonal,
      );
      expect(late.index, 1);
      expect(
        late.position,
        const Offset(300, 250),
        reason:
            'projected exactly onto the vertical leg down from the '
            'waypoint, not onto the nearest sample',
      );
      final early = ConnectionPath.nearestOnRoute(
        const Offset(200, 90),
        from: from,
        to: to,
        via: via,
        style: ConnectionStyle.orthogonal,
      );
      expect(early.index, 0);
      expect(early.position, const Offset(200, 100));
    });

    test('axis-aligned arrows point along an axis even on an arc', () {
      final path = ConnectionPath.build(
        from,
        to,
        style: ConnectionStyle.orthogonal,
      );
      final arrows = ConnectionPath.arrowsAlong(
        path,
        spacing: 30,
        maxCount: 40,
        axisAligned: true,
      );
      expect(arrows, isNotEmpty);
      for (final arrow in arrows) {
        expect(
          arrow.direction.dx.abs() + arrow.direction.dy.abs(),
          1,
          reason: '${arrow.direction} is not a unit axis vector',
        );
      }
    });
  });

  group('ConnectionLayout', () {
    GraphNode node(String id, Offset position) => GraphNode(
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

    test('a style switch rebuilds every wire, once', () {
      final controller = NodeEditorController(
        graph: NodeGraph(
          nodes: <GraphNode>[
            node('a', Offset.zero),
            node('b', const Offset(400, 200)),
          ],
          connections: const <NodeConnection>[
            NodeConnection(
              id: 'ab',
              from: PortRef('a', 'out'),
              to: PortRef('b', 'in'),
            ),
          ],
        ),
      );
      addTearDown(controller.dispose);
      final layout = ConnectionLayout()..sync(controller);
      double length() => layout['ab']!.path.computeMetrics().single.length;
      final curved = length();
      final built = layout.pathBuildCount;

      layout
        ..style = ConnectionStyle.orthogonal
        ..sync(controller);
      expect(layout.pathBuildCount, built + 1);
      expect(
        length(),
        greaterThan(curved),
        reason: 'the same rect, but a Manhattan route is the longer one',
      );

      layout.sync(controller);
      expect(layout.pathBuildCount, built + 1, reason: 'settled');
    });
  });

  group('on the canvas', () {
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
      required NodeEditorTheme theme,
    }) async {
      final controller = NodeEditorController(
        graph: NodeGraph(
          nodes: <GraphNode>[
            GraphNode(
              id: 'a',
              type: 'step',
              position: const Offset(100, 100),
              width: 100,
              height: 50,
            ),
            GraphNode(
              id: 'b',
              type: 'step',
              position: const Offset(500, 300),
              width: 100,
              height: 50,
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
              nodeBuilder: (context, graphNode, state) =>
                  const ColoredBox(color: Color(0xFF2A2E38)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final id = controller.connect(
        const PortRef('a', 'out'),
        const PortRef('b', 'in'),
      )!;
      controller.setConnectionWaypoints(id, const <Offset>[Offset(300, 200)]);
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

    Future<void> dragHandle(
      WidgetTester tester,
      NodeEditorController controller,
      Offset from,
      Offset to,
    ) async {
      final gesture = await tester.startGesture(
        screenPoint(tester, controller, from),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.moveTo(screenPoint(tester, controller, to));
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.up();
      await tester.pumpAndSettle();
    }

    testWidgets('a dragged handle snaps onto the row of its neighbour', (
      tester,
    ) async {
      final controller = await pump(
        tester,
        theme: NodeEditorTheme.dark().copyWith(
          connectionStyle: ConnectionStyle.orthogonal,
        ),
      );
      final wire = controller.graph.connections.values.single;
      final portY = controller.layout.portPosition(wire.from)!.dy;

      await dragHandle(
        tester,
        controller,
        const Offset(300, 200),
        Offset(320, portY + 4),
      );

      final moved = controller.graph.connections.values.single.waypoints.single;
      expect(moved.dy, portY, reason: 'four pixels off the row snaps onto it');
      expect(moved.dx, 320, reason: 'the other axis is left alone');
    });

    testWidgets('with the grid on, a row still beats a line', (tester) async {
      final controller = await pump(
        tester,
        theme: NodeEditorTheme.dark().copyWith(
          connectionStyle: ConnectionStyle.orthogonal,
        ),
      );
      controller.snapToGrid = true;
      final wire = controller.graph.connections.values.single;
      final portY = controller.layout.portPosition(wire.from)!.dy;

      await dragHandle(
        tester,
        controller,
        const Offset(300, 200),
        Offset(320, portY + 4),
      );

      final moved = controller.graph.connections.values.single.waypoints.single;
      expect(
        moved.dy,
        portY,
        reason:
            'the alignment is asked about the raw pointer, so it still fires '
            'at four pixels — snapping first would hand it a point 24 units '
            'away from the row and it would quietly stop firing rather than '
            'lose',
      );
      expect(
        moved.dx,
        312,
        reason: 'and the axis no neighbour claimed takes the grid',
      );
    });

    testWidgets('with the grid on, an unclaimed handle takes both lines', (
      tester,
    ) async {
      final controller = await pump(
        tester,
        theme: NodeEditorTheme.dark().copyWith(
          connectionStyle: ConnectionStyle.orthogonal,
        ),
      );
      controller.snapToGrid = true;

      await dragHandle(
        tester,
        controller,
        const Offset(300, 200),
        const Offset(350, 250),
      );

      final moved = controller.graph.connections.values.single.waypoints.single;
      expect(moved, const Offset(360, 240));
    });

    testWidgets('with the grid on, an exact alignment is still an alignment', (
      tester,
    ) async {
      final controller = await pump(
        tester,
        theme: NodeEditorTheme.dark().copyWith(
          connectionStyle: ConnectionStyle.orthogonal,
        ),
      );
      controller.snapToGrid = true;
      final wire = controller.graph.connections.values.single;
      final portX = controller.layout.portPosition(wire.to)!.dx;

      await dragHandle(
        tester,
        controller,
        const Offset(300, 200),
        Offset(portX, 400),
      );

      final moved = controller.graph.connections.values.single.waypoints.single;
      expect(
        moved.dx,
        portX,
        reason:
            'the handle was already dead on the column, so the alignment '
            'claimed that axis at zero distance. Reading the claim off a '
            'changed coordinate would call this axis free and snap it to a '
            'line — breaking the alignment on the one frame it was perfect',
      );
      expect(
        moved.dx % 24,
        isNot(0),
        reason: 'and a port column is not a line',
      );
      expect(moved.dy, 408, reason: 'the free axis still takes the grid');
    });

    testWidgets('with the grid on, a curved handle takes both lines', (
      tester,
    ) async {
      final controller = await pump(tester, theme: NodeEditorTheme.dark());
      controller.snapToGrid = true;
      final wire = controller.graph.connections.values.single;
      final portY = controller.layout.portPosition(wire.from)!.dy;

      await dragHandle(
        tester,
        controller,
        const Offset(300, 200),
        Offset(320, portY + 4),
      );

      final moved = controller.graph.connections.values.single.waypoints.single;
      expect(
        moved.dx,
        312,
        reason:
            'a point on a curve has no row to be on, so only the grid '
            'reaches it',
      );
      expect(moved.dy % 24, 0);
    });

    testWidgets(
      'a curved wire ignores the rows: a handle goes where it is put',
      (tester) async {
        final controller = await pump(tester, theme: NodeEditorTheme.dark());
        final wire = controller.graph.connections.values.single;
        final portY = controller.layout.portPosition(wire.from)!.dy;

        await dragHandle(
          tester,
          controller,
          const Offset(300, 200),
          Offset(320, portY + 4),
        );

        final moved =
            controller.graph.connections.values.single.waypoints.single;
        expect(moved, Offset(320, portY + 4));
      },
    );
  });
}
