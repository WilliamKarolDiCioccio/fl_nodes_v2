import 'dart:ui';

import 'package:flutter/foundation.dart';

/// How the canvas scrolls itself when a drag reaches its edge.
///
/// Holding a wire or a node against the side of the viewport pans the camera
/// toward that side, so a target off screen can be reached without letting go
/// to zoom out first. The pointer never has to move for it: parking it in the
/// margin keeps the canvas going until it leaves.
///
/// Everything here is in *screen* pixels, deliberately. The feel of the edge
/// should not change with the zoom — a margin that shrank as you zoomed in
/// would be hardest to hit exactly when the graph is largest on screen.
@immutable
class EdgeScrollConfig {
  const EdgeScrollConfig({this.margin = 40, this.speed = 600})
    : assert(margin > 0, 'margin must be positive'),
      assert(speed >= 0, 'speed cannot be negative');

  /// How far in from each edge of the canvas the scroll zone reaches.
  final double margin;

  /// How fast the canvas moves at the very edge, in screen pixels per second.
  ///
  /// The speed ramps linearly from nothing at the inner boundary of the
  /// [margin] to this at the edge, and holds there when the pointer is past
  /// it — a drag that has left the window altogether scrolls at full speed.
  final double speed;

  /// The scroll velocity a pointer at [localPosition] asks for, in screen
  /// pixels per second, pointing toward the edge it is near.
  ///
  /// [Offset.zero] anywhere outside the margins. A canvas narrower than two
  /// margins has zones that overlap, and the two pulls simply cancel where
  /// they do — nothing sensible can be meant on a canvas that small.
  Offset velocityAt(Offset localPosition, Size viewportSize) {
    if (speed == 0 || viewportSize.isEmpty) return Offset.zero;
    return Offset(
      _pull(localPosition.dx, viewportSize.width) * speed,
      _pull(localPosition.dy, viewportSize.height) * speed,
    );
  }

  /// -1..1 along one axis: negative toward the near edge, positive toward the
  /// far one, zero in the middle.
  double _pull(double position, double extent) {
    final double toStart = ((margin - position) / margin).clamp(0.0, 1.0);
    final double toEnd = ((position - (extent - margin)) / margin).clamp(
      0.0,
      1.0,
    );
    return toEnd - toStart;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EdgeScrollConfig &&
          other.margin == margin &&
          other.speed == speed;

  @override
  int get hashCode => Object.hash(margin, speed);
}
