import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'payload_equality.dart';

/// Whether a port accepts incoming connections or originates outgoing ones.
enum PortDirection { input, output }

/// What a port carries: a value, or the flow of execution itself.
///
/// The distinction only matters to the runner — a data edge moves a value, a
/// control edge decides what runs next — but it is declared on the port
/// because that is where the editor needs it: wiring one kind to the other is
/// refused at the point the wire is drawn.
enum PortKind { data, control }

/// The edge of the node a port is anchored to.
///
/// The side also determines the direction the connection curve leaves the
/// port, which is what keeps beziers from doubling back on themselves.
enum PortSide { left, right, top, bottom }

/// A connection endpoint attached to a [GraphNode].
///
/// Ports are pure data: the editor derives their on-screen position from the
/// owning node's rect, so moving a node moves its ports for free.
@immutable
class NodePort {
  const NodePort({
    required this.id,
    required this.direction,
    this.label,
    PortSide? side,
    this.anchor,
    this.color,
    this.maxConnections,
    this.data,
    this.family,
    this.linkType,
    this.kind = PortKind.data,
    this.dataType,
  }) : _side = side;

  /// Convenience constructor for an input port (defaults to the left edge).
  const NodePort.input({
    required String id,
    String? label,
    PortSide? side,
    Offset? anchor,
    Color? color,
    int? maxConnections,
    Object? data,
    String? family,
    String? linkType,
    PortKind kind = PortKind.data,
    String? dataType,
  }) : this(
         id: id,
         direction: PortDirection.input,
         label: label,
         side: side,
         anchor: anchor,
         color: color,
         maxConnections: maxConnections,
         data: data,
         family: family,
         linkType: linkType,
         kind: kind,
         dataType: dataType,
       );

  /// Convenience constructor for an output port (defaults to the right edge).
  const NodePort.output({
    required String id,
    String? label,
    PortSide? side,
    Offset? anchor,
    Color? color,
    int? maxConnections,
    Object? data,
    String? family,
    String? linkType,
    PortKind kind = PortKind.data,
    String? dataType,
  }) : this(
         id: id,
         direction: PortDirection.output,
         label: label,
         side: side,
         anchor: anchor,
         color: color,
         maxConnections: maxConnections,
         data: data,
         family: family,
         linkType: linkType,
         kind: kind,
         dataType: dataType,
       );

  /// Unique within the owning node.
  final String id;

  final PortDirection direction;

  /// Optional caption rendered next to the port handle.
  final String? label;

  final PortSide? _side;

  /// Position within the node's rect, normalised to `0..1` on both axes.
  ///
  /// When null the editor distributes ports evenly along [side]. Set this to
  /// pin a port to a specific row — e.g. one output per dialogue choice.
  final Offset? anchor;

  /// Overrides the theme's port colour.
  final Color? color;

  /// Maximum number of connections this port accepts; null means unlimited.
  final int? maxConnections;

  /// Arbitrary payload for the host application.
  final Object? data;

  /// The prototype family that produced this port, if any.
  ///
  /// Ports without a family are the host's own: no prototype rewrites or
  /// removes them, which is what lets a prototyped node keep hand-authored
  /// ports alongside generated ones. A stamped port, by contrast, belongs to
  /// its prototype — including being retired when that family stops existing.
  final String? family;

  /// The kind of connection a wire drawn from this port becomes.
  ///
  /// Matched against [LinkPrototype.type], so the port decides what the link
  /// it emits is allowed to do — whether its caption can be edited, for one.
  /// Null leaves the connection on the default kind.
  final String? linkType;

  /// Whether this port carries a value or the flow of execution.
  ///
  /// Defaults to [PortKind.data], so a graph that never mentions kinds behaves
  /// exactly as it did before there were any.
  final PortKind kind;

  /// The kind of value this port carries, as a tag the host chooses.
  ///
  /// Null accepts anything, and an untyped end always matches a typed one, so
  /// adding a type to one side of an existing graph never invalidates a wire
  /// on its own.
  ///
  /// A tag rather than a Dart `Type` because ports are serialised and
  /// `Type.toString()` is not stable under obfuscation. It is a **wiring**
  /// constraint: nothing checks a value against it at run time, since a string
  /// cannot be compared to a Dart object's type.
  final String? dataType;

  /// The edge this port was authored on, or null to take [side]'s default.
  ///
  /// [side] answers where the port *is*; this answers what was written down. A
  /// codec that stored [side] and read it back would turn every unset side into
  /// an explicit one — and equality compares the authored value, so the port
  /// would stop equalling the one it came from.
  PortSide? get declaredSide => _side;

  /// The resolved edge: inputs default to the left, outputs to the right.
  PortSide get side =>
      _side ??
      (direction == PortDirection.input ? PortSide.left : PortSide.right);

  bool get isInput => direction == PortDirection.input;
  bool get isOutput => direction == PortDirection.output;

  NodePort copyWith({
    String? id,
    PortDirection? direction,
    String? label,
    PortSide? side,
    Offset? anchor,
    Color? color,
    int? maxConnections,
    Object? data,
    String? family,
    String? linkType,
    PortKind? kind,
    String? dataType,
  }) {
    return NodePort(
      id: id ?? this.id,
      direction: direction ?? this.direction,
      label: label ?? this.label,
      side: side ?? _side,
      anchor: anchor ?? this.anchor,
      color: color ?? this.color,
      maxConnections: maxConnections ?? this.maxConnections,
      data: data ?? this.data,
      family: family ?? this.family,
      linkType: linkType ?? this.linkType,
      kind: kind ?? this.kind,
      dataType: dataType ?? this.dataType,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NodePort &&
          other.id == id &&
          other.direction == direction &&
          other.label == label &&
          other._side == _side &&
          other.anchor == anchor &&
          other.color == color &&
          other.maxConnections == maxConnections &&
          payloadEquals(other.data, data) &&
          other.family == family &&
          other.linkType == linkType &&
          other.kind == kind &&
          other.dataType == dataType;

  @override
  int get hashCode => Object.hash(
    id,
    direction,
    label,
    _side,
    anchor,
    color,
    maxConnections,
    payloadHash(data),
    family,
    linkType,
    kind,
    dataType,
  );

  @override
  String toString() => 'NodePort($id, ${direction.name}, ${side.name})';
}
