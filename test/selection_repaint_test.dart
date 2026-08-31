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
        node('a', const Offset(60, 200)),
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

  Widget harness(NodeEditorController controller) => MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 800,
          height: 600,
          child: NodeEditor(
            controller: controller,
            theme: NodeEditorTheme.dark(),
            nodeBuilder: (context, graphNode, state) => ColoredBox(
              key: ValueKey<String>('body_${graphNode.id}'),
              color: const Color(0xFF2A2E38),
            ),
          ),
        ),
      ),
    ),
  );

  ConnectionsPainter painterOf(WidgetTester tester) => tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .map((widget) => widget.painter)
      .whereType<ConnectionsPainter>()
      .single;

  test('selection getters are snapshots, not live views', () {
    final controller = wired();
    addTearDown(controller.dispose);

    final connectionsBefore = controller.selection.connectionIds;
    final nodesBefore = controller.selection.nodeIds;

    controller.selection.selectConnection('c1');
    expect(connectionsBefore, isEmpty, reason: 'must not mutate underneath');

    controller.selection.selectNode('a');
    expect(nodesBefore, isEmpty, reason: 'must not mutate underneath');
  });

  testWidgets('selecting a connection repaints the connection layer', (
    tester,
  ) async {
    final controller = wired();
    addTearDown(controller.dispose);

    await tester.pumpWidget(harness(controller));
    final before = painterOf(tester);

    controller.selection.selectConnection('c1');
    await tester.pump();

    expect(painterOf(tester).shouldRepaint(before), isTrue);
  });

  testWidgets('clearing the selection repaints the connection layer', (
    tester,
  ) async {
    final controller = wired();
    addTearDown(controller.dispose);
    controller.selection.selectConnection('c1');

    await tester.pumpWidget(harness(controller));
    final before = painterOf(tester);

    controller.selection.clear();
    await tester.pump();

    expect(painterOf(tester).shouldRepaint(before), isTrue);
  });

  testWidgets('selecting a node deselects the connection and repaints', (
    tester,
  ) async {
    final controller = wired();
    addTearDown(controller.dispose);
    controller.selection.selectConnection('c1');

    await tester.pumpWidget(harness(controller));
    final before = painterOf(tester);

    controller.selection.selectNode('a');
    await tester.pump();

    expect(controller.selection.connectionIds, isEmpty);
    expect(painterOf(tester).shouldRepaint(before), isTrue);
  });

  testWidgets('a click deselects a connection, as does clicking a node', (
    tester,
  ) async {
    final controller = wired();
    addTearDown(controller.dispose);

    await tester.pumpWidget(harness(controller));

    // Both ports sit at y = 230, so the curve runs flat between them.
    await tester.tapAt(const Offset(330, 230));
    await tester.pump();
    expect(controller.selection.connectionIds, <String>{'c1'});

    await tester.tapAt(const Offset(650, 500));
    await tester.pump();
    expect(
      controller.selection.connectionIds,
      isEmpty,
      reason: 'clicking empty canvas deselects',
    );

    await tester.tapAt(const Offset(330, 230));
    await tester.pump();
    expect(controller.selection.connectionIds, <String>{'c1'});

    await tester.tap(find.byKey(const ValueKey<String>('body_a')));
    await tester.pump();
    expect(
      controller.selection.connectionIds,
      isEmpty,
      reason: 'clicking a node deselects the connection',
    );
    expect(controller.selection.nodeIds, <String>{'a'});
  });

  testWidgets('clicking a second connection swaps the selection', (
    tester,
  ) async {
    final controller = NodeEditorController(
      graph: NodeGraph(
        nodes: <GraphNode>[
          node('a', const Offset(60, 200)),
          node('b', const Offset(400, 200)),
          node('c', const Offset(60, 400)),
          node('d', const Offset(400, 400)),
        ],
        connections: const <NodeConnection>[
          NodeConnection(
            id: 'c1',
            from: PortRef('a', 'out'),
            to: PortRef('b', 'in'),
          ),
          NodeConnection(
            id: 'c2',
            from: PortRef('c', 'out'),
            to: PortRef('d', 'in'),
          ),
        ],
      ),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(harness(controller));

    await tester.tapAt(const Offset(330, 230));
    await tester.pump();
    expect(controller.selection.connectionIds, <String>{'c1'});

    await tester.tapAt(const Offset(330, 430));
    await tester.pump();
    expect(controller.selection.connectionIds, <String>{'c2'});
  });
}
