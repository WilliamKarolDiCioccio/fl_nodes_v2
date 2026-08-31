import 'dart:ui';

import 'graph_node.dart';

/// A free-standing note the app user writes on the canvas.
///
/// A comment is an ordinary [GraphNode] of a reserved [type] rather than a
/// model of its own, and that is the whole design. Paint order, selection,
/// dragging, the marquee, cut and paste, undo and the document format are all
/// things a node already has and a note needs unchanged; a parallel entity
/// would have meant a second copy of every one of them, kept in step by hand.
///
/// The editor renders comments itself and never hands one to the host's
/// `nodeBuilder`, so a host neither has to know this type exists nor can be
/// surprised by one arriving. It carries no ports, which is what keeps it out
/// of the runner: a node declaring no control ports sits outside the flow.
abstract final class NodeComment {
  /// Reserved. Registering a prototype for it, or authoring a node of this
  /// type by hand, is not supported — call [create].
  static const String type = '__comment__';

  /// Where the note's text lives inside [GraphNode.data].
  static const String textKey = 'text';

  /// Width used for a note whose author did not choose one.
  ///
  /// Wider than [GraphNode.defaultWidth]: a note is prose, and prose at a
  /// node's width wraps every few words.
  static const double defaultWidth = 260;

  /// A new note at [position].
  ///
  /// Height is deliberately left unset — a note is measured from the text in
  /// it, so it grows as it is written and there is nothing to resize.
  static GraphNode create({
    required String id,
    required Offset position,
    String text = '',
    double width = defaultWidth,
  }) => GraphNode(
    id: id,
    type: type,
    position: position,
    width: width,
    data: <String, Object?>{textKey: text},
  );

  static bool isComment(GraphNode node) => node.type == type;

  /// The note's text, or the empty string for anything that is not one.
  static String textOf(GraphNode node) {
    final value = node.data[textKey];
    return value is String ? value : '';
  }

  static GraphNode withText(GraphNode node, String text) =>
      NodeComment.textOf(node) == text
      ? node
      : node.withData(<String, Object?>{textKey: text});
}
