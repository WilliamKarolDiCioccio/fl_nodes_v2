import 'dart:math' as math;

import 'package:flutter/rendering.dart';

import '../model/graph_emphasis.dart';
import '../model/graph_node.dart';
import '../theme/node_editor_theme.dart';
import 'connection_label.dart';
import 'connection_layout.dart';
import 'connections_painter.dart';

/// The focus layer: the scrim, the halos behind lifted cards, and the lifted
/// wires redrawn above it.
///
/// One painter for three jobs because they are one job — everything here
/// happens between the dimmed canvas and the cards that stand above it, and
/// splitting them would be three widgets that have to stay in the same slot of
/// the same stack.
///
/// **The wires have to be redrawn here rather than recoloured in place**, and
/// that is the thing to remember before trying to simplify this away.
/// [ConnectionsPainter] draws every curve *below* the whole node layer, so a
/// forced colour applied there would be washed out by a scrim painted above
/// it. Redrawing costs nothing: the geometry comes from [ConnectionLayout]'s
/// cache, which was built for the layer underneath and is already warm.
///
/// It paints inside the node layer's own scaled stack, so its local
/// coordinates are scene coordinates offset by [origin] — the same space the
/// node `Positioned`s use, which is what lets a halo be drawn from a node's
/// stored position with no viewport arithmetic of its own.
class EmphasisPainter extends CustomPainter {
  const EmphasisPainter({
    required this.emphasis,
    required this.emphasisRevision,
    required this.lifted,
    required this.sizeOf,
    required this.connections,
    required this.origin,
    required this.scale,
    required this.theme,
    required this.revision,
  });

  final GraphEmphasis emphasis;

  /// [NodeEditorEmphasis.revision], so a changed focus repaints without
  /// comparing the maps themselves.
  final int emphasisRevision;

  /// The lifted nodes that are actually on screen, already culled.
  final List<GraphNode> lifted;

  final Size Function(GraphNode node) sizeOf;

  final ConnectionLayout connections;

  /// Scene position this layer's local origin sits at.
  final Offset origin;

  /// The viewport scale the enclosing `Transform.scale` is applying, needed
  /// only to keep stroke widths constant on screen.
  final double scale;

  final NodeEditorTheme theme;

  /// [ConnectionLayout]'s invalidation key.
  final int revision;

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..translate(-origin.dx, -origin.dy);

    // The scrim is drawn in local coordinates, so it covers exactly what this
    // layer was sized to — everything the grid, the wires and the dimmed cards
    // beneath it could have reached.
    final visible = Rect.fromLTWH(
      origin.dx,
      origin.dy,
      size.width,
      size.height,
    );
    canvas.drawRect(
      visible,
      Paint()..color = emphasis.scrim ?? theme.resolvedScrim,
    );

    _paintHalos(canvas);
    _paintConnections(canvas, visible);

    canvas.restore();
  }

  /// A tinted plate behind each lifted card.
  ///
  /// Behind rather than over, which is the whole reason this can be a
  /// package-level feature: a host's node widget is opaque and unchanged, and
  /// what shows is a coloured border of [NodeEditorTheme.emphasisInset] around
  /// it. Nothing here has to know what a card looks like.
  void _paintHalos(Canvas canvas) {
    final byColor = <Color, Path>{};
    for (final node in lifted) {
      final tint = emphasis.nodes[node.id];
      if (tint == null) continue;
      (byColor[tint] ??= Path()).addRRect(
        RRect.fromRectAndRadius(
          node.rect(sizeOf(node)).inflate(theme.emphasisInset),
          theme.emphasisRadius,
        ),
      );
    }
    byColor.forEach((color, path) {
      canvas.drawPath(path, Paint()..color = color);
    });
  }

  /// The lifted wires, batched by colour exactly as the layer below batches
  /// its own — a stroked path with many subpaths draws the same as stroking
  /// each on its own, for one call instead of many.
  void _paintConnections(Canvas canvas, Rect visible) {
    if (emphasis.connections.isEmpty) return;
    final drawDetail = scale >= ConnectionLabel.detailScaleThreshold;
    final curves = <Color, Path>{};
    final arrows = <Color, Path>{};

    for (final entry in connections.entriesIn(visible)) {
      if (!emphasis.connections.containsKey(entry.key)) continue;
      final color =
          emphasis.connections[entry.key] ??
          entry.value.connection.color ??
          theme.connectionColor;
      (curves[color] ??= Path()).addPath(entry.value.path, Offset.zero);
      if (drawDetail) {
        (arrows[color] ??= Path()).addPath(
          arrowheadsPath(entry.value.arrows, arrowheadSize(scale)),
          Offset.zero,
        );
      }
    }

    curves.forEach((color, path) {
      canvas.drawPath(path, _strokePaint(color, theme.selectedConnectionWidth));
    });
    arrows.forEach((color, path) {
      canvas.drawPath(path, Paint()..color = color);
    });
  }

  /// The width arithmetic [ConnectionsPainter] uses, so a wire does not change
  /// thickness when it is lifted for any reason other than being lifted.
  Paint _strokePaint(Color color, double width) => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = math.max(1, width * math.min(scale, 1.5)) / scale
    ..strokeCap = StrokeCap.round;

  /// [lifted] is deliberately **not** compared: it is culled fresh on every
  /// build and so is never identical to the last one, which would make this
  /// answer true forever. Everything that can change what it holds is already
  /// here — geometry moves [revision], the cull moves [origin], and the focus
  /// itself moves [emphasisRevision]. The same reasoning [ConnectionsPainter]
  /// uses for the node list it is handed.
  @override
  bool shouldRepaint(EmphasisPainter oldDelegate) =>
      oldDelegate.emphasisRevision != emphasisRevision ||
      oldDelegate.revision != revision ||
      oldDelegate.origin != origin ||
      oldDelegate.scale != scale ||
      oldDelegate.theme != theme;
}
