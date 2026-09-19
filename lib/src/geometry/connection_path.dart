import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../model/node_port.dart';
import 'node_geometry.dart';
import 'orthogonal_route.dart';

/// How a wire is drawn between its two ports.
///
/// One choice for the whole canvas, on the theme: which is readable is a
/// question about the graph and the reader, not about one wire. The
/// waypoints mean the same thing under both — points the wire passes
/// through — so switching moves no data.
enum ConnectionStyle {
  /// A cubic bezier leaving and arriving along the port normals; through
  /// waypoints, a smooth run of them.
  curved,

  /// Axis-aligned legs with rounded corners; through waypoints, a corner at
  /// each. No obstacle avoidance: the waypoints are how a wire is taken
  /// around a card, and a horizontal leg under a card reads as a mistake
  /// where a bezier's swoop does not — which is why this is not the default.
  orthogonal,
}

/// Builds and probes the paths used for connections.
abstract final class ConnectionPath {
  /// Fraction of the endpoint distance used for the bezier control arms.
  static const double defaultCurvature = 0.5;

  /// How far an orthogonal wire runs straight out of a port before its
  /// first corner, in scene units.
  static const double defaultStub = 24;

  /// Radius of an orthogonal wire's corners, in scene units.
  static const double defaultCornerRadius = 8;

  /// The conic weight that makes a quarter turn a true circular arc.
  static const double _quarterArcWeight = 0.70710678;
  static const double minControlArm = 36;
  static const double maxControlArm = 220;

