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
  /// [to] against its own — or, with [via], a run of them through every
  /// point in it, in order.
  ///
  /// Both points are in whatever space the caller is painting in — pass screen
  /// coordinates when painting, scene coordinates when hit-testing the model.
  ///
  /// [via] are the points the wire is *routed through*, not bezier control
  /// points: the user places them on the wire and the control points are
  /// solved from them. Each waypoint takes the direction that bisects its two
  /// neighbours, and each segment's arms are [controlArm] on that segment's
  /// own length — so the ends leave and arrive exactly as they would without
  /// any, and a wire with no waypoints is the very same curve as before.
  static Path build(
    Offset from,
    Offset to, {
    PortSide fromSide = PortSide.right,
    PortSide toSide = PortSide.left,
    List<Offset> via = const <Offset>[],
    double curvature = defaultCurvature,
    double scale = 1.0,
  }) {
    final path = Path()..moveTo(from.dx, from.dy);
    for (final segment in segments(
      from,
      to,
      fromSide: fromSide,
      toSide: toSide,
      via: via,
      curvature: curvature,
      scale: scale,
    )) {
      path.cubicTo(
        segment.c1.dx,
        segment.c1.dy,
        segment.c2.dx,
        segment.c2.dy,
        segment.end.dx,
        segment.end.dy,
      );
    }
    return path;
  }

  /// The cubics [build] strings together, one per span between consecutive
  /// points of `[from, ...via, to]`.
  ///
  /// The tangent at a waypoint bisects the two spans that meet there — the
  /// sum of their unit vectors — rather than the chord between its
  /// neighbours, so a short span beside a long one is not dragged into the
  /// long one's direction. Only the direction is shared across the join; the
  /// arm lengths belong to each span, which keeps a tight pair of waypoints
  /// from looping. A waypoint that doubles straight back on itself has no
  /// bisector and takes the outgoing span's direction instead.
  static List<CubicSegment> segments(
    Offset from,
    Offset to, {
    PortSide fromSide = PortSide.right,
    PortSide toSide = PortSide.left,
    List<Offset> via = const <Offset>[],
    double curvature = defaultCurvature,
    double scale = 1.0,
  }) {
    final points = <Offset>[from, ...via, to];
    final last = points.length - 1;

    // The direction of travel at every point: the port normals at the two
    // ends — inward at the receiving end, since travel arrives against it —
    // and the bisector at every waypoint.
    final directions = List<Offset>.filled(points.length, Offset.zero);
    directions[0] = NodeGeometry.normalOf(fromSide);
    directions[last] = -NodeGeometry.normalOf(toSide);
    for (var i = 1; i < last; i++) {
      final incoming = _unit(points[i] - points[i - 1]);
      final outgoing = _unit(points[i + 1] - points[i]);
      final bisector = _unit(incoming + outgoing);
      directions[i] = bisector == Offset.zero ? outgoing : bisector;
    }

    return <CubicSegment>[
      for (var i = 0; i < last; i++)
        () {
          final start = points[i];
          final end = points[i + 1];
          final arm = controlArm(
            start,
            end,
            curvature: curvature,
            scale: scale,
          );
          return CubicSegment(
            start: start,
            c1: start + directions[i] * arm,
            c2: end - directions[i + 1] * arm,
            end: end,
          );
        }(),
    ];
  }

  static Offset _unit(Offset v) {
    final length = v.distance;
    return length == 0 ? Offset.zero : v / length;
  }

  /// Where a new waypoint dropped at [point] belongs on the route
  /// `[from, ...via, to]`: the closest point on the curve as drawn, and the
  /// index in [via] to insert it at so the wire still runs in order.
  ///
  /// Per segment rather than over the whole path, because the index is the
  /// answer that matters and one contour cannot say which cubic a distance
  /// along it fell in. A click, not a frame — it walks the metrics of every
  /// segment of one wire.
  static RoutePoint nearestOnRoute(
    Offset point, {
    required Offset from,
    required Offset to,
    PortSide fromSide = PortSide.right,
    PortSide toSide = PortSide.left,
    List<Offset> via = const <Offset>[],
    double curvature = defaultCurvature,
    double step = 4,
  }) {
    var best = RoutePoint(index: 0, position: from, distance: double.infinity);
    final route = segments(
      from,
      to,
      fromSide: fromSide,
      toSide: toSide,
      via: via,
      curvature: curvature,
    );
    for (final (index, segment) in route.indexed) {
      final path = Path()
        ..moveTo(segment.start.dx, segment.start.dy)
        ..cubicTo(
          segment.c1.dx,
          segment.c1.dy,
          segment.c2.dx,
          segment.c2.dy,
          segment.end.dx,
          segment.end.dy,
        );
      for (final metric in path.computeMetrics()) {
        final length = metric.length;
        if (length == 0) continue;
        final samples = math.max(2, (length / step).ceil());
        for (var i = 0; i <= samples; i++) {
          final position = metric
              .getTangentForOffset(length * i / samples)
              ?.position;
          if (position == null) continue;
          final distance = (position - point).distance;
          if (distance < best.distance) {
            best = RoutePoint(
              index: index,
              position: position,
              distance: distance,
            );
          }
        }
      }
    }
    return best;
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

/// One cubic of a connection's route, as [ConnectionPath.segments] builds it.
@immutable
class CubicSegment {
  const CubicSegment({
    required this.start,
    required this.c1,
    required this.c2,
    required this.end,
  });

  final Offset start;
  final Offset c1;
  final Offset c2;
  final Offset end;
}

/// The answer to [ConnectionPath.nearestOnRoute].
@immutable
class RoutePoint {
  const RoutePoint({
    required this.index,
    required this.position,
    required this.distance,
  });

  /// Where in the wire's waypoints a point here would be inserted: the index
  /// of the segment it lies on, which is also the number of waypoints before
  /// it.
  final int index;

  /// The closest point on the curve.
  final Offset position;

  /// How far the probe was from [position].
  final double distance;
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
