import 'dart:ui';

import 'package:flutter/painting.dart' show EdgeInsets;
import 'package:flutter_test/flutter_test.dart';
import 'package:fl_nodes_v2/fl_nodes_v2.dart';

void main() {
  GraphNode node(
    String id, {
    Offset position = Offset.zero,
    List<NodePort> ports = const <NodePort>[
      NodePort.input(id: 'in'),
      NodePort.output(id: 'out'),
    ],
  }) => GraphNode(
    id: id,
    position: position,
    width: 100,
    height: 50,
    ports: ports,
  );

  NodeEditorController controllerWith(List<GraphNode> nodes) =>
      NodeEditorController(graph: NodeGraph(nodes: nodes));

  group('port kinds and types', () {
    NodeEditorController pair(NodePort out, NodePort into) {
      final controller = NodeEditorController(
        graph: NodeGraph(
          nodes: <GraphNode>[
            GraphNode(id: 'a', position: Offset.zero, ports: <NodePort>[out]),
            GraphNode(id: 'b', position: Offset.zero, ports: <NodePort>[into]),
          ],
        ),
      );
      addTearDown(controller.dispose);
      return controller;
    }

    test('a control output does not wire to a data input', () {
      final controller = pair(
        const NodePort.output(id: 'out', kind: PortKind.control),
        const NodePort.input(id: 'in'),
      );

      expect(
        controller.connect(const PortRef('a', 'out'), const PortRef('b', 'in')),
        isNull,
        reason: 'one decides what runs next, the other moves a value',
      );
    });

    test('types must agree unless one side declares none', () {
      NodePort out(String? type) => NodePort.output(id: 'out', dataType: type);
      NodePort into(String? type) => NodePort.input(id: 'in', dataType: type);

      expect(NodeEditorController.portsCompatible(out('s'), into('s')), isTrue);
      expect(
        NodeEditorController.portsCompatible(out('s'), into('n')),
        isFalse,
      );
      expect(
        NodeEditorController.portsCompatible(out(null), into('n')),
        isTrue,
        reason:
            'an untyped port is a wildcard, so adding a type to one side '
            'of an existing graph never invalidates a wire on its own',
      );
      expect(
        NodeEditorController.portsCompatible(out('s'), into(null)),
        isTrue,
      );

      final controller = pair(out('string'), into('number'));
      expect(
        controller.connect(const PortRef('a', 'out'), const PortRef('b', 'in')),
        isNull,
      );
    });

    test('two control ports wire together', () {
      final controller = pair(
        const NodePort.output(id: 'out', kind: PortKind.control),
        const NodePort.input(id: 'in', kind: PortKind.control),
      );

      expect(
        controller.connect(const PortRef('a', 'out'), const PortRef('b', 'in')),
        isNotNull,
      );
    });
  });

  group('connecting', () {
    test('wires an output to an input in either drag order', () {
      final controller = controllerWith(<GraphNode>[node('a'), node('b')]);

      final id = controller.connect(
        const PortRef('b', 'in'),
        const PortRef('a', 'out'),
      );

      expect(id, isNotNull);
      final connection = controller.graph.connections[id]!;
      expect(connection.from, const PortRef('a', 'out'));
      expect(connection.to, const PortRef('b', 'in'));
    });

    test('rejects same-direction, self and duplicate connections', () {
      final controller = controllerWith(<GraphNode>[node('a'), node('b')]);

      expect(
        controller.connect(
          const PortRef('a', 'out'),
          const PortRef('b', 'out'),
        ),
        isNull,
      );
      expect(
        controller.connect(const PortRef('a', 'in'), const PortRef('a', 'out')),
        isNull,
      );

      expect(
        controller.connect(const PortRef('a', 'out'), const PortRef('b', 'in')),
        isNotNull,
      );
      expect(
        controller.connect(const PortRef('a', 'out'), const PortRef('b', 'in')),
        isNull,
      );
      expect(controller.graph.connections, hasLength(1));
    });

    test('respects maxConnections', () {
      final controller = controllerWith(<GraphNode>[
        node('a'),
        node('b'),
        node(
          'c',
          ports: const <NodePort>[NodePort.input(id: 'in', maxConnections: 1)],
        ),
      ]);

      expect(
        controller.connect(const PortRef('a', 'out'), const PortRef('c', 'in')),
        isNotNull,
      );
      expect(
        controller.canConnect(
          const PortRef('b', 'out'),
          const PortRef('c', 'in'),
        ),
        isFalse,
      );
    });

    test('honours a custom validator', () {
      final controller = NodeEditorController(
        graph: NodeGraph(nodes: <GraphNode>[node('a'), node('b')]),
        connectionValidator: (graph, from, to) => to.nodeId != 'b',
      );

      expect(
        controller.connect(const PortRef('a', 'out'), const PortRef('b', 'in')),
        isNull,
      );
    });
  });

  group('history', () {
    test('undo and redo walk the graph snapshots', () {
      final controller = controllerWith(<GraphNode>[node('a')]);

      controller.addNode(node('b'));
      expect(controller.graph.nodes, hasLength(2));

      controller.history.undo();
      expect(controller.graph.nodes, hasLength(1));
      expect(controller.history.canRedo, isTrue);

      controller.history.redo();
      expect(controller.graph.nodes, hasLength(2));
    });

    test('a transaction collapses into a single undo step', () {
      final controller = controllerWith(<GraphNode>[node('a')]);

      controller.history.beginTransaction();
      for (var i = 1; i <= 10; i++) {
        controller.moveNodes(<String, Offset>{'a': Offset(i * 10, 0)});
      }
      controller.history.commitTransaction();

      expect(controller.graph.node('a')!.position, const Offset(100, 0));
      controller.history.undo();
      expect(controller.graph.node('a')!.position, Offset.zero);
      expect(controller.history.canUndo, isFalse);
    });

    test('cancelTransaction restores the starting snapshot', () {
      final controller = controllerWith(<GraphNode>[node('a')]);

      controller.history.beginTransaction();
      controller.moveNodes(<String, Offset>{'a': const Offset(50, 50)});
      controller.history.cancelTransaction();

      expect(controller.graph.node('a')!.position, Offset.zero);
      expect(controller.history.canUndo, isFalse);
    });

    test('history is capped at historyLimit', () {
      final controller = NodeEditorController(
        graph: NodeGraph(nodes: <GraphNode>[node('a')]),
        historyLimit: 3,
      );

      for (var i = 1; i <= 6; i++) {
        controller.moveNodes(<String, Offset>{'a': Offset(i * 10, 0)});
      }
      for (var i = 0; i < 3; i++) {
        controller.history.undo();
      }

      expect(controller.history.canUndo, isFalse);
      expect(controller.graph.node('a')!.position, const Offset(30, 0));
    });
  });

  group('metadata', () {
    test(
      'setNodeMetadata is one undo step, and undo puts the old map back',
      () {
        final controller = controllerWith(<GraphNode>[
          node('a').copyWith(metadata: <String, Object?>{'draft': true}),
        ]);
        addTearDown(controller.dispose);

        controller.setNodeMetadata('a', <String, Object?>{
          'draft': false,
          'notes': <String, Object?>{
            'reviewed': <String>['me'],
          },
        });

        expect(controller.graph.node('a')!.metadata, <String, Object?>{
          'draft': false,
          'notes': <String, Object?>{
            'reviewed': <String>['me'],
          },
        });
        controller.history.undo();
        expect(controller.graph.node('a')!.metadata, <String, Object?>{
          'draft': true,
        });
        expect(controller.history.canUndo, isFalse);
      },
    );

    test('setting equal metadata is a no-op', () {
      final controller = controllerWith(<GraphNode>[
        node('a').copyWith(
          metadata: <String, Object?>{
            'tags': <String>['x'],
          },
        ),
      ]);
      addTearDown(controller.dispose);
      final revision = controller.revision;

      // A fresh map, equal by value and not by identity — what a dialog hands
      // back when it is closed without a change.
      controller.setNodeMetadata('a', <String, Object?>{
        'tags': <String>['x'],
      });

      expect(controller.revision, revision);
      expect(
        controller.history.canUndo,
        isFalse,
        reason:
            'an undo step that changes nothing is a step the user cannot '
            'see and has to press through',
      );
    });

    test('a node that is not there is left alone', () {
      final controller = controllerWith(<GraphNode>[node('a')]);
      addTearDown(controller.dispose);
      final revision = controller.revision;

      controller.setNodeMetadata('missing', <String, Object?>{'k': 1});

      expect(controller.revision, revision);
    });

    test('the map handed in is not the map the node keeps', () {
      final controller = controllerWith(<GraphNode>[node('a')]);
      addTearDown(controller.dispose);
      final handed = <String, Object?>{'k': 1};

      controller.setNodeMetadata('a', handed);
      handed['k'] = 2;

      expect(
        controller.graph.node('a')!.metadata['k'],
        1,
        reason: 'the graph is an immutable snapshot the history relies on',
      );
    });
  });

  group('selection', () {
    test('drops ids that no longer exist', () {
      final controller = controllerWith(<GraphNode>[node('a'), node('b')]);
      controller.selection.selectNodes(<String>['a', 'b']);

      controller.removeNodes(<String>['a']);

      expect(controller.selection.nodeIds, <String>{'b'});
    });

    test('adding a node to the selection keeps the selected wire', () {
      final controller = controllerWith(<GraphNode>[node('a'), node('b')]);
      final wire = controller.connect(
        const PortRef('a', 'out'),
        const PortRef('b', 'in'),
      )!;
      controller.selection.selectConnection(wire);

      controller.selection.toggleNode('a');

      expect(
        controller.selection.connectionIds,
        <String>{wire},
        reason:
            '"keep what you had" is passed as the live set, and clearing '
            'that set before reading it used to empty it',
      );
      expect(controller.selection.nodeIds, <String>{'a'});
    });

    test('marquee selects overlapping nodes only', () {
      final controller = controllerWith(<GraphNode>[
        node('a', position: Offset.zero),
        node('b', position: const Offset(400, 400)),
      ]);

      controller.selection.selectInRect(const Rect.fromLTWH(-10, -10, 60, 60));

      expect(controller.selection.nodeIds, <String>{'a'});
    });

    test('deleteSelection removes nodes and their connections at once', () {
      final controller = controllerWith(<GraphNode>[node('a'), node('b')]);
      controller.connect(const PortRef('a', 'out'), const PortRef('b', 'in'));
      controller.selection.selectNode('a');

      controller.selection.deleteSelected();

      expect(controller.graph.nodes.keys, <String>['b']);
      expect(controller.graph.connections, isEmpty);

      controller.history.undo();
      expect(controller.graph.nodes, hasLength(2));
      expect(controller.graph.connections, hasLength(1));
    });
  });

  group('spatial index', () {
    test('tracks nodes through moves, removal and undo', () {
      final controller = controllerWith(<GraphNode>[
        node('a', position: Offset.zero),
        node('b', position: const Offset(900, 900)),
      ]);

      expect(controller.layout.nodeAt(const Offset(10, 10))?.id, 'a');
      expect(controller.layout.nodeAt(const Offset(910, 910))?.id, 'b');
      expect(controller.layout.nodeAt(const Offset(400, 400)), isNull);

      controller.moveNodes(<String, Offset>{'a': const Offset(400, 400)});
      expect(controller.layout.nodeAt(const Offset(10, 10)), isNull);
      expect(controller.layout.nodeAt(const Offset(410, 410))?.id, 'a');

      controller.history.undo();
      expect(controller.layout.nodeAt(const Offset(10, 10))?.id, 'a');
      expect(controller.layout.nodeAt(const Offset(410, 410)), isNull);

      controller.removeNodes(<String>['a']);
      expect(controller.layout.nodeAt(const Offset(10, 10)), isNull);
      expect(controller.layout.cellReferences, 1);
    });

    test('follows a measured height', () {
      final controller = controllerWith(<GraphNode>[
        const GraphNode(id: 'auto', position: Offset.zero, width: 100),
      ]);

      final fallbackBottom = GraphNode.fallbackHeight;
      expect(controller.layout.nodeAt(Offset(50, fallbackBottom + 40)), isNull);

      controller.layout.reportMeasuredSize(
        'auto',
        Size(100, fallbackBottom + 100),
      );
      expect(
        controller.layout.nodeAt(Offset(50, fallbackBottom + 40))?.id,
        'auto',
      );
    });

    test('nodesIn returns only the overlapping nodes, in paint order', () {
      final controller = controllerWith(<GraphNode>[
        node('a', position: Offset.zero),
        node('b', position: const Offset(60, 0)),
        node('far', position: const Offset(5000, 5000)),
      ]);
      controller.selection.selectNode('a');

      final visible = controller.layout.nodesIn(
        const Rect.fromLTWH(0, 0, 400, 400),
      );

      expect(visible.map((n) => n.id), <String>['b', 'a']);
    });

    test('portAt finds the nearest port and ignores distant ones', () {
      final controller = controllerWith(<GraphNode>[
        node('a', position: Offset.zero),
      ]);

      // Ports sit mid-edge on a 100x50 node at the origin.
      expect(
        controller.layout.portAt(const Offset(100, 25), radius: 11),
        const PortRef('a', 'out'),
      );
      expect(
        controller.layout.portAt(const Offset(0, 25), radius: 11),
        const PortRef('a', 'in'),
      );
      expect(
        controller.layout.portAt(const Offset(50, 25), radius: 11),
        isNull,
      );
    });

    test('revision moves on graph edits but not on viewport changes', () {
      final controller = controllerWith(<GraphNode>[node('a')]);
      final start = controller.revision;

      controller.camera.panBy(const Offset(40, 40));
      controller.camera.setScale(2);
      expect(controller.revision, start);

      controller.moveNodes(<String, Offset>{'a': const Offset(5, 5)});
      expect(controller.revision, greaterThan(start));
    });
  });

  group('viewport', () {
    test('fitToContent frames the whole graph', () {
      final controller = controllerWith(<GraphNode>[
        node('a', position: Offset.zero),
        node('b', position: const Offset(900, 400)),
      ]);
      controller.camera.setScaleLimits(0.1, 4);

      controller.camera.fitToContent(
        const Size(500, 500),
        padding: EdgeInsets.zero,
      );

      final visible = controller.camera.viewport.visibleSceneRect(
        const Size(500, 500),
      );
      final bounds = controller.graph.contentBounds(controller.layout.sizeOf)!;
      expect(visible.contains(bounds.topLeft), isTrue);
      expect(
        visible.contains(bounds.bottomRight - const Offset(0.01, 0.01)),
        isTrue,
      );
    });

    test('clamps zoom to the configured limits', () {
      final controller = controllerWith(<GraphNode>[node('a')]);
      controller.camera.setScaleLimits(0.5, 2);

      controller.camera.setScale(10);
      expect(controller.camera.viewport.scale, 2);

      controller.camera.setScale(0.01);
      expect(controller.camera.viewport.scale, 0.5);
    });
  });

  test('sizeOf prefers a declared height and falls back to measurement', () {
    final controller = controllerWith(<GraphNode>[
      node('fixed'),
      const GraphNode(id: 'auto', position: Offset.zero, width: 120),
    ]);

    expect(
      controller.layout.sizeOf(controller.graph.node('fixed')!),
      const Size(100, 50),
    );
    expect(
      controller.layout.sizeOf(controller.graph.node('auto')!).height,
      GraphNode.fallbackHeight,
    );

    controller.layout.reportMeasuredSize('auto', const Size(120, 77));
    expect(
      controller.layout.sizeOf(controller.graph.node('auto')!),
      const Size(120, 77),
    );
  });

  group('prototypes', () {
    final placeholder = RegExp(r'\{(\d+)\}');

    /// One input per placeholder in `format`, plus a fixed output.
    NodePrototype formatPrototype({NodeHeightResolver? resolveHeight}) =>
        NodePrototype(
          type: 'format',
          resolveHeight: resolveHeight,
          ports: <PortFamily>[
            const StaticPortFamily(
              id: 'flow',
              ports: <NodePort>[NodePort.output(id: 'out')],
            ),
            DynamicPortFamily(
              id: 'args',
              build: (context) => <NodePort>[
                for (final match in placeholder.allMatches(
                  context.fieldOr<String>('format', ''),
                ))
                  NodePort.input(id: 'arg_${match.group(1)}'),
              ],
            ),
          ],
        );

    /// Keeps every wired exit and always leaves one free.
    NodePrototype fanOutPrototype() => NodePrototype(
      type: 'fanout',
      ports: <PortFamily>[
        const StaticPortFamily(
          id: 'entry',
          ports: <NodePort>[NodePort.input(id: 'in')],
        ),
        DynamicPortFamily(
          id: 'exits',
          build: PortFamilies.variadic(
            idPrefix: 'out_',
            create: (index) => NodePort.output(id: 'out_$index'),
          ),
        ),
      ],
    );

    GraphNode seed(
      String id, {
      String type = 'format',
      Map<String, Object?> data = const <String, Object?>{},
      Offset position = Offset.zero,
    }) => GraphNode(
      id: id,
      type: type,
      position: position,
      width: 100,
      data: data,
    );

    List<String> portIds(NodeEditorController controller, String id) =>
        <String>[for (final port in controller.graph.node(id)!.ports) port.id];

    test('adding a node derives its ports', () {
      final controller = NodeEditorController(
        prototypes: NodePrototypeRegistry(<NodePrototype>[formatPrototype()]),
      );
      addTearDown(controller.dispose);

      controller.addNode(seed('a', data: <String, Object?>{'format': '{0}'}));

      expect(portIds(controller, 'a'), <String>[
        'out',
        'arg_0',
      ], reason: 'resolution doubles as instantiation');
    });

    test('the constructor normalises the graph it is handed', () {
      final controller = NodeEditorController(
        graph: NodeGraph(
          nodes: <GraphNode>[
            seed('a', data: <String, Object?>{'format': '{0} {1}'}),
          ],
        ),
        prototypes: NodePrototypeRegistry(<NodePrototype>[formatPrototype()]),
      );
      addTearDown(controller.dispose);

      expect(portIds(controller, 'a'), <String>['out', 'arg_0', 'arg_1']);
    });

    test('editing a field re-derives the ports, dragging does not', () {
      var builds = 0;
      final controller = NodeEditorController(
        prototypes: NodePrototypeRegistry(<NodePrototype>[
          NodePrototype(
            type: 'format',
            ports: <PortFamily>[
              DynamicPortFamily(
                id: 'args',
                build: (context) {
                  builds++;
                  return <NodePort>[
                    for (final match in placeholder.allMatches(
                      context.fieldOr<String>('format', ''),
                    ))
                      NodePort.input(id: 'arg_${match.group(1)}'),
                  ];
                },
              ),
            ],
          ),
        ]),
      );
      addTearDown(controller.dispose);
      controller.addNode(seed('a', data: <String, Object?>{'format': '{0}'}));

      final afterAdd = builds;
      controller.moveNodes(<String, Offset>{'a': const Offset(40, 40)});
      expect(
        builds,
        afterAdd,
        reason:
            'dragging changes geometry only and must not enter the resolver',
      );

      controller.updateNode(
        'a',
        (node) => node.withData(<String, Object?>{'format': '{0} {1}'}),
      );
      expect(builds, greaterThan(afterAdd));
      expect(portIds(controller, 'a'), <String>['arg_0', 'arg_1']);
    });

    test('a metadata edit does not enter the resolver', () {
      var builds = 0;
      final controller = NodeEditorController(
        prototypes: NodePrototypeRegistry(<NodePrototype>[
          NodePrototype(
            type: 'format',
            ports: <PortFamily>[
              DynamicPortFamily(
                id: 'args',
                build: (context) {
                  builds++;
                  return <NodePort>[
                    for (final match in placeholder.allMatches(
                      context.fieldOr<String>('format', ''),
                    ))
                      NodePort.input(id: 'arg_${match.group(1)}'),
                  ];
                },
              ),
            ],
          ),
        ]),
      );
      addTearDown(controller.dispose);
      controller.addNode(seed('a', data: <String, Object?>{'format': '{0}'}));
      final afterAdd = builds;

      controller.setNodeMetadata('a', <String, Object?>{'note': 'hello'});

      expect(
        builds,
        afterAdd,
        reason: 'nothing a prototype answers reads metadata',
      );
      expect(portIds(controller, 'a'), <String>['arg_0']);
      expect(controller.graph.node('a')!.metadata, <String, Object?>{
        'note': 'hello',
      });
    });

    test('wiring the last exit spawns another', () {
      final controller = NodeEditorController(
        prototypes: NodePrototypeRegistry(<NodePrototype>[
          fanOutPrototype(),
          formatPrototype(),
        ]),
      );
      addTearDown(controller.dispose);
      controller.addNode(seed('r', type: 'fanout'));
      controller.addNode(seed('a', data: <String, Object?>{'format': '{0}'}));
      expect(portIds(controller, 'r'), <String>['in', 'out_0']);

      controller.connect(
        const PortRef('r', 'out_0'),
        const PortRef('a', 'arg_0'),
      );

      expect(portIds(controller, 'r'), <String>['in', 'out_0', 'out_1']);
    });

    test('removing a connection lets the far node shrink again', () {
      final controller = NodeEditorController(
        prototypes: NodePrototypeRegistry(<NodePrototype>[
          fanOutPrototype(),
          formatPrototype(),
        ]),
      );
      addTearDown(controller.dispose);
      controller.addNode(seed('r', type: 'fanout'));
      controller.addNode(seed('a', data: <String, Object?>{'format': '{0}'}));
      final id = controller.connect(
        const PortRef('r', 'out_0'),
        const PortRef('a', 'arg_0'),
      )!;

      controller.removeConnections(<String>[id]);

      expect(portIds(controller, 'r'), <String>['in', 'out_0']);
    });

    test('deleting a node lets its neighbour shrink again', () {
      final controller = NodeEditorController(
        prototypes: NodePrototypeRegistry(<NodePrototype>[
          fanOutPrototype(),
          formatPrototype(),
        ]),
      );
      addTearDown(controller.dispose);
      controller.addNode(seed('r', type: 'fanout'));
      controller.addNode(seed('a', data: <String, Object?>{'format': '{0}'}));
      controller.connect(
        const PortRef('r', 'out_0'),
        const PortRef('a', 'arg_0'),
      );
      expect(portIds(controller, 'r'), hasLength(3));

      controller.removeNodes(<String>['a']);

      expect(portIds(controller, 'r'), <String>['in', 'out_0']);
    });

    test('connect returns null when the resolver prunes the new wire', () {
      // A family that refuses to keep any port once it is wired: the
      // connection is made and then resolved away in the same mutation.
      final controller = NodeEditorController(
        prototypes: NodePrototypeRegistry(<NodePrototype>[
          NodePrototype(
            type: 'shy',
            ports: <PortFamily>[
              DynamicPortFamily(
                id: 'in',
                build: (context) => <NodePort>[
                  if (!context.isConnected('in'))
                    const NodePort.input(id: 'in'),
                ],
              ),
            ],
          ),
          formatPrototype(),
        ]),
      );
      addTearDown(controller.dispose);
      controller.addNode(seed('a', data: <String, Object?>{'format': ''}));
      controller.addNode(seed('s', type: 'shy'));

      final id = controller.connect(
        const PortRef('a', 'out'),
        const PortRef('s', 'in'),
      );

      expect(
        id,
        isNull,
        reason: 'the caller would otherwise dereference a connection that went',
      );
      expect(controller.graph.connections, isEmpty);
    });

    test('a resolution that changes the height patches the spatial index', () {
      final controller = NodeEditorController(
        prototypes: NodePrototypeRegistry(<NodePrototype>[
          formatPrototype(
            resolveHeight: (context) =>
                40 + 30.0 * context.portsOf('args').length,
          ),
        ]),
      );
      addTearDown(controller.dispose);
      controller.addNode(seed('a', data: <String, Object?>{'format': '{0}'}));
      expect(controller.layout.boundsOf('a')!.height, 70);

      controller.updateNode(
        'a',
        (node) => node.withData(<String, Object?>{'format': '{0} {1}'}),
      );

      expect(controller.layout.boundsOf('a')!.height, 100);
      expect(
        controller.layout.nodeAt(const Offset(50, 90)),
        isNotNull,
        reason: 'the new area has to be pickable, not just painted',
      );
    });

    test('a port and the wire it loses come back in one undo', () {
      final controller = NodeEditorController(
        prototypes: NodePrototypeRegistry(<NodePrototype>[
          formatPrototype(),
          fanOutPrototype(),
        ]),
      );
      addTearDown(controller.dispose);
      controller.addNode(seed('r', type: 'fanout'));
      controller.addNode(seed('a', data: <String, Object?>{'format': '{0}'}));
      final id = controller.connect(
        const PortRef('r', 'out_0'),
        const PortRef('a', 'arg_0'),
      )!;

      controller.updateNode(
        'a',
        (node) => node.withData(<String, Object?>{'format': 'none'}),
      );
      expect(controller.graph.connections.containsKey(id), isFalse);
      expect(portIds(controller, 'a'), <String>['out']);

      controller.history.undo();

      expect(portIds(controller, 'a'), <String>['out', 'arg_0']);
      expect(
        controller.graph.connections.containsKey(id),
        isTrue,
        reason: 'both happened inside one mutation, so one undo restores both',
      );
    });

    test('field edits inside a transaction collapse to one undo step', () {
      final controller = NodeEditorController(
        prototypes: NodePrototypeRegistry(<NodePrototype>[formatPrototype()]),
      );
      addTearDown(controller.dispose);
      controller.addNode(seed('a', data: <String, Object?>{'format': ''}));

      controller.history.beginTransaction();
      for (final value in <String>['{0}', '{0} {1}', '{0} {1} {2}']) {
        controller.updateNode(
          'a',
          (node) => node.withData(<String, Object?>{'format': value}),
        );
      }
      controller.history.commitTransaction();
      expect(portIds(controller, 'a'), hasLength(4));

      controller.history.undo();

      expect(portIds(controller, 'a'), <String>['out']);
      expect(
        controller.history.canUndo,
        isTrue,
        reason: 'the add is still on the stack',
      );
    });

    test('an edit the prototype undoes is a true no-op', () {
      final controller = NodeEditorController(
        prototypes: NodePrototypeRegistry(<NodePrototype>[formatPrototype()]),
      );
      addTearDown(controller.dispose);
      controller.addNode(seed('a', data: <String, Object?>{'format': '{0}'}));
      controller.history.clear();

      var notifications = 0;
      controller.addListener(() => notifications++);

      // A rogue port stamped with a family the prototype owns: the family is
      // rebuilt from the format string, so this resolves straight back out and
      // there is nothing to record.
      controller.updateNode(
        'a',
        (node) => node.copyWith(
          ports: <NodePort>[
            ...node.ports,
            const NodePort.input(id: 'rogue', family: 'args'),
          ],
        ),
      );

      expect(portIds(controller, 'a'), <String>['out', 'arg_0']);
      expect(notifications, 0);
      expect(controller.history.canUndo, isFalse);
    });

    test('swapping the registry re-normalises the document', () {
      final controller = NodeEditorController(
        prototypes: NodePrototypeRegistry(<NodePrototype>[formatPrototype()]),
      );
      addTearDown(controller.dispose);
      controller.addNode(seed('a', data: <String, Object?>{'format': '{0}'}));

      controller.prototypes = NodePrototypeRegistry(<NodePrototype>[
        NodePrototype(
          type: 'format',
          ports: <PortFamily>[
            const StaticPortFamily(
              id: 'flow',
              ports: <NodePort>[NodePort.output(id: 'out')],
            ),
          ],
        ),
      ]);

      expect(
        portIds(controller, 'a'),
        <String>['out'],
        reason: 'editing a builder has to reach nodes that already exist',
      );
    });

    test('revalidate records no history by default', () {
      final controller = NodeEditorController(
        prototypes: NodePrototypeRegistry(<NodePrototype>[formatPrototype()]),
      );
      addTearDown(controller.dispose);
      controller.addNode(seed('a', data: <String, Object?>{'format': '{0}'}));
      controller.history.clear();

      controller.revalidate();

      expect(controller.history.canUndo, isFalse);
    });

    test('a controller with no registry behaves exactly as it did', () {
      NodeGraph run(NodePrototypeRegistry? prototypes) {
        final controller = NodeEditorController(
          graph: NodeGraph(nodes: <GraphNode>[node('a'), node('b')]),
          prototypes: prototypes,
        );
        addTearDown(controller.dispose);
        controller.connect(const PortRef('a', 'out'), const PortRef('b', 'in'));
        controller.moveNodes(<String, Offset>{'a': const Offset(30, 30)});
        controller.updateNode(
          'b',
          (node) => node.withData(<String, Object?>{'x': 1}),
        );
        return controller.graph;
      }

      expect(run(null), run(NodePrototypeRegistry.empty));
    });
  });
}
