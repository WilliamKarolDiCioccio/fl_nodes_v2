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
    this.minHeight,
    this.ports = const <NodePort>[],
    this.data = const <String, Object?>{},
    this.metadata = const <String, Object?>{},
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

  /// The least tall the node is drawn, whatever [height] or its content says
  /// — what a person dragging the corner chose. Null when nobody has.
  ///
  /// A floor rather than a height, so it never fights the prototype: a card
  /// that grows a row keeps the row, and one that loses a row keeps the room
  /// somebody asked for. The box extends **below** the declared height and
  /// the ports stay where they were — every explicit anchor is a fraction of
  /// [height], not of the box — so a wire lands on the same row of a card
  /// however tall the card has been made. A prototype that wants the extra
  /// room *used* rather than left blank reads this in `resolveHeight` and
  /// answers with a taller [height] laid out to it.
  final double? minHeight;

  final List<NodePort> ports;

  /// Arbitrary payload for the host application.
  final Map<String, Object?> data;

  /// Annotations the host's *user* attaches to a node: plain JSON the editor
  /// never reads and no prototype ever shapes.
  ///
  /// Beside [data] rather than in it, because [data] is what a prototype
  /// declares and resolution keeps in step — `seedAndPrune` drops a key a
  /// dynamic family stopped declaring — whereas what somebody wrote *about* a
  /// node is nobody's to prune. Nested as deep as the host likes; encoded
  /// through the same path as [data], so a value the codec cannot spell is
  /// refused the same way. Omitted from a document when empty.
  final Map<String, Object?> metadata;

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
    double? minHeight,
    List<NodePort>? ports,
    Map<String, Object?>? data,
    Map<String, Object?>? metadata,
    bool? draggable,
    bool? selectable,
  }) {
    return GraphNode(
      id: id ?? this.id,
      type: type ?? this.type,
      position: position ?? this.position,
      width: width ?? this.width,
      height: height ?? this.height,
      minHeight: minHeight ?? this.minHeight,
      ports: ports ?? this.ports,
      data: data ?? this.data,
      metadata: metadata ?? this.metadata,
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
    minHeight: minHeight,
    ports: ports,
    data: data,
    metadata: metadata,
    draggable: draggable,
    selectable: selectable,
  );

  /// Returns a copy with [minHeight] set, or cleared when null — the same
  /// reason [withHeight] exists beside [copyWith].
  GraphNode withMinHeight(double? minHeight) => GraphNode(
    id: id,
    type: type,
    position: position,
    width: width,
    height: height,
    minHeight: minHeight,
    ports: ports,
    data: data,
    metadata: metadata,
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
          other.minHeight == minHeight &&
          listEquals(other.ports, ports) &&
          payloadEquals(other.data, data) &&
          payloadEquals(other.metadata, metadata) &&
          other.draggable == draggable &&
          other.selectable == selectable;

  @override
  int get hashCode => Object.hash(
    id,
    type,
    position,
    width,
    height,
    minHeight,
    Object.hashAll(ports),
    Object.hashAllUnordered(data.keys),
    Object.hashAllUnordered(metadata.keys),
    draggable,
    selectable,
  );

  @override
  String toString() => 'GraphNode($id, $type, $position)';
}
