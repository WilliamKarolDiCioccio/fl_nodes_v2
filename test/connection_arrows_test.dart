import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fl_nodes_v2/fl_nodes_v2.dart';

/// Direction markers live on the curve, not at the port.
///
/// An arrowhead at the receiving port has to pick an angle, and the only one
/// available there is the port's normal — which is axis-aligned while the
/// curve arriving is not, so the head disagreed with its own wire at the one
/// place the two touch. Sampling the path fixes the angle and, repeated, says
/// which way the data runs along the whole length rather than only where it
/// lands.
void main() {
  Path curve({Offset from = Offset.zero, Offset to = const Offset(400, 300)}) =>
      ConnectionPath.build(from, to);

  group('arrowsAlong', () {
    test('the count follows the length and is clamped both ways', () {
      List<PathArrow> arrowsFor(Offset to) =>
          ConnectionPath.arrowsAlong(curve(to: to), spacing: 140, maxCount: 4);

      expect(
        arrowsFor(const Offset(60, 0)),
        hasLength(1),
        reason: 'a stub still has to say which way it points',
      );
      expect(arrowsFor(const Offset(300, 0)), hasLength(2));
      expect(
        arrowsFor(const Offset(4000, 0)),
        hasLength(4),
        reason: 'a wire across the canvas must not become a dotted line',
      );
    });

    test('nothing lands on either end', () {
      final path = curve();
      final arrows = ConnectionPath.arrowsAlong(
        path,
        spacing: 140,
        maxCount: 4,
      );
      final metric = path.computeMetrics().first;
      final start = metric.getTangentForOffset(0)!.position;
      final end = metric.getTangentForOffset(metric.length)!.position;

      for (final arrow in arrows) {
        expect(
          (arrow.position - start).distance,
          greaterThan(8),
          reason: 'the seam is the thing being moved away from',
        );
        expect((arrow.position - end).distance, greaterThan(8));
      }
    });

    test('spacing is even', () {
      final path = curve(to: const Offset(900, 0));
      final arrows = ConnectionPath.arrowsAlong(
        path,
        spacing: 140,
        maxCount: 8,
      );
      expect(arrows.length, greaterThan(2));

      final gaps = <double>[
        for (var i = 1; i < arrows.length; i++)
          (arrows[i].position - arrows[i - 1].position).distance,
      ];
      for (final gap in gaps) {
        expect(gap, closeTo(gaps.first, 1));
      }
    });

    test('the angle is the curve\'s own, not a port normal', () {
      final arrows = ConnectionPath.arrowsAlong(
        curve(),
        spacing: 90,
        maxCount: 4,
      );
      final middle = arrows[arrows.length ~/ 2];

      expect(middle.direction.distance, closeTo(1, 1e-6));
      expect(
        middle.direction.dy.abs(),
        greaterThan(0.1),
        reason:
            'this curve climbs 300 units; a port normal is axis-aligned and '
            'would report a flat dy here, which is the bug being fixed',
      );
    });

    test('the direction is the data flow, so a leftward link points left', () {
      double dx(Offset from, Offset to) => ConnectionPath.arrowsAlong(
        ConnectionPath.build(from, to),
        spacing: 500,
        maxCount: 1,
      ).single.direction.dx;

      expect(dx(Offset.zero, const Offset(400, 0)), greaterThan(0));
      expect(
        dx(const Offset(400, 0), Offset.zero),
        lessThan(0),
        reason: 'the marker follows the wire from emitter to receiver',
      );
    });

    test('a degenerate curve yields nothing rather than throwing', () {
      expect(
        ConnectionPath.arrowsAlong(Path(), spacing: 140, maxCount: 4),
        isEmpty,
      );
    });
  });

  group('the cache holds them', () {
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
          node('b', const Offset(500, 260)),
          node('c', const Offset(60, 500)),
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

    test('sampled once with the path, not on every paint', () {
      final controller = wired();
      addTearDown(controller.dispose);
      final layout = ConnectionLayout()..sync(controller);
      final arrows = layout['ab']!.arrows;
      expect(arrows, isNotEmpty);

      // An unrelated node moving bumps the revision but not this curve.
      controller.moveNodes(<String, Offset>{'c': const Offset(60, 520)});
      layout.sync(controller);

      expect(
        identical(layout['ab']!.arrows, arrows),
        isTrue,
        reason: 'walking a path\'s metrics is not a per-frame cost',
      );
    });

    test('resampled when the curve moves', () {
      final controller = wired();
      addTearDown(controller.dispose);
      final layout = ConnectionLayout()..sync(controller);
      final before = layout['ab']!.arrows.first.position;

      controller.moveNodes(<String, Offset>{'b': const Offset(900, 700)});
      layout.sync(controller);

      expect(layout['ab']!.arrows.first.position, isNot(before));
    });

    test('changing the spacing resamples every curve', () {
      final controller = wired();
      addTearDown(controller.dispose);
      final layout = ConnectionLayout()..sync(controller);
      final before = layout['ab']!.arrows.length;

      layout.arrowSpacing = 20;
      layout.sync(controller);

      expect(layout['ab']!.arrows.length, greaterThan(before));
    });

    testWidgets('the editor feeds it from the theme', (tester) async {
      final controller = wired();
      addTearDown(controller.dispose);
      final key = GlobalKey<NodeEditorState>();

      Future<void> pump(int maxArrows) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: NodeEditor(
                key: key,
                controller: controller,
                theme: NodeEditorTheme.dark().copyWith(
                  connectionArrowSpacing: 30,
                  connectionArrowMaxCount: maxArrows,
                ),
                nodeBuilder: (context, node, state) =>
                    const ColoredBox(color: Color(0xFF2A2E38)),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await pump(2);
      expect(key.currentState!.connectionLayout['ab']!.arrows, hasLength(2));

      // A theme change has to reach the cache, not just the painter.
      await pump(6);
      expect(key.currentState!.connectionLayout['ab']!.arrows, hasLength(6));
    });
  });
}