  /// The wire from [from] to [to] in [style] — or, with [via], through every
  /// point in it, in order — as one contour.
  ///
  /// Both points are in whatever space the caller is painting in — pass screen
  /// coordinates when painting, scene coordinates when hit-testing the model;
  /// [scale] then scales the arms, the stub and the corners with them.
  ///
  /// [via] are the points the wire is *routed through*, not bezier control
  /// points: the user places them on the wire and the geometry is solved
  /// from them. Curved, each waypoint takes the direction that bisects its
  /// two neighbours and each segment's arms are [controlArm] on that
  /// segment's own length — so the ends leave and arrive exactly as they
  /// would without any, and a wire with no waypoints is the very same curve
  /// as before. Orthogonal, each waypoint is a corner.
  static Path build(
    Offset from,
    Offset to, {
    PortSide fromSide = PortSide.right,
    PortSide toSide = PortSide.left,
    List<Offset> via = const <Offset>[],
    ConnectionStyle style = ConnectionStyle.curved,
    double curvature = defaultCurvature,
    double stub = defaultStub,
    double cornerRadius = defaultCornerRadius,
    double scale = 1.0,
  }) {
    switch (style) {
      case ConnectionStyle.curved:
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
          segment.appendTo(path);
        }
        return path;
      case ConnectionStyle.orthogonal:
        // Rounded over the whole run rather than span by span: the corner
        // at a waypoint has one leg in each span, and a span cannot round a
        // corner it only sees half of.
        final corners = <Offset>[from];
        for (final span in orthogonalSpans(
          from,
          to,
          fromSide: fromSide,
          toSide: toSide,
          via: via,
          stub: stub * scale,
        )) {
          corners.addAll(span.corners.skip(1));
        }
        return roundedPolyline(corners, radius: cornerRadius * scale);
    }
  }

  /// The route of an orthogonal wire, one span per consecutive pair of
  /// `[from, ...via, to]`, each span's corners running from its start to
  /// its end.
  ///
  /// Spans are routed in order because each one is told how the wire
  /// arrived at its start — a waypoint is a corner, and the router prefers
  /// to leave one across the axis it came in on.
  static List<PolylineSpan> orthogonalSpans(
    Offset from,
    Offset to, {
    PortSide fromSide = PortSide.right,
    PortSide toSide = PortSide.left,
    List<Offset> via = const <Offset>[],
    double stub = defaultStub,
  }) {
    final points = <Offset>[from, ...via, to];
    final last = points.length - 1;
    final spans = <PolylineSpan>[];
    Offset? incoming;
    for (var i = 0; i < last; i++) {
      final legs = OrthogonalRoute.legs(
        start: points[i],
        end: points[i + 1],
        startDirection: i == 0 ? NodeGeometry.normalOf(fromSide) : null,
        endDirection: i + 1 == last ? -NodeGeometry.normalOf(toSide) : null,
        incomingAxis: incoming,
        stub: stub,
      );
      spans.add(PolylineSpan(legs));
      incoming = legs.length >= 2
          ? legs[legs.length - 1] - legs[legs.length - 2]
          : null;
    }
    return spans;
  }

  /// [corners] joined by straight legs, each corner turned through a
  /// circular arc of [radius] — or less, where a leg is too short for one.
  static Path roundedPolyline(List<Offset> corners, {required double radius}) {
    final path = Path();
    if (corners.isEmpty) return path;
    path.moveTo(corners.first.dx, corners.first.dy);
    for (var i = 1; i < corners.length - 1; i++) {
      final prev = corners[i - 1];
      final corner = corners[i];
      final next = corners[i + 1];
      final inLeg = corner - prev;
      final outLeg = next - corner;
      final r = math.min(radius, math.min(inLeg.distance, outLeg.distance) / 2);
      if (r <= 0 || inLeg.distance == 0 || outLeg.distance == 0) {
        path.lineTo(corner.dx, corner.dy);
        continue;
      }
      final arcIn = corner - inLeg / inLeg.distance * r;
      final arcOut = corner + outLeg / outLeg.distance * r;
      path
        ..lineTo(arcIn.dx, arcIn.dy)
        ..conicTo(
          corner.dx,
          corner.dy,
          arcOut.dx,
          arcOut.dy,
          _quarterArcWeight,
        );
    }
    path.lineTo(corners.last.dx, corners.last.dy);
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

  /// The point of the segment `a`–`b` closest to [point].
  static Offset _projectOntoLeg(Offset point, Offset a, Offset b) {
    final leg = b - a;
    final lengthSquared = leg.distanceSquared;
    if (lengthSquared == 0) return a;
    final t =
        ((point - a).dx * leg.dx + (point - a).dy * leg.dy) / lengthSquared;
    return a + leg * t.clamp(0.0, 1.0);
  }

  static Offset _unit(Offset v) {
    final length = v.distance;
    return length == 0 ? Offset.zero : v / length;
  }

  /// Where a new waypoint dropped at [point] belongs on the route
  /// `[from, ...via, to]`: the closest point on the wire, and the index in
  /// [via] to insert it at so the wire still runs in order.
  ///
  /// Per span rather than over the whole path, because the index is the
  /// answer that matters and one contour cannot say which span a distance
  /// along it fell in. A click, not a frame — it walks the metrics of every
  /// span of one wire. A straight leg is projected onto exactly; a cubic is
  /// sampled every [step]. Orthogonal spans are probed unrounded, so at a
  /// corner the answer can sit a couple of pixels off the drawn arc.
  static RoutePoint nearestOnRoute(
    Offset point, {
    required Offset from,
    required Offset to,
    PortSide fromSide = PortSide.right,
    PortSide toSide = PortSide.left,
    List<Offset> via = const <Offset>[],
    ConnectionStyle style = ConnectionStyle.curved,
    double curvature = defaultCurvature,
    double stub = defaultStub,
    double step = 4,
  }) {
    var best = RoutePoint(index: 0, position: from, distance: double.infinity);
    final List<ConnectionSpan> route = switch (style) {
      ConnectionStyle.curved => segments(
        from,
        to,
        fromSide: fromSide,
        toSide: toSide,
        via: via,
        curvature: curvature,
      ),
      ConnectionStyle.orthogonal => orthogonalSpans(
        from,
        to,
        fromSide: fromSide,
        toSide: toSide,
        via: via,
        stub: stub,
      ),
    };
    for (final (index, span) in route.indexed) {
      if (span is PolylineSpan) {
        for (var i = 1; i < span.corners.length; i++) {
          final position = _projectOntoLeg(
            point,
            span.corners[i - 1],
            span.corners[i],
          );
          final distance = (position - point).distance;
          if (distance < best.distance) {
            best = RoutePoint(
              index: index,
              position: position,
              distance: distance,
            );
          }
        }
        continue;
      }
      final path = Path()..moveTo(span.start.dx, span.start.dy);
      span.appendTo(path);
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
  ///
  /// [axisAligned] squares each head to the nearer axis, for an orthogonal
  /// wire: a sample that lands on a corner's arc would otherwise take the
  /// arc's slant, and a head skewed forty degrees on a right-angled wire
  /// reads as a glitch.
  static List<PathArrow> arrowsAlong(
    Path path, {
    required double spacing,
    required int maxCount,
    bool axisAligned = false,
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
        final direction = axisAligned
            ? _squared(tangent.vector)
            : tangent.vector;
        arrows.add(PathArrow(tangent.position, direction));
      }
      return arrows;
    }
    return const <PathArrow>[];
  }

  static Offset _squared(Offset v) =>
      v.dx.abs() >= v.dy.abs() ? Offset(v.dx.sign, 0) : Offset(0, v.dy.sign);

  static Offset? midpoint(Path path) {
    for (final metric in path.computeMetrics()) {
      if (metric.length == 0) continue;
      return metric.getTangentForOffset(metric.length / 2)?.position;
    }
    return null;
  }
}

/// One span of a wire's route — from a port or a waypoint to the next.
///
/// What [ConnectionPath.nearestOnRoute] walks, in either style: it needs a
/// path per span and does not care what the span is made of.
sealed class ConnectionSpan {
  const ConnectionSpan();

  Offset get start;
  Offset get end;

  /// Draws the span onto [path], whose current point is [start].
  void appendTo(Path path);
}

/// One cubic of a curved route, as [ConnectionPath.segments] builds it.
@immutable
final class CubicSegment extends ConnectionSpan {
  const CubicSegment({
    required this.start,
    required this.c1,
    required this.c2,
    required this.end,
  });

  @override
  final Offset start;
  final Offset c1;
  final Offset c2;
  @override
  final Offset end;

  @override
  void appendTo(Path path) =>
      path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, end.dx, end.dy);
}

/// The legs of one span of an orthogonal route, as
/// [ConnectionPath.orthogonalSpans] builds it: [corners] runs from the
/// span's start to its end, every leg between two of them axis-aligned.
@immutable
final class PolylineSpan extends ConnectionSpan {
  const PolylineSpan(this.corners);

  final List<Offset> corners;

  @override
  Offset get start => corners.first;
  @override
  Offset get end => corners.last;

  /// Sharp corners: the rounding is done over the whole wire, since a corner
  /// at a waypoint has one leg in each of two spans.
  @override
  void appendTo(Path path) {
    for (final corner in corners.skip(1)) {
      path.lineTo(corner.dx, corner.dy);
    }
  }
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
