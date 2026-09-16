import 'package:flutter_test/flutter_test.dart';
import 'package:fl_nodes_v2/fl_nodes_v2.dart';

void main() {
  // Placeholders like "{0}" in a format string, the print-node example.
  final placeholder = RegExp(r'\{(\d+)\}');

  List<int> slotsOf(String text) => <int>{
    for (final match in placeholder.allMatches(text))
      int.parse(match.group(1)!),
  }.toList()..sort();

  /// One input per placeholder in `format`, plus a fixed output.
  NodePrototype formatPrototype({
    NodeHeightResolver? resolveHeight,
    PortRemovalHandler? onPortsRemoved,
    NodeFieldMerge? inheritFields,
  }) {
    return NodePrototype(
      type: 'format',
      resolveHeight: resolveHeight,
      onPortsRemoved: onPortsRemoved ?? NodePortRemoval.dropConnections,
      inheritFields: inheritFields ?? NodeFields.seedAndPrune,
      fields: const <FieldFamily>[
        StaticFieldFamily(
          id: 'main',
          fields: <NodeField>[NodeField(key: 'format', defaultValue: '')],
        ),
      ],
      ports: <PortFamily>[
        const StaticPortFamily(
          id: 'flow',
          ports: <NodePort>[NodePort.output(id: 'out')],
        ),
        DynamicPortFamily(
          id: 'args',
          build: (context) => <NodePort>[
            for (final slot in slotsOf(context.fieldOr<String>('format', '')))
              NodePort.input(id: 'arg_$slot', label: '{$slot}'),
          ],
        ),
      ],
    );
  }

  /// Keeps every wired exit and always leaves one free, so wiring the last one
  /// grows the family.
  NodePrototype fanOutPrototype() {
    return NodePrototype(
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
  }

  GraphNode node(
    String id, {
    String type = 'format',
    Map<String, Object?> data = const <String, Object?>{},
    List<NodePort> ports = const <NodePort>[],
    double? height,
  }) => GraphNode(
    id: id,
    type: type,
    position: Offset.zero,
    height: height,
    data: data,
    ports: ports,
  );

  List<String> portIds(GraphNode node) => <String>[
    for (final port in node.ports) port.id,
  ];

  group('ownership', () {
    test('a node with no prototype is returned untouched', () {
      final registry = NodePrototypeRegistry(<NodePrototype>[
        formatPrototype(),
      ]);
      final original = node('a', type: 'unknown');
      final graph = NodeGraph(nodes: <GraphNode>[original]);

      final result = registry.resolve(graph, seeds: <String>['a']);

      expect(result.isUnchanged, isTrue);
      expect(identical(result.graph.node('a'), original), isTrue);
    });

    test('an empty registry leaves a whole graph alone', () {
      final graph = NodeGraph(
        nodes: <GraphNode>[
          node('a'),
          node('b', type: 'fanout'),
        ],
      );

      final result = NodePrototypeRegistry.empty.resolveAll(graph);

      expect(result.isUnchanged, isTrue);
      expect(identical(result.graph, graph), isTrue);
    });

    test('resolution keeps a node\'s metadata', () {
      final registry = NodePrototypeRegistry(<NodePrototype>[
        formatPrototype(),
      ]);
      final notes = <String, Object?>{
        'note': 'hello',
        'nested': <String, Object?>{'k': 1},
      };
      final graph = NodeGraph(
        nodes: <GraphNode>[node('a').copyWith(metadata: notes)],
      );

      final resolved = registry.resolve(graph, seeds: <String>['a']).graph;

      expect(portIds(resolved.node('a')!), <String>['out']);
      expect(
        resolved.node('a')!.metadata,
        notes,
        reason: 'no family declares it, so seedAndPrune never sees it',
      );
    });

    test('a static family materialises on a node added with no ports', () {
      final registry = NodePrototypeRegistry(<NodePrototype>[
        formatPrototype(),
      ]);
      final graph = NodeGraph(nodes: <GraphNode>[node('a')]);

      final resolved = registry.resolve(graph, seeds: <String>['a']).graph;

      expect(portIds(resolved.node('a')!), <String>['out']);
      expect(
        resolved.node('a')!.portById('out')!.family,
        'flow',
        reason: 'the engine stamps the family, so builders need not',
      );
    });

    test('a generated port adopts a hand-authored one with the same id', () {
      final registry = NodePrototypeRegistry(<NodePrototype>[
        formatPrototype(),
      ]);
      final graph = NodeGraph(
        nodes: <GraphNode>[
          // Authored before the prototype existed: 'out' is exactly what the
          // static family declares.
          node('a', ports: const <NodePort>[NodePort.output(id: 'out')]),
        ],
      );

      final resolved = registry.resolve(graph, seeds: <String>['a']).graph;

      expect(
        portIds(resolved.node('a')!),
        <String>['out'],
        reason: 'doubling the id up would break every portById lookup',
      );
      expect(
        resolved.node('a')!.portById('out')!.family,
        'flow',
        reason: 'the prototype takes it over, which is the migration path',
      );
    });

    test(
      'ports the prototype does not own survive, after the generated ones',
      () {
        final registry = NodePrototypeRegistry(<NodePrototype>[
          formatPrototype(),
        ]);
        final graph = NodeGraph(
          nodes: <GraphNode>[
            node(
              'a',
              data: <String, Object?>{'format': 'Hi {0}'},
              // Hand-authored, no family: the host's own port.
              ports: const <NodePort>[NodePort.input(id: 'mine')],
            ),
          ],
        );

        final resolved = registry.resolve(graph, seeds: <String>['a']).graph;

        expect(portIds(resolved.node('a')!), <String>['out', 'arg_0', 'mine']);
        expect(resolved.node('a')!.portById('mine')!.family, isNull);
      },
    );
  });

  group('format string ports', () {
    test('placeholders become inputs', () {
      final registry = NodePrototypeRegistry(<NodePrototype>[
        formatPrototype(),
      ]);
      final graph = NodeGraph(
        nodes: <GraphNode>[
          node('a', data: <String, Object?>{'format': 'Hello, {0}. {1}!'}),
        ],
      );

      final resolved = registry.resolve(graph, seeds: <String>['a']).graph;

      expect(portIds(resolved.node('a')!), <String>['out', 'arg_0', 'arg_1']);
      expect(resolved.node('a')!.portById('arg_1')!.label, '{1}');
    });

    test('resolving twice changes nothing', () {
      final registry = NodePrototypeRegistry(<NodePrototype>[
        formatPrototype(),
      ]);
      final graph = NodeGraph(
        nodes: <GraphNode>[
          node('a', data: <String, Object?>{'format': '{0} {1}'}),
        ],
      );

      final once = registry.resolve(graph, seeds: <String>['a']).graph;
      final twice = registry.resolve(once, seeds: <String>['a']);

      expect(twice.isUnchanged, isTrue, reason: 'the node is already settled');
    });

    test('losing a placeholder drops the port and its connection at once', () {
      final registry = NodePrototypeRegistry(<NodePrototype>[
        formatPrototype(),
        fanOutPrototype(),
      ]);
      var graph = NodeGraph(
        nodes: <GraphNode>[
          node('a', data: <String, Object?>{'format': '{0} {1}'}),
          node('b', type: 'fanout'),
        ],
      );
      graph = registry.resolveAll(graph).graph;
      graph = graph.putConnection(
        const NodeConnection(
          id: 'c1',
          from: PortRef('b', 'out_0'),
          to: PortRef('a', 'arg_1'),
        ),
      );

      final result = registry.resolve(
        graph.putNode(
          graph.node('a')!.withData(<String, Object?>{'format': '{0}'}),
        ),
        seeds: <String>['a'],
      );

      expect(portIds(result.graph.node('a')!), <String>['out', 'arg_0']);
      expect(result.pruned, contains('c1'));
      expect(
        result.graph.connections,
        isEmpty,
        reason: 'the port and the wire go in the same graph',
      );
    });
  });

  group('variadic outputs', () {
    test('a fresh node starts with exactly one free exit', () {
      final registry = NodePrototypeRegistry(<NodePrototype>[
        fanOutPrototype(),
      ]);
      final graph = NodeGraph(nodes: <GraphNode>[node('r', type: 'fanout')]);

      final resolved = registry.resolve(graph, seeds: <String>['r']).graph;

      expect(portIds(resolved.node('r')!), <String>['in', 'out_0']);
    });

    test('wiring the last exit spawns another, repeatedly', () {
      final registry = NodePrototypeRegistry(<NodePrototype>[
        fanOutPrototype(),
        formatPrototype(),
      ]);
      var graph = NodeGraph(
        nodes: <GraphNode>[
          node('r', type: 'fanout'),
          node('a', data: <String, Object?>{'format': '{0} {1}'}),
        ],
      );
      graph = registry.resolveAll(graph).graph;

      graph = registry
          .resolve(
            graph.putConnection(
              const NodeConnection(
                id: 'c0',
                from: PortRef('r', 'out_0'),
                to: PortRef('a', 'arg_0'),
              ),
            ),
            seeds: <String>['r'],
          )
          .graph;
      expect(portIds(graph.node('r')!), <String>['in', 'out_0', 'out_1']);

      graph = registry
          .resolve(
            graph.putConnection(
              const NodeConnection(
                id: 'c1',
                from: PortRef('r', 'out_1'),
                to: PortRef('a', 'arg_1'),
              ),
            ),
            seeds: <String>['r'],
          )
          .graph;
      expect(portIds(graph.node('r')!), <String>[
        'in',
        'out_0',
        'out_1',
        'out_2',
      ]);

      expect(
        registry.resolve(graph, seeds: <String>['r']).isUnchanged,
        isTrue,
        reason:
            'the rule is a pure function of link state, so it is idempotent',
      );
    });

    test(
      'disconnecting a middle exit removes it and keeps the tail id stable',
      () {
        final registry = NodePrototypeRegistry(<NodePrototype>[
          fanOutPrototype(),
          formatPrototype(),
        ]);
        var graph = NodeGraph(
          nodes: <GraphNode>[
            node('r', type: 'fanout'),
            node('a', data: <String, Object?>{'format': '{0} {1}'}),
          ],
        );
        graph = registry.resolveAll(graph).graph;
        graph = graph
            .putConnection(
              const NodeConnection(
                id: 'c0',
                from: PortRef('r', 'out_0'),
                to: PortRef('a', 'arg_0'),
              ),
            )
            .putConnection(
              const NodeConnection(
                id: 'c1',
                from: PortRef('r', 'out_1'),
                to: PortRef('a', 'arg_1'),
              ),
            );
        graph = registry.resolve(graph, seeds: <String>['r']).graph;
        expect(portIds(graph.node('r')!), <String>[
          'in',
          'out_0',
          'out_1',
          'out_2',
        ]);

        graph = registry
            .resolve(
              graph.removeConnections(<String>['c0']),
              seeds: <String>['r'],
            )
            .graph;

        expect(
          portIds(graph.node('r')!),
          <String>['in', 'out_1', 'out_2'],
          reason:
              'numbering one past the highest in use keeps the tail from '
              'colliding with a port that is still wired',
        );
      },
    );
  });

  group('cascade', () {
    test('a pruned wire re-resolves the node at the other end', () {
      final registry = NodePrototypeRegistry(<NodePrototype>[
        formatPrototype(),
        fanOutPrototype(),
      ]);
      var graph = NodeGraph(
        nodes: <GraphNode>[
          node('a', data: <String, Object?>{'format': '{0}'}),
          node('r', type: 'fanout'),
        ],
      );
      graph = registry.resolveAll(graph).graph;
      graph = registry
          .resolve(
            graph.putConnection(
              const NodeConnection(
                id: 'c0',
                from: PortRef('r', 'out_0'),
                to: PortRef('a', 'arg_0'),
              ),
            ),
            seeds: <String>['r'],
          )
          .graph;
      expect(portIds(graph.node('r')!), <String>['in', 'out_0', 'out_1']);

      // Only 'a' is seeded. Losing arg_0 prunes the wire, which changes r's
      // link state — a node-local design would leave r with a stale port.
      final result = registry.resolve(
        graph.putNode(
          graph.node('a')!.withData(<String, Object?>{'format': 'no slots'}),
        ),
        seeds: <String>['a'],
      );

      expect(portIds(result.graph.node('a')!), <String>['out']);
      expect(
        portIds(result.graph.node('r')!),
        <String>['in', 'out_0'],
        reason: 'r shrank back to one free exit because its wire went away',
      );
      expect(result.changed, containsAll(<String>['a', 'r']));
    });
  });

  group('port removal handling', () {
    test('a handler can rewire instead of dropping', () {
      final registry = NodePrototypeRegistry(<NodePrototype>[
        formatPrototype(
          onPortsRemoved: (removal) {
            var graph = removal.graph;
            for (final connection in removal.affected) {
              graph = graph.putConnection(
                connection.copyWith(to: PortRef(removal.node.id, 'arg_0')),
              );
            }
            return graph;
          },
        ),
        fanOutPrototype(),
      ]);
      var graph = NodeGraph(
        nodes: <GraphNode>[
          node('a', data: <String, Object?>{'format': '{0} {1}'}),
          node('r', type: 'fanout'),
        ],
      );
      graph = registry.resolveAll(graph).graph;
      graph = graph.putConnection(
        const NodeConnection(
          id: 'c1',
          from: PortRef('r', 'out_0'),
          to: PortRef('a', 'arg_1'),
        ),
      );

      final result = registry.resolve(
        graph.putNode(
          graph.node('a')!.withData(<String, Object?>{'format': '{0}'}),
        ),
        seeds: <String>['a'],
      );

      expect(result.graph.connections.containsKey('c1'), isTrue);
      expect(result.graph.connection('c1')!.to, const PortRef('a', 'arg_0'));
    });

    test('a wire onto a port no prototype creates is swept away', () {
      final registry = NodePrototypeRegistry(<NodePrototype>[
        formatPrototype(),
        fanOutPrototype(),
      ]);
      // As a loaded document arrives: the fan-out carries no ports, and a wire
      // already references an exit that resolution is not going to produce.
      final graph = NodeGraph(
        nodes: <GraphNode>[
          node('r', type: 'fanout'),
          node('a', data: <String, Object?>{'format': '{0}'}),
        ],
        connections: <NodeConnection>[
          const NodeConnection(
            id: 'ghost',
            from: PortRef('r', 'out_9'),
            to: PortRef('a', 'arg_0'),
          ),
        ],
      );

      final result = registry.resolveAll(graph);

      expect(result.graph.node('r')!.portById('out_9'), isNull);
      expect(
        result.graph.connections.containsKey('ghost'),
        isFalse,
        reason:
            'a wire onto a port that is not there draws nothing but survives '
            'undo and gets written out again — worse than an honest deletion',
      );
      expect(result.pruned, contains('ghost'));
    });

    test('a handler that keeps everything still leaves nothing dangling', () {
      final registry = NodePrototypeRegistry(<NodePrototype>[
        formatPrototype(onPortsRemoved: NodePortRemoval.keep),
        fanOutPrototype(),
      ]);
      var graph = NodeGraph(
        nodes: <GraphNode>[
          node('a', data: <String, Object?>{'format': '{0} {1}'}),
          node('r', type: 'fanout'),
        ],
      );
      graph = registry.resolveAll(graph).graph;
      graph = graph.putConnection(
        const NodeConnection(
          id: 'c1',
          from: PortRef('r', 'out_0'),
          to: PortRef('a', 'arg_1'),
        ),
      );

      final result = registry.resolve(
        graph.putNode(
          graph.node('a')!.withData(<String, Object?>{'format': '{0}'}),
        ),
        seeds: <String>['a'],
      );

      expect(
        result.graph.connections,
        isEmpty,
        reason:
            'a connection pointing at a missing port draws nothing but stays '
            'in the model, so the sweep is unconditional',
      );
    });
  });

  group('field inheritance', () {
    test('seedAndPrune seeds, retains, and only drops what it manages', () {
      final registry = NodePrototypeRegistry(<NodePrototype>[
        NodePrototype(
          type: 'args',
          fields: <FieldFamily>[
            DynamicFieldFamily(
              id: 'args',
              keyPrefix: 'arg.',
              build: (context) => <NodeField>[
                for (final slot in slotsOf(
                  context.fieldOr<String>('format', ''),
                ))
                  NodeField(key: 'arg.$slot', defaultValue: ''),
              ],
            ),
          ],
        ),
      ]);
      var graph = NodeGraph(
        nodes: <GraphNode>[
          node(
            'a',
            type: 'args',
            data: <String, Object?>{
              'format': '{0} {1}',
              'title': 'kept',
              'arg.0': 'zero',
              'arg.1': 'one',
            },
          ),
        ],
      );

      graph = registry
          .resolve(
            graph.putNode(
              graph.node('a')!.withData(<String, Object?>{'format': '{0} {2}'}),
            ),
            seeds: <String>['a'],
          )
          .graph;

      final data = graph.node('a')!.data;
      expect(
        data['arg.0'],
        'zero',
        reason: 'a surviving field keeps its value',
      );
      expect(
        data['arg.2'],
        '',
        reason: 'a new field is seeded with its default',
      );
      expect(data.containsKey('arg.1'), isFalse, reason: 'managed and gone');
      expect(
        data['title'],
        'kept',
        reason:
            'keys outside a managed prefix are none of the prototype\'s business',
      );
    });

    test('a custom merge can renumber values instead of orphaning them', () {
      final registry = NodePrototypeRegistry(<NodePrototype>[
        NodePrototype(
          type: 'args',
          // Inserting a placeholder at the front should carry the old values
          // up rather than seed a default and orphan them — a policy no
          // general rule could guess at, so it belongs to the host.
          //
          // Note the marker. A merge is re-run until the node settles, so one
          // that shifts unconditionally would shift again on every pass and
          // never converge. Clearing the mark is what makes it idempotent.
          inheritFields: (context) {
            if (context.previous['shiftArgs'] != true) {
              return NodeFields.seedAndPrune(context);
            }
            final next = <String, Object?>{
              for (final entry in context.previous.entries)
                if (!entry.key.startsWith('arg.')) entry.key: entry.value,
              'shiftArgs': false,
            };
            for (final entry in context.previous.entries) {
              if (!entry.key.startsWith('arg.')) continue;
              final index = int.parse(entry.key.substring(4));
              next['arg.${index + 1}'] = entry.value;
            }
            for (final field in context.declared) {
              if (!next.containsKey(field.key)) {
                next[field.key] = field.defaultValue;
              }
            }
            return next;
          },
          fields: <FieldFamily>[
            DynamicFieldFamily(
              id: 'args',
              keyPrefix: 'arg.',
              build: (context) => <NodeField>[
                for (final slot in slotsOf(
                  context.fieldOr<String>('format', ''),
                ))
                  NodeField(key: 'arg.$slot', defaultValue: ''),
              ],
            ),
          ],
        ),
      ]);
      final graph = NodeGraph(
        nodes: <GraphNode>[
          node(
            'a',
            type: 'args',
            data: <String, Object?>{
              'format': '{0} {1}',
              'shiftArgs': true,
              'arg.0': 'was zero',
            },
          ),
        ],
      );

      final result = registry.resolve(graph, seeds: <String>['a']);

      expect(result.diverged, isEmpty, reason: 'clearing the mark settles it');
      expect(result.graph.node('a')!.data['arg.1'], 'was zero');
      expect(result.graph.node('a')!.data['arg.0'], '');
    });
  });

  group('height', () {
    test('a declared height can track the port count', () {
      final registry = NodePrototypeRegistry(<NodePrototype>[
        formatPrototype(
          resolveHeight: (context) =>
              40 + 20.0 * context.portsOf('args').length,
        ),
      ]);
      var graph = NodeGraph(
        nodes: <GraphNode>[
          node('a', data: <String, Object?>{'format': '{0}'}),
        ],
      );

      graph = registry.resolve(graph, seeds: <String>['a']).graph;
      expect(graph.node('a')!.height, 60);

      graph = registry
          .resolve(
            graph.putNode(
              graph.node('a')!.withData(<String, Object?>{'format': '{0} {1}'}),
            ),
            seeds: <String>['a'],
          )
          .graph;
      expect(graph.node('a')!.height, 80);
    });

    test(
      'a prototype with no height resolver leaves the node measuring itself',
      () {
        final registry = NodePrototypeRegistry(<NodePrototype>[
          formatPrototype(),
        ]);
        final graph = NodeGraph(
          nodes: <GraphNode>[
            node('a', data: <String, Object?>{'format': '{0}'}),
          ],
        );

        final resolved = registry.resolve(graph, seeds: <String>['a']).graph;

        expect(resolved.node('a')!.height, isNull);
        expect(resolved.node('a')!.hasIntrinsicHeight, isTrue);
      },
    );

    test(
      'withHeight(null) sends a node back to auto, which copyWith cannot',
      () {
        final fixed = node('a', height: 120);
        expect(fixed.copyWith(height: null).height, 120);
        expect(fixed.withHeight(null).height, isNull);
      },
    );
  });

  group('convergence', () {
    test('a builder that never repeats is reported, not hung', () {
      final diverged = <String>[];
      final registry = NodePrototypeRegistry(<NodePrototype>[
        NodePrototype(
          type: 'unstable',
          ports: <PortFamily>[
            DynamicPortFamily(
              id: 'bad',
              // A fresh object every pass: ports compare their payload with
              // `==`, so this reads as a change forever.
              build: (context) => <NodePort>[
                NodePort.output(id: 'out', data: Object()),
              ],
            ),
          ],
        ),
      ], onDiverged: (node, passes) => diverged.add(node.id));
      final graph = NodeGraph(nodes: <GraphNode>[node('a', type: 'unstable')]);

      final result = registry.resolve(graph, seeds: <String>['a']);

      expect(diverged, <String>['a']);
      expect(result.diverged, contains('a'));
      expect(
        result.graph.node('a')!.ports,
        hasLength(1),
        reason: 'giving up still leaves a usable node',
      );
    });
  });

  test('instantiate builds a node without a controller', () {
    final registry = NodePrototypeRegistry(<NodePrototype>[formatPrototype()]);

    final built = registry.instantiate(
      'format',
      id: 'n1',
      position: const Offset(10, 20),
      data: <String, Object?>{'format': '{0} {1}'},
    );

    expect(portIds(built), <String>['out', 'arg_0', 'arg_1']);
    expect(built.position, const Offset(10, 20));
    expect(
      registry.instantiate('unknown', id: 'n2', position: Offset.zero).ports,
      isEmpty,
    );
  });

  test('fieldsOf reports what a node declares right now', () {
    final registry = NodePrototypeRegistry(<NodePrototype>[formatPrototype()]);
    final graph = NodeGraph(
      nodes: <GraphNode>[
        node('a', data: <String, Object?>{'format': '{0}'}),
      ],
    );

    final fields = registry.fieldsOf(graph, graph.node('a')!);

    expect(<String>[for (final field in fields) field.key], <String>['format']);
  });
}
