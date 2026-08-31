import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fl_nodes_v2/fl_nodes_v2.dart';
import 'package:fl_nodes_v2_example/main.dart';

void main() {
  Future<NodeEditorController> boot(WidgetTester tester) async {
    await tester.pumpWidget(const NodeEditorDemoApp());
    await tester.pumpAndSettle();
    return tester.widget<NodeEditor>(find.byType(NodeEditor)).controller;
  }

  testWidgets('the sample workflow runs end to end', (tester) async {
    final controller = await boot(tester);

    final run = await controller.runner.run();

    expect(run.succeeded, isTrue);
    expect(
      run.trace.first,
      'trigger',
      reason: 'the only node with a control output and nothing wired into it',
    );
    expect(
      run.valueAt(const PortRef('greeting', 'out')),
      'Hello, Mr. Allen. !',
      reason:
          'slot 0 came down the wire from the constant node, slot 1 from '
          "the greeting's own literal field, which is empty",
    );
    expect(
      run.trace,
      containsAllInOrder(<String>['route', 'name', 'greeting', 'deliver']),
      reason:
          'the data nodes are pulled by the node that reads them, so they '
          'run just before it and in dependency order',
    );
  });

  testWidgets('converging branches run the archive more than once', (
    tester,
  ) async {
    final controller = await boot(tester);

    final run = await controller.runner.run();

    expect(
      run.runCounts['archive'],
      greaterThan(1),
      reason:
          'the demo condition takes every branch, and control flow is a '
          'pulse: one turn per token that arrives',
    );
    expect(
      run.diagnostics.map((d) => d.issue),
      contains(GraphRunIssue.reentered),
    );
  });

  testWidgets('running leaves the document alone', (tester) async {
    final controller = await boot(tester);
    final graph = controller.graph;
    final revision = controller.revision;

    await controller.runner.run();
    await tester.pumpAndSettle();

    expect(identical(controller.graph, graph), isTrue);
    expect(controller.revision, revision);
    expect(controller.project.isDirty, isFalse);
  });

  testWidgets('the Run button reports what happened', (tester) async {
    await boot(tester);

    final run = find.byTooltip('Run the workflow');
    await tester.ensureVisible(run);
    await tester.pumpAndSettle();
    await tester.tap(run);
    await tester.pumpAndSettle();

    // Scoped to the snackbar: the constant node's own field says the same
    // thing on the canvas.
    expect(
      find.descendant(
        of: find.byType(SnackBar),
        matching: find.textContaining('Mr. Allen'),
      ),
      findsOneWidget,
    );
  });
}
