import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:fl_nodes_v2/fl_nodes_v2.dart';

void main() {
  final placeholder = RegExp(r'\{(\d+)\}');

  List<int> slotsOf(String text) => <int>{
    for (final match in placeholder.allMatches(text))
      int.parse(match.group(1)!),
  }.toList()..sort();

  /// One input per placeholder, and one literal field per input — a family
  /// whose output is a pure function of `data`.
  NodePrototype formatPrototype() => NodePrototype(
    type: 'format',
    fields: <FieldFamily>[
      const StaticFieldFamily(
        id: 'text',
        fields: <NodeField>[NodeField(key: 'format', defaultValue: '')],
      ),
      DynamicFieldFamily(
        id: 'args',
        keyPrefix: 'arg.',
        build: (context) => <NodeField>[
          for (final slot in slotsOf(context.fieldOr<String>('format', '')))
            NodeField(key: 'arg.$slot', defaultValue: ''),
        ],
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
            NodePort.input(id: 'arg_$slot'),
        ],
      ),
    ],
  );

  /// Every wired exit plus one free — a family whose output depends on link
  /// state, and so cannot be re-derived from `data` alone.
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

  NodePrototypeRegistry registry() => NodePrototypeRegistry(
    <NodePrototype>[formatPrototype(), fanOutPrototype()],
    links: <LinkPrototype>[
      const LinkPrototype(type: 'branch', label: EditableLinkLabel()),
      LinkPrototype(
        type: 'exit',
        label: DerivedLinkLabel(build: (context) => context.fromPort?.label),
      ),
    ],
  );

  GraphNode seed(
    String id, {
    String type = 'format',
    Map<String, Object?> data = const <String, Object?>{},
  }) => GraphNode(
    id: id,
    type: type,
    position: Offset.zero,
    width: 120,
    data: data,
  );

  List<String> portIds(GraphNode node) => <String>[
    for (final port in node.ports) port.id,
  ];

  Map<String, Object?> roundTripJson(
    NodeGraph graph, {
    NodeGraphCodec codec = const NodeGraphCodec(),
  }) => codec.encode(GraphDocument(graph: graph));

  NodeGraph roundTrip(
    NodeGraph graph, {
    NodeGraphCodec codec = const NodeGraphCodec(),
  }) => codec.decode(codec.encode(GraphDocument(graph: graph))).graph;

  group('prototypes', () {
    test('a wired exit survives a save and load', () {
      final shared = registry();
      final controller = NodeEditorController(prototypes: shared);
      addTearDown(controller.dispose);
      controller
        ..addNode(seed('r', type: 'fanout'))
        ..addNode(seed('a', data: <String, Object?>{'format': '{0} {1}'}));

      final first = controller.connect(
        const PortRef('r', 'out_0'),
        const PortRef('a', 'arg_0'),
      )!;
      final second = controller.connect(
        const PortRef('r', 'out_1'),
        const PortRef('a', 'arg_1'),
      )!;
      // A hole in the middle is what the regeneration cannot guess at.
      controller.removeConnections(<String>[first]);
      expect(portIds(controller.graph.node('r')!), <String>[
        'in',
        'out_1',
        'out_2',
      ]);

      final codec = NodeGraphCodec(prototypes: shared);
      final json = codec.encode(GraphDocument(graph: controller.graph));

      final reloaded = NodeEditorController(prototypes: shared);
      addTearDown(reloaded.dispose);
      reloaded.replaceGraph(codec.decode(json).graph, recordHistory: false);

      expect(
        reloaded.graph.node('r')!.portById('out_1'),
        isNotNull,
        reason:
            'the exits family counts wired ports, and on load there are '
            'none to count unless the document carried them',
      );
      expect(reloaded.graph.connections.containsKey(second), isTrue);
      expect(portIds(reloaded.graph.node('r')!), <String>[
        'in',
        'out_1',
        'out_2',
      ]);
    });

    test(
      'dropping generated ports loses that wire — why the default is all',
      () {
        final shared = registry();
        final controller = NodeEditorController(prototypes: shared);
        addTearDown(controller.dispose);
        controller
          ..addNode(seed('r', type: 'fanout'))
          ..addNode(seed('a', data: <String, Object?>{'format': '{0} {1}'}));
        final first = controller.connect(
          const PortRef('r', 'out_0'),
          const PortRef('a', 'arg_0'),
        )!;
        final second = controller.connect(
          const PortRef('r', 'out_1'),
          const PortRef('a', 'arg_1'),
        )!;
        controller.removeConnections(<String>[first]);

        final codec = NodeGraphCodec(
          prototypes: shared,
          ports: PortStorage.foreign,
        );
        final reloaded = NodeEditorController(prototypes: shared);
        addTearDown(reloaded.dispose);
        reloaded.replaceGraph(
          codec
              .decode(codec.encode(GraphDocument(graph: controller.graph)))
              .graph,
          recordHistory: false,
        );

        expect(reloaded.graph.node('r')!.portById('out_1'), isNull);
        expect(
          reloaded.graph.connections.containsKey(second),
          isFalse,
          reason:
              'the wire is swept rather than left pointing at nothing, but '
              'it is gone either way — this is what PortStorage.foreign costs',
        );
      },
    );

    test('a family driven by data alone is safe to drop', () {
      final shared = registry();
      final controller = NodeEditorController(prototypes: shared);
      addTearDown(controller.dispose);
      controller.addNode(
        seed('a', data: <String, Object?>{'format': '{0} {1}'}),
      );

      final codec = NodeGraphCodec(
        prototypes: shared,
        ports: PortStorage.foreign,
      );
      final json = codec.encode(GraphDocument(graph: controller.graph));
      expect(
        (json['nodes']! as List<Object?>).single,
        isNot(contains('ports')),
        reason: 'nothing but generated ports, so nothing is written',
      );

      final reloaded = NodeEditorController(prototypes: shared);
      addTearDown(reloaded.dispose);
      reloaded.replaceGraph(codec.decode(json).graph, recordHistory: false);

      expect(portIds(reloaded.graph.node('a')!), <String>[
        'out',
        'arg_0',
        'arg_1',
      ]);
    });

    test('a derived caption is left out, and an editable one kept', () {
      final shared = registry();
      final graph = NodeGraph(
        nodes: <GraphNode>[
          GraphNode(
            id: 'a',
            position: Offset.zero,
            ports: const <NodePort>[NodePort.output(id: 'out')],
          ),
          GraphNode(
            id: 'b',
            position: const Offset(300, 0),
            ports: const <NodePort>[NodePort.input(id: 'in')],
          ),
        ],
        connections: <NodeConnection>[
          const NodeConnection(
            id: 'derived',
            from: PortRef('a', 'out'),
            to: PortRef('b', 'in'),
            type: 'exit',
            label: 'recomputed anyway',
          ),
          const NodeConnection(
            id: 'owned',
            from: PortRef('a', 'out'),
            to: PortRef('b', 'in'),
            type: 'branch',
            label: 'High',
          ),
        ],
      );

      final json = NodeGraphCodec(
        prototypes: shared,
      ).encode(GraphDocument(graph: graph));
      final connections = (json['connections']! as List<Object?>)
          .cast<Map<String, Object?>>();

      expect(connections[0].containsKey('label'), isFalse);
      expect(connections[1]['label'], 'High');
      expect(
        NodeGraphCodec(
          prototypes: shared,
          storeDerivedLabels: true,
        ).encode(GraphDocument(graph: graph))['connections'],
        contains(containsPair('label', 'recomputed anyway')),
      );
    });

    test('a node type nobody claims still loads', () {
      final graph = NodeGraph(
        nodes: <GraphNode>[
          GraphNode(
            id: 'x',
            type: 'from-a-plugin-we-do-not-have',
            position: const Offset(4, 8),
            ports: const <NodePort>[NodePort.input(id: 'in')],
          ),
        ],
      );

      final codec = NodeGraphCodec(prototypes: registry());
      final decoded = codec.decode(codec.encode(GraphDocument(graph: graph)));

      expect(
        decoded.graph,
        graph,
        reason:
            'an unknown type is ordinary data, not a reason to refuse the '
            'whole document',
      );
    });

    test('field values keep the family that declared them', () {
      final shared = registry();
      final controller = NodeEditorController(prototypes: shared);
      addTearDown(controller.dispose);
      controller.addNode(
        seed('a', data: <String, Object?>{'format': '{0}', 'title': 'mine'}),
      );

      final json = NodeGraphCodec(
        prototypes: shared,
      ).encode(GraphDocument(graph: controller.graph));
      final groups =
          ((json['nodes']! as List<Object?>).single
                  as Map<String, Object?>)['fields']!
              as List<Object?>;

      expect(groups, hasLength(3));
      expect(
        (groups[0]! as Map<String, Object?>)['family'],
        'text',
        reason: 'the static family that declares "format"',
      );
      expect((groups[1]! as Map<String, Object?>)['keyPrefix'], 'arg.');
      expect(
        (groups[2]! as Map<String, Object?>).containsKey('family'),
        isFalse,
        reason: '"title" belongs to no family, so it lands in the remainder',
      );

      // And it all comes back as one flat map.
      expect(
        NodeGraphCodec(prototypes: shared).decode(json).graph.node('a')!.data,
        controller.graph.node('a')!.data,
      );
    });
  });

  group('round trip', () {
    test('every optional field survives', () {
      final graph = NodeGraph(
        nodes: <GraphNode>[
          GraphNode(
            id: 'a',
            type: 'widget',
            position: const Offset(12.5, -4),
            width: 180,
            height: 90,
            draggable: false,
            selectable: false,
            data: <String, Object?>{
              'title': 'Hello',
              'count': 3,
              'ratio': 0.25,
              'flag': true,
              'nothing': null,
              'branches': <String>['High', 'Medium'],
              'nested': <String, Object?>{
                'a': 1,
                'b': <int>[2, 3],
              },
            },
            metadata: <String, Object?>{
              'author': 'me',
              'tags': <String>['draft', 'act one'],
              'notes': <String, Object?>{
                'reviewed': false,
                'scores': <num>[1, 2.5],
              },
            },
            ports: <NodePort>[
              const NodePort.input(id: 'in'),
              const NodePort.output(
                id: 'out',
                label: 'Out',
                side: PortSide.bottom,
                anchor: Offset(0.5, 1),
                color: Color(0xFF6E97F0),
                maxConnections: 2,
                linkType: 'branch',
                data: 'payload',
              ),
            ],
          ),
          GraphNode(id: 'b', position: const Offset(400, 0)),
        ],
        connections: <NodeConnection>[
          const NodeConnection(
            id: 'c1',
            from: PortRef('a', 'out'),
            to: PortRef('b', 'in'),
            type: 'branch',
            label: 'yes',
            color: Color(0xFFE0716A),
            data: 'edge payload',
          ),
        ],
      );

      expect(roundTrip(graph), graph);
    });

    test('a port round-trips its kind and type', () {
      final graph = NodeGraph(
        nodes: <GraphNode>[
          GraphNode(
            id: 'a',
            position: Offset.zero,
            ports: const <NodePort>[
              NodePort.output(id: 'go', kind: PortKind.control),
              NodePort.input(id: 'value', dataType: 'string'),
              NodePort.input(id: 'anything'),
            ],
          ),
        ],
      );

      expect(roundTrip(graph), graph);
    });

    test('a node with no metadata writes no key', () {
      final json = roundTripJson(NodeGraph(nodes: <GraphNode>[seed('a')]));
      final node =
          (json['nodes']! as List<Object?>).single as Map<String, Object?>;

      expect(
        node.containsKey('metadata'),
        isFalse,
        reason:
            'an empty map is the default, and a default that is written is '
            'one that cannot be changed later without reinterpreting every '
            'document already on disk — the rule `meta` and `groups` keep',
      );
    });

    test('a document written before metadata existed reads as empty', () {
      final json = roundTripJson(
        NodeGraph(
          nodes: <GraphNode>[
            seed('a').copyWith(metadata: <String, Object?>{'k': 1}),
          ],
        ),
      );
      final node =
          (json['nodes']! as List<Object?>).single as Map<String, Object?>;
      expect(node.remove('metadata'), isNotNull);

      final decoded = const NodeGraphCodec().decode(json).graph;

      expect(decoded.node('a')!.metadata, isEmpty);
    });

    test(r'a metadata key called $type round-trips', () {
      final graph = NodeGraph(
        nodes: <GraphNode>[
          seed('a').copyWith(
            metadata: <String, Object?>{
              r'$type': 'the author picked this word',
              'inner': <String, Object?>{r'$type': 'and this one'},
            },
          ),
        ],
      );

      expect(
        roundTrip(graph).node('a')!.metadata,
        graph.node('a')!.metadata,
        reason:
            'the encoder wraps a map holding that key as a tagged map, and '
            'the metadata reader has to take the wrapper off again at the '
            'top level as well as inside a value',
      );
    });

    test('metadata that is not an object is refused', () {
      final json = roundTripJson(NodeGraph(nodes: <GraphNode>[seed('a')]));
      final node =
          (json['nodes']! as List<Object?>).single as Map<String, Object?>;
      node['metadata'] = 'a string';

      expect(
        () => const NodeGraphCodec().decode(json),
        throwsA(
          isA<GraphDocumentFormatException>().having(
            (e) => e.message,
            'message',
            contains('metadata'),
          ),
        ),
      );
    });

    test('a document written before kinds existed reads as data', () {
      final json = roundTripJson(
        NodeGraph(
          nodes: <GraphNode>[
            GraphNode(
              id: 'a',
              position: Offset.zero,
              ports: const <NodePort>[NodePort.output(id: 'out')],
            ),
          ],
        ),
      );
      // As 0.4 wrote it: no `kind` key at all.
      final ports =
          ((json['nodes']! as List<Object?>).single
                  as Map<String, Object?>)['ports']!
              as List<Object?>;
      final port =
          ((ports.single as Map<String, Object?>)['ports']! as List<Object?>)
                  .single
              as Map<String, Object?>;
      expect(port.remove('kind'), 'data');

      final decoded = const NodeGraphCodec().decode(json).graph;

      expect(decoded.node('a')!.ports.single.kind, PortKind.data);
    });

    test('an unset side stays unset', () {
      final graph = NodeGraph(
        nodes: <GraphNode>[
          GraphNode(
            id: 'a',
            position: Offset.zero,
            ports: const <NodePort>[
              NodePort.input(id: 'implicit'),
              NodePort.input(id: 'explicit', side: PortSide.left),
            ],
          ),
        ],
      );

      final decoded = roundTrip(graph).node('a')!;

      expect(
        decoded.portById('implicit')!.declaredSide,
        isNull,
        reason:
            'storing the resolved side would make every port explicit, and '
            'equality compares what was authored',
      );
      expect(decoded.portById('explicit')!.declaredSide, PortSide.left);
      expect(decoded, graph.node('a'));
    });

    test('a declared height and an auto one stay apart', () {
      final graph = NodeGraph(
        nodes: <GraphNode>[
          GraphNode(id: 'fixed', position: Offset.zero, height: 120),
          GraphNode(id: 'auto', position: Offset.zero),
        ],
      );

      final decoded = roundTrip(graph);

      expect(decoded.node('fixed')!.height, 120);
      expect(decoded.node('auto')!.height, isNull);
      expect(decoded.node('auto')!.hasIntrinsicHeight, isTrue);
    });

    test('colours packed when exact, spelled out when not', () {
      const packable = Color(0xFF6E97F0);
      final exact = Color.from(alpha: 0.5, red: 0.25, green: 0.5, blue: 1);
      final graph = NodeGraph(
        nodes: <GraphNode>[
          GraphNode(
            id: 'a',
            position: Offset.zero,
            ports: <NodePort>[
              const NodePort.input(id: 'packed', color: packable),
              NodePort.input(id: 'exact', color: exact),
            ],
          ),
        ],
      );

      final json = roundTripJson(graph);
      final group =
          (((json['nodes']! as List<Object?>).single
                          as Map<String, Object?>)['ports']!
                      as List<Object?>)
                  .single
              as Map<String, Object?>;
      final portsJson = (group['ports']! as List<Object?>)
          .cast<Map<String, Object?>>();

      expect(portsJson[0]['color'], packable.toARGB32());
      expect(portsJson[1]['color'], isA<Map<String, Object?>>());
      expect(roundTrip(graph), graph);
    });

    test('encoding a decoded document is a fixed point', () {
      final graph = NodeGraph(
        nodes: <GraphNode>[
          GraphNode(
            id: 'a',
            position: const Offset(3, 4),
            data: <String, Object?>{
              'list': <String>['x'],
            },
            ports: const <NodePort>[NodePort.output(id: 'out')],
          ),
        ],
      );

      const codec = NodeGraphCodec();
      final once = codec.encode(GraphDocument(graph: graph));
      final twice = codec.encode(codec.decode(once));

      expect(twice, once);
    });

    test('the envelope carries the camera and the host metadata', () {
      const codec = NodeGraphCodec();
      final document = GraphDocument(
        graph: NodeGraph.empty,
        viewport: ViewportTransform(offset: Offset(-120, 40), scale: 0.85),
        meta: <String, Object?>{'title': 'Lead routing'},
        appVersion: 'demo/1.0.0',
      );

      final decoded = codec.decode(codec.encode(document));

      expect(decoded.viewport, document.viewport);
      expect(decoded.meta, document.meta);
      expect(decoded.appVersion, 'demo/1.0.0');
      expect(decoded.packageVersion, isNotNull);
    });

    test('an empty graph and a self-connection', () {
      expect(roundTrip(NodeGraph.empty), NodeGraph.empty);

      final looped = NodeGraph(
        nodes: <GraphNode>[
          GraphNode(
            id: 'a',
            position: Offset.zero,
            ports: const <NodePort>[
              NodePort.input(id: 'in'),
              NodePort.output(id: 'out'),
            ],
          ),
        ],
        connections: <NodeConnection>[
          const NodeConnection(
            id: 'self',
            from: PortRef('a', 'out'),
            to: PortRef('a', 'in'),
          ),
        ],
      );
      expect(roundTrip(looped), looped);
    });

    test('a decoded payload compares by value, not by identity', () {
      final graph = NodeGraph(
        nodes: <GraphNode>[
          GraphNode(
            id: 'a',
            position: Offset.zero,
            data: <String, Object?>{
              'branches': <String>['High', 'Low'],
            },
          ),
        ],
      );

      final value = roundTrip(graph).node('a')!.data['branches'];

      expect(value, isA<List<Object?>>());
      expect((value! as List<Object?>).cast<String>(), <String>['High', 'Low']);
      expect(
        payloadEquals(value, <String>['High', 'Low']),
        isTrue,
        reason:
            'Dart compares containers by identity, so the model compares '
            'its open payloads with payloadEquals instead',
      );
    });
  });

  group('port families', () {
    test('are run-length grouped, so interleaving survives', () {
      final graph = NodeGraph(
        nodes: <GraphNode>[
          GraphNode(
            id: 'a',
            position: Offset.zero,
            ports: const <NodePort>[
              NodePort.input(id: 'p0', family: 'f1'),
              NodePort.input(id: 'p1'),
              NodePort.input(id: 'p2', family: 'f1'),
            ],
          ),
        ],
      );

      final json = roundTripJson(graph);
      final groups =
          (((json['nodes']! as List<Object?>).single
                      as Map<String, Object?>)['ports']!
                  as List<Object?>)
              .cast<Map<String, Object?>>();

      expect(groups, hasLength(3), reason: 'three runs, not two families');
      expect(groups[1].containsKey('family'), isFalse);

      final decoded = roundTrip(graph).node('a')!;
      expect(portIds(decoded), <String>['p0', 'p1', 'p2']);
      expect(decoded.ports[1].family, isNull);
      expect(decoded, graph.node('a'));
    });

    test('order survives where it is observable — in the geometry', () {
      final graph = NodeGraph(
        nodes: <GraphNode>[
          GraphNode(
            id: 'a',
            position: Offset.zero,
            height: 100,
            ports: const <NodePort>[
              NodePort.input(id: 'first', family: 'f1'),
              NodePort.input(id: 'second'),
            ],
          ),
        ],
      );
      final before = graph.node('a')!;
      final after = roundTrip(graph).node('a')!;

      for (final id in <String>['first', 'second']) {
        expect(
          NodeGeometry.anchorOf(after, after.portById(id)!),
          NodeGeometry.anchorOf(before, before.portById(id)!),
          reason:
              'anchorless ports spread by declaration index, so a '
              'reordered list moves handles on screen',
        );
      }
    });

    test('a group restamps its ports', () {
      const codec = NodeGraphCodec();
      final decoded = codec.decode(<String, Object?>{
        'version': 1,
        'nodes': <Object?>[
          <String, Object?>{
            'id': 'a',
            'position': <Object?>[0, 0],
            'ports': <Object?>[
              <String, Object?>{
                'family': 'exits',
                'ports': <Object?>[
                  <String, Object?>{'id': 'out_0', 'direction': 'output'},
                ],
              },
            ],
          },
        ],
      });

      expect(decoded.graph.node('a')!.portById('out_0')!.family, 'exits');
    });
  });

  group('versions', () {
    test('a newer document is refused, not misread', () {
      const codec = NodeGraphCodec();

      expect(
        () => codec.decode(<String, Object?>{'version': 2}),
        throwsA(
          isA<GraphDocumentVersionException>()
              .having((e) => e.found, 'found', 2)
              .having((e) => e.supported, 'supported', 1),
        ),
      );
    });

    test('a missing or nonsense version is a format error', () {
      const codec = NodeGraphCodec();

      for (final bad in <Map<String, Object?>>[
        <String, Object?>{},
        <String, Object?>{'version': 'one'},
        <String, Object?>{'version': 0},
      ]) {
        expect(
          () => codec.decode(bad),
          throwsA(
            isA<GraphDocumentFormatException>().having(
              (e) => e.location,
              'location',
              'version',
            ),
          ),
        );
      }
    });

    test('a chain lifts an old document forward', () {
      var ran = false;
      final codec = NodeGraphCodec(
        migrations: <int, GraphDocumentMigration>{
          0: (document) {
            ran = true;
            return <String, Object?>{...document, 'version': 1};
          },
        },
      );

      // Reaching the migration means passing the "1 or greater" gate, so this
      // exercises `upgrade` through a chain supplied by the host.
      expect(
        GraphDocumentMigrations.upgrade(
          <String, Object?>{'version': 0},
          from: 0,
          target: 1,
          chain: codec.migrations,
        ),
        containsPair('version', 1),
      );
      expect(ran, isTrue);
    });

    test('a gap in the chain names the missing step', () {
      expect(
        () => GraphDocumentMigrations.upgrade(
          <String, Object?>{'version': 1},
          from: 1,
          target: 3,
          chain: <int, GraphDocumentMigration>{1: (document) => document},
        ),
        throwsA(
          isA<GraphDocumentVersionException>().having(
            (e) => e.message,
            'message',
            contains('version 2 to 3'),
          ),
        ),
      );
    });
  });

  group('schema versions', () {
    /// A host chain that records the order its steps ran in.
    (Map<int, GraphDocumentMigration>, List<int>) recordingChain(
      Iterable<int> from,
    ) {
      final ran = <int>[];
      return (
        <int, GraphDocumentMigration>{
          for (final step in from)
            step: (document) {
              ran.add(step);
              return <String, Object?>{...document, 'schema': step + 1};
            },
        },
        ran,
      );
    }

    test('the stamp is written only by a codec that has an axis', () {
      final graph = NodeGraph();

      expect(
        const NodeGraphCodec(
          schemaVersion: 3,
        ).encode(GraphDocument(graph: graph)),
        containsPair('schema', 3),
      );
      expect(
        const NodeGraphCodec().encode(GraphDocument(graph: graph)),
        isNot(contains('schema')),
      );
    });

    test('a document with no schema key reads as the floor and is lifted', () {
      final (chain, ran) = recordingChain(<int>[1, 2]);
      final codec = NodeGraphCodec(schemaVersion: 3, schemaMigrations: chain);

      final document = codec.decode(<String, Object?>{'version': 1});

      expect(ran, <int>[1, 2], reason: 'the chain runs one step at a time');
      expect(
        document.schemaVersion,
        3,
        reason: 'a decoded document reports the version it was lifted to',
      );
    });

    test('a newer schema is refused, and says so as a schema', () {
      const codec = NodeGraphCodec(schemaVersion: 3);

      expect(
        () => codec.decode(<String, Object?>{'version': 1, 'schema': 4}),
        throwsA(
          isA<GraphDocumentVersionException>()
              .having((e) => e.found, 'found', 4)
              .having((e) => e.supported, 'supported', 3)
              .having((e) => e.location, 'location', 'schema')
              // Not 'format version 4' — that would send somebody looking on
              // the package's side of the boundary for a change of the host's.
              .having((e) => e.message, 'message', contains('schema version')),
        ),
      );
    });

    test('a nonsense schema is a format error, located', () {
      const codec = NodeGraphCodec(schemaVersion: 3);

      for (final bad in <Object?>['one', 0, -1, 1.5]) {
        expect(
          () => codec.decode(<String, Object?>{'version': 1, 'schema': bad}),
          throwsA(
            isA<GraphDocumentFormatException>().having(
              (e) => e.location,
              'location',
              'schema',
            ),
          ),
          reason: 'schema: $bad',
        );
      }
    });

    test('a gap in the host chain names the missing step', () {
      final codec = NodeGraphCodec(
        schemaVersion: 4,
        schemaMigrations: <int, GraphDocumentMigration>{
          1: (document) => <String, Object?>{...document, 'schema': 2},
        },
      );

      expect(
        () => codec.decode(<String, Object?>{'version': 1, 'schema': 1}),
        throwsA(
          isA<GraphDocumentVersionException>()
              .having((e) => e.message, 'message', contains('version 2 to 3'))
              .having((e) => e.message, 'message', contains('schema version'))
              .having((e) => e.location, 'location', 'schema'),
        ),
      );
    });

    test('the format gate runs before the schema gate', () {
      const codec = NodeGraphCodec(schemaVersion: 1);

      // Both axes are out of range. The format one is the honest answer: this
      // build cannot read the envelope, so what the host meant by its contents
      // is not a question worth reaching.
      expect(
        () => codec.decode(<String, Object?>{'version': 2, 'schema': 99}),
        throwsA(
          isA<GraphDocumentVersionException>().having(
            (e) => e.location,
            'location',
            'version',
          ),
        ),
      );
    });

    test('a codec with no axis carries a schema it does not understand', () {
      const codec = NodeGraphCodec();
      const once = <String, Object?>{
        'version': 1,
        'schema': 9,
        'package': 'fl_nodes_v2/0.4.0',
        'nodes': <Object?>[],
        'connections': <Object?>[],
      };

      final document = codec.decode(once);

      expect(document.schemaVersion, 9, reason: 'read, not acted on');
      expect(
        codec.encode(document),
        once,
        reason: 'a host with no opinion about the schema must not drop it',
      );
    });
  });

  group('payloads', () {
    final codecs = PayloadCodecs(<PayloadCodec<Object>>[
      PayloadCodec<DateTime>(
        tag: 'datetime',
        toJson: (value) => value.toUtc().toIso8601String(),
        fromJson: (json) => DateTime.parse(json! as String),
      ),
    ]);

    NodeGraph withData(Map<String, Object?> data) => NodeGraph(
      nodes: <GraphNode>[GraphNode(id: 'a', position: Offset.zero, data: data)],
    );

    test('a registered type round-trips, tagged in the document', () {
      final when = DateTime.utc(2026, 8, 31, 12);
      final codec = NodeGraphCodec(payloads: codecs);
      final graph = withData(<String, Object?>{'when': when});

      final json = codec.encode(GraphDocument(graph: graph));
      final values =
          ((((json['nodes']! as List<Object?>).single
                              as Map<String, Object?>)['fields']!
                          as List<Object?>)
                      .single
                  as Map<String, Object?>)['values']!
              as Map<String, Object?>;

      expect(values['when'], <String, Object?>{
        r'$type': 'datetime',
        'value': when.toIso8601String(),
      });
      expect(codec.decode(json).graph.node('a')!.data['when'], when);
    });

    test('an unregistered type names the node and the key', () {
      const codec = NodeGraphCodec();

      expect(
        () => codec.encode(
          GraphDocument(
            graph: withData(<String, Object?>{'when': DateTime.utc(2026)}),
          ),
        ),
        throwsA(
          isA<UnencodablePayloadException>()
              .having((e) => e.type, 'type', DateTime)
              .having((e) => e.location, 'location', contains('when')),
        ),
      );
    });

    test('an unknown tag on the way in is refused', () {
      const codec = NodeGraphCodec();

      expect(
        () => codec.decode(<String, Object?>{
          'version': 1,
          'nodes': <Object?>[
            <String, Object?>{
              'id': 'a',
              'position': <Object?>[0, 0],
              'fields': <Object?>[
                <String, Object?>{
                  'values': <String, Object?>{
                    'when': <String, Object?>{r'$type': 'geo', 'value': 1},
                  },
                },
              ],
            },
          ],
        }),
        throwsA(
          isA<GraphDocumentFormatException>().having(
            (e) => e.message,
            'message',
            contains('"geo"'),
          ),
        ),
      );
    });

    test(r'a map holding its own $type key is escaped', () {
      final graph = withData(<String, Object?>{
        'raw': <String, Object?>{r'$type': 'not a payload', 'value': 7},
      });

      expect(roundTrip(graph).node('a')!.data['raw'], <String, Object?>{
        r'$type': 'not a payload',
        'value': 7,
      });
    });

    test('a generic type matches its codec', () {
      final generics = PayloadCodecs(<PayloadCodec<Object>>[
        PayloadCodec<List<int>>(
          tag: 'ints',
          toJson: (value) => value,
          fromJson: (json) => (json! as List<Object?>).cast<int>().toList(),
        ),
      ]);

      expect(
        generics.forValue(<int>[1, 2])?.tag,
        'ints',
        reason:
            'List<int>.runtimeType is not List<dynamic>, which is exactly '
            'where a type-keyed table alone falls through',
      );
    });

    test('duplicate and reserved tags are refused at construction', () {
      PayloadCodec<Object> stub(String tag) => PayloadCodec<DateTime>(
        tag: tag,
        toJson: (value) => null,
        fromJson: (json) => DateTime.utc(2026),
      );

      expect(
        () => PayloadCodecs(<PayloadCodec<Object>>[stub('a'), stub('a')]),
        throwsArgumentError,
      );
      expect(
        () => PayloadCodecs(<PayloadCodec<Object>>[stub('map')]),
        throwsArgumentError,
      );
    });
  });

  group('errors', () {
    const codec = NodeGraphCodec();

    test('a malformed value reports its path', () {
      expect(
        () => codec.decode(<String, Object?>{
          'version': 1,
          'nodes': <Object?>[
            <String, Object?>{
              'id': 'a',
              'position': <Object?>[0, 0],
            },
            <String, Object?>{
              'id': 'b',
              'position': <Object?>[0, 0],
            },
            <String, Object?>{
              'id': 'c',
              'position': <Object?>[0, 0],
              'ports': <Object?>[
                <String, Object?>{
                  'ports': <Object?>[
                    <String, Object?>{
                      'id': 'p',
                      'direction': 'input',
                      'anchor': 'nope',
                    },
                  ],
                },
              ],
            },
          ],
        }),
        throwsA(
          isA<GraphDocumentFormatException>().having(
            (e) => e.location,
            'location',
            'nodes[2].ports[0].ports[0].anchor',
          ),
        ),
      );
    });

    test('an unknown enum name lists the legal ones', () {
      expect(
        () => codec.decode(<String, Object?>{
          'version': 1,
          'nodes': <Object?>[
            <String, Object?>{
              'id': 'a',
              'position': <Object?>[0, 0],
              'ports': <Object?>[
                <String, Object?>{
                  'ports': <Object?>[
                    <String, Object?>{'id': 'p', 'direction': 'sideways'},
                  ],
                },
              ],
            },
          ],
        }),
        throwsA(
          isA<GraphDocumentFormatException>().having(
            (e) => e.message,
            'message',
            allOf(contains('sideways'), contains('input, output')),
          ),
        ),
      );
    });

    test('duplicate ids are refused rather than silently collapsed', () {
      Map<String, Object?> node(String id) => <String, Object?>{
        'id': id,
        'position': <Object?>[0, 0],
      };

      expect(
        () => codec.decode(<String, Object?>{
          'version': 1,
          'nodes': <Object?>[node('a'), node('a')],
        }),
        throwsA(
          isA<GraphDocumentFormatException>().having(
            (e) => e.message,
            'message',
            contains('duplicate node id "a"'),
          ),
        ),
      );

      expect(
        () => codec.decode(<String, Object?>{
          'version': 1,
          'nodes': <Object?>[
            <String, Object?>{
              'id': 'a',
              'position': <Object?>[0, 0],
              'ports': <Object?>[
                <String, Object?>{
                  'ports': <Object?>[
                    <String, Object?>{'id': 'p', 'direction': 'input'},
                    <String, Object?>{'id': 'p', 'direction': 'output'},
                  ],
                },
              ],
            },
          ],
        }),
        throwsA(
          isA<GraphDocumentFormatException>().having(
            (e) => e.message,
            'message',
            contains('duplicate port id "p"'),
          ),
        ),
      );
    });

    test('a wire to a port that does not exist yet is allowed through', () {
      final decoded = codec.decode(<String, Object?>{
        'version': 1,
        'nodes': <Object?>[
          <String, Object?>{
            'id': 'a',
            'position': <Object?>[0, 0],
          },
        ],
        'connections': <Object?>[
          <String, Object?>{
            'id': 'c1',
            'from': <String, Object?>{'nodeId': 'a', 'portId': 'exit_0'},
            'to': <String, Object?>{'nodeId': 'ghost', 'portId': 'in'},
          },
        ],
      });

      expect(
        decoded.graph.connections,
        hasLength(1),
        reason:
            'a prototyped document legitimately names ports before they '
            'are derived — referential integrity is the resolver\'s job',
      );
    });
  });
}
