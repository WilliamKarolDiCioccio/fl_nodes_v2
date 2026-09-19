import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'payload_equality.dart';
import 'port_ref.dart';

/// One waypoint of one connection: which wire, and which of its points.
typedef WaypointRef = ({String connectionId, int index});

/// A directed edge between an output port and an input port.
@immutable
class NodeConnection {
  const NodeConnection({
    required this.id,
    required this.from,
    required this.to,
    this.type = 'default',
    this.label,
    this.color,
    this.data,
    this.waypoints = const <Offset>[],
  });

  final String id;

  /// The originating output port.
  final PortRef from;

  /// The receiving input port.
  final PortRef to;

  /// Host-defined kind, matched against a [LinkPrototype].
  final String type;

  /// Optional caption drawn at the midpoint of the curve.
  final String? label;

  /// Overrides the theme's connection colour.
  final Color? color;

  /// Arbitrary payload for the host application.
  final Object? data;

  /// Scene points the wire is routed through, in order from [from] to [to].
  ///
  /// Not bezier control points: these sit *on* the wire, where the user put
  /// them, and the curve's own control points are solved from them. Empty for
  /// the plain curve between the two ports. Nothing but the drawing reads
  /// them — the runner does not know they exist.
  final List<Offset> waypoints;

  bool touches(String nodeId) => from.nodeId == nodeId || to.nodeId == nodeId;

  bool touchesPort(PortRef port) => from == port || to == port;

  NodeConnection copyWith({
    String? id,
    PortRef? from,
    PortRef? to,
    String? type,
    String? label,
    Color? color,
    Object? data,
    List<Offset>? waypoints,
  }) {
    return NodeConnection(
      id: id ?? this.id,
      from: from ?? this.from,
      to: to ?? this.to,
      type: type ?? this.type,
      label: label ?? this.label,
      color: color ?? this.color,
      data: data ?? this.data,
      waypoints: waypoints ?? this.waypoints,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NodeConnection &&
          other.id == id &&
          other.from == from &&
          other.to == to &&
          other.type == type &&
          other.label == label &&
          other.color == color &&
          payloadEquals(other.data, data) &&
          listEquals(other.waypoints, waypoints);

  @override
  int get hashCode => Object.hash(
    id,
    from,
    to,
    type,
    label,
    color,
    payloadHash(data),
    Object.hashAll(waypoints),
  );

  /// Returns a copy captioned [label], or uncaptioned when null.
  ///
  /// [copyWith] cannot express this: a null argument there means "keep what you
  /// had", so there is no way to take a caption back off.
  NodeConnection withLabel(String? label) => NodeConnection(
    id: id,
    from: from,
    to: to,
    type: type,
    label: label,
    color: color,
    data: data,
    waypoints: waypoints,
  );

  @override
  String toString() => 'NodeConnection($id, $from -> $to)';
}
