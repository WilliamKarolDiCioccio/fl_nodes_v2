import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../geometry/connection_path.dart';
import '../geometry/viewport_transform.dart';
import '../model/node_port.dart';
import '../theme/node_editor_theme.dart';

/// The connection currently being dragged out of a port.
@immutable
class PendingConnection {
  const PendingConnection({
    required this.origin,
    required this.pointer,
    required this.originSide,
    this.isValidTarget = true,
    this.snappedTo,
  });

  /// Scene position of the port the drag started from.
  final Offset origin;

  /// Scene position of the pointer.
  final Offset pointer;

  final PortSide originSide;

  /// False while the pointer is over a port that cannot accept the link.
  final bool isValidTarget;

  /// Scene position of the port the drag would snap to, when there is one.
  final Offset? snappedTo;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PendingConnection &&
          other.origin == origin &&
          other.pointer == pointer &&
          other.originSide == originSide &&
          other.isValidTarget == isValidTarget &&
          other.snappedTo == snappedTo;

  @override
  int get hashCode =>
      Object.hash(origin, pointer, originSide, isValidTarget, snappedTo);
}

/// Draws transient interaction feedback above the nodes: the in-flight
/// connection curve and the marquee selection rectangle.
class OverlayPainter extends CustomPainter {
  const OverlayPainter({
    required this.viewport,
    required this.theme,
    this.pending,
    this.marquee,
  });

  final ViewportTransform viewport;
  final NodeEditorTheme theme;
  final PendingConnection? pending;

  /// Marquee rect in scene coordinates.
  final Rect? marquee;

  @override
  void paint(Canvas canvas, Size size) {
    _paintPending(canvas);
    _paintMarquee(canvas);
  }

  void _paintPending(Canvas canvas) {
    final pending = this.pending;
    if (pending == null) return;

    final from = viewport.toScreen(pending.origin);
    final target = pending.snappedTo ?? pending.pointer;
    final to = viewport.toScreen(target);
    final color = pending.isValidTarget
        ? theme.pendingConnectionColor
        : theme.invalidConnectionColor;

    // The far end has no port yet, so mirror the origin side to keep the
    // curve leaving and arriving along the same axis.
    final path = ConnectionPath.build(
      from,
      to,
      fromSide: pending.originSide,
      toSide: _opposite(pending.originSide),
      style: theme.connectionStyle,
      curvature: theme.connectionCurvature,
      stub: theme.connectionStub,
      cornerRadius: theme.connectionCornerRadius,
      scale: viewport.scale,
    );

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = theme.selectedConnectionWidth
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(to, theme.portRadius * 0.7, Paint()..color = color);
  }

  void _paintMarquee(Canvas canvas) {
    final marquee = this.marquee;
    if (marquee == null) return;

    final rect = viewport.sceneRectToScreen(marquee);
    canvas
      ..drawRect(
        rect,
        Paint()..color = theme.marqueeColor.withValues(alpha: 0.12),
      )
      ..drawRect(
        rect,
        Paint()
          ..color = theme.marqueeColor.withValues(alpha: 0.85)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
  }

  static PortSide _opposite(PortSide side) => switch (side) {
    PortSide.left => PortSide.right,
    PortSide.right => PortSide.left,
    PortSide.top => PortSide.bottom,
    PortSide.bottom => PortSide.top,
  };

  @override
  bool shouldRepaint(OverlayPainter oldDelegate) =>
      oldDelegate.viewport != viewport ||
      oldDelegate.theme != theme ||
      oldDelegate.pending != pending ||
      oldDelegate.marquee != marquee;
}
