import 'package:fl_nodes_v2/fl_nodes_v2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The three descriptions a card can carry, and the one rule that is easy to
/// break by accident.
///
/// A port's description is **outside equality and outside the codec**. That is
/// not tidiness: resolution keeps the node it already has when the ports it
/// would build compare equal to the ones on it, so a description inside `==`
/// would make every document written before the prose existed differ from what
/// its prototype now builds — and opening one would rewrite every node in it.
/// The last test here is that regression, written down.
void main() {
  group('a port', () {
    test('carries a description through both convenience constructors', () {
      const input = NodePort.input(id: 'in', description: 'The way in.');
      const output = NodePort.output(id: 'out', description: 'The way on.');

      expect(input.description, 'The way in.');
      expect(output.description, 'The way on.');
    });

    test('keeps it across copyWith, and lets one be given', () {
      const port = NodePort.input(id: 'in', description: 'The way in.');

      expect(port.copyWith(family: 'flow').description, 'The way in.');
      expect(port.copyWith(description: 'Another.').description, 'Another.');
    });

    test('equals one that differs only in its description', () {
      const bare = NodePort.input(id: 'in');
      const described = NodePort.input(id: 'in', description: 'The way in.');

      expect(described, bare);
      expect(described.hashCode, bare.hashCode);
    });

    test('does not equal one that differs in anything else', () {
      const described = NodePort.input(id: 'in', description: 'The way in.');

      expect(
        described,
        isNot(const NodePort.input(id: 'in', label: 'in')),
        reason: 'a label is the document\'s; a description is the kind\'s',
      );
    });
  });

  group('a field', () {
    test('carries a description, and compares on it', () {
      const described = NodeField(key: 'board', description: 'Where it goes.');

      expect(described.description, 'Where it goes.');
      expect(described, isNot(const NodeField(key: 'board')));
      expect(
        described,
        const NodeField(key: 'board', description: 'Where it goes.'),
      );
    });
  });

  group('the dialog', () {
    Future<void> open(
      WidgetTester tester, {
      Widget Function(BuildContext, String)? builder,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showNodeDescription(
                context,
                description: 'What **it** does.',
                builder: builder,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('shows selectable plain text by default', (tester) async {
      await open(tester);

      expect(find.byType(SelectableText), findsOneWidget);
      expect(find.text('What **it** does.'), findsOneWidget);
    });

    testWidgets('hands the description to a builder when given', (
      tester,
    ) async {
      var seen = '';
      await open(
        tester,
        builder: (context, description) {
          seen = description;
          return const Text('rendered');
        },
      );

      expect(seen, 'What **it** does.');
      expect(find.text('rendered'), findsOneWidget);
      expect(find.byType(SelectableText), findsNothing);
    });
  });

  test('resolution leaves a node whose stored ports carry no description', () {
    // What a board written before the prose existed holds.
    final stored = GraphNode(
      id: 'n',
      type: 'documented',
      position: Offset.zero,
      width: 120,
      height: 80,
      ports: const <NodePort>[
        NodePort.output(id: 'out', family: 'flow', kind: PortKind.control),
      ],
    );
    final registry = NodePrototypeRegistry(<NodePrototype>[
      NodePrototype(
        type: 'documented',
        description: 'What it does.',
        ports: const <PortFamily>[
          StaticPortFamily(
            id: 'flow',
            ports: <NodePort>[
              NodePort.output(
                id: 'out',
                kind: PortKind.control,
                description: 'The single wire the story leaves by.',
              ),
            ],
          ),
        ],
      ),
    ]);

    final resolved = registry.resolveAll(NodeGraph(nodes: <GraphNode>[stored]));

    expect(
      resolved.graph.nodes['n'],
      same(stored),
      reason: 'opening a board may not rewrite it because the prose moved',
    );
  });
}
