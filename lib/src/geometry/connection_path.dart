import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../model/node_port.dart';
import 'node_geometry.dart';

/// Builds and probes the cubic beziers used for connections.
abstract final class ConnectionPath {
  /// Fraction of the endpoint distance used for the bezier control arms.
  static const double defaultCurvature = 0.5;
  static const double minControlArm = 36;
  static const double maxControlArm = 220;

  /// A cubic bezier leaving [from] along its side's normal and arriving at
  /// [to] against its own.
  ///
  /// Both points are in whatever space the caller is painting in — pass screen
  /// coordinates when painting, scene coordinates when hit-testing the model.
  static Path build(
    Offset from,
    Offset to, {
    PortSide fromSide = PortSide.right,
    PortSide toSide = PortSide.left,
    double curvature = defaultCurvature,
    double scale = 1.0,
  }) {
    final arm = controlArm(from, to, curvature: curvature, scale: scale);
    final c1 = from + NodeGeometry.normalOf(fromSide) * arm;
    final c2 = to + NodeGeometry.normalOf(toSide) * arm;

    return Path()
      ..moveTo(from.dx, from.dy)
      ..cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, to.dx, to.dy);
  }

  static double controlArm(
    Offset from,
    Offset to, {
    double curvature = defaultCurvature,
    double scale = 1.0,
  }) {
    final distance = (to - from).distance;
    return (distance * curvature).clamp(
      minControlArm * scale,
      maxControlArm * scale,
    );
  }

  /// Distance from [point] to the closest sampled point on [path].
  ///
  /// `Path.contains` only reports the *filled* interior, which is empty for a
  /// stroked curve, so connection picking has to walk the path instead.
  /// [step] trades accuracy for speed; the default is well under a typical
  /// hit tolerance.
  static double distanceTo(Path path, Offset point, {double step = 6}) {
    var best = double.infinity;
    for (final metric in path.computeMetrics()) {
      final length = metric.length;
      if (length == 0) continue;
      final samples = math.max(2, (length / step).ceil());
      for (var i = 0; i <= samples; i++) {
        final tangent = metric.getTangentForOffset(length * i / samples);
        if (tangent == null) continue;
        final delta = (tangent.position - point).distanceSquared;
        if (delta < best) best = delta;
      }
    }
    return best == double.infinity ? double.infinity : math.sqrt(best);
  }

  /// Whether [point] lands within [tolerance] of the stroked path.
  static bool hitTest(Path path, Offset point, {double tolerance = 8}) =>
      distanceTo(path, point, step: tolerance * 0.75) <= tolerance;

  /// The point halfway along the path, used to anchor connection labels.
  /// Evenly spaced points along [path], each with the direction of travel
  /// there.
  ///
  /// Arrowheads used to sit at the receiving port and point along that port's
  /// normal, which is straight while the curve arriving at it is not — so the
  /// head visibly disagreed with its own wire at the one place the two meet.
  /// Sampling the path instead gives each head the curve's own angle, and
  /// repeating them says which way the data flows along the whole length
  /// rather than only where it lands.
  ///
  /// [spacing] is the scene distance aimed for between heads; the count is
  /// rounded to fit and clamped to `1..maxCount`, so a short link still says
  /// which way it points and a very long one does not become a dotted line.
  static List<PathArrow> arrowsAlong(
    Path path, {
    required double spacing,
    required int maxCount,
  }) {
    assert(spacing > 0);
    for (final metric in path.computeMetrics()) {
      final length = metric.length;
      if (length == 0) continue;
      final count = (length / spacing).round().clamp(1, maxCount);
      final arrows = <PathArrow>[];
      for (var i = 0; i < count; i++) {
        // Half a gap in from each end: the run stays centred, and no head
        // lands back on the seam it was moved away from.
        final tangent = metric.getTangentForOffset(length * (i + 0.5) / count);
        if (tangent == null) continue;
        arrows.add(PathArrow(tangent.position, tangent.vector));
      }
      return arrows;
    }
    return const <PathArrow>[];
  }

  static Offset? midpoint(Path path) {
    for (final metric in path.computeMetrics()) {
      if (metric.length == 0) continue;
      return metric.getTangentForOffset(metric.length / 2)?.position;
    }
    return null;
  }
}

/// A direction marker sampled from a connection's curve.
@immutable
class PathArrow {
  const PathArrow(this.position, this.direction);

  /// Scene position on the curve.
  final Offset position;

  /// Unit vector along the curve, pointing the way the data flows — from the
  /// emitting port towards the receiving one.
  final Offset direction;
}
