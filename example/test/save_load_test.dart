import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fl_nodes_v2/fl_nodes_v2.dart';
import 'package:fl_nodes_v2_example/main.dart';
import 'package:fl_nodes_v2_example/prototype_nodes.dart';
import 'package:fl_nodes_v2_example/sample_graph.dart';

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

  Future<void> useDocumentMenu(WidgetTester tester, String item) async {
    final button = find.widgetWithText(OutlinedButton, 'Document');
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.tap(find.text(item));
    await tester.pumpAndSettle();
  }

  test('the demo document survives a round trip', () {
    final codec = NodeGraphCodec(prototypes: workflowPrototypes);
    // As the controller would hold it: authored, then normalised.
    final resolved = workflowPrototypes.resolveAll(buildSampleGraph()).graph;

    final reloaded = codec
        .decode(codec.encode(GraphDocument(graph: resolved)))
        .graph;

    final controller = NodeEditorController(
      graph: reloaded,
      prototypes: workflowPrototypes,
    );
    addTearDown(controller.dispose);

    expect(controller.graph, resolved);
    expect(
      controller.graph.connections.keys.toSet(),
      resolved.connections.keys.toSet(),
      reason: 'no wire may be swept on the way back in',
    );
  });

  testWidgets('copy writes a document, paste reads it back', (tester) async {
    await tester.pumpWidget(const NodeEditorDemoApp());
    await tester.pumpAndSettle();

    await useDocumentMenu(tester, 'Copy as JSON');

    expect(clipboard, isNotNull);
    final json = jsonDecode(clipboard!) as Map<String, Object?>;
    expect(json['version'], 1);
    // Twelve: the eleven workflow nodes and the note, which is a node of a
    // reserved type and goes in the document like any other.
    expect(json['nodes'], hasLength(12));
    expect(json['viewport'], isNotNull);
    expect(json['meta'], containsPair('title', 'Lead routing'));

    // Change something, then paste the saved document back over it.
    final controller = tester
        .widget<NodeEditor>(find.byType(NodeEditor))
        .controller;
    controller.removeNodes(<String>['archive']);
    await tester.pumpAndSettle();
    expect(controller.graph.nodes, hasLength(11));

    await useDocumentMenu(tester, 'Paste from JSON');

    expect(
      tester.widget<NodeEditor>(find.byType(NodeEditor)).controller.graph.nodes,
      hasLength(12),
    );
    expect(find.text('Route reply'), findsOneWidget);
  });

  testWidgets('a document from the future is refused, and nothing is lost', (
    tester,
  ) async {
    await tester.pumpWidget(const NodeEditorDemoApp());
    await tester.pumpAndSettle();
    clipboard = jsonEncode(<String, Object?>{'version': 99});

    await useDocumentMenu(tester, 'Paste from JSON');

    expect(find.textContaining('format version 99'), findsOneWidget);
    expect(
      find.text('Form submitted'),
      findsOneWidget,
      reason:
          'decoding happens before the graph is replaced, so a bad '
          'document cannot blank the editor',
    );
  });

  testWidgets('malformed JSON says where it went wrong', (tester) async {
    await tester.pumpWidget(const NodeEditorDemoApp());
    await tester.pumpAndSettle();
    clipboard = jsonEncode(<String, Object?>{
      'version': 1,
      'nodes': <Object?>[
        <String, Object?>{'id': 'a', 'position': 'over there'},
      ],
    });

    await useDocumentMenu(tester, 'Paste from JSON');

    expect(find.textContaining('nodes[0].position'), findsOneWidget);
    expect(find.text('Form submitted'), findsOneWidget);
  });
}
