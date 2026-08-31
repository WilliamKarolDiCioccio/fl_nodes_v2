import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fl_nodes_v2/fl_nodes_v2.dart';

const int kNodes = 5000;
const Size kViewport = Size(1600, 900);

NodeEditorController buildBig() {
  final nodes = <GraphNode>[];
  final connections = <NodeConnection>[];
  const columns = 70;
  for (var i = 0; i < kNodes; i++) {
    nodes.add(
      GraphNode(
        id: 'n$i',
        position: Offset((i % columns) * 300.0, (i ~/ columns) * 200.0),
        width: 220,
        height: 120,
        ports: const <NodePort>[
          NodePort.input(id: 'in'),
          NodePort.output(id: 'out'),
        ],
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

double timeUs(int iterations, void Function() body) {
  for (var i = 0; i < 20; i++) {
    body();
  }
  final watch = Stopwatch()..start();
  for (var i = 0; i < iterations; i++) {
    body();
  }
  watch.stop();
  return watch.elapsedMicroseconds / iterations;
}

/// Reproducible measurements for the optimizations in this package.
///
/// Not part of the default suite — numbers are machine-dependent and would
/// make a flaky assertion. Run it explicitly:
///
/// ```sh
/// flutter test benchmark/node_editor_benchmark.dart
/// ```
void main() {
  test('node editor benchmark', () {
    final controller = buildBig();
    final graph = controller.graph;
    final visible = controller.camera.viewport.visibleSceneRect(kViewport);
    debugPrint(
      '\n--- ${graph.nodes.length} nodes, ${graph.connections.length} links, '
      'viewport ${kViewport.width.toInt()}x${kViewport.height.toInt()} ---',
    );

    // --- viewport culling -------------------------------------------------
    final indexed = timeUs(200, () => controller.layout.nodesIn(visible));
    final linear = timeUs(200, () {
      final hits = <GraphNode>[];
      for (final node in graph.nodes.values) {
        if (node.rect(controller.layout.sizeOf(node)).overlaps(visible)) {
          hits.add(node);
        }
      }
      hits.sort((a, b) => 0);
    });
    debugPrint(
      'CULL   indexed=${indexed.toStringAsFixed(1)}us '
      'linear=${linear.toStringAsFixed(1)}us '
      'visible=${controller.layout.nodesIn(visible).length}',
    );

    // --- connection geometry ----------------------------------------------
    final layout = ConnectionLayout();
    final cold = timeUs(20, () {
      layout.invalidate();
      layout.sync(controller);
    });
    final warm = timeUs(2000, () => layout.sync(controller));
    debugPrint(
      'LAYOUT rebuild=${cold.toStringAsFixed(1)}us '
      'cached=${warm.toStringAsFixed(2)}us',
    );

    // --- hover picking -----------------------------------------------------
    layout.sync(controller);
    const probe = Offset(660, 460);
    final picked = timeUs(500, () => layout.hitTest(probe, tolerance: 9));
    final naive = timeUs(20, () {
      final router = ConnectionRouter(
        graph: graph,
        sizeOf: controller.layout.sizeOf,
      );
      String? best;
      for (final c in graph.connections.values) {
        final path = router.scenePath(c);
        if (path == null) continue;
        if (!path.getBounds().inflate(9).contains(probe)) continue;
        if (ConnectionPath.distanceTo(path, probe) <= 9) {
          best = c.id;
        }
      }
      expect(best, anything);
    });
    debugPrint(
      'HOVER  cached+indexed=${picked.toStringAsFixed(1)}us '
      'rebuild-every-path=${naive.toStringAsFixed(1)}us',
    );

    // --- port picking ------------------------------------------------------
    final port = timeUs(
      2000,
      () => controller.layout.portAt(probe, radius: 11),
    );
    debugPrint('PORT   indexed=${port.toStringAsFixed(2)}us');

    // --- node drag (index maintenance) -------------------------------------
    var x = 0.0;
    final drag = timeUs(500, () {
      x += 1;
      controller.moveNodes(<String, Offset>{'n10': Offset(x, 0)});
    });
    debugPrint('DRAG   moveNodes(1 of $kNodes)=${drag.toStringAsFixed(1)}us');

    controller.dispose();

    // --- prototype resolution ---------------------------------------------
    // The question is whether normalising nodes costs anything on the paths
    // that run every frame. It must not: dragging seeds no nodes to resolve,
    // so it never enters the resolver at all.
    final prototyped = buildBig()
      ..prototypes = NodePrototypeRegistry(<NodePrototype>[
        NodePrototype(
          type: 'default',
          ports: <PortFamily>[
            const StaticPortFamily(
              id: 'io',
              ports: <NodePort>[
                NodePort.input(id: 'in'),
                NodePort.output(id: 'out'),
              ],
            ),
          ],
        ),
      ]);
    var y = 0.0;
    final protoDrag = timeUs(500, () {
      y += 1;
      prototyped.moveNodes(<String, Offset>{'n10': Offset(0, y)});
    });
    var tick = 0;
    final protoEdit = timeUs(200, () {
      tick++;
      prototyped.updateNode(
        'n20',
        (node) => node.withData(<String, Object?>{'tick': tick}),
      );
    });
    debugPrint(
      'PROTO  drag=${protoDrag.toStringAsFixed(1)}us '
      '(vs ${drag.toStringAsFixed(1)}us unprototyped) '
      'field-edit=${protoEdit.toStringAsFixed(1)}us',
    );

    // A single wide variadic family, to price the fixed point itself.
    final wide = NodePrototypeRegistry(<NodePrototype>[
      NodePrototype(
        type: 'wide',
        ports: <PortFamily>[
          DynamicPortFamily(
            id: 'exits',
            build: PortFamilies.variadic(
              idPrefix: 'out_',
              create: (index) => NodePort.output(id: 'out_$index'),
            ),
          ),
        ],
      ),
    ]);
    const wideCount = 200;
    var wideGraph = NodeGraph(
      nodes: <GraphNode>[
        GraphNode(
          id: 'w',
          type: 'wide',
          position: Offset.zero,
          ports: <NodePort>[
            for (var i = 0; i < wideCount; i++)
              NodePort.output(id: 'out_$i', family: 'exits'),
          ],
        ),
        const GraphNode(
          id: 'sink',
          position: Offset(600, 0),
          ports: <NodePort>[NodePort.input(id: 'in')],
        ),
      ],
      connections: <NodeConnection>[
        for (var i = 0; i < wideCount - 1; i++)
          NodeConnection(
            id: 'wc$i',
            from: PortRef('w', 'out_$i'),
            to: const PortRef('sink', 'in'),
          ),
      ],
    );
    wideGraph = wide.resolveAll(wideGraph).graph;
    final wideResolve = timeUs(200, () {
      wide.resolve(wideGraph, seeds: const <String>['w']);
    });
    debugPrint(
      'PROTO  settled $wideCount-port family='
      '${wideResolve.toStringAsFixed(1)}us',
    );

    prototyped.dispose();
  });
}
