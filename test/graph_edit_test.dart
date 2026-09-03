import 'package:fl_nodes_v2/fl_nodes_v2.dart';
import 'package:flutter_test/flutter_test.dart';

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

  NodeEditorController controllerWith(List<GraphNode> nodes) {
    final controller = NodeEditorController(graph: NodeGraph(nodes: nodes));
    addTearDown(controller.dispose);
    return controller;
  }

  /// A controller reporting every edit into [into].
  NodeEditorController watched(List<GraphEdit> into, {List<GraphNode>? nodes}) {
    final controller = controllerWith(
      nodes ??
          <GraphNode>[node('a'), node('b', position: const Offset(200, 0))],
    );
    controller.onEdit = into.add;
    return controller;
  }

  group('being told what changed', () {
    test('adding a node', () {
      final edits = <GraphEdit>[];
      final controller = watched(edits, nodes: <GraphNode>[]);

      controller.addNode(node('a'));

      expect(edits.single.kind, GraphEditKind.addNodes);
      expect(edits.single.nodeIds, <String>{'a'});
    });

    test('removing one, and which one', () {
      final edits = <GraphEdit>[];
      final controller = watched(edits);

      controller.removeNodes(<String>['a']);

      expect(edits.single.kind, GraphEditKind.removeNodes);
      expect(edits.single.removes('a'), isTrue);
      expect(edits.single.removes('b'), isFalse);
    });

    test('updating one', () {
      final edits = <GraphEdit>[];
      final controller = watched(edits);

      controller.updateNode(
        'a',
        (one) => one.withData(<String, Object?>{'x': 1}),
      );

      expect(edits.single.kind, GraphEditKind.updateNodes);
      expect(edits.single.nodeIds, <String>{'a'});
    });

    test('moving one, which a host usually wants to ignore', () {
      final edits = <GraphEdit>[];
      final controller = watched(edits);

      controller.moveNodes(<String, Offset>{'a': const Offset(50, 50)});

      expect(edits.single.kind, GraphEditKind.moveNodes);
    });

    test('wiring, reported with both ends and the wire', () {
      final edits = <GraphEdit>[];
      final controller = watched(edits);

      final wire = controller.connect(
        const PortRef('a', 'out'),
        const PortRef('b', 'in'),
      )!;

      expect(edits.single.kind, GraphEditKind.connect);
      expect(edits.single.nodeIds, <String>{'a', 'b'});
      expect(edits.single.connectionIds, <String>{wire});
    });

    test('unwiring', () {
      final edits = <GraphEdit>[];
      final controller = watched(edits);
      final wire = controller.connect(
        const PortRef('a', 'out'),
        const PortRef('b', 'in'),
      )!;
      edits.clear();

      controller.removeConnections(<String>[wire]);

      expect(edits.single.kind, GraphEditKind.disconnect);
      expect(edits.single.connectionIds, <String>{wire});
    });

    test('a recaptioned wire is not a rewired one', () {
      final edits = <GraphEdit>[];
      final controller = watched(edits);
      final wire = controller.connect(
        const PortRef('a', 'out'),
        const PortRef('b', 'in'),
      )!;
      edits.clear();

      controller.setConnectionLabel(wire, 'onward');

      expect(edits.single.kind, GraphEditKind.labelConnection);
    });

    test('replacing the document', () {
      final edits = <GraphEdit>[];
      final controller = watched(edits);

      controller.replaceGraph(NodeGraph(nodes: <GraphNode>[node('c')]));

      expect(edits.single.kind, GraphEditKind.replace);
      expect(edits.single.nodeIds, <String>{'c'});
    });

    test('an edit that changes nothing is not an edit', () {
      final edits = <GraphEdit>[];
      final controller = watched(edits);

      controller.updateNode('a', (one) => one);

      expect(
        edits,
        isEmpty,
        reason: 'the settled graph is compared, not the caller\'s',
      );
    });

    test('undo does not come through here', () {
      final edits = <GraphEdit>[];
      final controller = watched(edits);
      controller.removeNodes(<String>['a']);
      edits.clear();

      controller.history.undo();

      expect(
        edits,
        isEmpty,
        reason:
            'undo restores a graph the hook already saw on the way in; a host '
            'that must catch every way a node leaves also listens',
      );
      expect(controller.graph.nodes.containsKey('a'), isTrue);
    });
  });

  group('refusing an edit', () {
    test('a guard that says no leaves the graph alone', () {
      final controller = controllerWith(<GraphNode>[node('a')]);
      controller.guard = (edit) => edit.kind != GraphEditKind.removeNodes;

      controller.removeNodes(<String>['a']);

      expect(controller.graph.nodes.containsKey('a'), isTrue);
    });

    test('and records no undo step, because nothing happened', () {
      final controller = controllerWith(<GraphNode>[node('a')]);
      controller.guard = (_) => false;

      controller.removeNodes(<String>['a']);

      expect(controller.history.canUndo, isFalse);
    });

    test('and is not then reported as an edit', () {
      final edits = <GraphEdit>[];
      final controller = watched(edits);
      controller.guard = (_) => false;

      controller.removeNodes(<String>['a']);

      expect(edits, isEmpty);
    });

    test('a guard can refuse one kind and allow another', () {
      final controller = controllerWith(<GraphNode>[node('a')]);
      controller.guard = (edit) => edit.kind != GraphEditKind.removeNodes;

      controller
        ..moveNodes(<String, Offset>{'a': const Offset(10, 10)})
        ..removeNodes(<String>['a']);

      expect(controller.graph.nodes['a']!.position, const Offset(10, 10));
      expect(controller.graph.nodes.containsKey('a'), isTrue);
    });

    test('a host can refuse, ask, and re-issue', () {
      final controller = controllerWith(<GraphNode>[node('a')]);
      var asked = false;
      controller.guard = (edit) {
        if (edit.kind != GraphEditKind.removeNodes) return true;
        if (asked) return true;
        asked = true;
        return false;
      };

      controller.removeNodes(<String>['a']);
      expect(controller.graph.nodes.containsKey('a'), isTrue);

      // The answer came back yes.
      controller.removeNodes(<String>['a']);

      expect(
        controller.graph.nodes.containsKey('a'),
        isFalse,
        reason:
            'the contract a synchronous guard is for: refuse now, ask, and '
            'do it again once there is an answer',
      );
    });

    test('no guard is the ordinary case and costs nothing', () {
      final controller = controllerWith(<GraphNode>[node('a')]);

      controller.removeNodes(<String>['a']);

      expect(controller.graph.nodes, isEmpty);
    });
  });
}
