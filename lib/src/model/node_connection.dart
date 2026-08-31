import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'payload_equality.dart';
import 'port_ref.dart';

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
  }) {
    return NodeConnection(
      id: id ?? this.id,
      from: from ?? this.from,
      to: to ?? this.to,
      type: type ?? this.type,
      label: label ?? this.label,
      color: color ?? this.color,
      data: data ?? this.data,
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
          payloadEquals(other.data, data);

  @override
  int get hashCode =>
      Object.hash(id, from, to, type, label, color, payloadHash(data));

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
  );

  @override
  String toString() => 'NodeConnection($id, $from -> $to)';
}
