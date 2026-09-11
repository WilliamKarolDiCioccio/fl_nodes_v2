import 'package:flutter/widgets.dart';

/// The two short diagonal strokes that mark a corner as something to drag.
///
/// One drawing for the minimap panel and for a node, so a person who has
/// found one knows the other. The minimap owns its gesture; a node's grip
/// takes none — see `NodeView.onResizeStart` for why — so the painter is the
/// shared part and the widget is only a square of it.
class CornerGrip extends StatelessWidget {
  const CornerGrip({super.key, required this.color});

  /// The square the strokes sit in, and the size of the corner that resizes.
  static const double size = 14;

  final Color color;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size.square(size),
    painter: CornerGripPainter(color),
  );
}

class CornerGripPainter extends CustomPainter {
  const CornerGripPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    for (final inset in <double>[3, 7]) {
      canvas.drawLine(
        Offset(size.width - 2, size.height - inset),
        Offset(size.width - inset, size.height - 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(CornerGripPainter old) => old.color != color;
}
