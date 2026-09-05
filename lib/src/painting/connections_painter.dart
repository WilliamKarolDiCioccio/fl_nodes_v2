import 'dart:math' as math;

import 'package:flutter/rendering.dart';

import '../geometry/viewport_transform.dart';
import '../model/node_connection.dart';
import '../model/node_graph.dart';
import '../prototype/node_prototype_registry.dart';
import '../theme/node_editor_theme.dart';
import 'connection_label.dart';
import 'connection_layout.dart';

/// Draws every connection curve beneath the node layer.
///
/// Two things keep this cheap on a dense graph. Paths come from
/// [ConnectionLayout], so nothing is recomputed while panning. And curves
/// sharing a colour are merged into one [Path] and stroked in a single call,
/// rather than paying per-connection draw overhead — stroking a path with many
/// subpaths gives the same result as stroking each on its own.
class ConnectionsPainter extends CustomPainter {
  const ConnectionsPainter({
    required this.layout,
    required this.graph,
    required this.viewport,
    required this.theme,
    required this.selectedIds,
    required this.revision,
    required this.selectionRevision,
    this.hoveredId,
    this.labelStyle,
    this.prototypes,
  });

  final ConnectionLayout layout;
  final NodeGraph graph;
  final ViewportTransform viewport;
  final NodeEditorTheme theme;
  final Set<String> selectedIds;

  /// [ConnectionLayout]'s invalidation key, used to decide repaints.
  final int revision;

  /// [NodeEditorSelection.revision], so a selection change repaints
  /// without comparing the sets themselves.
  final int selectionRevision;

  final String? hoveredId;
  final TextStyle? labelStyle;

  /// Decides which links are captionable, so those without a caption yet still
  /// draw something to aim at.
  final NodePrototypeRegistry? prototypes;

  /// Below this zoom, arrowheads and labels stop being readable and are
  /// skipped along with their layout cost.
  static const double _detailScaleThreshold =
      ConnectionLabel.detailScaleThreshold;

  @override
  void paint(Canvas canvas, Size size) {
    final visible = viewport.visibleSceneRect(size);
    final drawDetail = viewport.scale >= _detailScaleThreshold;

    // Curves painted in scene space under the viewport transform; stroke
    // widths are divided by the scale so they stay constant on screen.
    final normal = <Color, Path>{};
    final arrows = <Color, Path>{};
    final highlighted = <_Layer>[];

    for (final entry in layout.entriesIn(visible)) {
      final geometry = entry.value;
      final connection = graph.connections[entry.key];
      if (connection == null) continue;

      final priority = _priority(entry.key);
      if (priority == 0) {
        final color = connection.color ?? theme.connectionColor;
        (normal[color] ??= Path()).addPath(geometry.path, Offset.zero);
        if (drawDetail) {
          (arrows[color] ??= Path()).addPath(
            _arrowheads(geometry, connection),
            Offset.zero,
          );
        }
      } else {
        highlighted.add(_Layer(priority, entry.key, geometry, connection));
      }
    }

    canvas
      ..save()
      ..transform(viewport.toMatrix4().storage);

    normal.forEach((color, path) {
      canvas.drawPath(path, _strokePaint(color, theme.connectionWidth));
    });
    arrows.forEach((color, path) {
      canvas.drawPath(path, Paint()..color = color);
    });

    // Hovered, then selected, so they read on top of the batches.
    highlighted.sort((a, b) => a.priority - b.priority);
    for (final layer in highlighted) {
      final color = layer.priority == 2
          ? theme.selectedConnectionColor
          : theme.hoveredConnectionColor;
      final width = layer.priority == 2
          ? theme.selectedConnectionWidth
          : theme.connectionWidth;
      canvas.drawPath(layer.geometry.path, _strokePaint(color, width));
      if (drawDetail) {
        canvas.drawPath(
          _arrowheads(layer.geometry, layer.connection),
          Paint()..color = color,
        );
      }
    }

    canvas.restore();

    if (drawDetail) _paintLabels(canvas, visible);
  }

  int _priority(String id) {
    if (selectedIds.contains(id)) return 2;
    if (id == hoveredId) return 1;
    return 0;
  }

  Paint _strokePaint(Color color, double width) => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth =
        math.max(1, width * math.min(viewport.scale, 1.5)) / viewport.scale
    ..strokeCap = StrokeCap.round;

  /// Filled triangles along the curve, in scene units.
  ///
  /// One per marker cached on the geometry, angled to the curve's own slope
  /// there and pointing from the emitting port towards the receiving one. Any
  /// that would land under a caption are dropped: the caption sits at the
  /// midpoint, which is exactly where an odd-numbered run puts one.
  Path _arrowheads(ConnectionGeometry geometry, NodeConnection connection) {
    final caption = ConnectionLabel.captionFor(
      text: geometry.caption,
      anchor: geometry.labelAnchor,
      editable: prototypes?.allowsLabelEditing(connection) ?? false,
      viewport: viewport,
      style: labelStyle,
    );
    final avoid = caption?.rect.inflate(2);

    return arrowheadsPath(
      geometry.arrows,
      arrowheadSize(viewport.scale),
      skip: avoid == null
          ? null
          : (position) => avoid.contains(viewport.toScreen(position)),
    );
  }

  /// Labels are drawn in screen space so they keep a constant size, unlike
  /// the curves they sit on.
  void _paintLabels(Canvas canvas, Rect visible) {
    for (final entry in layout.entriesIn(visible)) {
      final anchor = entry.value.labelAnchor;
      if (anchor == null || !visible.contains(anchor)) continue;
      final connection = graph.connections[entry.key];
      if (connection == null) continue;

      final caption = ConnectionLabel.captionFor(
        text: entry.value.caption,
        anchor: anchor,
        editable: prototypes?.allowsLabelEditing(connection) ?? false,
        viewport: viewport,
        style: labelStyle,
      );
      if (caption == null) continue;

      canvas.drawRRect(
        RRect.fromRectAndRadius(caption.rect, const Radius.circular(4)),
        Paint()..color = theme.background.withValues(alpha: 0.92),
      );
      ConnectionLabel.layout(
        caption.text,
        caption.style,
        viewport.scale,
      ).paint(canvas, caption.textOrigin);
    }
  }

  @override
  bool shouldRepaint(ConnectionsPainter oldDelegate) =>
      oldDelegate.revision != revision ||
      oldDelegate.viewport != viewport ||
      oldDelegate.theme != theme ||
      oldDelegate.hoveredId != hoveredId ||
      oldDelegate.selectionRevision != selectionRevision ||
      !identical(oldDelegate.prototypes, prototypes);
}

class _Layer {
  const _Layer(this.priority, this.id, this.geometry, this.connection);

  final int priority;
  final String id;
  final ConnectionGeometry geometry;
  final NodeConnection connection;
}
