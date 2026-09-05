import 'dart:ui';

import 'package:flutter/foundation.dart';

/// Which parts of the graph are being pointed at.
///
/// A focus, not a decoration: while this is non-empty the editor washes the
/// canvas with a scrim and lifts the named nodes and connections above it, so
/// what is left standing is what somebody asked about. A host uses it to answer
/// a question *about* the graph — every route between two nodes, everything one
/// value reaches — without changing the graph to say so.
///
/// **Presentation, not content.** It is outside the undo history, outside the
/// document, and never reaches `guard` or `onEdit`, for the same reason
/// selection is: it is where the user is looking rather than something they
/// authored, and an undo that moved it around would fight the edit it was meant
/// to reverse.
///
/// [nodes] and [connections] are deliberately **independent**. A run that
/// passes through a node the host does not want to show — a helper the flow
/// merely traverses — is expressed by tinting the wires either side of it and
/// leaving the node out, so the coloured run stays continuous across a card
/// that is still dimmed. One map could not say that.
///
/// Membership lifts; the value tints. A null value lifts a node above the
/// scrim without painting anything behind it, and lifts a connection without
/// overriding its colour.
@immutable
class GraphEmphasis {
  const GraphEmphasis({
    this.nodes = const <String, Color?>{},
    this.connections = const <String, Color?>{},
    this.scrim,
  });

  /// Nothing emphasised, which is what every editor starts with and what makes
  /// the whole feature cost nothing until a host asks for it.
  static const GraphEmphasis none = GraphEmphasis();

  /// Node ids that rise above the scrim, each with the colour of the halo
  /// painted behind its card, or null for no halo.
  final Map<String, Color?> nodes;

  /// Connection ids drawn above the scrim, each with the colour to draw it in,
  /// or null to keep the colour it would have had.
  final Map<String, Color?> connections;

  /// The wash over everything else. Null uses the theme's own.
  final Color? scrim;

  bool get isEmpty => nodes.isEmpty && connections.isEmpty;
  bool get isNotEmpty => !isEmpty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GraphEmphasis &&
          other.scrim == scrim &&
          mapEquals(other.nodes, nodes) &&
          mapEquals(other.connections, connections);

  @override
  int get hashCode => Object.hash(
    scrim,
    Object.hashAllUnordered(
      nodes.entries.map((e) => Object.hash(e.key, e.value)),
    ),
    Object.hashAllUnordered(
      connections.entries.map((e) => Object.hash(e.key, e.value)),
    ),
  );
}
