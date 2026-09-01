import 'package:fl_nodes_v2/fl_nodes_v2.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Who holds the keyboard after a click on the canvas.
///
/// A tap is not a drag, so the scale recogniser never starts and nothing on
/// that path used to take focus. The consequence is not that a shortcut is
/// merely ignored: the key event goes to whatever the *host* had focused, and
/// on an editor embedded beside a file tree that turned Delete into a deleted
/// file.
void main() {
  NodeEditorController editor({NodeGraph? graph}) {
    final controller = NodeEditorController(graph: graph);
    addTearDown(controller.dispose);
    return controller;
  }

  GraphNode node(String id, Offset position) => GraphNode(
    id: id,
    position: position,
    width: 120,
    height: 60,
    ports: const <NodePort>[
      NodePort.input(id: 'in', anchor: Offset(0, 0.5)),
      NodePort.output(id: 'out', anchor: Offset(1, 0.5)),
    ],
  );

  /// The editor beside something else that wants the keyboard, which is the
  /// arrangement the bug needs in order to be visible at all.
  Widget harness(NodeEditorController controller, FocusNode outsider) =>
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: <Widget>[
              SizedBox(
                width: 100,
                height: 600,
                child: Focus(
                  focusNode: outsider,
                  child: const ColoredBox(color: Color(0xFF202020)),
                ),
              ),
              SizedBox(
                width: 700,
                height: 600,
                child: NodeEditor(
                  controller: controller,
                  theme: NodeEditorTheme.dark(),
                  nodeBuilder: (context, graphNode, state) =>
                      const ColoredBox(color: Color(0xFF2A2E38)),
                ),
              ),
            ],
          ),
        ),
      );

  testWidgets('clicking empty canvas takes focus off whatever had it', (
    tester,
  ) async {
    final outsider = FocusNode(debugLabel: 'the file tree');
    addTearDown(outsider.dispose);
    final controller = editor();

    await tester.pumpWidget(harness(controller, outsider));
    outsider.requestFocus();
    await tester.pump();
    expect(outsider.hasFocus, isTrue);

    await tester.tapAt(const Offset(500, 300));
    await tester.pump();

    expect(
      outsider.hasFocus,
      isFalse,
      reason:
          'the host went on receiving key events while somebody was plainly '
          'working on the canvas',
    );
  });

  testWidgets('clicking a connection takes focus, so Delete removes it', (
    tester,
  ) async {
    final outsider = FocusNode(debugLabel: 'the file tree');
    addTearDown(outsider.dispose);
    final controller = editor(
      graph: NodeGraph(
        nodes: <GraphNode>[
          node('a', const Offset(100, 200)),
          node('b', const Offset(400, 200)),
        ],
      ),
    );
    final wire = controller.connect(
      const PortRef('a', 'out'),
      const PortRef('b', 'in'),
    );
    expect(wire, isNotNull);

    await tester.pumpWidget(harness(controller, outsider));
    outsider.requestFocus();
    await tester.pump();

    // Halfway along the wire, in the editor's own coordinates: the panel
    // beside it is 100 wide.
    await tester.tapAt(const Offset(100 + 340, 230));
    await tester.pump();

    expect(
      controller.selection.connectionIds,
      contains(wire),
      reason: 'the tap has to have hit the wire for the rest to mean anything',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pump();

    expect(
      controller.graph.connections[wire],
      isNull,
      reason:
          'selecting a wire and pressing Delete is the whole gesture; without '
          'focus it did nothing here and something unwelcome elsewhere',
    );
  });
}
