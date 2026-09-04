import 'package:fl_nodes_v2/fl_nodes_v2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Auto-layout, which this package deliberately does not do.
///
/// What it supplies is the two halves a host cannot get for itself: the sizes
/// nodes are really drawn at, and one edit that places the lot. The algorithm
/// is the host's, and these tests are written from that side of the seam.
void main() {
  GraphNode node(
    String id, {
    Offset position = Offset.zero,
    bool drag = true,
  }) => GraphNode(
    id: id,
    position: position,
    width: 100,
    height: 50,
    draggable: drag,
    ports: const <NodePort>[
      NodePort.input(id: 'in'),
      NodePort.output(id: 'out'),
    ],
  );

  NodeEditorController controllerWith(List<GraphNode> nodes) {
    final controller = NodeEditorController(graph: NodeGraph(nodes: nodes));
    addTearDown(controller.dispose);
    return controller;
  }

  /// A layout that puts every node on a row, spaced by [gap].
  GraphLayout inARow({double gap = 300}) => (graph, sizeOf) {
    var x = 0.0;
    final placed = <String, Offset>{};
    for (final id in graph.nodes.keys) {
      placed[id] = Offset(x, 0);
      x += gap;
    }
    return placed;
  };

  group('placing nodes', () {
    test('moves them where the layout says', () {
      final controller = controllerWith(<GraphNode>[node('a'), node('b')]);

      final moved = controller.applyLayout(inARow());

      expect(moved, isTrue);
      expect(controller.graph.nodes['a']!.position, Offset.zero);
      expect(controller.graph.nodes['b']!.position, const Offset(300, 0));
    });

    test('places a node a pointer may not drag', () {
      final controller = controllerWith(<GraphNode>[
        node('a', drag: false),
        node('b', drag: false),
      ]);

      final moved = controller.applyLayout(inARow());

      expect(
        moved,
        isTrue,
        reason:
            'draggable says whether a pointer may push a node, not whether an '
            'arrangement may place one — and a read-only canvas is where '
            'auto-layout is most wanted',
      );
      expect(controller.graph.nodes['b']!.position, const Offset(300, 0));
    });

    test('moveNodes still refuses one, which is the difference', () {
      final controller = controllerWith(<GraphNode>[node('a', drag: false)]);

      controller.moveNodes(<String, Offset>{'a': const Offset(50, 50)});

      expect(controller.graph.nodes['a']!.position, Offset.zero);
    });

    test('a whole arrangement is one undo step', () {
      final controller = controllerWith(<GraphNode>[
        node('a'),
        node('b'),
        node('c'),
      ]);

      controller.applyLayout(inARow());
      controller.history.undo();

      expect(controller.graph.nodes['b']!.position, Offset.zero);
      expect(
        controller.graph.nodes['c']!.position,
        Offset.zero,
        reason: 'one edit for the lot, not one per node',
      );
    });

    test('is one edit, naming only what actually moved', () {
      final edits = <GraphEdit>[];
      final controller = controllerWith(<GraphNode>[
        node('a', position: const Offset(500, 500)),
        node('b'),
      ]);
      controller.onEdit = edits.add;

      controller.applyLayout(inARow());

      expect(edits, hasLength(1));
      expect(edits.single.kind, GraphEditKind.moveNodes);
      expect(edits.single.nodeIds, <String>{'a', 'b'});
    });

    test('a node the layout leaves where it found it is not an edit', () {
      final edits = <GraphEdit>[];
      final controller = controllerWith(<GraphNode>[node('a'), node('b')]);
      controller.onEdit = edits.add;

      // `a` is already at the origin, which is where this layout puts it.
      controller.applyLayout(inARow());

      expect(
        edits.single.nodeIds,
        <String>{'b'},
        reason: 'the edit describes what changed, not what was considered',
      );
    });

    test('a layout that names nobody changes nothing', () {
      final controller = controllerWith(<GraphNode>[node('a')]);

      expect(
        controller.applyLayout((graph, sizeOf) => const <String, Offset>{}),
        isFalse,
      );
    });

    test('nodes it leaves out stay where they are', () {
      final controller = controllerWith(<GraphNode>[
        node('a'),
        node('b', position: const Offset(7, 9)),
      ]);

      controller.applyLayout(
        (graph, sizeOf) => <String, Offset>{'a': const Offset(40, 0)},
      );

      expect(
        controller.graph.nodes['b']!.position,
        const Offset(7, 9),
        reason: 'arranging a selection is just a smaller map',
      );
    });

    test('placing everything where it already is reports nothing', () {
      final controller = controllerWith(<GraphNode>[node('a')]);

      expect(
        controller.applyLayout(
          (graph, sizeOf) => <String, Offset>{'a': Offset.zero},
        ),
        isFalse,
      );
    });

    test('a refused arrangement says so rather than lying', () {
      final controller = controllerWith(<GraphNode>[node('a'), node('b')]);
      controller.guard = (_) => false;

      expect(controller.applyLayout(inARow()), isFalse);
      expect(controller.graph.nodes['b']!.position, Offset.zero);
    });

    test('the layout is handed the graph and the size of each node', () {
      final controller = controllerWith(<GraphNode>[node('a')]);
      NodeGraph? seen;
      Size? measured;

      controller.applyLayout((graph, sizeOf) {
        seen = graph;
        measured = sizeOf(graph.nodes['a']!);
        return const <String, Offset>{};
      });

      expect(seen, same(controller.graph));
      expect(
        measured,
        const Size(100, 50),
        reason:
            'the same measurement the painter uses, or the layout and the '
            'picture would disagree',
      );
    });
  });

  group('knowing when the sizes are real', () {
    /// A node with no declared height: its extent is whatever it is drawn at.
    GraphNode growing(String id) => GraphNode(
      id: id,
      position: Offset.zero,
      width: 100,
      ports: const <NodePort>[NodePort.input(id: 'in')],
    );

    test('fires once the last node has reported', () {
      final controller = controllerWith(<GraphNode>[
        growing('a'),
        growing('b'),
      ]);
      var told = 0;
      controller.layout.onMeasured = () => told++;

      expect(controller.layout.hasUnmeasuredNodes, isTrue);
      controller.layout.reportMeasuredSize('a', const Size(100, 40));
      expect(told, 0, reason: 'b has still not said how tall it is');

      controller.layout.reportMeasuredSize('b', const Size(100, 60));

      expect(told, 1);
      expect(controller.layout.hasUnmeasuredNodes, isFalse);
    });

    test('does not fire again for a node that changed size', () {
      final controller = controllerWith(<GraphNode>[growing('a')]);
      var told = 0;
      controller.layout.onMeasured = () => told++;

      controller.layout.reportMeasuredSize('a', const Size(100, 40));
      controller.layout.reportMeasuredSize('a', const Size(100, 80));

      expect(
        told,
        1,
        reason: 'it reports the transition, not every measurement after it',
      );
    });

    test(
      'a graph that declares every height never has anything to wait for',
      () {
        final controller = controllerWith(<GraphNode>[node('a')]);
        var told = 0;
        controller.layout.onMeasured = () => told++;

        expect(controller.layout.hasUnmeasuredNodes, isFalse);
        controller.layout.reportMeasuredSize('a', const Size(100, 50));

        expect(told, 0);
      },
    );

    test('arranging from the callback sees the measured sizes', () {
      final controller = controllerWith(<GraphNode>[growing('a')]);
      Size? whenArranged;
      controller.layout.onMeasured = () =>
          controller.applyLayout((graph, sizeOf) {
            whenArranged = sizeOf(graph.nodes['a']!);
            return <String, Offset>{'a': const Offset(10, 10)};
          });

      controller.layout.reportMeasuredSize('a', const Size(100, 72));

      expect(whenArranged, const Size(100, 72));
      expect(controller.graph.nodes['a']!.position, const Offset(10, 10));
    });
  });
}
