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
    // Start just above the cleft, follow the left lobe and pointed bottom,
    // and stop on the right shoulder. The two rounded ends stay separated.
    final outline = Path()
      ..moveTo(18.1, 5.1)
      ..cubicTo(16.4, 5.1, 14.8, 6.2, 13.7, 7.7)
      ..cubicTo(10.3, 2.5, 2.0, 3.4, 2.0, 10.2)
      ..cubicTo(2.0, 15.5, 8.3, 20.6, 13.7, 24.5)
      ..cubicTo(18.4, 21.1, 24.2, 16.3, 25.2, 11.8);
    if (selected) {
      // The same opening becomes a shallow bite in the filled red lobe.
      final filled = Path.from(outline)
        ..cubicTo(25.4, 10.9, 25.4, 10.0, 25.2, 9.2)
        ..lineTo(20.2, 9.2)
        ..quadraticBezierTo(18.1, 9.2, 18.1, 7.1)
        ..close();
      canvas.drawPath(filled, Paint()..color = color);
    } else {
      canvas.drawPath(
        outline,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.65
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
