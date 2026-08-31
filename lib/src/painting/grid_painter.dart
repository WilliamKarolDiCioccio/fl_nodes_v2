import 'dart:ui' show FragmentShader;

import 'package:flutter/rendering.dart';

import '../geometry/viewport_transform.dart';
import '../theme/node_editor_theme.dart';
import 'grid_shader.dart';

/// Draws the infinite background grid in screen space.
///
/// With a [shader] the whole background is one `drawRect`, and the cost is
/// fixed no matter how many lines are on screen. Without one it falls back to
/// emitting a line per visible grid step, which is correct but scales with the
/// zoom-out level.
class GridPainter extends CustomPainter {
  const GridPainter({required this.viewport, required this.theme, this.shader});

  final ViewportTransform viewport;
  final NodeEditorTheme theme;

  /// The compiled grid shader, or null while it loads or where unsupported.
  final FragmentShader? shader;

  /// Below this on-screen spacing, CPU-drawn minor lines are visual noise.
  static const double _minLineSpacing = 7;

  @override
  void paint(Canvas canvas, Size size) {
    final shader = this.shader;
    final showGrid = theme.showGrid && theme.gridSpacing > 0;

    if (shader != null &&
        showGrid &&
        !GridShader.isTooDense(theme, viewport.scale)) {
      GridShader.configure(shader, viewport, theme);
      canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
      return;
    }

    canvas.drawRect(Offset.zero & size, Paint()..color = theme.background);
    if (showGrid) _paintLines(canvas, size);
  }

  void _paintLines(Canvas canvas, Size size) {
    final spacing = theme.gridSpacing;
    final step = spacing * viewport.scale;
    final majorEvery = theme.gridMajorEvery < 1 ? 1 : theme.gridMajorEvery;
    final drawMinor = step >= _minLineSpacing;
    if (!drawMinor && step * majorEvery < _minLineSpacing) return;

    final scene = viewport.visibleSceneRect(size);
    final minor = Paint()
      ..color = theme.gridLine
      ..strokeWidth = 1;
    final major = Paint()
      ..color = theme.gridLineMajor
      ..strokeWidth = 1;

    final firstX = (scene.left / spacing).floor();
    final lastX = (scene.right / spacing).ceil();
    for (var i = firstX; i <= lastX; i++) {
      final isMajor = i % majorEvery == 0;
      if (!isMajor && !drawMinor) continue;
      final x = viewport.toScreen(Offset(i * spacing, 0)).dx;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        isMajor ? major : minor,
      );
    }

    final firstY = (scene.top / spacing).floor();
    final lastY = (scene.bottom / spacing).ceil();
    for (var i = firstY; i <= lastY; i++) {
      final isMajor = i % majorEvery == 0;
      if (!isMajor && !drawMinor) continue;
      final y = viewport.toScreen(Offset(0, i * spacing)).dy;
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        isMajor ? major : minor,
      );
    }
  }

  @override
  bool shouldRepaint(GridPainter oldDelegate) =>
      oldDelegate.viewport != viewport ||
      oldDelegate.theme != theme ||
      !identical(oldDelegate.shader, shader);
}
