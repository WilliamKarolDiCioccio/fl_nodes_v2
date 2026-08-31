import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'node_port.dart';
import 'payload_equality.dart';

/// A single box on the canvas.
///
/// The node owns its geometry and its ports, but nothing about how it looks:
/// rendering is delegated to the host's `nodeBuilder`, which switches on
/// [type] and reads [data]. That split is what makes the editor reusable
/// across very different domains.
@immutable
class GraphNode {
  const GraphNode({
    required this.id,
    required this.position,
    this.type = 'default',
    this.width = defaultWidth,
    this.height,
    this.ports = const <NodePort>[],
    this.data = const <String, Object?>{},
    this.draggable = true,
    this.selectable = true,
  });

  /// Width used when a node does not specify one.
  static const double defaultWidth = 220;

  /// Height assumed for a node whose content has not been measured yet.
  static const double fallbackHeight = 96;

  final String id;

  /// Host-defined kind, dispatched on by the node builder.
  final String type;

  /// Top-left corner in scene (graph) coordinates.
  final Offset position;

  final double width;

  /// Fixed height, or null to size to the built content.
  final double? height;

  final List<NodePort> ports;

  /// Arbitrary payload for the host application.
  final Map<String, Object?> data;

  final bool draggable;
  final bool selectable;

  bool get hasIntrinsicHeight => height == null;

  Iterable<NodePort> get inputs => ports.where((p) => p.isInput);
  Iterable<NodePort> get outputs => ports.where((p) => p.isOutput);

  NodePort? portById(String portId) {
    for (final port in ports) {
      if (port.id == portId) return port;
    }
    return null;
  }

  /// The node's rect given a resolved [size].
  Rect rect(Size size) => position & size;

  GraphNode copyWith({
    String? id,
    String? type,
    Offset? position,
    double? width,
    double? height,
    List<NodePort>? ports,
    Map<String, Object?>? data,
    bool? draggable,
    bool? selectable,
  }) {
    return GraphNode(
      id: id ?? this.id,
      type: type ?? this.type,
      position: position ?? this.position,
      width: width ?? this.width,
      height: height ?? this.height,
      ports: ports ?? this.ports,
      data: data ?? this.data,
      draggable: draggable ?? this.draggable,
      selectable: selectable ?? this.selectable,
    );
  }

  /// Returns a copy with [entries] merged into [data].
  GraphNode withData(Map<String, Object?> entries) =>
      copyWith(data: <String, Object?>{...data, ...entries});

  /// Returns a copy with a declared [height], or sized to its content if null.
  ///
  /// [copyWith] cannot express this: a null argument there means "keep what you
  /// had", so there is no way to send a node back to measuring itself.
  GraphNode withHeight(double? height) => GraphNode(
    id: id,
    type: type,
    position: position,
    width: width,
    height: height,
    ports: ports,
    data: data,
    draggable: draggable,
    selectable: selectable,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GraphNode &&
          other.id == id &&
          other.type == type &&
          other.position == position &&
          other.width == width &&
          other.height == height &&
          listEquals(other.ports, ports) &&
          payloadEquals(other.data, data) &&
          other.draggable == draggable &&
          other.selectable == selectable;

  @override
  int get hashCode => Object.hash(
    id,
    type,
    position,
    width,
    height,
    Object.hashAll(ports),
    Object.hashAllUnordered(data.keys),
    draggable,
    selectable,
  );

  @override
  String toString() => 'GraphNode($id, $type, $position)';
}
