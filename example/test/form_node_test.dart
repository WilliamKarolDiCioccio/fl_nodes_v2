import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fl_nodes_v2/fl_nodes_v2.dart';
import 'package:fl_nodes_v2_example/form_node_body.dart';
import 'package:fl_nodes_v2_example/main.dart';
import 'package:fl_nodes_v2_example/workflow_node.dart';

void main() {
  // The demo has more than one text field on screen now, so say which.
  final Finder subjectField = find.descendant(
    of: find.byType(FormNodeBody),
    matching: find.byType(TextField),
  );

  Future<NodeEditorController> boot(WidgetTester tester) async {
    await tester.pumpWidget(const NodeEditorDemoApp());
    await tester.pumpAndSettle();
    return tester.widget<NodeEditor>(find.byType(NodeEditor)).controller;
  }

  GraphNode compose(NodeEditorController controller) =>
      controller.graph.node('compose')!;

  testWidgets('the checkbox writes through to the graph', (tester) async {
    final controller = await boot(tester);
    expect(compose(controller).sendAsHtml, isFalse);

    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();

    expect(compose(controller).sendAsHtml, isTrue);

    controller.history.undo();
    expect(compose(controller).sendAsHtml, isFalse);
  });

  testWidgets('typing writes live but undoes as a single step', (tester) async {
    final controller = await boot(tester);
    final before = compose(controller).subject;

    await tester.tap(subjectField);
    await tester.pumpAndSettle();

    // Several separate edits while the field holds focus.
    for (final value in <String>['A', 'AB', 'ABC']) {
      await tester.enterText(subjectField, value);
      await tester.pump();
    }
    expect(
      compose(controller).subject,
      'ABC',
      reason: 'the model follows every keystroke',
    );

    // Committing happens when the field gives up focus.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();

    controller.history.undo();
    expect(
      compose(controller).subject,
      before,
      reason: 'one undo should discard the whole editing session',
    );
  });

  testWidgets('the slider collapses its drag into one undo step', (
    tester,
  ) async {
    final controller = await boot(tester);
    final before = compose(controller).delayMinutes;

    await tester.drag(find.byType(Slider), const Offset(-40, 0));
    await tester.pumpAndSettle();

    final after = compose(controller).delayMinutes;
    expect(after, isNot(before));

    controller.history.undo();
    expect(compose(controller).delayMinutes, before);
  });

  testWidgets('the colour picker opens and applies a swatch', (tester) async {
    final controller = await boot(tester);
    final before = compose(controller).labelColor;

    // Scoped to the node: the sample's group handle carries the same arrow.
    await tester.tap(
      find.descendant(
        of: find.byType(FormNodeBody),
        matching: find.byIcon(Icons.arrow_drop_down),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(MenuItemButton), findsWidgets);

    await tester.tap(find.byType(MenuItemButton).last);
    await tester.pumpAndSettle();

    expect(compose(controller).labelColor, isNot(before));
  });

  testWidgets('undo from the toolbar restores the model in the field', (
    tester,
  ) async {
    final controller = await boot(tester);
    final before = compose(controller).subject;

    await tester.tap(subjectField);
    await tester.pumpAndSettle();
    await tester.enterText(subjectField, 'changed');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();

    // The toolbar scrolls once it outgrows the window, and a button parked
    // outside the viewport takes no taps.
    final undo = find.byTooltip('Undo (Ctrl+Z)');
    await tester.ensureVisible(undo);
    await tester.pumpAndSettle();
    await tester.tap(undo);
    await tester.pumpAndSettle();

    expect(compose(controller).subject, before);
    // The text field adopts the reverted value rather than keeping stale text.
    expect(tester.widget<TextField>(subjectField).controller!.text, before);
  });
}
