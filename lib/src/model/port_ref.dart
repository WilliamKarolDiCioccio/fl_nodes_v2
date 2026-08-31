import 'package:flutter/foundation.dart';

/// Identifies a single port on a single node.
///
/// Ports are only unique within their owning node, so both halves are needed
/// to address one from the graph level.
@immutable
class PortRef {
  const PortRef(this.nodeId, this.portId);

  final String nodeId;
  final String portId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PortRef && other.nodeId == nodeId && other.portId == portId;

  @override
  int get hashCode => Object.hash(nodeId, portId);

  @override
  String toString() => 'PortRef($nodeId.$portId)';
}
