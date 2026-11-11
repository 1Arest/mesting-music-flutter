import 'package:flutter/material.dart';

/// A heart with an upper-right opening reserved for its adjacent count.
/// Painted directly so the silhouette does not vary with the system icon font.
class NotchedFavoriteHeart extends StatelessWidget {
  const NotchedFavoriteHeart({
    required this.selected,
    required this.color,
    required this.size,
    super.key,
  });
  final bool selected;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(painter: _HeartPainter(selected, color)),
  );
}

class _HeartPainter extends CustomPainter {
  const _HeartPainter(this.selected, this.color);
  final bool selected;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 28, size.height / 28);
    // Traced from the supplied enlarged reference: shallow cleft, rounded
    // lower tip and an inward curved shoulder beside the upper-right count.
    final outline = Path()
      ..moveTo(18.4, 1.2)
      ..cubicTo(16.8, .5, 15.3, 1.8, 14.0, 2.1)
      ..cubicTo(9.6, .1, 4.4, 1.0, 1.9, 5.5)
      ..cubicTo(-.4, 9.2, .8, 15.2, 4.7, 20.0)
      ..cubicTo(7.1, 23.0, 10.4, 25.5, 12.8, 26.8)
      ..quadraticBezierTo(13.7, 27.5, 14.8, 26.8)
      ..cubicTo(21.7, 22.3, 26.5, 16.5, 27.0, 12.5);
    if (selected) {
      final filled = Path.from(outline)
        ..cubicTo(22.6, 12.8, 18.2, 12.5, 18.2, 7.4)
        ..cubicTo(18.0, 5.0, 18.2, 2.9, 18.4, 1.2)
        ..close();
      canvas.drawPath(filled, Paint()..color = color);
    } else {
      canvas.drawPath(
        outline,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.25
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_HeartPainter old) =>
      old.selected != selected || old.color != color;
}
