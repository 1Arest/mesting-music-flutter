import 'package:flutter/material.dart';

/// Authored circular quotation bubble shared with the interactive guide.
void paintPlayerCommentGlyph(Canvas canvas, Rect bounds, Color color) {
  canvas.save();
  canvas.translate(bounds.left, bounds.top);
  canvas.scale(bounds.width / 32, bounds.height / 32);
  final fill = Paint()
    ..isAntiAlias = true
    ..color = color;
  canvas.drawCircle(const Offset(16, 16), 15, fill);
  fill.color = const Color(0xFF24292D);
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      const Rect.fromLTWH(8, 8, 17, 14),
      const Radius.circular(5),
    ),
    fill,
  );
  canvas.drawPath(
    Path()
      ..moveTo(12, 20)
      ..lineTo(11, 26)
      ..lineTo(18, 21)
      ..close(),
    fill,
  );
  fill.color = color;
  for (final x in [12.0, 18.0]) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x, 12, 3, 4),
        const Radius.circular(1),
      ),
      fill,
    );
    canvas.drawPath(
      Path()
        ..moveTo(x + 3, 15)
        ..quadraticBezierTo(x + 3, 19, x, 19)
        ..lineTo(x, 17)
        ..quadraticBezierTo(x + 1, 17, x + 1, 15)
        ..close(),
      fill,
    );
  }
  canvas.restore();
}

class PlayerCommentGlyph extends StatelessWidget {
  const PlayerCommentGlyph({
    this.size = 29,
    this.color = const Color(0xFFD3D5D6),
    super.key,
  });
  final double size;
  final Color color;
  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _GlyphPainter(color));
}

class _GlyphPainter extends CustomPainter {
  _GlyphPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) =>
      paintPlayerCommentGlyph(canvas, Offset.zero & size, color);
  @override
  bool shouldRepaint(_GlyphPainter old) => color != old.color;
}
