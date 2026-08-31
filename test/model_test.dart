import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:fl_nodes_v2/fl_nodes_v2.dart';

void main() {
  GraphNode node(String id, {Offset position = Offset.zero}) => GraphNode(
    id: id,
    position: position,
    width: 100,
    height: 50,
    ports: const <NodePort>[
      NodePort.input(id: 'in'),
      NodePort.output(id: 'out'),
    ],
  );

  group('NodeGraph', () {
    test('indexes connections by node', () {
      final graph = NodeGraph(
        nodes: <GraphNode>[node('a'), node('b')],
        connections: const <NodeConnection>[
          NodeConnection(
            id: 'c',
            from: PortRef('a', 'out'),
            to: PortRef('b', 'in'),
          ),
        ],
      );

      expect(graph.connectionsOf('a').single.id, 'c');
      expect(graph.connectionsOf('b').single.id, 'c');
      expect(graph.connectionsOf('missing'), isEmpty);
      expect(graph.connectionsAt(const PortRef('a', 'in')), isEmpty);
      expect(graph.connectionsAt(const PortRef('a', 'out')).single.id, 'c');
    });

    test('removing a node drops its connections', () {
      final graph = NodeGraph(
        nodes: <GraphNode>[node('a'), node('b')],
        connections: const <NodeConnection>[
          NodeConnection(
            id: 'c',
            from: PortRef('a', 'out'),
            to: PortRef('b', 'in'),
          ),
        ],
      ).removeNodes(<String>['a']);

      expect(graph.nodes.keys, <String>['b']);
      expect(graph.connections, isEmpty);
      expect(graph.connectionsOf('b'), isEmpty);
    });

    test('mutations leave the original snapshot untouched', () {
      final original = NodeGraph(nodes: <GraphNode>[node('a')]);
      final next = original.putNode(node('b'));

      expect(original.nodes.keys, <String>['a']);
      expect(next.nodes.keys, <String>['a', 'b']);
    });

    test('contentBounds spans every node', () {
      final graph = NodeGraph(
        nodes: <GraphNode>[
          node('a', position: const Offset(0, 0)),
          node('b', position: const Offset(200, 100)),
        ],
      );

      expect(
        graph.contentBounds((n) => Size(n.width, n.height!)),
        const Rect.fromLTRB(0, 0, 300, 150),
      );
    });
  });

  group('NodeGeometry', () {
    test('spreads same-side ports evenly', () {
      const target = GraphNode(
        id: 'n',
        position: Offset.zero,
        width: 100,
        height: 90,
        ports: <NodePort>[
          NodePort.output(id: 'a'),
          NodePort.output(id: 'b'),
        ],
      );

      expect(
        NodeGeometry.anchorOf(target, target.ports[0]),
        const Offset(1, 1 / 3),
      );
      expect(
        NodeGeometry.anchorOf(target, target.ports[1]),
        const Offset(1, 2 / 3),
      );
    });

    test('honours an explicit anchor', () {
      const target = GraphNode(
        id: 'n',
        position: Offset(10, 20),
        width: 100,
        height: 50,
        ports: <NodePort>[NodePort.output(id: 'a', anchor: Offset(1, 0.25))],
      );

      expect(
        NodeGeometry.portPosition(
          target,
          target.ports.first,
          const Size(100, 50),
        ),
        const Offset(110, 32.5),
      );
    });
  });

  group('ViewportTransform', () {
    test('round-trips scene and screen coordinates', () {
      const viewport = ViewportTransform(offset: Offset(30, -12), scale: 1.75);
      const point = Offset(123, 456);

      final roundTripped = viewport.toScene(viewport.toScreen(point));
      expect(roundTripped.dx, closeTo(point.dx, 1e-9));
      expect(roundTripped.dy, closeTo(point.dy, 1e-9));
    });

    test('zoomedAt pins the focal point', () {
      const viewport = ViewportTransform(offset: Offset(10, 10), scale: 1);
      const focal = Offset(400, 300);

      final zoomed = viewport.zoomedAt(focal, 2.5);
      final before = viewport.toScene(focal);
      final after = zoomed.toScene(focal);

      expect(after.dx, closeTo(before.dx, 1e-9));
      expect(after.dy, closeTo(before.dy, 1e-9));
      expect(zoomed.scale, 2.5);
    });

    test('visibleSceneRect covers the viewport', () {
      const viewport = ViewportTransform(offset: Offset(-100, -50), scale: 2);
      expect(
        viewport.visibleSceneRect(const Size(800, 600)),
        const Rect.fromLTRB(50, 25, 450, 325),
      );
    });
  });

  group('ConnectionPath', () {
    test('hit tests along the stroked curve, not its fill', () {
      final path = ConnectionPath.build(
        Offset.zero,
        const Offset(200, 0),
        fromSide: PortSide.right,
        toSide: PortSide.left,
      );

      expect(ConnectionPath.hitTest(path, const Offset(100, 0)), isTrue);
      expect(ConnectionPath.hitTest(path, const Offset(100, 60)), isFalse);
    });

    test('follows the bend of a curved connection', () {
      // Ports on perpendicular sides bow the curve well clear of the straight
      // line between its ends, which is why picking has to walk the path.
      final path = ConnectionPath.build(
        Offset.zero,
        const Offset(100, 100),
        fromSide: PortSide.right,
        toSide: PortSide.bottom,
      );

      expect(
        ConnectionPath.hitTest(path, ConnectionPath.midpoint(path)!),
        isTrue,
      );
      expect(ConnectionPath.hitTest(path, const Offset(50, 50)), isFalse);
    });
  });
}
