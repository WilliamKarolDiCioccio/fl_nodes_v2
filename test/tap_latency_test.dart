import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fl_nodes_v2/fl_nodes_v2.dart';

void main() {
  GraphNode node(String id, Offset position) => GraphNode(
    id: id,
    position: position,
    width: 140,
    height: 60,
    ports: const <NodePort>[NodePort.output(id: 'out')],
  );

  testWidgets(
    'a node selects on the first tap even with a double-tap handler',
    (tester) async {
      final controller = NodeEditorController(
        graph: NodeGraph(nodes: <GraphNode>[node('a', const Offset(60, 60))]),
      );
      addTearDown(controller.dispose);
      var renames = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 800,
                height: 600,
                child: NodeEditor(
                  controller: controller,
                  theme: NodeEditorTheme.dark(),
                  // The demo wires this up, which is what pulls a
                  // DoubleTapGestureRecognizer into the arena.
                  onNodeDoubleTap: (graphNode) => renames++,
                  nodeBuilder: (context, graphNode, state) => ColoredBox(
                    key: ValueKey<String>('body_${graphNode.id}'),
                    color: const Color(0xFF2A2E38),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey<String>('body_a')));
      await tester.pump();

      expect(
        controller.selection.nodeIds,
        <String>{'a'},
        reason: 'selection must not wait out the double-tap timeout',
      );
      expect(renames, 0);

      // A second tap in quick succession still reaches the double-tap handler.
      await tester.tap(find.byKey(const ValueKey<String>('body_a')));
      await tester.pump();
      expect(renames, 1);

      await tester.pumpAndSettle();
    },
  );
}
