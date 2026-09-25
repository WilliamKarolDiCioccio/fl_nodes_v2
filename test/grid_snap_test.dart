import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fl_nodes_v2/fl_nodes_v2.dart';

/// A move lands on the grid the canvas draws, when the user asks it to.
///
/// The step is never a number of its own: it is the theme's `gridSpacing`,
/// which the editor reports to the controller, so the line a card lands on is
/// a line somebody can see. These pin that, the arithmetic under it, and the
/// three places where "snap everything to the grid" is the wrong answer — a
/// fine nudge, a waypoint lined up with its neighbours, and an arrangement.
void main() {
  const double spacing = 24;

  final NodeEditorTheme theme = NodeEditorTheme.dark().copyWith(
    gridSpacing: spacing,
  );

  final NodePrototypeRegistry prototypes = NodePrototypeRegistry(
    const <NodePrototype>[
      NodePrototype(
        type: 'step',
        label: 'Step',
        ports: <PortFamily>[
          StaticPortFamily(
            id: 'io',
            ports: <NodePort>[
              NodePort.input(id: 'in'),
              NodePort.output(id: 'out'),
            ],
          ),
        ],
      ),
    ],
  );

  GraphNode node(String id, Offset position) => GraphNode(
    id: id,
    type: 'step',
    position: position,
    width: 160,
    height: 90,
  );

  /// A bare controller, no editor: nothing has told it a spacing.
  NodeEditorController headless(List<GraphNode> nodes) {
    final controller = NodeEditorController(
      graph: NodeGraph(nodes: nodes),
      prototypes: prototypes,
    );
    addTearDown(controller.dispose);
    return controller;
  }

  Future<NodeEditorController> boot(
    WidgetTester tester, {
    List<GraphNode>? nodes,
    bool snap = true,
    NodeEditorTheme? withTheme,
  }) async {
    final controller = NodeEditorController(
      graph: NodeGraph(
        nodes: nodes ?? <GraphNode>[node('a', const Offset(100, 100))],
      ),
      prototypes: prototypes,
    );
    addTearDown(controller.dispose);
    controller.history.clear();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 800,
              height: 600,
              child: NodeEditor(
                controller: controller,
                theme: withTheme ?? theme,
                nodeBuilder: (context, node, state) => const SizedBox.expand(
                  child: ColoredBox(color: Colors.grey),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    controller.snapToGrid = snap;
    return controller;
  }

  Offset screen(WidgetTester tester, NodeEditorController c, Offset scene) =>
      tester.getTopLeft(find.byType(NodeEditor)) +
      c.camera.viewport.toScreen(scene);

  /// A mouse drag from [from] by [by], both in scene units.
  Future<void> drag(
    WidgetTester tester,
    NodeEditorController controller,
    Offset from,
    Offset by,
  ) async {
    final gesture = await tester.startGesture(
      screen(tester, controller, from),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await gesture.moveBy(by * controller.camera.viewport.scale);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
  }

  Future<void> press(
    WidgetTester tester,
    LogicalKeyboardKey key, {
    bool shift = false,
  }) async {
    if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(key);
    if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
  }

  group('GridSnap', () {
    test('rounds to the nearest line, not down to it', () {
      expect(GridSnap.axis(13, spacing), 24);
      expect(GridSnap.axis(11, spacing), 0);
      expect(GridSnap.axis(36, spacing), 48, reason: 'a half goes outward');
    });

    test('is symmetric about the origin', () {
      expect(GridSnap.axis(-13, spacing), -24);
      expect(GridSnap.axis(-36, spacing), -48);
    });

    test('never hands back a negative zero', () {
      final snapped = GridSnap.axis(-0.4, spacing);
      expect(snapped, 0.0);
      expect(
        snapped.toString(),
        '0.0',
        reason:
            '-0.0 compares equal to 0.0 and then serialises as itself, '
            'so a document would carry it out to disk',
      );
    });

    test('a step of zero or less is the identity', () {
      expect(GridSnap.axis(13.7, 0), 13.7);
      expect(GridSnap.axis(13.7, -5), 13.7);
      expect(
        GridSnap.offset(const Offset(13.7, -2.5), 0),
        const Offset(13.7, -2.5),
      );
    });

    test('snaps the two axes independently', () {
      expect(
        GridSnap.offset(const Offset(13, 35), spacing),
        const Offset(24, 24),
      );
    });
  });

  group('the controller', () {
    test('has no step until an editor gives it one', () {
      final controller = headless(<GraphNode>[node('a', const Offset(7, 7))]);
      controller.snapToGrid = true;
      expect(
        controller.snapStep,
        0,
        reason:
            'a headless controller has no grid to be drawn against, and '
            'moves nodes exactly where it is told',
      );
      controller.translateNodes(<String>['a'], const Offset(3, 3));
      expect(controller.graph.node('a')!.position, const Offset(10, 10));
    });

    test('snaps its own moves once it has one', () {
      final controller = headless(<GraphNode>[node('a', const Offset(7, 7))]);
      controller.reportGridStep(spacing);
      controller.snapToGrid = true;
      controller.translateNodes(<String>['a'], const Offset(3, 3));
      expect(
        controller.graph.node('a')!.position,
        const Offset(0, 0),
        reason:
            'the toggle means what it says on the controller too, which '
            'is why the editor hands the step down rather than keeping it',
      );
    });

    test('an exact move overrides the preference', () {
      final controller = headless(<GraphNode>[node('a', const Offset(0, 0))]);
      controller.reportGridStep(spacing);
      controller.snapToGrid = true;
      controller.translateNodes(<String>['a'], const Offset(1, 1), snap: false);
      expect(controller.graph.node('a')!.position, const Offset(1, 1));
    });

    test('setting the toggle to what it already is notifies nobody', () {
      final controller = headless(<GraphNode>[node('a', Offset.zero)]);
      var notifications = 0;
      controller.addListener(() => notifications++);
      controller.snapToGrid = false;
      expect(notifications, 0);
      controller.snapToGrid = true;
      expect(notifications, 1);
    });

    test('the toggle does not bump the revision', () {
      final controller = headless(<GraphNode>[node('a', Offset.zero)]);
      final before = controller.revision;
      controller.snapToGrid = true;
      expect(
        controller.revision,
        before,
        reason:
            'nothing has moved, and the revision is what throws away the '
            'connection path cache',
      );
    });

    test(
      'a move that lands everything where it already is reaches no guard',
      () {
        final controller = headless(<GraphNode>[
          node('a', const Offset(24, 24)),
        ]);
        controller.reportGridStep(spacing);
        controller.snapToGrid = true;
        final seen = <GraphEditKind>[];
        controller.guard = (edit) {
          seen.add(edit.kind);
          return true;
        };
        controller.translateNodes(<String>['a'], const Offset(2, 2));
        expect(
          seen,
          isEmpty,
          reason:
              'the guard is asked before an edit is found to be a no-op, and '
              'with snapping on most frames of a drag are no-ops',
        );
        expect(controller.graph.node('a')!.position, const Offset(24, 24));
      },
    );

    test('each node snaps its own corner, so a selection may change shape', () {
      final controller = headless(<GraphNode>[
        node('a', const Offset(0, 0)),
        node('b', const Offset(10, 0)),
      ]);
      controller.reportGridStep(spacing);
      controller.snapToGrid = true;
      controller.translateNodes(<String>['a', 'b'], const Offset(5, 0));
      expect(controller.graph.node('a')!.position, const Offset(0, 0));
      expect(
        controller.graph.node('b')!.position,
        const Offset(24, 0),
        reason:
            'chosen deliberately over snapping one anchor and carrying the '
            'rest by its delta: everything ends on a line, and the gap between '
            'two cards can change as they land',
      );
    });
  });

  group('a carried route', () {
    NodeEditorController wired() {
      final controller = headless(<GraphNode>[
        node('a', const Offset(0, 0)),
        node('b', const Offset(10, 0)),
      ]);
      controller.connect(
        const PortRef('a', 'out'),
        const PortRef('b', 'in'),
        id: 'ab',
      );
      controller.setConnectionWaypoints('ab', const <Offset>[Offset(200, 50)]);
      controller.reportGridStep(spacing);
      controller.snapToGrid = true;
      return controller;
    }

    test('follows a snapped drag although the ends move on other frames', () {
      final controller = wired();

      // Frame one: `b` crosses its line, `a` does not.
      controller.moveNodes(<String, Offset>{
        'a': const Offset(5, 0),
        'b': const Offset(15, 0),
      });
      expect(controller.graph.node('a')!.position, const Offset(0, 0));
      expect(controller.graph.node('b')!.position, const Offset(24, 0));

      // Frame two: `a` crosses, `b` stands still.
      controller.moveNodes(<String, Offset>{
        'a': const Offset(13, 0),
        'b': const Offset(23, 0),
      });
      expect(controller.graph.node('a')!.position, const Offset(24, 0));
      expect(controller.graph.node('b')!.position, const Offset(24, 0));

      expect(
        controller.graph.connections['ab']!.waypoints,
        const <Offset>[Offset(224, 50)],
        reason:
            'the route travels by the emitting end, and neither frame '
            'moved both ends — which is exactly the case snapping produces',
      );
    });

    test('still stays put when only one end is in the move', () {
      final controller = wired();
      controller.moveNodes(<String, Offset>{'b': const Offset(100, 0)});
      expect(
        controller.graph.connections['ab']!.waypoints,
        const <Offset>[Offset(200, 50)],
        reason: 'the user pinned those points to the canvas',
      );
    });
  });

  group('on the canvas', () {
    testWidgets('a drag lands the top-left corner on a line', (tester) async {
      final controller = await boot(tester);
      await drag(
        tester,
        controller,
        const Offset(180, 140),
        const Offset(53, 47),
      );
      final position = controller.graph.node('a')!.position;
      expect(position, const Offset(144, 144));
      expect(position.dx % spacing, 0);
      expect(position.dy % spacing, 0);
    });

    testWidgets('the step is the grid that is drawn', (tester) async {
      final controller = await boot(
        tester,
        withTheme: NodeEditorTheme.dark().copyWith(gridSpacing: 40),
      );
      await drag(
        tester,
        controller,
        const Offset(180, 140),
        const Offset(53, 47),
      );
      expect(
        controller.graph.node('a')!.position,
        const Offset(160, 160),
        reason:
            'the same drag lands somewhere else because the lines are '
            'somewhere else — the snap has no number of its own',
      );
    });

    testWidgets('with the toggle off a drag goes where it is put', (
      tester,
    ) async {
      final controller = await boot(tester, snap: false);
      await drag(
        tester,
        controller,
        const Offset(180, 140),
        const Offset(53, 47),
      );
      expect(controller.graph.node('a')!.position, const Offset(153, 147));
    });

    testWidgets('a snapped drag is still one undo step', (tester) async {
      final controller = await boot(tester);
      await drag(
        tester,
        controller,
        const Offset(180, 140),
        const Offset(53, 47),
      );
      expect(controller.graph.node('a')!.position, const Offset(144, 144));
      controller.history.undo();
      expect(controller.graph.node('a')!.position, const Offset(100, 100));
      expect(controller.history.canUndo, isFalse);
    });

    testWidgets('snapping needs no grid to be painted', (tester) async {
      final controller = await boot(
        tester,
        withTheme: NodeEditorTheme.dark().copyWith(
          gridSpacing: spacing,
          showGrid: false,
        ),
      );
      await drag(
        tester,
        controller,
        const Offset(180, 140),
        const Offset(53, 47),
      );
      expect(
        controller.graph.node('a')!.position,
        const Offset(144, 144),
        reason:
            'the lattice is a fact about the scene, not about what is drawn',
      );
    });

    testWidgets('an arrow puts an off-grid card on the grid', (tester) async {
      final controller = await boot(
        tester,
        nodes: <GraphNode>[node('a', const Offset(7, 7))],
      );
      controller.selection.selectNode('a');
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(
        controller.graph.node('a')!.position,
        const Offset(24, 0),
        reason:
            'a whole cell added and then rounded always moves, and never '
            'backwards — and the axis that was not nudged is pulled on too, '
            'because a snapped node stands on the grid rather than on one '
            'line of it',
      );
    });

    testWidgets('an arrow still moves with the toggle off', (tester) async {
      final controller = await boot(tester, snap: false);
      controller.selection.selectNode('a');
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(
        controller.graph.node('a')!.position,
        const Offset(108, 100),
        reason:
            'the 8-unit fallback has to stand on its own: reaching for the '
            'resolved step here would make it zero and the arrows dead',
      );
    });

    testWidgets('shift is the fine nudge and ignores the grid', (tester) async {
      final controller = await boot(tester);
      controller.selection.selectNode('a');
      await press(tester, LogicalKeyboardKey.arrowRight, shift: true);
      expect(
        controller.graph.node('a')!.position,
        const Offset(101, 100),
        reason:
            'one unit rounded to a cell is a guaranteed no-op, so shift '
            'means place it exactly',
      );
    });
  });

  group('the step handover', () {
    testWidgets('reaches a controller swapped under an unchanged theme', (
      tester,
    ) async {
      final first = NodeEditorController(
        graph: NodeGraph(nodes: <GraphNode>[node('a', Offset.zero)]),
        prototypes: prototypes,
      );
      addTearDown(first.dispose);
      final second = NodeEditorController(
        graph: NodeGraph(nodes: <GraphNode>[node('a', const Offset(7, 7))]),
        prototypes: prototypes,
      );
      addTearDown(second.dispose);

      Widget editorFor(NodeEditorController controller) => MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 600,
            child: NodeEditor(
              controller: controller,
              theme: theme,
              nodeBuilder: (context, node, state) => const SizedBox.expand(),
            ),
          ),
        ),
      );

      await tester.pumpWidget(editorFor(first));
      await tester.pumpAndSettle();
      await tester.pumpWidget(editorFor(second));
      await tester.pumpAndSettle();

      second.snapToGrid = true;
      expect(
        second.snapStep,
        spacing,
        reason:
            'the theme did not change, so the editor never re-resolved it — '
            'and a controller that was never told the spacing would place '
            'every node exactly where it was asked to',
      );
      second.translateNodes(<String>['a'], const Offset(3, 3));
      expect(second.graph.node('a')!.position, Offset.zero);
    });
  });

  group('rebuild isolation', () {
    testWidgets('flipping the toggle builds no node body', (tester) async {
      final builds = <String, int>{};
      final controller = NodeEditorController(
        graph: NodeGraph(
          nodes: <GraphNode>[
            node('a', const Offset(100, 100)),
            node('b', const Offset(320, 100)),
          ],
        ),
        prototypes: prototypes,
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: NodeEditor(
                controller: controller,
                theme: theme,
                nodeBuilder: (context, node, state) {
                  builds[node.id] = (builds[node.id] ?? 0) + 1;
                  return const SizedBox.expand();
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      builds.clear();
      controller.snapToGrid = true;
      await tester.pump();
      expect(
        builds,
        isEmpty,
        reason:
            'the toggle changes where a drag lands, not what any node '
            'looks like — which is the whole reason it is not a theme field',
      );
    });
  });

  group('an arrangement', () {
    test('ignores the toggle', () {
      final controller = headless(<GraphNode>[node('a', Offset.zero)]);
      controller.reportGridStep(spacing);
      controller.snapToGrid = true;
      expect(
        controller.applyLayout(
          (graph, sizeOf) => <String, Offset>{'a': const Offset(37, 41)},
        ),
        isTrue,
      );
      expect(
        controller.graph.node('a')!.position,
        const Offset(37, 41),
        reason:
            'the same rule that has it ignore `draggable`: the toggle says '
            'what a pointer may express, and a computed picture is not one',
      );
    });
  });

  group('the clipboard', () {
    test('nudges a duplicate by a cell rather than by 32', () {
      final controller = headless(<GraphNode>[node('a', Offset.zero)]);
      controller.reportGridStep(spacing);
      controller.snapToGrid = true;
      controller.selection.selectNode('a');
      final made = controller.clipboard.duplicate();
      expect(made, hasLength(1));
      expect(
        controller.graph.node(made.single)!.position,
        const Offset(spacing, spacing),
        reason:
            '32 is not a multiple of 24, so the old nudge put a duplicate '
            'eight units off a line and it jumped on its first drag',
      );
    });

    test('keeps the plain nudge with the toggle off', () {
      final controller = headless(<GraphNode>[node('a', Offset.zero)]);
      controller.reportGridStep(spacing);
      controller.selection.selectNode('a');
      final made = controller.clipboard.duplicate();
      expect(
        controller.graph.node(made.single)!.position,
        NodeEditorClipboard.pasteNudge,
      );
    });
  });
}
