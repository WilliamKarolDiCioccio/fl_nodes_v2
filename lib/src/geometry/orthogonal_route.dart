import 'dart:math' as math;
import 'dart:ui';

/// Where a wire runs when it is drawn in right angles: the corners of one
/// span, from a port or a waypoint to the next.
///
/// Templates rather than a search. Between the two ends there are only so
/// many shapes an axis-aligned wire can take without a detour — an L either
/// way round, a Z either way round, and the Z again with its middle leg
/// pushed out to a lane beyond both ends for the cases where it has to come
/// back on itself — and the right one is the shortest of those that never
/// double back. A grid search would route around cards this cannot see, and
/// costs a grid; the waypoints are what the user routes around cards with.
abstract final class OrthogonalRoute {
  /// The corners of one span, [start] first and [end] last, with no two
  /// consecutive legs pointing opposite ways.
  ///
  /// A port end leaves or arrives along its normal: [startDirection] is the
  /// unit axis the wire must set off along, [endDirection] the one it must
  /// arrive along, and each puts a leg of [stub] on its side before the
  /// templates begin — a wire that turned on the port's own edge would read
  /// as leaving from the wrong side. Null at a waypoint, which has no side.
  ///
  /// [incomingAxis] is how the wire arrived at a free [start], and it tips
  /// the choice toward setting off *across* it: a waypoint is a corner the
  /// user placed, and a wire that ran straight through one and turned
  /// somewhere else would be turning where nobody asked it to.
  static List<Offset> legs({
    required Offset start,
    required Offset end,
    Offset? startDirection,
    Offset? endDirection,
    Offset? incomingAxis,
    required double stub,
  }) {
    final s = startDirection == null ? start : start + startDirection * stub;
    final e = endDirection == null ? end : end - endDirection * stub;

    final midX = (s.dx + e.dx) / 2;
    final midY = (s.dy + e.dy) / 2;
    // The lanes a Z's middle leg may run down: through the middle, level
    // with either end, and a stub's clearance past either end. The last two
    // are for a wire that has to come back on itself along its own row —
    // every other lane then lies on that row and doubles back with it.
    final lanesX = <double>[
      math.min(s.dx, e.dx),
      math.max(s.dx, e.dx),
      math.min(s.dx, e.dx) - stub,
      math.max(s.dx, e.dx) + stub,
    ];
    final lanesY = <double>[
      math.min(s.dy, e.dy),
      math.max(s.dy, e.dy),
      math.min(s.dy, e.dy) - stub,
      math.max(s.dy, e.dy) + stub,
    ];

    // In the order they win a tie: a Z through the middle is the wire every
    // editor draws between two facing ports, and beats the L that would put
    // its one corner against a port.
    final templates = <List<Offset>>[
      <Offset>[Offset(midX, s.dy), Offset(midX, e.dy)],
      <Offset>[Offset(s.dx, midY), Offset(e.dx, midY)],
      <Offset>[Offset(e.dx, s.dy)],
      <Offset>[Offset(s.dx, e.dy)],
      for (final x in lanesX) <Offset>[Offset(x, s.dy), Offset(x, e.dy)],
      for (final y in lanesY) <Offset>[Offset(s.dx, y), Offset(e.dx, y)],
    ];

    _Candidate? best;
    for (final (priority, interior) in templates.indexed) {
      final route = _tidy(<Offset>[start, s, ...interior, e, end]);
      if (_doublesBack(route)) continue;
      final candidate = _Candidate(
        route,
        corners: _corners(route),
        length: _length(route),
        turns: incomingAxis == null || _turnsAcross(route, incomingAxis),
        priority: priority,
      );
      if (best == null || candidate.beats(best)) best = candidate;
    }
    // The clearance lanes always survive the U-turn filter, so the field is
    // never empty; the fallback is for the reader, not the compiler.
    return best?.route ?? _tidy(<Offset>[start, s, e, end]);
  }

  /// Drops zero-length legs and the middle of any three collinear points.
  static List<Offset> _tidy(List<Offset> points) {
    final out = <Offset>[];
    for (final point in points) {
      if (out.isNotEmpty && _near(out.last, point)) continue;
      if (out.length >= 2) {
        final a = out[out.length - 2];
        final b = out.last;
        if (_axisOf(b - a) == _axisOf(point - b) &&
            _sameWay(b - a, point - b)) {
          out.removeLast();
        }
      }
      out.add(point);
    }
    return out;
  }

  static bool _doublesBack(List<Offset> route) {
    for (var i = 2; i < route.length; i++) {
      final a = route[i - 1] - route[i - 2];
      final b = route[i] - route[i - 1];
      if (_axisOf(a) == _axisOf(b) && !_sameWay(a, b)) return true;
    }
    return false;
  }

  static int _corners(List<Offset> route) => math.max(0, route.length - 2);

  static double _length(List<Offset> route) {
    var total = 0.0;
    for (var i = 1; i < route.length; i++) {
      total += (route[i] - route[i - 1]).distance;
    }
    return total;
  }

  static bool _turnsAcross(List<Offset> route, Offset incomingAxis) =>
      route.length < 2 || _axisOf(route[1] - route[0]) != _axisOf(incomingAxis);

  static bool _near(Offset a, Offset b) => (a - b).distanceSquared < 1e-6;

  /// 0 for horizontal, 1 for vertical. A leg is one or the other by
  /// construction; a diagonal would be a bug upstream.
  static int _axisOf(Offset v) => v.dx.abs() >= v.dy.abs() ? 0 : 1;

  static bool _sameWay(Offset a, Offset b) => a.dx * b.dx + a.dy * b.dy > 0;
}

class _Candidate {
  const _Candidate(
    this.route, {
    required this.corners,
    required this.length,
    required this.turns,
    required this.priority,
  });

  final List<Offset> route;
  final int corners;
  final double length;
  final bool turns;
  final int priority;

  bool beats(_Candidate other) {
    if (corners != other.corners) return corners < other.corners;
    if ((length - other.length).abs() > 1e-6) return length < other.length;
    if (turns != other.turns) return turns;
    return priority < other.priority;
  }
}
