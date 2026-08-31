import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fl_nodes_v2/fl_nodes_v2.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Stands in for the platform clipboard.
  String? system;

  setUp(() {
    system = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          switch (call.method) {
            case 'Clipboard.setData':
              system =
                  (call.arguments as Map<Object?, Object?>)['text'] as String?;
              return null;
            case 'Clipboard.getData':
              // A real platform answers null for an empty clipboard;
              // Clipboard.getData casts a present 'text' to a non-null
              // String and would throw on {'text': null}.
              return system == null ? null : <String, Object?>{'text': system};
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  GraphNode node(String id, {Offset position = Offset.zero}) => GraphNode(
    id: id,
    position: position,
    width: 100,
    height: 50,
    data: <String, Object?>{'name': id},
    ports: const <NodePort>[
      NodePort.input(id: 'in'),
      NodePort.output(id: 'out'),
    ],
  );

  /// Keeps every wired exit and always leaves one spare, so the family is a
  /// function of which exits are connected rather than of any stored field.
  final fanOut = NodePrototype(
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

  NodeEditorController controllerWith(
    List<GraphNode> nodes, {
    List<NodeConnection> connections = const <NodeConnection>[],
    NodePrototypeRegistry? prototypes,
    NodeGraphCodec? codec,
  }) {
    final controller = NodeEditorController(
      graph: NodeGraph(nodes: nodes, connections: connections),
      prototypes: prototypes,
      codec: codec,
    );
    addTearDown(controller.dispose);
    return controller;
  }

  /// The name a node was authored with, so a pasted copy can be identified
  /// without depending on the generated ids.
  String nameOf(NodeEditorController controller, String id) =>
      controller.graph.nodes[id]!.data['name']! as String;

  group('copying', () {
    test('copies the selected nodes and the wires between them', () {
      final controller = controllerWith(
        <GraphNode>[
          node('a'),
          node('b', position: const Offset(200, 0)),
          node('c', position: const Offset(600, 0)),
        ],
        connections: const <NodeConnection>[
          NodeConnection(
            id: 'ab',
            from: PortRef('a', 'out'),
            to: PortRef('b', 'in'),
          ),
        ],
      );

      controller.selection.selectNodes(<String>['a', 'b']);
      expect(controller.clipboard.copy(), isTrue);
      final pasted = controller.clipboard.paste();

      expect(pasted.length, 2);
      expect(controller.graph.nodes.length, 5);
      expect(controller.graph.connections.length, 2);

      final copied = controller.graph.connections.values.firstWhere(
        (connection) => connection.id != 'ab',
      );
      expect(
        <String>{copied.from.nodeId, copied.to.nodeId},
        pasted,
        reason: 'the copied wire must join the new pair, not the originals',
      );
      expect(nameOf(controller, copied.from.nodeId), 'a');
      expect(nameOf(controller, copied.to.nodeId), 'b');
      expect(
        controller.selection.nodeIds,
        pasted,
        reason: 'what was just pasted is what the user is now working on',
      );
    });

    test('leaves behind a wire to a node that was not selected', () {
      final controller = controllerWith(
        <GraphNode>[node('a'), node('b', position: const Offset(200, 0))],
        connections: const <NodeConnection>[
          NodeConnection(
            id: 'ab',
            from: PortRef('a', 'out'),
            to: PortRef('b', 'in'),
          ),
        ],
      );

      controller.selection.selectNode('a');
      controller.clipboard.copy();
      controller.clipboard.paste();

      expect(controller.graph.nodes.length, 3);
      expect(
        controller.graph.connections.length,
        1,
        reason: 'reattaching a half-copied wire would rewire the document',
      );
    });

    test('an empty selection copies nothing and keeps the buffer', () {
      final controller = controllerWith(<GraphNode>[node('a')]);

      controller.selection.selectNode('a');
      expect(controller.clipboard.copy(), isTrue);

      controller.selection.clear();
      expect(controller.clipboard.copy(), isFalse);
      expect(controller.clipboard.canPaste, isTrue);
      expect(controller.clipboard.paste().length, 1);
    });
  });

  group('pasting', () {
    test('successive pastes cascade instead of stacking', () {
      final controller = controllerWith(<GraphNode>[
        node('a', position: const Offset(100, 100)),
      ]);

      controller.selection.selectNode('a');
      controller.clipboard.copy();

      final first = controller.clipboard.paste().single;
      final second = controller.clipboard.paste().single;

      expect(
        controller.graph.nodes[first]!.position,
        const Offset(100, 100) + NodeEditorClipboard.pasteNudge,
      );
      expect(
        controller.graph.nodes[second]!.position,
        const Offset(100, 100) + NodeEditorClipboard.pasteNudge * 2,
      );
    });

    test('pastes at an explicit position when given one', () {
      final controller = controllerWith(<GraphNode>[
        node('a', position: const Offset(100, 100)),
        node('b', position: const Offset(300, 180)),
      ]);

      controller.selection.selectNodes(<String>['a', 'b']);
      controller.clipboard.copy();
      final pasted = controller.clipboard.paste(
        scenePosition: const Offset(0, 0),
      );

      final positions = <Offset>{
        for (final id in pasted) controller.graph.nodes[id]!.position,
      };
      expect(
        positions,
        <Offset>{Offset.zero, const Offset(200, 80)},
        reason:
            'the fragment keeps its internal layout, anchored at its '
            'top-left',
      );
    });

    test('undo removes exactly what was pasted', () {
      final controller = controllerWith(
        <GraphNode>[node('a'), node('b', position: const Offset(200, 0))],
        connections: const <NodeConnection>[
          NodeConnection(
            id: 'ab',
            from: PortRef('a', 'out'),
            to: PortRef('b', 'in'),
          ),
        ],
      );

      controller.selection.selectNodes(<String>['a', 'b']);
      controller.clipboard.copy();
      controller.clipboard.paste();
      controller.history.undo();

      expect(controller.graph.nodes.keys, <String>['a', 'b']);
      expect(controller.graph.connections.keys, <String>['ab']);
    });

    test('duplicate leaves the buffer and the system clipboard alone', () {
      final controller = controllerWith(<GraphNode>[
        node('a'),
        node('b', position: const Offset(200, 0)),
      ], codec: const NodeGraphCodec());

      controller.selection.selectNode('a');
      controller.clipboard.copy();
      final buffer = controller.clipboard.buffer;
      final written = system;

      controller.selection.selectNode('b');
      final duplicated = controller.clipboard.duplicate().single;

      expect(nameOf(controller, duplicated), 'b');
      expect(identical(controller.clipboard.buffer, buffer), isTrue);
      expect(system, written);
      expect(
        nameOf(controller, controller.clipboard.paste().single),
        'a',
        reason:
            'the buffer still holds what was copied, not what was '
            'duplicated',
      );
    });
  });

  group('cutting', () {
    test('cut is one undo step', () {
      final controller = controllerWith(
        <GraphNode>[node('a'), node('b', position: const Offset(200, 0))],
        connections: const <NodeConnection>[
          NodeConnection(
            id: 'ab',
            from: PortRef('a', 'out'),
            to: PortRef('b', 'in'),
          ),
        ],
      );

      controller.selection.selectNodes(<String>['a', 'b']);
      expect(controller.clipboard.cut(), isTrue);
      expect(controller.graph.nodes, isEmpty);
      expect(controller.graph.connections, isEmpty);

      controller.history.undo();
      expect(controller.graph.nodes.keys, <String>['a', 'b']);
      expect(controller.graph.connections.keys, <String>['ab']);
      expect(controller.history.canUndo, isFalse);
    });

    test('cut leaves the fragment ready to paste', () {
      final controller = controllerWith(<GraphNode>[node('a')]);

      controller.selection.selectNode('a');
      controller.clipboard.cut();
      final pasted = controller.clipboard.paste().single;

      expect(nameOf(controller, pasted), 'a');
    });
  });

  group('prototypes', () {
    NodeEditorController fanOutController() {
      final controller = controllerWith(<GraphNode>[
        const GraphNode(id: 'f', type: 'fanout', position: Offset.zero),
        node('sink', position: const Offset(400, 0)),
      ], prototypes: NodePrototypeRegistry(<NodePrototype>[fanOut]));
      controller.connect(
        const PortRef('f', 'out_0'),
        const PortRef('sink', 'in'),
      );
      return controller;
    }

    test('a node copied with its wires keeps the ports they earned', () {
      final controller = fanOutController();
      expect(
        controller.graph.nodes['f']!.outputs.length,
        2,
        reason: 'wiring the last exit is what grows the next one',
      );

      controller.selection.selectNodes(<String>['f', 'sink']);
      controller.clipboard.copy();
      final pasted = controller.clipboard.paste();

      final copy = pasted
          .map((id) => controller.graph.nodes[id]!)
          .firstWhere((node) => node.type == 'fanout');
      expect(copy.outputs.length, 2);
      expect(
        controller.graph.connectionsOf(copy.id).length,
        1,
        reason: 'the wire came along, so the exit it fills came with it',
      );
    });

    test('a node copied alone comes back with only what it can justify', () {
      final controller = fanOutController();

      controller.selection.selectNode('f');
      controller.clipboard.copy();
      final pasted = controller.clipboard.paste().single;
      final copy = controller.graph.nodes[pasted]!;

      expect(
        copy.outputs.length,
        1,
        reason:
            'nothing is wired to the copy, so the spare exit is all it '
            'has earned',
      );
      expect(
        controller.graph.nodes['f']!.outputs.length,
        2,
        reason: 'the original is untouched by the copy',
      );
    });
  });

  group('the system clipboard', () {
    test('a copy in one editor pastes into another', () async {
      const codec = NodeGraphCodec();
      final source = controllerWith(
        <GraphNode>[
          node('a', position: const Offset(40, 60)),
          node('b', position: const Offset(240, 60)),
        ],
        connections: const <NodeConnection>[
          NodeConnection(
            id: 'ab',
            from: PortRef('a', 'out'),
            to: PortRef('b', 'in'),
          ),
        ],
        codec: codec,
      );

      source.selection.selectNodes(<String>['a', 'b']);
      source.clipboard.copy();
      expect(system, isNotNull);

      final target = controllerWith(const <GraphNode>[], codec: codec);
      final pasted = await target.clipboard.pasteFromSystem();

      expect(pasted.length, 2);
      expect(target.graph.connections.length, 1);
      expect(
        <String>{for (final id in pasted) nameOf(target, id)},
        <String>{'a', 'b'},
      );
      expect(
        target.graph.nodes[pasted.first]!.position -
            target.graph.nodes[pasted.last]!.position,
        isNot(Offset.zero),
        reason: 'the fragment keeps its shape across the round trip',
      );
    });

    test('text from another app falls back to the buffer', () async {
      final controller = controllerWith(<GraphNode>[
        node('a'),
      ], codec: const NodeGraphCodec());

      controller.selection.selectNode('a');
      controller.clipboard.copy();
      system = 'a shopping list, not a graph';

      final pasted = await controller.clipboard.pasteFromSystem();
      expect(pasted.length, 1);
      expect(nameOf(controller, pasted.single), 'a');
    });

    test('a document of ours that cannot be read throws', () async {
      final controller = controllerWith(<GraphNode>[
        node('a'),
      ], codec: const NodeGraphCodec());

      system = jsonEncode(<String, Object?>{'version': 99});

      expect(
        () => controller.clipboard.pasteFromSystem(),
        throwsA(isA<GraphDocumentVersionException>()),
        reason:
            'silently ignoring our own unreadable document would look '
            'like the paste key was broken',
      );
    });

    test('without a codec nothing reaches the system clipboard', () async {
      final controller = controllerWith(<GraphNode>[node('a')]);

      controller.selection.selectNode('a');
      controller.clipboard.copy();

      expect(controller.clipboard.mirrorsToSystem, isFalse);
      expect(system, isNull);
      expect(
        (await controller.clipboard.pasteFromSystem()).length,
        1,
        reason: 'the in-process buffer still works without a codec',
      );
    });
  });
}
