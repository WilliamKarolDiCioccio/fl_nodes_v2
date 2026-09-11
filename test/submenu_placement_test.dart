import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fl_nodes_v2/fl_nodes_v2.dart';

/// Where a submenu lands, and whether a pointer can get to it.
///
/// Material's `SubmenuButton` flips a panel that would run off the bottom of
/// the window to end at the *top* of its row, and the pointer's path up to it
/// then crosses siblings that close it on hover. These pin the replacement:
/// the panel slides instead, keeps touching its row, and everything else
/// about a menu — hover, keyboard, choosing, dismissing — still works.
void main() {
  final NodeEditorTheme theme = NodeEditorTheme.dark();

  /// Enough categories to make the Create panel taller than the room a
  /// low right-click leaves under it.
  final NodePrototypeRegistry prototypes =
      NodePrototypeRegistry(<NodePrototype>[
        for (var i = 0; i < 12; i++)
          NodePrototype(type: 'kind$i', label: 'Kind $i', category: 'Group $i'),
      ]);

  Future<NodeEditorController> boot(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = NodeEditorController(prototypes: prototypes);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NodeEditor(
            controller: controller,
            theme: theme,
            contextMenus: const NodeEditorMenus(),
            nodeBuilder: (context, graphNode, state) =>
                const ColoredBox(color: Color(0xFF2A2E38)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  Future<TestGesture> rightClick(WidgetTester tester, Offset at) async {
    final gesture = await tester.startGesture(
      at,
      buttons: kSecondaryButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.up();
    await tester.pumpAndSettle();
    return gesture;
  }

  /// The row labelled [label] as it sits on screen.
  Rect rowRect(WidgetTester tester, String label) => tester.getRect(
    find.ancestor(of: find.text(label), matching: find.byType(MenuItemButton)),
  );

  /// The submenu panel that [label]'s row opened.
  Rect panelRect(WidgetTester tester, String firstEntry) => tester.getRect(
    find
        .ancestor(
          of: find.text(firstEntry),
          matching: find.byKey(NodeSubmenuButton.panelKey),
        )
        .first,
  );

  testWidgets('a submenu near the bottom slides up, and stays beside its row', (
    tester,
  ) async {
    await boot(tester);
    // Low on the canvas: the Create panel has twelve groups and no room.
    await rightClick(tester, const Offset(300, 560));
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    final row = rowRect(tester, 'Create');
    final panel = panelRect(tester, 'Group 0');

    expect(
      panel.bottom,
      lessThanOrEqualTo(600),
      reason: 'it fits on the screen',
    );
    expect(
      panel.bottom,
      greaterThan(row.top),
      reason:
          'Material ended the panel at the top of its row, and a panel '
          'entirely above its row is one the pointer cannot reach without '
          'crossing the siblings that close it',
    );
    expect(
      panel.left,
      moreOrLessEquals(row.right, epsilon: 1),
      reason: 'touching the row, so leaving it sideways lands on the panel',
    );
  });

  testWidgets('a submenu opens on hover and survives the pointer crossing '
      'into it', (tester) async {
    await boot(tester);
    // The mouse that right-clicked is still there after the button comes up,
    // and hovering with it is what a person does next.
    final mouse = await rightClick(tester, const Offset(300, 560));
    await mouse.moveTo(rowRect(tester, 'Create').center);
    await tester.pumpAndSettle();
    expect(find.text('Group 0'), findsOneWidget, reason: 'opened on hover');

    // Straight sideways off the row and onto the panel, then down it.
    final panel = panelRect(tester, 'Group 0');
    await mouse.moveTo(
      Offset(panel.left + 8, rowRect(tester, 'Create').center.dy),
    );
    await tester.pumpAndSettle();
    await mouse.moveTo(rowRect(tester, 'Group 3').center);
    await tester.pumpAndSettle();

    expect(find.text('Group 0'), findsOneWidget, reason: 'still open');
    expect(find.text('Kind 3'), findsOneWidget, reason: 'and cascades');
  });

  testWidgets('hovering a sibling row closes it', (tester) async {
    await boot(tester);
    final mouse = await rightClick(tester, const Offset(300, 200));
    await mouse.moveTo(rowRect(tester, 'Create').center);
    await tester.pumpAndSettle();
    expect(find.text('Group 0'), findsOneWidget);

    await mouse.moveTo(rowRect(tester, 'Reset zoom').center);
    await tester.pumpAndSettle();
    expect(find.text('Group 0'), findsNothing);
  });

  testWidgets('the arrow keys walk in and out of it', (tester) async {
    await boot(tester);
    await rightClick(tester, const Offset(300, 200));

    // Down to Create, which is the last row of the canvas menu.
    bool onCreate() =>
        tester
            .widget<MenuItemButton>(
              find.ancestor(
                of: find.text('Create'),
                matching: find.byType(MenuItemButton),
              ),
            )
            .focusNode
            ?.hasPrimaryFocus ??
        false;
    for (var i = 0; i < 6 && !onCreate(); i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
    }
    expect(onCreate(), isTrue, reason: 'the arrows walk the menu');
    expect(
      find.text('Group 0'),
      findsNothing,
      reason: 'focus alone opens nothing',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.text('Group 0'), findsOneWidget, reason: 'right opens it');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byWidget(FocusManager.instance.primaryFocus!.context!.widget),
        matching: find.text('Group 1'),
      ),
      findsOneWidget,
      reason: 'and the keyboard is inside it',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(find.text('Group 0'), findsNothing, reason: 'left closes it');
    expect(
      find.descendant(
        of: find.byWidget(FocusManager.instance.primaryFocus!.context!.widget),
        matching: find.text('Create'),
      ),
      findsOneWidget,
      reason: 'and hands the keyboard back to the row',
    );
  });

  testWidgets('choosing an entry two levels down closes the whole tree', (
    tester,
  ) async {
    final controller = await boot(tester);
    await rightClick(tester, const Offset(300, 200));
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Group 5'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kind 5'));
    await tester.pumpAndSettle();

    expect(controller.graph.nodes.values.single.type, 'kind5');
    expect(find.text('Create'), findsNothing);
    expect(find.text('Group 5'), findsNothing);
  });

  testWidgets('Escape closes the whole tree from inside a submenu', (
    tester,
  ) async {
    await boot(tester);
    await rightClick(tester, const Offset(300, 200));
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(find.text('Group 0'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.text('Group 0'), findsNothing);
    expect(find.text('Create'), findsNothing);
  });
}
