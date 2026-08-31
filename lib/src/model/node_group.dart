import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show EdgeInsets;
import 'dart:ui' show Color;

/// A named frame drawn behind a set of nodes.
///
/// A group owns no geometry. Its rectangle is the bounding box of whatever it
/// holds, plus [padding], recomputed as those nodes move — which is why this is
/// its own model rather than a node of a reserved type the way `NodeComment`
/// is. A node stores a position; a group derives one, and giving it a stored
/// position would mean rewriting the model on every frame of every drag.
///
/// Membership is explicit, not geometric: dragging a node over a group does
/// not put it in, and dragging one out does not take it out. A node belongs to
/// at most one group, and groups do not nest.
@immutable
class NodeGroup {
  const NodeGroup({
    required this.id,
    required this.nodeIds,
    this.name = defaultName,
    this.color,
  });

  /// What an unnamed group is called. Groups are made in one keystroke, so
  /// most of them never get a name and this is what shows.
  static const String defaultName = 'Untitled';

  /// Scene-space margin between the members' bounding box and the frame.
  ///
  /// Wide enough on top for the handle to sit clear of every member: the frame
  /// paints *below* its nodes, and a handle overlapped by one could not be
  /// clicked.
  static const EdgeInsets padding = EdgeInsets.fromLTRB(20, 40, 20, 20);

  /// What an uncoloured group is drawn in — the same neutral grey a comment
  /// slab uses, so the two unthemed things on the canvas match.
  static const Color neutralColor = Color(0xFF6D727C);

  /// The colours the editor offers, beyond [neutralColor].
  static const List<Color> palette = <Color>[
    Color(0xFF5B8DEF), // blue
    Color(0xFF3FA796), // teal
    Color(0xFF74A644), // green
    Color(0xFFCE9C3F), // amber
    Color(0xFFD06B57), // rust
    Color(0xFF9A6BC4), // violet
  ];

  final String id;

  /// The nodes inside, in no particular order.
  final Set<String> nodeIds;

  final String name;

  /// One of [palette], or null for [neutralColor].
  final Color? color;

  /// What this group is actually drawn in.
  Color get effectiveColor => color ?? neutralColor;

  bool contains(String nodeId) => nodeIds.contains(nodeId);

  bool get isEmpty => nodeIds.isEmpty;

  NodeGroup copyWith({String? id, Set<String>? nodeIds, String? name}) =>
      NodeGroup(
        id: id ?? this.id,
        nodeIds: nodeIds ?? this.nodeIds,
        name: name ?? this.name,
        color: color,
      );

  /// Returns a copy in [color], or in the neutral grey when null.
  ///
  /// [copyWith] cannot express this: a null argument there means "keep what
  /// you had", so there would be no way to take a colour back off.
  NodeGroup withColor(Color? color) =>
      NodeGroup(id: id, nodeIds: nodeIds, name: name, color: color);

  NodeGroup withNodes(Iterable<String> ids) =>
      copyWith(nodeIds: Set<String>.unmodifiable(ids));

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NodeGroup &&
          other.id == id &&
          other.name == name &&
          other.color == color &&
          setEquals(other.nodeIds, nodeIds);

  @override
  int get hashCode =>
      Object.hash(id, name, color, Object.hashAllUnordered(nodeIds));

  @override
  String toString() => 'NodeGroup($id, "$name", ${nodeIds.length} nodes)';
}
