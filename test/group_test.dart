import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fl_nodes_v2/fl_nodes_v2.dart';

/// Groups: frames drawn behind a set of nodes, owning no geometry of their
/// own. What is pinned here is the membership rules, the derived frame, the
/// paint order, and that the handle is the only part of one you can grab.
void main() {
  final NodeEditorTheme theme = NodeEditorTheme.dark();

  GraphNode node(String id, Offset position) => GraphNode(
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

  NodeGraph threeNodes() => NodeGraph(
    nodes: <GraphNode>[
      node('a', const Offset(100, 100)),
      node('b', const Offset(400, 100)),
      node('c', const Offset(800, 400)),
    ],
  );

  NodeEditorController boot({NodeGraph? graph}) {
    final controller = NodeEditorController(graph: graph ?? threeNodes());
    addTearDown(controller.dispose);
    return controller;
  }

  group('membership', () {
    test('the graph refuses to hold a group naming nodes it does not have', () {
      final graph = NodeGraph(
        nodes: <GraphNode>[node('a', Offset.zero)],
        groups: const <NodeGroup>[
          NodeGroup(id: 'g1', nodeIds: <String>{'a', 'ghost'}),
          NodeGroup(id: 'g2', nodeIds: <String>{'ghost'}),
        ],
      );

      expect(graph.groups['g1']!.nodeIds, <String>{'a'});
      expect(
        graph.groups['g2'],
        isNull,
        reason: 'a frame with nothing left in it is a frame around nothing',
      );
    });

    test('membership is exclusive — putGroup steals from the others', () {
      var graph = threeNodes();
      graph = graph.putGroup(
        const NodeGroup(id: 'g1', nodeIds: <String>{'a', 'b'}),
      );
      graph = graph.putGroup(const NodeGroup(id: 'g2', nodeIds: <String>{'b'}));

      expect(graph.groups['g1']!.nodeIds, <String>{'a'});
      expect(graph.groups['g2']!.nodeIds, <String>{'b'});
      expect(graph.groupOf('b')!.id, 'g2');
    });

    test('removing the last member removes the group', () {
      var graph = threeNodes().putGroup(
        const NodeGroup(id: 'g1', nodeIds: <String>{'a', 'b'}),
      );

      graph = graph.removeNodes(<String>['a']);
      expect(graph.groups['g1']!.nodeIds, <String>{'b'});

      graph = graph.removeNodes(<String>['b']);
      expect(graph.groups, isEmpty);
    });

    test('disbanding leaves the nodes alone', () {
      final controller = boot();
      controller.selection.selectNodes(<String>['a', 'b']);
      final id = controller.groupSelection()!;

      controller.disbandGroups(<String>[id]);
      expect(controller.graph.groups, isEmpty);
      expect(controller.graph.nodes, hasLength(3));
    });
  });

  group('the frame', () {
    test('is the members bounding box, padded', () {
      final controller = boot();
      controller.selection.selectNodes(<String>['a', 'b']);
      // `controller.graph` is read before `groupSelection()` runs if these
      // are one expression, so the lookup would miss the group it just made.
      final id = controller.groupSelection()!;
      final group = controller.graph.groups[id]!;

      final frame = controller.layout.boundsOfGroup(group)!;
      // a is (100,100)+160x90, b is (400,100)+160x90 -> union (100,100)-(560,190)
      expect(frame.left, 100 - NodeGroup.padding.left);
      expect(frame.top, 100 - NodeGroup.padding.top);
      expect(frame.right, 560 + NodeGroup.padding.right);
      expect(frame.bottom, 190 + NodeGroup.padding.bottom);
    });

    test('follows its members without being told', () {
      final controller = boot();
      controller.selection.selectNodes(<String>['a', 'b']);
      final id = controller.groupSelection()!;
      final group = controller.graph.groups[id]!;
      final before = controller.layout.boundsOfGroup(group)!;

      controller.translateNodes(<String>['b'], const Offset(200, 0));

      expect(
        controller.layout.boundsOfGroup(group)!.right,
        before.right + 200,
        reason: 'a group owns no geometry — the frame is derived every time',
      );
    });

    test('is included when framing the content', () {
      final controller = boot(
        graph: NodeGraph(nodes: <GraphNode>[node('a', const Offset(100, 100))]),
      );
      controller.selection.selectNode('a');
      controller.groupSelection();

      final bounds = controller.graph.contentBounds(controller.layout.sizeOf)!;
      expect(
        bounds.top,
        100 - NodeGroup.padding.top,
        reason: 'fitting the view to the nodes alone would clip the frames',
      );
    });

    test('a frame can be visible with no member on screen', () {
      final controller = boot(
        graph: NodeGraph(
          nodes: <GraphNode>[
            node('left', const Offset(-4000, 0)),
            node('right', const Offset(4000, 0)),
          ],
        ),
      );
      controller.selection.selectNodes(<String>['left', 'right']);
      controller.groupSelection();

      const middle = Rect.fromLTWH(-200, -200, 400, 400);
      expect(controller.layout.nodesIn(middle), isEmpty);
      expect(
        controller.layout.groupsIn(middle),
        hasLength(1),
        reason: 'which is why the group cull is asked separately',
      );
    });
  });

  group('Ctrl+G', () {
    test('frames a plain selection of nodes', () {
      final controller = boot();
      controller.selection.selectNodes(<String>['a', 'b']);

      final id = controller.groupSelection()!;
      expect(controller.graph.groups[id]!.nodeIds, <String>{'a', 'b'});
      expect(controller.graph.groups[id]!.name, NodeGroup.defaultName);
      expect(
        controller.selection.groupIds,
        <String>{id},
        reason: 'the frame you just made is what you want to act on next',
      );
      controller.history.undo();
      expect(controller.graph.groups, isEmpty);
    });

    test('widens the group already in the selection', () {
      final controller = boot();
      controller.selection.selectNodes(<String>['a', 'b']);
      final id = controller.groupSelection()!;

      controller.selection.selectGroup(id);
      controller.selection.selectNode('c', additive: true);
      expect(controller.groupSelection(), id);

      expect(controller.graph.groups, hasLength(1));
      expect(controller.graph.groups[id]!.nodeIds, <String>{'a', 'b', 'c'});
    });

    test('refuses a node that belongs to another group', () {
      final controller = boot();
      controller.selection.selectNodes(<String>['a']);
      final first = controller.groupSelection()!;
      controller.selection.selectNodes(<String>['b']);
      final second = controller.groupSelection()!;

      // The second frame, plus a node the first one holds.
      controller.selection.selectGroup(second);
      controller.selection.selectNode('a', additive: true);

      expect(
        controller.groupSelection(),
        isNull,
        reason: 'stealing a member would rewrite a frame nobody was looking at',
      );
      expect(controller.graph.groups[first]!.nodeIds, <String>{'a'});
      expect(controller.graph.groups[second]!.nodeIds, <String>{'b'});
    });

    test('refuses two groups at once, and an empty selection', () {
      final controller = boot();
      controller.selection.selectNode('a');
      final first = controller.groupSelection()!;
      controller.selection.selectNode('b');
      final second = controller.groupSelection()!;

      controller.selection.selectGroup(first);
      controller.selection.selectGroup(second, additive: true);
      expect(controller.groupSelection(), isNull);

      controller.selection.clear();
      expect(controller.groupSelection(), isNull);
    });

    test('a group alone is a no-op, not a new frame', () {
      final controller = boot();
      controller.selection.selectNodes(<String>['a', 'b']);
      final id = controller.groupSelection()!;

      controller.selection.selectGroup(id);
      expect(controller.groupSelection(), id);
      expect(controller.graph.groups, hasLength(1));
    });
  });

  group('selection', () {
    test('deleting a selected group takes its contents', () {
      final controller = boot();
      controller.selection.selectNodes(<String>['a', 'b']);
      final id = controller.groupSelection()!;

      controller.selection.selectGroup(id);
      controller.selection.deleteSelected();

      expect(controller.graph.nodes.keys, <String>['c']);
      expect(controller.graph.groups, isEmpty);

      controller.history.undo();
      expect(
        controller.graph.nodes,
        hasLength(3),
        reason: 'the frame and its contents go in one step',
      );
    });

    test('selecting a group does not select its nodes', () {
      final controller = boot();
      controller.selection.selectNodes(<String>['a', 'b']);
      final id = controller.groupSelection()!;
      controller.selection.selectGroup(id);

      expect(controller.selection.nodeIds, isEmpty);
      expect(controller.selection.nodeIdsWithGroups, <String>{'a', 'b'});
    });

    test('select-all leaves the frames out', () {
      final controller = boot();
      controller.selection.selectNodes(<String>['a', 'b']);
      controller.groupSelection();

      controller.selection.selectAll();
      expect(controller.selection.groupIds, isEmpty);

      controller.selection.deleteSelected();
      expect(controller.graph.nodes, isEmpty);
      expect(controller.graph.groups, isEmpty);
    });

    test('copying a group brings the frame and its nodes', () {
      final controller = boot();
      controller.selection.selectNodes(<String>['a', 'b']);
      final id = controller.groupSelection()!;
      controller.selection.selectGroup(id);

      expect(controller.clipboard.copy(), isTrue);
      final pasted = controller.clipboard.paste();

      expect(pasted, hasLength(2));
      expect(controller.graph.groups, hasLength(2));
      final fresh = controller.graph.groups.values.firstWhere(
        (group) => group.id != id,
      );
      expect(fresh.nodeIds, pasted);
    });

    test('copying half a group leaves the frame behind', () {
      final controller = boot();
      controller.selection.selectNodes(<String>['a', 'b']);
      controller.groupSelection();

      controller.selection.selectNode('a');
      controller.clipboard.copy();
      controller.clipboard.paste();

      expect(
        controller.graph.groups,
        hasLength(1),
        reason: 'a frame around half of what it framed is not what was copied',
      );
    });
  });

  group('document', () {
    test('groups round-trip with their name, colour and members', () {
      const codec = NodeGraphCodec();
      final graph = threeNodes().putGroup(
        NodeGroup(
          id: 'g1',
          nodeIds: const <String>{'a', 'b'},
          name: 'Act one',
          color: NodeGroup.palette.first,
        ),
      );

      final restored = codec
          .decode(codec.encode(GraphDocument(graph: graph)))
          .graph;

      final group = restored.groups['g1']!;
      expect(group.name, 'Act one');
      expect(group.color, NodeGroup.palette.first);
      expect(group.nodeIds, <String>{'a', 'b'});
    });

    test('a document with no groups omits the key', () {
      const codec = NodeGraphCodec();
      final json = codec.encode(GraphDocument(graph: threeNodes()));
      expect(json.containsKey('groups'), isFalse);
      expect(codec.decode(json).graph.groups, isEmpty);
    });

    test('a member the document does not carry is dropped, not fatal', () {
      const codec = NodeGraphCodec();
      final json = codec.encode(
        GraphDocument(
          graph: threeNodes().putGroup(
            const NodeGroup(id: 'g1', nodeIds: <String>{'a', 'b'}),
          ),
        ),
      );
      (json['nodes']! as List<Object?>).removeWhere(
        (entry) => (entry! as Map<String, Object?>)['id'] == 'b',
      );

      final restored = codec.decode(json).graph;
      expect(
        restored.groups['g1']!.nodeIds,
        <String>{'a'},
        reason:
            'a frame around four of five nodes is still a frame; refusing '
            'to open the document over it would be worse',
      );
    });
  });

  group('canvas', () {
    Future<NodeEditorController> pump(
      WidgetTester tester, {
      NodeGraph? graph,
    }) async {
      final controller = NodeEditorController(graph: graph ?? threeNodes());
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NodeEditor(
              controller: controller,
              theme: theme,
              nodeBuilder: (context, node, state) =>
                  const ColoredBox(color: Color(0xFF2A2E38)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return controller;
    }

    testWidgets('Ctrl+G frames the selection from the keyboard', (
      tester,
    ) async {
      final controller = await pump(tester);
      controller.selection.selectNodes(<String>['a', 'b']);
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(controller.graph.groups, hasLength(1));
      expect(find.text(NodeGroup.defaultName), findsOneWidget);
    });

    testWidgets('the handle selects and drags the whole group', (tester) async {
      final controller = await pump(tester);
      controller.selection.selectNodes(<String>['a', 'b']);
      controller.groupSelection();
      controller.selection.clear();
      await tester.pumpAndSettle();

      final handle = find.byIcon(Icons.drag_indicator);
      expect(handle, findsOneWidget);

      final gesture = await tester.startGesture(
        tester.getCenter(handle),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.moveBy(const Offset(50, 30));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(controller.selection.groupIds, hasLength(1));
      expect(controller.graph.nodes['a']!.position, const Offset(150, 130));
      expect(controller.graph.nodes['b']!.position, const Offset(450, 130));
      expect(
        controller.graph.nodes['c']!.position,
        const Offset(800, 400),
        reason: 'a node outside the frame is not part of it',
      );

      controller.history.undo();
      expect(
        controller.graph.nodes['a']!.position,
        const Offset(100, 100),
        reason: 'one drag is one step, however many nodes it moved',
      );
    });

    testWidgets('the frame itself takes no clicks', (tester) async {
      final controller = await pump(tester);
      controller.selection.selectNodes(<String>['a', 'b']);
      controller.groupSelection();
      controller.selection.clear();
      await tester.pumpAndSettle();

      // Between the two nodes, well inside the frame and clear of the handle.
      final origin = tester.getTopLeft(find.byType(NodeEditor));
      await tester.tapAt(origin + const Offset(320, 160));
      await tester.pumpAndSettle();

      expect(
        controller.selection.isEmpty,
        isTrue,
        reason: 'the space inside a frame is still canvas',
      );
    });

    testWidgets('a frame paints below its own members', (tester) async {
      final controller = await pump(tester);
      controller.selection.selectNodes(<String>['a', 'b']);
      controller.groupSelection();
      controller.selection.clear();
      await tester.pumpAndSettle();

      // Clicking a node inside the frame does what it always did.
      final origin = tester.getTopLeft(find.byType(NodeEditor));
      await tester.tapAt(origin + const Offset(180, 140));
      await tester.pumpAndSettle();

      expect(controller.selection.nodeIds, <String>{'a'});
      expect(controller.selection.groupIds, isEmpty);
    });

    testWidgets('right-clicking the handle offers Disband', (tester) async {
      final controller = await pump(tester);
      controller.selection.selectNodes(<String>['a', 'b']);
      controller.groupSelection();
      controller.selection.clear();
      await tester.pumpAndSettle();

      final gesture = await tester.startGesture(
        tester.getCenter(find.byIcon(Icons.drag_indicator)),
        buttons: kSecondaryButton,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.text('Disband'), findsOneWidget);
      await tester.tap(find.text('Disband'));
      await tester.pumpAndSettle();

      expect(controller.graph.groups, isEmpty);
      expect(controller.graph.nodes, hasLength(3));
    });

    testWidgets('the colour menu recolours the frame', (tester) async {
      final controller = await pump(tester);
      controller.selection.selectNodes(<String>['a', 'b']);
      final id = controller.groupSelection()!;
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.arrow_drop_down));
      await tester.pumpAndSettle();

      final swatch = NodeGroup.palette.first;
      final label = '#${swatch.toARGB32().toRadixString(16).substring(2)}';
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();

      expect(controller.graph.groups[id]!.color, swatch);
    });
  });
}
