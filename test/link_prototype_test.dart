import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fl_nodes_v2/fl_nodes_v2.dart';

void main() {
  GraphNode node(String id, {Offset position = Offset.zero}) => GraphNode(
    id: id,
    position: position,
    width: 120,
    height: 60,
    ports: const <NodePort>[
      NodePort.input(id: 'in'),
      NodePort.output(id: 'out'),
    ],
  );

  NodeGraph twoWired({String type = 'branch', String? label = 'High'}) =>
      NodeGraph(
        nodes: <GraphNode>[
          node('a', position: const Offset(80, 240)),
          node('b', position: const Offset(520, 240)),
        ],
        connections: <NodeConnection>[
          NodeConnection(
            id: 'c1',
            from: const PortRef('a', 'out'),
            to: const PortRef('b', 'in'),
            type: type,
            label: label,
          ),
        ],
      );

  NodePrototypeRegistry registry({bool editable = true}) =>
      NodePrototypeRegistry(
        const <NodePrototype>[],
        links: <LinkPrototype>[
          LinkPrototype(
            type: 'branch',
            label: editable ? const EditableLinkLabel() : null,
          ),
        ],
      );

  Widget harness(
    NodeEditorController controller, {
    Future<String?> Function(BuildContext, NodeConnection)? onEdit,
  }) => MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 800,
          height: 600,
          child: NodeEditor(
            controller: controller,
            theme: NodeEditorTheme.dark(),
            onEditConnectionLabel: onEdit,
            nodeBuilder: (context, graphNode, state) => ColoredBox(
              key: ValueKey<String>('body_${graphNode.id}'),
              color: const Color(0xFF2A2E38),
            ),
          ),
        ),
      ),
    ),
  );

  /// Where the caption for [id] was actually painted.
  Offset captionCentre(WidgetTester tester, String id) {
    final state = tester.state<NodeEditorState>(find.byType(NodeEditor));
    final controller = tester
        .widget<NodeEditor>(find.byType(NodeEditor))
        .controller;
    final anchor = state.connectionLayout[id]!.labelAnchor!;
    return controller.camera.viewport.toScreen(anchor);
  }

  group('the toggle', () {
    test('is off unless a link prototype opts in', () {
      const connection = NodeConnection(
        id: 'c1',
        from: PortRef('a', 'out'),
        to: PortRef('b', 'in'),
        type: 'branch',
      );

      expect(registry().allowsLabelEditing(connection), isTrue);
      expect(registry(editable: false).allowsLabelEditing(connection), isFalse);
      expect(
        NodePrototypeRegistry.empty.allowsLabelEditing(connection),
        isFalse,
      );
      expect(
        registry().allowsLabelEditing(
          connection.copyWith(type: 'somethingElse'),
        ),
        isFalse,
        reason: 'the toggle is per link type, like a family is per family',
      );
    });

    test('setConnectionLabel writes through history and can clear', () {
      final controller = NodeEditorController(graph: twoWired());
      addTearDown(controller.dispose);

      controller.setConnectionLabel('c1', 'Low');
      expect(controller.graph.connection('c1')!.label, 'Low');

      controller.setConnectionLabel('c1', '');
      expect(
        controller.graph.connection('c1')!.label,
        isNull,
        reason: 'an empty caption is no caption',
      );

      controller.history.undo();
      expect(controller.graph.connection('c1')!.label, 'Low');
    });

    test('writing the same caption twice records nothing', () {
      final controller = NodeEditorController(graph: twoWired());
      addTearDown(controller.dispose);
      controller.history.clear();

      controller.setConnectionLabel('c1', 'High');

      expect(controller.history.canUndo, isFalse);
    });
  });

  group('captions', () {
    test('are not drawn, and so not tappable, when zoomed far out', () {
      expect(
        ConnectionLabel.captionFor(
          text: 'High',
          anchor: Offset.zero,
          editable: true,
          viewport: const ViewportTransform(scale: 0.2),
          style: null,
        ),
        isNull,
      );
      expect(
        ConnectionLabel.captionFor(
          text: 'High',
          anchor: Offset.zero,
          editable: true,
          viewport: ViewportTransform.identity,
          style: null,
        ),
        isNotNull,
      );
    });

    test('an editable link with no caption still gets a box to aim at', () {
      expect(
        ConnectionLabel.captionFor(
          text: null,
          anchor: Offset.zero,
          editable: false,
          viewport: ViewportTransform.identity,
          style: null,
        ),
        isNull,
      );
      final caption = ConnectionLabel.captionFor(
        text: null,
        anchor: Offset.zero,
        editable: true,
        viewport: ViewportTransform.identity,
        style: null,
      );
      expect(caption, isNotNull);
      expect(caption!.text, ConnectionLabel.placeholder);
    });
  });

  testWidgets('a port decides what kind of link it emits', (tester) async {
    final controller = NodeEditorController(
      graph: NodeGraph(
        nodes: <GraphNode>[
          GraphNode(
            id: 'a',
            position: const Offset(80, 240),
            width: 120,
            height: 60,
            // Wires drawn from here are captionable; nothing else has to know.
            ports: const <NodePort>[
              NodePort.output(id: 'out', linkType: 'branch'),
            ],
          ),
          node('b', position: const Offset(520, 240)),
        ],
      ),
      prototypes: registry(),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(harness(controller));

    final id = controller.connect(
      const PortRef('a', 'out'),
      const PortRef('b', 'in'),
    )!;
    await tester.pumpAndSettle();

    expect(controller.graph.connection(id)!.type, 'branch');
    expect(
      controller.prototypes.allowsLabelEditing(
        controller.graph.connection(id)!,
      ),
      isTrue,
    );

    // And it is immediately captionable, placeholder and all.
    await tester.tapAt(captionCentre(tester, id));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Named on the spot');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(controller.graph.connection(id)!.label, 'Named on the spot');
  });

  group('derived captions', () {
    NodePrototypeRegistry derived() => NodePrototypeRegistry(
      const <NodePrototype>[],
      links: <LinkPrototype>[
        LinkPrototype(
          type: 'branch',
          label: DerivedLinkLabel(build: (context) => context.fromPort?.label),
        ),
      ],
    );

    test('exclude editing, by construction', () {
      const connection = NodeConnection(
        id: 'c1',
        from: PortRef('a', 'out'),
        to: PortRef('b', 'in'),
        type: 'branch',
      );

      expect(derived().allowsLabelEditing(connection), isFalse);
      expect(
        const LinkPrototype(
          type: 'branch',
          label: DerivedLinkLabel(build: _never),
        ).editableLabel,
        isFalse,
      );
      expect(
        const LinkPrototype(
          type: 'branch',
          label: EditableLinkLabel(),
        ).editableLabel,
        isTrue,
      );
    });

    test('are computed, and ignore what the connection carries', () {
      final graph = NodeGraph(
        nodes: <GraphNode>[
          GraphNode(
            id: 'a',
            position: Offset.zero,
            ports: const <NodePort>[
              NodePort.output(id: 'out', label: 'From the port'),
            ],
          ),
          node('b'),
        ],
        connections: <NodeConnection>[
          const NodeConnection(
            id: 'c1',
            from: PortRef('a', 'out'),
            to: PortRef('b', 'in'),
            type: 'branch',
            label: 'stale, and ignored',
          ),
        ],
      );

      expect(
        derived().captionOf(graph, graph.connection('c1')!),
        'From the port',
      );
    });

    testWidgets('follow what they are derived from', (tester) async {
      final controller = NodeEditorController(
        graph: NodeGraph(
          nodes: <GraphNode>[
            GraphNode(
              id: 'a',
              position: const Offset(80, 240),
              width: 120,
              height: 60,
              ports: const <NodePort>[
                NodePort.output(id: 'out', label: 'Out 0'),
              ],
            ),
            node('b', position: const Offset(520, 240)),
          ],
          connections: <NodeConnection>[
            const NodeConnection(
              id: 'c1',
              from: PortRef('a', 'out'),
              to: PortRef('b', 'in'),
              type: 'branch',
            ),
          ],
        ),
        prototypes: derived(),
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(harness(controller));

      final state = tester.state<NodeEditorState>(find.byType(NodeEditor));
      expect(state.connectionLayout['c1']!.caption, 'Out 0');

      controller.updateNode(
        'a',
        (node) => node.copyWith(
          ports: <NodePort>[node.ports.single.copyWith(label: 'Out 7')],
        ),
      );
      await tester.pump();

      expect(
        state.connectionLayout['c1']!.caption,
        'Out 7',
        reason: 'nothing was stored, so there is nothing to go stale',
      );
      expect(controller.graph.connection('c1')!.label, isNull);
    });

    testWidgets('are not tappable', (tester) async {
      final controller = NodeEditorController(
        graph: NodeGraph(
          nodes: <GraphNode>[
            GraphNode(
              id: 'a',
              position: const Offset(80, 240),
              width: 120,
              height: 60,
              ports: const <NodePort>[
                NodePort.output(id: 'out', label: 'Out 0'),
              ],
            ),
            node('b', position: const Offset(520, 240)),
          ],
          connections: <NodeConnection>[
            const NodeConnection(
              id: 'c1',
              from: PortRef('a', 'out'),
              to: PortRef('b', 'in'),
              type: 'branch',
            ),
          ],
        ),
        prototypes: derived(),
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(harness(controller));

      await tester.tapAt(captionCentre(tester, 'c1'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(controller.selection.connectionIds, contains('c1'));
    });
  });

  testWidgets('the editor title comes from the prototype', (tester) async {
    final controller = NodeEditorController(
      graph: twoWired(),
      prototypes: NodePrototypeRegistry(
        const <NodePrototype>[],
        links: const <LinkPrototype>[
          LinkPrototype(
            type: 'branch',
            label: EditableLinkLabel(editorTitle: 'Name this choice'),
          ),
        ],
      ),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(harness(controller));

    await tester.tapAt(captionCentre(tester, 'c1'));
    await tester.pumpAndSettle();

    expect(find.text('Name this choice'), findsOneWidget);
  });

  group('tapping a caption', () {
    testWidgets('opens an editor and writes the result back', (tester) async {
      final controller = NodeEditorController(
        graph: twoWired(),
        prototypes: registry(),
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(harness(controller));

      await tester.tapAt(captionCentre(tester, 'c1'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Medium');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(controller.graph.connection('c1')!.label, 'Medium');
      controller.history.undo();
      expect(controller.graph.connection('c1')!.label, 'High');
    });

    testWidgets('gives an uncaptioned link its first caption', (tester) async {
      final controller = NodeEditorController(
        graph: twoWired(label: null),
        prototypes: registry(),
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(harness(controller));

      // Nothing is written yet, but the placeholder is on screen to aim at.
      await tester.tapAt(captionCentre(tester, 'c1'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Yes');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(controller.graph.connection('c1')!.label, 'Yes');
    });

    testWidgets('backing out of the editor changes nothing', (tester) async {
      final controller = NodeEditorController(
        graph: twoWired(),
        prototypes: registry(),
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(harness(controller));
      controller.history.clear();

      await tester.tapAt(captionCentre(tester, 'c1'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Discarded');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(controller.graph.connection('c1')!.label, 'High');
      expect(controller.history.canUndo, isFalse);
    });

    testWidgets('a link that did not opt in just selects instead', (
      tester,
    ) async {
      final controller = NodeEditorController(
        graph: twoWired(),
        prototypes: registry(editable: false),
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(harness(controller));

      await tester.tapAt(captionCentre(tester, 'c1'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(
        controller.selection.connectionIds,
        contains('c1'),
        reason: 'the tap falls through to the curve underneath',
      );
    });

    testWidgets('the host can supply its own editor', (tester) async {
      final controller = NodeEditorController(
        graph: twoWired(),
        prototypes: registry(),
      );
      addTearDown(controller.dispose);
      NodeConnection? asked;
      await tester.pumpWidget(
        harness(
          controller,
          onEdit: (context, connection) async {
            asked = connection;
            return 'From the host';
          },
        ),
      );

      await tester.tapAt(captionCentre(tester, 'c1'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(asked?.id, 'c1');
      expect(controller.graph.connection('c1')!.label, 'From the host');
    });
  });
}

String? _never(LinkResolutionContext context) => null;
