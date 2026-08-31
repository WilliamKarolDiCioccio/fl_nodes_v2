import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fl_nodes_v2/fl_nodes_v2.dart';

/// Port handles are painted, not built, so they contribute nothing to the
/// semantics tree by construction. This pins that.
///
/// It matters because the obvious way to build a handle — a `GestureDetector`
/// around a drag — advertises itself as a *scrollable*. When handles were
/// widgets, a six-port node put six phantom scroll areas in front of a screen
/// reader and made every frame walk them: with semantics on, 300 nodes of four
/// ports cost 53 ms a frame against 5 ms without.
void main() {
  NodeEditorController withPorts(int count) => NodeEditorController(
    graph: NodeGraph(
      nodes: <GraphNode>[
        GraphNode(
          id: 'a',
          position: const Offset(120, 120),
          width: 180,
          height: 120,
          ports: <NodePort>[
            for (var i = 0; i < count; i++)
              i.isEven
                  ? NodePort.input(id: 'in$i')
                  : NodePort.output(id: 'out$i'),
          ],
        ),
      ],
    ),
  );

  Future<int> semanticsNodes(WidgetTester tester, int ports) async {
    final controller = withPorts(ports);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NodeEditor(
            controller: controller,
            nodeBuilder: (context, node, state) =>
                const ColoredBox(color: Color(0xFF2A2E38)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    var total = 0;
    void visit(SemanticsNode node) {
      total++;
      node.visitChildren((child) {
        visit(child);
        return true;
      });
    }

    visit(tester.binding.rootElement!.renderObject!.debugSemantics!);
    return total;
  }

  // `testWidgets` runs with semantics on, which is the whole point here.
  testWidgets('port handles add nothing to the semantics tree', (tester) async {
    final none = await semanticsNodes(tester, 0);
    final many = await semanticsNodes(tester, 6);

    expect(
      many,
      none,
      reason:
          'six handles must cost exactly nothing: they describe nothing, and '
          'the tree is walked on every frame that touches them',
    );
  });
}
