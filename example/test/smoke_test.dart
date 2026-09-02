import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fl_nodes_v2/fl_nodes_v2.dart';
import 'package:fl_nodes_v2_example/form_node_body.dart';
import 'package:fl_nodes_v2_example/main.dart';
import 'package:fl_nodes_v2_example/prototype_nodes.dart';
import 'package:fl_nodes_v2_example/sample_graph.dart';
import 'package:fl_nodes_v2_example/workflow_node.dart';

void main() {
  testWidgets('the demo boots with the sample workflow on screen', (
    tester,
  ) async {
    await tester.pumpWidget(const NodeEditorDemoApp());
    await tester.pumpAndSettle();

    expect(find.byType(NodeEditor), findsOneWidget);
    expect(find.text('Form submitted'), findsOneWidget);
    expect(find.text('Lead score'), findsOneWidget);
    // Each branch row lines up with its own anchored output port.
    expect(find.text('High'), findsOneWidget);
    expect(find.text('Nothing selected'), findsOneWidget);
    // The form node's body is real Flutter form UI, not a painted mock.
    expect(
      find.descendant(
        of: find.byType(FormNodeBody),
        matching: find.byType(TextField),
      ),
      findsOneWidget,
    );
    expect(find.byType(Checkbox), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('the sample note is on the canvas and can be written in', (
    tester,
  ) async {
    await tester.pumpWidget(const NodeEditorDemoApp());
    await tester.pumpAndSettle();

    final note = find.ancestor(
      of: find.textContaining('that branch is deliberate'),
      matching: find.byType(TextField),
    );
    expect(note, findsOneWidget);

    await tester.enterText(note, 'rewritten');
    await tester.pump();

    final controller = tester
        .widget<NodeEditor>(find.byType(NodeEditor))
        .controller;
    expect(NodeComment.textOf(controller.graph.nodes['note']!), 'rewritten');
  });

  testWidgets('the sample group frames its four nodes and moves them', (
    tester,
  ) async {
    await tester.pumpWidget(const NodeEditorDemoApp());
    await tester.pumpAndSettle();

    final controller = tester
        .widget<NodeEditor>(find.byType(NodeEditor))
        .controller;
    expect(controller.graph.groups['reply']!.nodeIds, hasLength(4));

    // Framed off screen at the demo's opening camera; bring it into view.
    controller.camera.centerOnNode('compose', const Size(800, 600));
    await tester.pumpAndSettle();
    expect(find.text('Composing the reply'), findsOneWidget);

    final before = controller.graph.nodes['compose']!.position;
    // Scoped to the group: the minimap's own bar carries the same grip glyph,
    // deliberately, because both are the same affordance.
    final gesture = await tester.startGesture(
      tester.getCenter(
        find.descendant(
          of: find.byKey(const ValueKey<String>('group:reply')),
          matching: find.byIcon(Icons.drag_indicator),
        ),
      ),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(
      controller.graph.nodes['compose']!.position.dx,
      greaterThan(before.dx),
      reason: 'the handle drags every member, not just itself',
    );
  });

  testWidgets('right-clicking the canvas offers every named node type', (
    tester,
  ) async {
    await tester.pumpWidget(const NodeEditorDemoApp());
    await tester.pumpAndSettle();

    // Top-right: clear of the sample graph, and clear of the status chip,
    // whose line of counts spans most of the bottom edge.
    final canvas = tester.getRect(find.byType(NodeEditor));
    final gesture = await tester.startGesture(
      canvas.topRight + const Offset(-40, 40),
      buttons: kSecondaryButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.text('Center view'), findsOneWidget);
    expect(find.text('Project'), findsOneWidget);

    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    // Grouped, because every demo prototype names a category.
    expect(find.text('Flow'), findsOneWidget);
    expect(find.text('Data'), findsOneWidget);
    expect(find.text('Content'), findsOneWidget);
  });

  test('every node type the demo draws is a registered prototype', () {
    expect(
      <String>{for (final type in WorkflowNodeType.values) type.name},
      workflowPrototypes.types.toSet(),
      reason:
          'the Create menu reads the registry, so a type missing from it '
          'is a type nobody can make',
    );
    for (final type in workflowPrototypes.types) {
      expect(
        workflowPrototypes[type]!.label,
        isNotNull,
        reason: '"$type" would be left out of the Create menu',
      );
      expect(workflowPrototypes[type]!.description, isNotNull);
    }
  });

  test('the sample graph is fully wired once it is resolved', () {
    final authored = buildSampleGraph();

    expect(authored.contentNodes, hasLength(11));
    expect(authored.connections, hasLength(11));
    expect(
      authored.comments,
      hasLength(1),
      reason: 'the sample ships a note, so the demo opens on one',
    );

    // The derived nodes are authored with no ports at all — that is the point,
    // and it is why a document only has to carry its field values.
    expect(authored.node('route')!.ports, isEmpty);
    expect(authored.node('greeting')!.ports, isEmpty);

    final graph = workflowPrototypes.resolveAll(authored).graph;

    for (final connection in graph.connections.values) {
      expect(graph.node(connection.from.nodeId), isNotNull);
      expect(graph.node(connection.to.nodeId), isNotNull);
      expect(
        graph.node(connection.from.nodeId)!.portById(connection.from.portId),
        isNotNull,
        reason: '${connection.id} leaves a port that does not exist',
      );
      expect(
        graph.node(connection.to.nodeId)!.portById(connection.to.portId),
        isNotNull,
        reason: '${connection.id} lands on a port that does not exist',
      );
    }

    // 'exit_0' is wired in the sample, so the fan-out must have grown a second,
    // free exit beneath it.
    expect(
      <String>[
        for (final port in graph.node('route')!.ports)
          if (port.isOutput) port.id,
      ],
      <String>['exit_0', 'exit_1'],
    );
    expect(
      <String>[
        for (final port in graph.node('greeting')!.ports)
          if (port.isInput) port.id,
      ],
      <String>['arg_0', 'arg_1'],
      reason: 'the default format string has two placeholders',
    );
  });
}
