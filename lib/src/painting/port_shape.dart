import 'dart:ui';

/// Half the height of an equilateral triangle of unit circumradius.
const double _sin60 = 0.8660254037844386;

/// What a port's handle is drawn as.
///
/// A setting on [NodeEditorTheme](../theme/node_editor_theme.dart), chosen per
/// [PortKind](../model/node_port.dart), the way `connectionStyle` picks a
/// router for every wire at once — so a host that wants its control pins to
/// look like everything else says so once rather than reaching into a painter.
///
/// **The shapes are the package's and the meaning is the host's.** Nothing
/// here knows that a triangle tends to mean "the flow goes this way"; it knows
/// how to put one on a row. A host that uses control ports for something else
/// entirely picks whichever shape says that.
enum PortShape {
  /// A dot. What every handle was before shapes existed, and still the default
  /// for data.
  circle,

  /// A triangle lying on its side, pointing the way the wire leaves — right
  /// on an output, right on an input, so a row reads left to right whichever
  /// end you are looking at.
  triangle,

  /// A square on its corner. Distinct from a dot without claiming a direction
  /// the wire already shows.
  diamond;

  /// The outline of one handle of this shape, centred on [centre] at
  /// [radius] — the circumradius, so every shape sits in the same circle and
  /// a row of mixed shapes lines up.
  ///
  /// **A triangle points the same way at both ends of a wire**, rather than
  /// out of the node it is on. An input on the left pointing right is the
  /// flow arriving; an output on the right pointing right is the flow
  /// leaving — so a card reads in one direction, which is the thing the shape
  /// is for. Pointing each one away from its own node would put two triangles
  /// nose to nose on a single wire and say nothing about which way it runs.
  Path path(Offset centre, double radius) {
    switch (this) {
      case PortShape.circle:
        return Path()
          ..addOval(Rect.fromCircle(center: centre, radius: radius))
          ..close();
      case PortShape.triangle:
        // Grown a little, because a triangle inscribed in a circle covers
        // about a third of it and reads smaller than a dot of the same
        // radius beside it. Measured by eye against a row of both.
        final r = radius * 1.18;
        return Path()
          ..moveTo(centre.dx + r, centre.dy)
          ..lineTo(centre.dx - r * 0.5, centre.dy - r * _sin60)
          ..lineTo(centre.dx - r * 0.5, centre.dy + r * _sin60)
          ..close();
      case PortShape.diamond:
        final r = radius * 1.12;
        return Path()
          ..moveTo(centre.dx, centre.dy - r)
          ..lineTo(centre.dx + r, centre.dy)
          ..lineTo(centre.dx, centre.dy + r)
          ..lineTo(centre.dx - r, centre.dy)
          ..close();
    }
  }
}
