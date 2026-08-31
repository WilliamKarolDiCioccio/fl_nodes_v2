import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fl_nodes_v2/fl_nodes_v2.dart';
import 'package:fl_nodes_v2_example/main.dart';

void main() {
  /// Stands in for the platform clipboard.
  String? clipboard;

  setUp(() {
    clipboard = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          switch (call.method) {
            case 'Clipboard.setData':
              clipboard =
                  (call.arguments as Map<Object?, Object?>)['text'] as String?;
              return null;
            case 'Clipboard.getData':
              // A real platform answers null for an empty clipboard;
              // Clipboard.getData casts a present 'text' to a non-null
              // String and would throw on {'text': null}.
              return clipboard == null
                  ? null
                  : <String, Object?>{'text': clipboard};
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<NodeEditorController> boot(WidgetTester tester) async {
    await tester.pumpWidget(const NodeEditorDemoApp());
    await tester.pumpAndSettle();
    return tester.widget<NodeEditor>(find.byType(NodeEditor)).controller;
  }

  Future<void> useEditMenu(WidgetTester tester, String item) async {
    final button = find.widgetWithText(OutlinedButton, 'Edit');
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.tap(find.text(item));
    await tester.pumpAndSettle();
  }

  testWidgets('the whole workflow copies and pastes through the menu', (
    tester,
  ) async {
    final controller = await boot(tester);
    final nodes = controller.graph.nodes.length;
    final connections = controller.graph.connections.length;

    await useEditMenu(tester, 'Select all');
    await useEditMenu(tester, 'Copy');
    expect(find.text('Selection copied'), findsOneWidget);

    await useEditMenu(tester, 'Paste');
    await tester.pumpAndSettle();

    expect(
      controller.graph.nodes.length,
      nodes * 2,
      reason: 'every node was selected, so every node has a copy',
    );
    expect(
      controller.graph.connections.length,
      connections * 2,
      reason:
          'every wire was internal to the selection, so all of them came '
          'along',
    );
    expect(
      controller.selection.nodeIds.length,
      nodes,
      reason: 'the copy is what the user is now holding',
    );

    controller.history.undo();
    await tester.pumpAndSettle();
    expect(controller.graph.nodes.length, nodes);
  });

  testWidgets('a copy reaches the system clipboard as a fragment', (
    tester,
  ) async {
    final controller = await boot(tester);

    controller.selection.selectNode('trigger');
    await tester.pumpAndSettle();
    await useEditMenu(tester, 'Copy');

    expect(clipboard, isNotNull);
    final json = jsonDecode(clipboard!) as Map<String, Object?>;
    expect(json['version'], NodeGraphCodec.version);
    expect((json['nodes']! as List<Object?>).length, 1);
    expect(
      (json['meta']! as Map<String, Object?>)[NodeEditorClipboard.fragmentKey],
      isTrue,
      reason: 'the marker is what tells a fragment from a saved document',
    );
  });

  testWidgets('cut removes the selection and can be pasted back', (
    tester,
  ) async {
    final controller = await boot(tester);
    final nodes = controller.graph.nodes.length;

    controller.selection.selectNode('archive');
    await tester.pumpAndSettle();
    await useEditMenu(tester, 'Cut');

    expect(controller.graph.nodes.containsKey('archive'), isFalse);
    expect(controller.graph.nodes.length, nodes - 1);

    await useEditMenu(tester, 'Paste');
    await tester.pumpAndSettle();

    expect(controller.graph.nodes.length, nodes);
    final pasted = controller.selection.nodeIds.single;
    expect(
      controller.graph.nodes[pasted]!.data['title'],
      'Archive',
      reason: 'what came back is the node that was cut, under a fresh id',
    );
    expect(pasted, isNot('archive'));
  });

  testWidgets('pasting with nothing to paste says so', (tester) async {
    await boot(tester);

    await useEditMenu(tester, 'Paste');
    await tester.pumpAndSettle();

    expect(find.text('Nothing to paste'), findsOneWidget);
  });
}
