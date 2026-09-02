import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fl_nodes_v2/fl_nodes_v2.dart';

/// Comment notes: a reserved node type the editor draws itself.
///
/// The point of the design is that a note is a node, so most of what a note
/// can do is already covered by the node tests. What is pinned here is the
/// part that is genuinely new — the reserved type, the typing-to-history
/// coalescing, and the editor drawing notes instead of asking the host to.
void main() {
  final NodeEditorTheme theme = NodeEditorTheme.dark();

  GraphNode plain(String id, Offset position) => GraphNode(
    id: id,
    type: 'plain',
    position: position,
    width: 160,
    height: 90,
    ports: const <NodePort>[
      NodePort.input(id: 'in'),
      NodePort.output(id: 'out'),
    ],
  );

  NodeEditorController boot({NodeGraph? graph}) {
    final controller = NodeEditorController(graph: graph);
    addTearDown(controller.dispose);
    return controller;
  }

  group('model', () {
    test('a note is a node of the reserved type, carrying its text', () {
      final note = NodeComment.create(
        id: 'n1',
        position: const Offset(20, 30),
        text: 'watch this branch',
      );

      expect(NodeComment.isComment(note), isTrue);
      expect(note.type, NodeComment.type);
      expect(NodeComment.textOf(note), 'watch this branch');
      expect(
        note.ports,
        isEmpty,
        reason:
            'a note carries no ports, which is what keeps it out of the '
            'runner and off the end of any wire',
      );
      expect(
        note.height,
        isNull,
        reason: 'a note is measured from the text in it',
      );
    });

    test('textOf reads the empty string off anything that is not a note', () {
      expect(NodeComment.textOf(plain('a', Offset.zero)), '');
    });

    test('withText returns the same instance when nothing changed', () {
      final note = NodeComment.create(
        id: 'n1',
        position: Offset.zero,
        text: 'same',
      );
      expect(identical(NodeComment.withText(note, 'same'), note), isTrue);
    });

    test('comments and contentNodes partition the graph', () {
      final graph = NodeGraph(
        nodes: <GraphNode>[
          plain('a', Offset.zero),
          NodeComment.create(id: 'n1', position: Offset.zero),
          plain('b', const Offset(200, 0)),
        ],
      );

      expect(graph.comments.map((node) => node.id), <String>['n1']);
      expect(graph.contentNodes.map((node) => node.id), <String>['a', 'b']);
      expect(graph.nodes, hasLength(3));
    });
  });

  group('controller', () {
    test('addComment adds a note and is one undo step', () {
      final controller = boot();

      final id = controller.addComment(position: const Offset(40, 60));

      expect(controller.graph.nodes[id], isNotNull);
      expect(NodeComment.isComment(controller.graph.nodes[id]!), isTrue);
      expect(controller.graph.nodes[id]!.position, const Offset(40, 60));

      controller.history.undo();
      expect(controller.graph.nodes, isEmpty);
    });

    test('a run of typing collapses into one undo step', () {
      final controller = boot();
      final id = controller.addComment(position: Offset.zero);

      controller.setCommentText(id, 'r');
      controller.setCommentText(id, 're');
      controller.setCommentText(id, 'red');
      expect(NodeComment.textOf(controller.graph.nodes[id]!), 'red');

      controller.history.undo();
      expect(
        NodeComment.textOf(controller.graph.nodes[id]!),
        '',
        reason: 'one undo takes back the whole run, not the last character',
      );
      expect(
        controller.graph.nodes[id],
        isNotNull,
        reason: 'and stops there — the note itself was a separate step',
      );
    });

    test('endCommentEdit starts a new step for the next keystroke', () {
      final controller = boot();
      final id = controller.addComment(position: Offset.zero);

      controller.setCommentText(id, 'one');
      controller.endCommentEdit();
      controller.setCommentText(id, 'one two');

      controller.history.undo();
      expect(NodeComment.textOf(controller.graph.nodes[id]!), 'one');
    });

    test('an unrelated edit mid-run closes it', () {
      final controller = boot();
      final id = controller.addComment(position: Offset.zero);

      controller.setCommentText(id, 'a');
      // Something else lands while the caret is elsewhere. The next keystroke
      // has to record, or undo would step back past it.
      controller.translateNodes(<String>[id], const Offset(0, 10));
      controller.setCommentText(id, 'ab');

      controller.history.undo();
      expect(NodeComment.textOf(controller.graph.nodes[id]!), 'a');
    });

    test('undo re-arms recording, so redo cannot be overwritten', () {
      final controller = boot();
      final id = controller.addComment(position: Offset.zero);

      controller.setCommentText(id, 'first');
      controller.history.undo();
      controller.setCommentText(id, 'second');

      controller.history.undo();
      expect(NodeComment.textOf(controller.graph.nodes[id]!), '');
    });

    test('typing into two notes in a row is two steps', () {
      final controller = boot();
      final a = controller.addComment(position: Offset.zero);
      final b = controller.addComment(position: const Offset(0, 200));

      controller.setCommentText(a, 'alpha');
      controller.setCommentText(b, 'beta');

      controller.history.undo();
      expect(NodeComment.textOf(controller.graph.nodes[b]!), '');
      expect(NodeComment.textOf(controller.graph.nodes[a]!), 'alpha');
    });

    test('setCommentText refuses a node that is not a note', () {
      final controller = boot(
        graph: NodeGraph(nodes: <GraphNode>[plain('a', Offset.zero)]),
      );

      controller.setCommentText('a', 'not yours');
      expect(controller.graph.nodes['a']!.data, isEmpty);
    });
  });

  group('document', () {
    test('a note round-trips with its text', () {
      const codec = NodeGraphCodec();
      final graph = NodeGraph(
        nodes: <GraphNode>[
          plain('a', const Offset(10, 10)),
          NodeComment.create(
            id: 'n1',
            position: const Offset(300, 40),
            text: 'rewrite this branch',
            width: 300,
          ),
        ],
      );

      final restored = codec
          .decode(codec.encode(GraphDocument(graph: graph)))
          .graph;

      final note = restored.nodes['n1']!;
      expect(NodeComment.isComment(note), isTrue);
      expect(NodeComment.textOf(note), 'rewrite this branch');
      expect(note.width, 300);
      expect(note.position, const Offset(300, 40));
    });

    test('a pasted note keeps its text', () {
      final controller = boot();
      final id = controller.addComment(
        position: const Offset(10, 10),
        text: 'copy me',
      );
      controller.selection.selectNode(id);
      controller.clipboard.copy();

      final pasted = controller.clipboard.paste();
      expect(pasted, hasLength(1));
      final note = controller.graph.nodes[pasted.single]!;
      expect(NodeComment.isComment(note), isTrue);
      expect(NodeComment.textOf(note), 'copy me');
    });
  });

  group('canvas', () {
    Future<NodeEditorController> pump(
      WidgetTester tester, {
      required NodeGraph graph,
      void Function(GraphNode node)? onBuild,
    }) async {
      final controller = NodeEditorController(graph: graph);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NodeEditor(
              controller: controller,
              theme: theme,
              nodeBuilder: (context, node, state) {
                onBuild?.call(node);
                return const ColoredBox(color: Color(0xFF2A2E38));
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return controller;
    }

    testWidgets('the editor draws notes, never the host builder', (
      tester,
    ) async {
      final seen = <String>[];
      await pump(
        tester,
        graph: NodeGraph(
          nodes: <GraphNode>[
            plain('a', const Offset(60, 60)),
            NodeComment.create(
              id: 'n1',
              position: const Offset(60, 300),
              text: 'a note',
            ),
          ],
        ),
        onBuild: (node) => seen.add(node.id),
      );

      expect(find.widgetWithText(TextField, 'a note'), findsOneWidget);
      expect(
        seen,
        <String>['a'],
        reason:
            'the host builder is never handed a note, so a host needs no '
            'case for a type it did not declare',
      );
    });

    testWidgets('typing in a note writes through to the graph', (tester) async {
      final controller = await pump(
        tester,
        graph: NodeGraph(
          nodes: <GraphNode>[
            NodeComment.create(id: 'n1', position: const Offset(60, 60)),
          ],
        ),
      );

      await tester.enterText(find.byType(TextField), 'scene two');
      await tester.pump();

      expect(NodeComment.textOf(controller.graph.nodes['n1']!), 'scene two');
    });

    testWidgets('a note edited elsewhere is picked up without losing the '
        'caret', (tester) async {
      final controller = await pump(
        tester,
        graph: NodeGraph(
          nodes: <GraphNode>[
            NodeComment.create(id: 'n1', position: const Offset(60, 60)),
          ],
        ),
      );

      await tester.enterText(find.byType(TextField), 'abcd');
      await tester.pump();
      final field = tester.widget<TextField>(find.byType(TextField));
      field.controller!.selection = const TextSelection.collapsed(offset: 2);
      await tester.pump();
      expect(field.controller!.selection.baseOffset, 2);

      // An undo rewrites the note from outside, and that does have to move
      // the caret; a repaint that changes nothing must not.
      controller.camera.panBy(const Offset(4, 0));
      await tester.pump();
      expect(field.controller!.selection.baseOffset, 2);

      controller.history.undo();
      await tester.pump();
      expect(field.controller!.text, '');
    });

    testWidgets('grabbing the padding drags the note', (tester) async {
      final controller = await pump(
        tester,
        graph: NodeGraph(
          nodes: <GraphNode>[
            NodeComment.create(id: 'n1', position: const Offset(100, 100)),
          ],
        ),
      );

      final origin = tester.getTopLeft(find.byType(NodeEditor));
      // Inside the slab but outside the text field: the ring of padding is
      // the only place a note can be grabbed.
      final gesture = await tester.startGesture(
        origin + const Offset(104, 104),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.moveBy(const Offset(60, 40));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(controller.graph.nodes['n1']!.position, const Offset(160, 140));
      controller.history.undo();
      expect(
        controller.graph.nodes['n1']!.position,
        const Offset(100, 100),
        reason: 'a drag is one step for a note exactly as it is for a node',
      );
    });

    testWidgets('dragging across the text field does not move the note', (
      tester,
    ) async {
      final controller = await pump(
        tester,
        graph: NodeGraph(
          nodes: <GraphNode>[
            NodeComment.create(
              id: 'n1',
              position: const Offset(100, 100),
              text: 'select me, do not move me',
            ),
          ],
        ),
      );

      final origin = tester.getTopLeft(find.byType(NodeEditor));
      // Well inside the field. The field's own recogniser is deeper in the
      // hit-test path, so it takes the press and drags out a text selection —
      // which is the whole reason the note needs a ring of padding to grab.
      final gesture = await tester.startGesture(
        origin + const Offset(160, 120),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.moveBy(const Offset(60, 40));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(controller.graph.nodes['n1']!.position, const Offset(100, 100));
    });

    testWidgets('selecting a note floats it above the nodes', (tester) async {
      final controller = await pump(
        tester,
        graph: NodeGraph(
          nodes: <GraphNode>[
            NodeComment.create(id: 'n1', position: const Offset(60, 60)),
            plain('a', const Offset(80, 80)),
          ],
        ),
      );

      expect(
        controller.layout.nodesInPaintOrder.last.id,
        'a',
        reason: 'nothing is selected, so document order stands',
      );

      controller.selection.selectNode('n1');
      expect(
        controller.layout.nodesInPaintOrder.last.id,
        'n1',
        reason: 'a note shares one paint order with the nodes',
      );
    });
  });

  /// A note has to be readable on whatever canvas it is drawn on, and it must
  /// not inherit the host app's input styling.
  ///
  /// Both halves were broken at once: the ink was a single near-white constant
  /// that vanished on a light canvas, and the field left
  /// [InputDecoration.filled] unset, so a host whose `InputDecorationTheme`
  /// fills its inputs painted a solid box straight across the note. In a light
  /// app that is white ink on a white box.
  group('legibility', () {
    Future<TextField> pumpNote(
      WidgetTester tester, {
      required NodeEditorTheme canvas,
      required ThemeData hostTheme,
    }) async {
      final controller = NodeEditorController(
        graph: NodeGraph(
          nodes: <GraphNode>[
            NodeComment.create(
              id: 'n1',
              position: const Offset(40, 40),
              text: 'a note',
            ),
          ],
        ),
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: hostTheme,
          home: Scaffold(
            body: NodeEditor(
              controller: controller,
              theme: canvas,
              nodeBuilder: (context, node, state) =>
                  const ColoredBox(color: Color(0xFF2A2E38)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return tester.widget<TextField>(find.byType(TextField));
    }

    /// A host that fills its inputs, which is an ordinary thing for an app to
    /// want and used to be enough to erase every note on the board.
    ThemeData filledHost(Brightness brightness) => ThemeData(
      brightness: brightness,
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: Color(0xFFFFFFFF),
      ),
    );

    testWidgets('the note refuses the host\'s input fill', (tester) async {
      final field = await pumpNote(
        tester,
        canvas: NodeEditorTheme.light(),
        hostTheme: filledHost(Brightness.light),
      );
      expect(
        field.decoration?.filled,
        isFalse,
        reason: 'left unset, the host paints a solid box over the note',
      );
    });

    testWidgets('the ink follows the canvas, not one fixed colour', (
      tester,
    ) async {
      final onLight = await pumpNote(
        tester,
        canvas: NodeEditorTheme.light(),
        hostTheme: filledHost(Brightness.light),
      );
      final onDark = await pumpNote(
        tester,
        canvas: NodeEditorTheme.dark(),
        hostTheme: filledHost(Brightness.dark),
      );

      final light = onLight.style!.color!;
      final dark = onDark.style!.color!;
      expect(light, isNot(dark));
      expect(
        light.computeLuminance(),
        lessThan(0.5),
        reason: 'dark ink on a light canvas',
      );
      expect(
        dark.computeLuminance(),
        greaterThan(0.5),
        reason: 'light ink on a dark canvas',
      );
    });

    testWidgets('the canvas decides, not the host brightness', (tester) async {
      // A light app around a dark canvas is a legitimate arrangement, and the
      // note is drawn on the canvas.
      final field = await pumpNote(
        tester,
        canvas: NodeEditorTheme.dark(),
        hostTheme: filledHost(Brightness.light),
      );
      expect(field.style!.color!.computeLuminance(), greaterThan(0.5));
    });
  });
}
