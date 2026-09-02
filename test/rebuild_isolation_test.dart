import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fl_nodes_v2/fl_nodes_v2.dart';

/// The editor rebuilds its whole canvas whenever anything on the controller
/// changes, and a host's node body can be arbitrarily expensive — a form, a
/// text field, a preview. These pin the rule that keeps that affordable: a
/// node's body is rebuilt only when something about *that node* changed.
///
/// Each of these fails the moment a per-node callback goes back to being a
/// closure built during the layer's build, because a fresh closure makes every
/// node look different to the widget the editor cached for it.
void main() {
  final builds = <String, int>{};

  Widget body(BuildContext context, GraphNode node, NodeRenderState state) {
    builds[node.id] = (builds[node.id] ?? 0) + 1;
    return const SizedBox.expand();
  }

  GraphNode node(String id, Offset position) => GraphNode(
    id: id,
    position: position,
    width: 160,
    height: 90,
    ports: const <NodePort>[
      NodePort.input(id: 'in'),
      NodePort.output(id: 'out'),
    ],
  );

  /// Four nodes in a row, all comfortably inside the test viewport.
  NodeEditorController build4() => NodeEditorController(
    graph: NodeGraph(
      nodes: <GraphNode>[
        node('a', Offset.zero),
        node('b', const Offset(200, 0)),
        node('c', const Offset(400, 0)),
        node('d', const Offset(0, 150)),
      ],
    ),
  );

  Future<NodeEditorController> boot(
    WidgetTester tester, {
    MinimapConfig? minimap,
  }) async {
    final controller = build4();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NodeEditor(
            controller: controller,
            nodeBuilder: body,
            minimap: minimap,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    builds.clear();
    return controller;
  }

  Set<String> rebuilt() => builds.keys.toSet();

  testWidgets('panning rebuilds no node bodies at all', (tester) async {
    final controller = await boot(tester);

    for (var i = 0; i < 5; i++) {
      controller.camera.panBy(const Offset(3, 2));
      await tester.pump();
    }

    expect(
      builds,
      isEmpty,
      reason: 'nothing about any node changed, only the view onto them',
    );
  });

  testWidgets('zooming rebuilds no node bodies at all', (tester) async {
    final controller = await boot(tester);

    controller.camera.setScale(0.75);
    await tester.pump();

    expect(builds, isEmpty);
  });

  testWidgets('moving one node rebuilds only that node', (tester) async {
    final controller = await boot(tester);

    controller.translateNodes(<String>['b'], const Offset(10, 0));
    await tester.pump();

    expect(rebuilt(), <String>{'b'});
  });

  testWidgets('dragging a node leaves its neighbours alone', (tester) async {
    await boot(tester);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey<String>('a'))),
    );
    for (var i = 0; i < 5; i++) {
      await gesture.moveBy(const Offset(4, 3));
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(rebuilt(), <String>{
      'a',
    }, reason: 'the dragged node moves; the rest of the canvas does not');
  });

  testWidgets('selection rebuilds only the nodes whose state changed', (
    tester,
  ) async {
    final controller = await boot(tester);

    controller.selection.selectNode('a');
    await tester.pump();
    expect(rebuilt(), <String>{'a'});

    builds.clear();
    controller.selection.selectNode('c');
    await tester.pump();
    expect(rebuilt(), <String>{
      'a',
      'c',
    }, reason: 'one node lost the outline and one gained it');
  });

  testWidgets('wiring two nodes rebuilds no bodies at all', (tester) async {
    final controller = await boot(tester);

    controller.connect(const PortRef('a', 'out'), const PortRef('b', 'in'));
    await tester.pump();

    expect(
      builds,
      isEmpty,
      reason:
          'a handle fills in when a wire lands on it, but handles are painted '
          'now — so what used to redraw both ends is a repaint of one layer '
          'and no node body is asked for again',
    );
  });

  testWidgets('editing one node rebuilds only that node', (tester) async {
    final controller = await boot(tester);

    controller.updateNode(
      'd',
      (node) => node.copyWith(data: <String, Object?>{'title': 'renamed'}),
    );
    await tester.pump();

    expect(rebuilt(), <String>{'d'});
  });

  testWidgets('swapping the controller drops the cached widgets', (
    tester,
  ) async {
    await boot(tester);
    final replacement = build4();
    addTearDown(replacement.dispose);

    // Same ids, a different document: nothing cached for the old one may be
    // handed to the new one.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NodeEditor(controller: replacement, nodeBuilder: body),
        ),
      ),
    );
    await tester.pump();

    expect(rebuilt(), <String>{'a', 'b', 'c', 'd'});
  });

  testWidgets('a node scrolled out of view stops being tracked', (
    tester,
  ) async {
    final controller = await boot(tester);
    final editor = tester.state<NodeEditorState>(find.byType(NodeEditor));

    expect(editor.debugTrackedNodeCount, 4);

    // Far enough that nothing is left in the cull rect.
    controller.camera.panBy(const Offset(-100000, 0));
    await tester.pump();

    expect(
      editor.debugTrackedNodeCount,
      0,
      reason:
          'per-node state has to be dropped with the node, or a long '
          'session over a big graph accumulates one entry per node ever seen',
    );
  });

  group('with the minimap on', () {
    // The panel is a sibling in the canvas stack, and a readout: it never
    // calls the controller, so it can never bump the revision and can never
    // make a node slot look changed. These re-run the three numbers in the
    // table in CLAUDE.md with it drawn.
    testWidgets('panning still rebuilds no node bodies at all', (tester) async {
      final controller = await boot(tester, minimap: const MinimapConfig());

      for (var i = 0; i < 5; i++) {
        controller.camera.panBy(const Offset(3, 2));
        await tester.pump();
      }

      expect(builds, isEmpty);
    });

    testWidgets('dragging a node still rebuilds only that node', (
      tester,
    ) async {
      await boot(tester, minimap: const MinimapConfig());

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey<String>('a'))),
      );
      for (var i = 0; i < 5; i++) {
        await gesture.moveBy(const Offset(4, 3));
        await tester.pump();
      }
      await gesture.up();
      await tester.pumpAndSettle();

      expect(rebuilt(), <String>{'a'});
    });

    testWidgets('a selection change still rebuilds only the two nodes', (
      tester,
    ) async {
      final controller = await boot(tester, minimap: const MinimapConfig());

      controller.selection.selectNode('a');
      await tester.pump();
      builds.clear();
      controller.selection.selectNode('c');
      await tester.pump();

      expect(rebuilt(), <String>{'a', 'c'});
    });

    testWidgets('dragging the panel rebuilds no node bodies at all', (
      tester,
    ) async {
      await boot(tester, minimap: const MinimapConfig());

      final gesture = await tester.startGesture(
        tester.getCenter(find.byIcon(Icons.drag_indicator)),
        kind: PointerDeviceKind.mouse,
      );
      for (var i = 0; i < 5; i++) {
        await gesture.moveBy(const Offset(-6, -4));
        await tester.pump();
      }
      await gesture.up();
      await tester.pumpAndSettle();

      expect(
        builds,
        isEmpty,
        reason:
            'the panel writes to its own controller, so the editor is not '
            'notified and its canvas is not rebuilt',
      );
    });

    testWidgets('the panel widget survives a pan', (tester) async {
      final controller = await boot(tester, minimap: const MinimapConfig());
      final editor = tester.state<NodeEditorState>(find.byType(NodeEditor));
      final before = editor.debugMinimapPanel;
      expect(before, isNotNull);

      for (var i = 0; i < 5; i++) {
        controller.camera.panBy(const Offset(3, 2));
        await tester.pump();
      }

      expect(
        identical(editor.debugMinimapPanel, before),
        isTrue,
        reason:
            'the map repaints through its painter\'s listenable; handing back '
            'a fresh widget would rebuild the bar, the menu and the grip on '
            'every scroll tick instead',
      );
    });
  });
}
