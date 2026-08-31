import 'dart:ui';

import '../model/graph_node.dart';
import '../model/node_connection.dart';
import '../model/node_graph.dart';
import '../model/node_port.dart';
import 'connection_path.dart';
import 'node_geometry.dart';

/// Resolved endpoints of a connection.
typedef ConnectionEndpoints = ({
  Offset from,
  Offset to,
  PortSide fromSide,
  PortSide toSide,
});

/// Turns connections into drawable paths.
///
/// Shared by the painter and by pointer hit-testing so a click always lands on
/// the curve that was actually drawn.
class ConnectionRouter {
  const ConnectionRouter({
    required this.graph,
    required this.sizeOf,
    this.curvature = ConnectionPath.defaultCurvature,
  });

  final NodeGraph graph;
  final Size Function(GraphNode node) sizeOf;
  final double curvature;

  /// Scene-space endpoints, or null if either end no longer exists.
  ConnectionEndpoints? endpointsOf(NodeConnection connection) {
    final fromNode = graph.nodes[connection.from.nodeId];
    final toNode = graph.nodes[connection.to.nodeId];
    if (fromNode == null || toNode == null) return null;

    final fromPort = fromNode.portById(connection.from.portId);
    final toPort = toNode.portById(connection.to.portId);
    if (fromPort == null || toPort == null) return null;

    return (
      from: NodeGeometry.portPosition(fromNode, fromPort, sizeOf(fromNode)),
      to: NodeGeometry.portPosition(toNode, toPort, sizeOf(toNode)),
      fromSide: fromPort.side,
      toSide: toPort.side,
    );
  }

  Path? scenePath(NodeConnection connection) {
    final ends = endpointsOf(connection);
    if (ends == null) return null;
    return ConnectionPath.build(
      ends.from,
      ends.to,
      fromSide: ends.fromSide,
      toSide: ends.toSide,
      curvature: curvature,
    );
  }
}
