import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../controller/node_editor_controller.dart';
import '../model/node_comment.dart';
import '../model/node_group.dart';
import '../painting/connection_layout.dart';
import '../theme/node_editor_theme.dart';
import 'minimap_config.dart';
import 'minimap_controller.dart';
import 'minimap_palette.dart';
import 'minimap_projection.dart';
import 'minimap_scene.dart';

/// Draws the whole document small: every node as a rect, and a wash over
/// everything the canvas is not currently showing.
class MinimapPainter extends CustomPainter {
  MinimapPainter({
    required this.controller,
    required this.minimap,
    required this.connections,
    required this.scene,
    required this.theme,
    required this.viewportSize,
    this.nodeColor,
  }) : palette = MinimapPalette.forCanvas(theme.background),
       // The one painter in this package with a `repaint` listenable, and the
       // reason it can have one is that every input it reads is on a
       // ChangeNotifier. The four canvas painters cannot: their inputs include
       // NodeEditorState fields — the hovered port, the marquee, the pending
       // wire — that only a rebuild can deliver.
       //
       // Here it buys the whole point. The panel widget is cached by identity,
       // so a scroll tick repaints this one layer and rebuilds no widget at
       // all. Do not "tidy" this away.
       super(repaint: Listenable.merge(<Listenable?>[controller, minimap]));

  /// Held live rather than snapshotted: `paint` reads the camera, the graph,
  /// the layout and the selection at the moment it draws.
  final NodeEditorController controller;
  final MinimapController minimap;
  final ConnectionLayout connections;
  final MinimapScene scene;
  final NodeEditorTheme theme;
  final MinimapPalette palette;

  /// Size of the *canvas*, which is what turns the camera into a scene rect.
  final Size viewportSize;

  final MinimapNodeColor? nodeColor;

  /// Smallest a node may be drawn, so a large graph does not thin out into
  /// invisible sub-pixel slivers.
  static const double _minNodeExtent = 2;

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..clipRect(Offset.zero & size)
      ..drawRect(Offset.zero & size, Paint()..color = palette.surface);

    // Cheap when nothing moved: compares one revision counter. Called here
    // rather than in a build, because the panel deliberately does not rebuild
    // on a camera tick.
    scene.sync(controller);

    final projection = MinimapProjection.fit(
      contentBounds: scene.contentBounds,
      mapSize: size,
      maxScale: minimap.maxScale,
    );
    if (projection.content == null) return;

    if (minimap.showGroups) _paintGroups(canvas, projection);
    if (minimap.showConnections) _paintConnections(canvas, projection);
    _paintNodes(canvas, projection);
    _paintViewport(canvas, size, projection);
  }

  /// The same numbers `GroupView` draws with, so a frame reads as the same
  /// object at both sizes.
  void _paintGroups(Canvas canvas, MinimapProjection projection) {
    for (final (color, frame) in scene.groups) {
      final rect = projection.sceneRectToMap(frame);
      canvas
        ..drawRect(rect, Paint()..color = color.withValues(alpha: 0.10))
        ..drawRect(
          rect,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = color.withValues(alpha: 0.45),
        );
    }
  }

  /// Straight lines, not beziers, batched into one [Path] and stroked once.
  ///
  /// At a few pixels of arc a chord and a curve are the same handful of
  /// pixels, and transforming a cached path costs an allocation per wire per
  /// frame. The endpoints are free: `ConnectionLayout.sync` walks every
  /// connection in the graph rather than only the visible ones, so they are
  /// already computed.
  void _paintConnections(Canvas canvas, MinimapProjection projection) {
    final path = Path();
    var any = false;
    for (final entry in connections.entries) {
      final ends = entry.value.endpoints;
      final from = projection.toMap(ends.from);
      final to = projection.toMap(ends.to);
      path
        ..moveTo(from.dx, from.dy)
        ..lineTo(to.dx, to.dy);
      any = true;
    }
    if (!any) return;
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = theme.connectionColor.withValues(alpha: 0.55),
    );
  }

  /// Batched by colour into one [Path] each, the way `PortsPainter` batches
  /// handles: at five thousand nodes the draw-call count is the cost, not the
  /// arithmetic.
  ///
  /// Selected nodes are drawn last in a second pass rather than by sorting,
  /// which matches `NodeEditorLayout` floating them above the rest on the
  /// canvas and costs nothing on a graph where nothing is selected.
  void _paintNodes(Canvas canvas, MinimapProjection projection) {
    final graph = controller.graph;
    final selection = controller.selection;
    final showComments = minimap.showComments;

    final byColor = <Color, Path>{};
    Path? selectedPath;

    for (final (node, sceneRect) in scene.nodes) {
      if (!showComments && NodeComment.isComment(node)) continue;
      final isSelected = selection.containsNode(node.id);
      final color = minimapNodeColor(
        node,
        graph: graph,
        selected: theme.selectionColor,
        // The same grey the note slab itself uses, named once.
        comment: NodeGroup.neutralColor,
        neutral: palette.node,
        isSelected: isSelected,
        override: nodeColor,
      );
      final rect = _atLeastVisible(projection.sceneRectToMap(sceneRect));
      if (isSelected) {
        (selectedPath ??= Path()).addRect(rect);
      } else {
        (byColor[color] ??= Path()..fillType = PathFillType.nonZero).addRect(
          rect,
        );
      }
    }

    for (final MapEntry(key: color, value: path) in byColor.entries) {
      canvas.drawPath(path, Paint()..color = color);
    }
    if (selectedPath != null) {
      canvas.drawPath(selectedPath, Paint()..color = theme.selectionColor);
    }
  }

  static Rect _atLeastVisible(Rect rect) {
    if (rect.width >= _minNodeExtent && rect.height >= _minNodeExtent) {
      return rect;
    }
    return Rect.fromCenter(
      center: rect.center,
      width: math.max(rect.width, _minNodeExtent),
      height: math.max(rect.height, _minNodeExtent),
    );
  }

  /// The wash, then the "you are here" rectangle over it.
  ///
  /// Four rects rather than a path. The runner-up is one even-odd [Path] of
  /// two rects — a single draw call, but a [Path] allocated on every paint,
  /// and this repaints on every scroll tick. `Path.combine` is the one to
  /// avoid outright: two paths plus a Skia path-ops pass, per frame.
  void _paintViewport(Canvas canvas, Size size, MinimapProjection projection) {
    if (viewportSize.isEmpty) return;
    final marker = projection.sceneRectToMap(
      controller.camera.viewport.visibleSceneRect(viewportSize),
    );

    final shade = Paint()..color = palette.shade;
    for (final band in minimapShadeBands(Offset.zero & size, marker)) {
      canvas.drawRect(band, shade);
    }

    canvas.drawRect(
      marker,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = palette.viewportBorder,
    );
  }

  /// Compares only what [repaint] cannot deliver.
  ///
  /// Deliberately not the viewport transform and not the revision: both arrive
  /// through the listenable, and asking here as well would be a second, later
  /// copy of the same question.
  @override
  bool shouldRepaint(MinimapPainter old) =>
      !identical(old.controller, controller) ||
      !identical(old.minimap, minimap) ||
      !identical(old.connections, connections) ||
      !identical(old.scene, scene) ||
      old.theme != theme ||
      old.viewportSize != viewportSize ||
      old.nodeColor != nodeColor;
}
