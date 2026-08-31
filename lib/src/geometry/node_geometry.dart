import 'dart:ui';

import '../model/graph_node.dart';
import '../model/node_port.dart';

/// Pure functions turning the data model into canvas geometry.
///
/// Both the painters and the node widget layout read port placement from
/// here, so a port handle and the curve that lands on it can never disagree.
abstract final class NodeGeometry {
  /// Where a port sits inside its node, normalised to `0..1` on both axes.
  ///
  /// Ports with an explicit [NodePort.anchor] use it verbatim; the rest are
  /// spread evenly along their side in declaration order.
  static Offset anchorOf(GraphNode node, NodePort port) {
    final explicit = port.anchor;
    if (explicit != null) return explicit;

    final side = port.side;
    final siblings = <NodePort>[
      for (final candidate in node.ports)
        if (candidate.side == side) candidate,
    ];
    final index = siblings.indexWhere((candidate) => candidate.id == port.id);
    final fraction = (index + 1) / (siblings.length + 1);

    return switch (side) {
      PortSide.left => Offset(0, fraction),
      PortSide.right => Offset(1, fraction),
      PortSide.top => Offset(fraction, 0),
      PortSide.bottom => Offset(fraction, 1),
    };
  }

  /// The port's centre in scene coordinates, for a node resolved to [size].
  static Offset portPosition(GraphNode node, NodePort port, Size size) {
    final anchor = anchorOf(node, port);
    return node.position +
        Offset(anchor.dx * size.width, anchor.dy * size.height);
  }

  /// Unit vector pointing away from the node at a given side.
  static Offset normalOf(PortSide side) => switch (side) {
    PortSide.left => const Offset(-1, 0),
    PortSide.right => const Offset(1, 0),
    PortSide.top => const Offset(0, -1),
    PortSide.bottom => const Offset(0, 1),
  };
}
