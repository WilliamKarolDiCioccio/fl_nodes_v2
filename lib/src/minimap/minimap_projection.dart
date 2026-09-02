import 'dart:math' as math;
import 'dart:ui' show Color, Offset, Rect, Size;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show EdgeInsets;

import '../geometry/viewport_transform.dart';
import '../model/graph_node.dart';
import '../model/node_comment.dart';
import '../model/node_graph.dart';
import 'minimap_config.dart';

/// Scene coordinates to minimap-panel coordinates.
///
/// Reuses [ViewportTransform] rather than inventing a second
/// `scene * scale + offset`: it is the same algebra, it already compares by
/// value, and that makes comparing two projections one `!=`.
@immutable
class MinimapProjection {
  const MinimapProjection({required this.transform, required this.content});

  /// Nothing to show: an empty graph, or a panel with no room in it.
  static const MinimapProjection empty = MinimapProjection(
    transform: ViewportTransform.identity,
    content: null,
  );

  static const EdgeInsets defaultPadding = EdgeInsets.all(6);

  final ViewportTransform transform;

  /// The scene rect the map is framing, or null when there is nothing to
  /// frame.
  final Rect? content;

  double get scale => transform.scale;

  Offset toMap(Offset scenePoint) => transform.toScreen(scenePoint);

  Rect sceneRectToMap(Rect rect) => transform.sceneRectToScreen(rect);

  /// Frames [contentBounds] inside a map of [mapSize], never zooming past
  /// [maxScale].
  ///
  /// **The cap can only ever bind downward.** `fitted` is by construction the
  /// scale at which the content exactly fills the padded map, and the result
  /// is the smaller of that and [maxScale] — so capping leaves slack on both
  /// axes and can never push content off the map. The centring is therefore
  /// unconditional. What this deliberately has no counterpart of is a
  /// *minimum* scale: a five-thousand-node graph legitimately needs 0.001, and
  /// a floor there would silently truncate the document.
  static MinimapProjection fit({
    required Rect? contentBounds,
    required Size mapSize,
    required double maxScale,
    EdgeInsets padding = defaultPadding,
  }) {
    final content = contentBounds;
    if (content == null || mapSize.isEmpty) return empty;

    final available = Size(
      math.max(1, mapSize.width - padding.horizontal),
      math.max(1, mapSize.height - padding.vertical),
    );
    // The same guard `NodeEditorCamera.fitToContent` uses: a single node has
    // no height to divide by until it has been measured, and a row of nodes
    // has no height at all.
    final fitted = math.min(
      available.width / math.max(content.width, 1.0),
      available.height / math.max(content.height, 1.0),
    );
    final scale = math.min(fitted, maxScale);
    if (!scale.isFinite || scale <= 0) return empty;

    return MinimapProjection(
      transform: ViewportTransform(
        offset:
            Offset(mapSize.width / 2, mapSize.height / 2) -
            content.center * scale,
        scale: scale,
      ),
      content: content,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MinimapProjection &&
          other.transform == transform &&
          other.content == content;

  @override
  int get hashCode => Object.hash(transform, content);
}

/// The parts of [map] lying outside [viewport], as a tiling of at most four
/// rects.
///
/// **Slices, not insets.** The top and bottom bands run the full width of the
/// map and the side bands run only *between* them, so the complement is
/// covered exactly once. Four inset rects would overlap at the corners, and
/// the wash drawn over them is translucent — overlapping bands composite twice
/// and show as a visibly darker cross through the panel, which looks like a
/// rendering artefact and is actually arithmetic.
///
/// A viewport that covers the map yields nothing; one that misses it entirely
/// yields the whole map.
List<Rect> minimapShadeBands(Rect map, Rect viewport) {
  final hole = viewport.intersect(map);
  if (hole.isEmpty) return <Rect>[map];

  final top = Rect.fromLTRB(map.left, map.top, map.right, hole.top);
  final bottom = Rect.fromLTRB(map.left, hole.bottom, map.right, map.bottom);
  final left = Rect.fromLTRB(map.left, hole.top, hole.left, hole.bottom);
  final right = Rect.fromLTRB(hole.right, hole.top, map.right, hole.bottom);

  return <Rect>[
    for (final band in <Rect>[top, bottom, left, right])
      if (!band.isEmpty) band,
  ];
}

/// The colour a node is drawn in on the map.
///
/// Precedence, and the order is the point:
///
/// 1. the selection, so a selected node is never lost among same-typed
///    siblings on the one panel whose job is telling you where you are;
/// 2. the host's [override], which is how a narrative app colours by its own
///    node vocabulary — the package has no per-node colour by design;
/// 3. a comment, in the same grey its slab uses;
/// 4. the node's group, so a framed cluster reads as one thing;
/// 5. [neutral].
Color minimapNodeColor(
  GraphNode node, {
  required NodeGraph graph,
  required Color selected,
  required Color comment,
  required Color neutral,
  required bool isSelected,
  MinimapNodeColor? override,
}) {
  if (isSelected) return selected;
  final hosted = override?.call(node);
  if (hosted != null) return hosted;
  if (NodeComment.isComment(node)) return comment;
  return graph.groupOf(node.id)?.effectiveColor ?? neutral;
}
