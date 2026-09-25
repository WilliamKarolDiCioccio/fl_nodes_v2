import 'dart:ui' show Offset;

/// Rounding onto the grid the canvas draws.
///
/// The grid has no phase. `grid.frag` takes `round(p / uSpacing)` about the
/// scene origin and `GridPainter._paintLines` walks `i * spacing` from it, so
/// a line stands wherever a scene coordinate is a multiple of the spacing and
/// the nearest one is a single `round` away. If the grid ever gains an origin
/// of its own, this is the only place that has to learn about it.
///
/// Public because a host that places a node itself — a drop, an arrangement of
/// its own — needs the same answer the canvas gives, and a second copy of this
/// is how the two start disagreeing about where a line is.
abstract final class GridSnap {
  /// [value] pulled onto the nearest multiple of [step].
  ///
  /// A [step] of zero or less is the identity, which is what lets a call site
  /// pass a step straight through instead of guarding it first. The rounding
  /// is symmetric about the origin — halves go away from zero either side —
  /// and `-0.0` is normalised away, since it survives arithmetic, compares
  /// equal to `0.0` and then serialises as itself.
  static double axis(double value, double step) {
    if (step <= 0) return value;
    return (value / step).roundToDouble() * step + 0.0;
  }

  /// [value] with each axis pulled onto the nearest multiple of [step].
  static Offset offset(Offset value, double step) =>
      Offset(axis(value.dx, step), axis(value.dy, step));
}
