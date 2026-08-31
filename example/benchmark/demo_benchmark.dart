import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fl_nodes_v2/fl_nodes_v2.dart';
import 'package:fl_nodes_v2_example/main.dart';
import 'package:fl_nodes_v2_example/sample_graph.dart';
import 'package:fl_nodes_v2_example/workflow_node_card.dart';

const Size kViewport = Size(1600, 900);

/// What a drag costs in the demo *as an app*, rather than in a harness built
/// to flatter the editor.
///
/// The package's own `widget_benchmark.dart` passes a top-level function as
/// its `nodeBuilder`. A real host writes a closure inline, and if it rebuilds
/// the editor on every controller tick that closure is new every frame — which
/// is a different measurement entirely, and the one that matches what the app
/// actually feels like.
///
/// ```sh
/// flutter test benchmark/demo_benchmark.dart
/// ```
void main() {
  // `testWidgets` turns semantics on by default and an app does not run
  // that way. Leaving it on measures a semantics tree walk over every
  // gesture handler on screen, which here is an order of magnitude more
  // than everything else put together — and pure fiction.
  testWidgets('demo drag benchmark', semanticsEnabled: false, (tester) async {
    tester.view.physicalSize = kViewport;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const NodeEditorDemoApp());
    await tester.pumpAndSettle();

    final editor = tester.widget<NodeEditor>(find.byType(NodeEditor));
    final controller = editor.controller;
    final state = tester.state<NodeEditorState>(find.byType(NodeEditor));

    for (final count in <int>[100, 500]) {
      controller.project.reset(buildStressGraph(count));
      await tester.pumpAndSettle();
      // What the Load menu does: frame the whole thing, which at this size
      // means every node is on screen at once.
      controller.camera.fitToContent(state.viewportSize);
      await tester.pumpAndSettle();

      final drawn = controller.layout
          .nodesIn(controller.camera.viewport.visibleSceneRect(kViewport))
          .length;

      // Grab a node in the middle of the grid, in screen coordinates.
      final grabbed = controller.graph.node('n${count ~/ 2}')!;
      final start = controller.camera.viewport.toScreen(
        grabbed.rect(controller.layout.sizeOf(grabbed)).center,
      );
      expect(
        Offset.zero & state.viewportSize,
        isNotNull,
        reason: 'the grabbed node has to be on screen',
      );

      final origin = tester.getTopLeft(find.byType(NodeEditor));
      final gesture = await tester.startGesture(origin + start);
      await tester.pump();

      WorkflowNodeCard.debugBuildCount = 0;
      const frames = 30;
      final watch = Stopwatch()..start();
      for (var i = 0; i < frames; i++) {
        await gesture.moveBy(const Offset(3, 2));
        await tester.pump();
      }
      watch.stop();
      final builds = WorkflowNodeCard.debugBuildCount;
      await gesture.up();
      await tester.pumpAndSettle();

      debugPrint(
        '\n--- demo, $count nodes ($drawn drawn, '
        'zoom ${(controller.camera.viewport.scale * 100).round()}%) ---\n'
        'DRAG ${(watch.elapsedMicroseconds / frames / 1000).toStringAsFixed(2)}'
        'ms/frame  ${(builds / frames).toStringAsFixed(1)} card bodies/frame',
      );
    }
  });
}
