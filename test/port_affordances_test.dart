import 'package:fl_nodes_v2/fl_nodes_v2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The two things a handle says about itself before a wire is traced: what
/// kind of pin it is, by its shape, and what it carries, by a label the host
/// writes.
void main() {
  group('port shapes', () {
    test('a control pin and a data pin are told apart by default', () {
      final theme = NodeEditorTheme.dark();
      expect(theme.shapeOf(PortKind.control), PortShape.triangle);
      expect(theme.shapeOf(PortKind.data), PortShape.circle);
    });

    test('a host that wants the old row of dots says so once', () {
      final plain = NodeEditorTheme.dark().copyWith(
        controlPortShape: PortShape.circle,
      );
      expect(plain.shapeOf(PortKind.control), PortShape.circle);
      expect(plain.shapeOf(PortKind.data), PortShape.circle);
    });

    test('the shapes are part of what makes two themes different', () {
      final theme = NodeEditorTheme.dark();
      expect(theme.copyWith(), theme);
      expect(
        theme.copyWith(controlPortShape: PortShape.diamond),
        isNot(theme),
        reason: 'a repaint has to follow a shape somebody changed',
      );
    });

    test('every shape sits on its row, in the circle they share', () {
      for (final shape in PortShape.values) {
        final bounds = shape.path(const Offset(50, 50), 6).getBounds();
        expect(
          bounds.center.dy,
          closeTo(50, 0.001),
          reason: '$shape is level with the handles either side of it',
        );
        expect(
          bounds.contains(const Offset(50, 50)),
          isTrue,
          reason: '$shape covers the point the wire attaches to',
        );
        // Within a few pixels of the circle they share, so a row of mixed
        // shapes reads as one row rather than as two sizes.
        expect(
          bounds.longestSide,
          closeTo(12, 3),
          reason: '$shape is about as big as the dot beside it',
        );
      }
    });

    test('a shape is built on its circumradius, not its bounding box', () {
      // The anchor is the wire's attachment and the hit target's centre, so
      // it is the *circumcentre* that sits on the row. A triangle's box is
      // therefore offset towards its tip, and that is the shape being
      // correct rather than a shape being off-centre.
      final circle = PortShape.circle.path(Offset.zero, 6).getBounds();
      expect(circle.center.dx, closeTo(0, 0.001));
      final triangle = PortShape.triangle.path(Offset.zero, 6).getBounds();
      expect(triangle.center.dx, greaterThan(0));
    });

    test('a triangle points the same way at both ends of a wire', () {
      final bounds = PortShape.triangle.path(Offset.zero, 6).getBounds();
      expect(
        bounds.right,
        greaterThan(-bounds.left),
        reason:
            'the tip is the rightmost point and the flat back is behind it, '
            'so an input and an output both read left to right',
      );
    });
  });

  group('port tooltips', () {
    NodePort portOf(String id, PortKind kind) => NodePort.input(
      id: id,
      label: id,
      kind: kind,
      anchor: const Offset(0, 0.5),
    );

    testWidgets('nothing is shown until the host is asked', (tester) async {
      // No `portTooltip` is the default, and a canvas with none draws no
      // label however long the pointer rests.
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SizedBox())),
      );
      expect(find.byType(Tooltip), findsNothing);
    });

    test('a host may label the ports worth labelling and skip the rest', () {
      // The contract the editor reads: null and empty both mean "say
      // nothing", so a host can answer for one port and not another without
      // building a map of the ones it wants.
      String? ask(GraphNode node, NodePort port) =>
          port.kind == PortKind.data ? 'anything' : null;

      final node = GraphNode(
        id: 'n',
        type: 't',
        position: Offset.zero,
        ports: <NodePort>[
          portOf('exec', PortKind.control),
          portOf('value', PortKind.data),
        ],
      );
      expect(ask(node, node.portById('exec')!), isNull);
      expect(ask(node, node.portById('value')!), 'anything');
    });
  });
}
