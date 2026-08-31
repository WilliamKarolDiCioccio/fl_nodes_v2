import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fl_nodes_v2/fl_nodes_v2.dart';

const Size kViewport = Size(1600, 900);

/// A grid packed tightly enough that most of it is on screen at once, which is
/// what any canvas degenerates to as soon as the user zooms out.
NodeEditorController buildVisibleGrid(int count) {
  final nodes = <GraphNode>[];
  final connections = <NodeConnection>[];
  const columns = 6;
  for (var i = 0; i < count; i++) {
    nodes.add(
      GraphNode(
        id: 'n$i',
        position: Offset((i % columns) * 260.0, (i ~/ columns) * 160.0),
        width: 220,
        height: 120,
        ports: const <NodePort>[
          NodePort.input(id: 'in'),
          NodePort.output(id: 'out'),
        ],
        data: <String, Object?>{'title': 'Node $i'},
      ),
    );
    if (i % columns != 0) {
      connections.add(
        NodeConnection(
          id: 'c$i',
          from: PortRef('n${i - 1}', 'out'),
          to: PortRef('n$i', 'in'),
        ),
      );
    }
  }
  return NodeEditorController(
    graph: NodeGraph(nodes: nodes, connections: connections),
  );
}

/// How many node bodies the editor asked the host to build.
int nodeBuilds = 0;

/// A body in the shape of a real one: a card, a header, a couple of rows. A
/// host's own is usually heavier — this understates what a rebuild costs.
Widget body(BuildContext context, GraphNode node, NodeRenderState state) {
  nodeBuilds++;
  return DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xFF23262E),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: const Color(0xFF3A3F4B)),
    ),
    child: Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            node.data['title'] as String? ?? '',
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
          const SizedBox(height: 6),
          const Text('subtitle', style: TextStyle(color: Colors.white54)),
          const Spacer(),
          Row(
            children: <Widget>[
              const Icon(Icons.circle, size: 10, color: Colors.white24),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'row ${node.id}',
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

/// What one frame of interaction costs at the widget layer.
///
/// The companion to `node_editor_benchmark.dart`, which prices the model. This
/// one prices the thing that is actually felt: how much of the widget tree a
/// pointer move puts back through build, layout and paint.
///
/// The number to watch is *node bodies per frame*, not the milliseconds — the
/// times are JIT and machine-dependent, but a host's node body is arbitrarily
/// expensive and every one of them rebuilt per frame is the difference between
/// a canvas that tracks the cursor and one that lags it.
///
/// ```sh
/// flutter test benchmark/widget_benchmark.dart
/// ```
void main() {
  // `testWidgets` turns semantics on by default and an app does not run
  // that way. Leaving it on measures a semantics tree walk over every
  // gesture handler on screen, which here is an order of magnitude more
  // than everything else put together — and pure fiction.
  testWidgets('widget layer benchmark', semanticsEnabled: false, (
    tester,
  ) async {
    tester.view.physicalSize = kViewport;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    for (final count in <int>[60, 500, 2000]) {
      final controller = buildVisibleGrid(count);
      addTearDown(controller.dispose);

      final editorKey = GlobalKey<NodeEditorState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NodeEditor(
              key: editorKey,
              controller: controller,
              nodeBuilder: body,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final layout = editorKey.currentState!.connectionLayout;
      final visible = controller.layout
          .nodesIn(controller.camera.viewport.visibleSceneRect(kViewport))
          .length;
      const frames = 40;

      // --- dragging one node --------------------------------------------
      final start = tester.getCenter(find.text('Node 0'));
      final gesture = await tester.startGesture(start);
      await tester.pump();

      nodeBuilds = 0;
      final curvesBefore = layout.pathBuildCount;
      final dragWatch = Stopwatch()..start();
      for (var i = 0; i < frames; i++) {
        await gesture.moveBy(const Offset(2, 1));
        await tester.pump();
      }
      dragWatch.stop();
      final dragBuilds = nodeBuilds;
      final dragCurves = layout.pathBuildCount - curvesBefore;
      final dragUs = dragWatch.elapsedMicroseconds / frames;
      await gesture.up();
      await tester.pumpAndSettle();

      // --- panning the view ---------------------------------------------
      nodeBuilds = 0;
      final panWatch = Stopwatch()..start();
      for (var i = 0; i < frames; i++) {
        controller.camera.panBy(const Offset(2, 1));
        await tester.pump();
      }
      panWatch.stop();
      final panBuilds = nodeBuilds;
      final panUs = panWatch.elapsedMicroseconds / frames;

      // --- a frame with nothing dirty, to price the harness itself -------
      final idleWatch = Stopwatch()..start();
      for (var i = 0; i < frames; i++) {
        await tester.pump();
      }
      idleWatch.stop();

      // --- selecting one node --------------------------------------------
      nodeBuilds = 0;
      controller.selection.selectNode('n1');
      await tester.pump();
      final selectBuilds = nodeBuilds;

      debugPrint(
        '\n--- $count nodes, ${controller.graph.connections.length} links '
        '($visible drawn) ---\n'
        'DRAG   ${(dragUs / 1000).toStringAsFixed(2)}ms/frame  '
        '${(dragBuilds / frames).toStringAsFixed(1)} node bodies, '
        '${(dragCurves / frames).toStringAsFixed(1)} curves per frame\n'
        'PAN    ${(panUs / 1000).toStringAsFixed(2)}ms/frame  '
        '${(panBuilds / frames).toStringAsFixed(1)} node bodies per frame\n'
        'IDLE   '
        '${(idleWatch.elapsedMicroseconds / frames / 1000).toStringAsFixed(2)}'
        'ms/frame  (the harness floor)\n'
        'SELECT one node -> $selectBuilds node bodies',
      );
    }
  });
}
