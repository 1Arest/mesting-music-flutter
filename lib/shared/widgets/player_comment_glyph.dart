import 'package:flutter/material.dart';

/// Authored circular quotation bubble shared with the interactive guide.
void paintPlayerCommentGlyph(Canvas canvas, Rect bounds, Color color) {
  // Same text-free outline bubble as playlist, song and MV comment entries.
  final rect = bounds.deflate(bounds.width * .12);
  final paint = Paint()
    ..isAntiAlias = true
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = bounds.width * .065
    ..strokeJoin = StrokeJoin.round;
  final path = Path()
    ..moveTo(rect.left, rect.top)
    ..lineTo(rect.right, rect.top)
    ..lineTo(rect.right, rect.bottom * .82)
    ..lineTo(rect.left + rect.width * .27, rect.bottom * .82)
    ..lineTo(rect.left, rect.bottom)
    ..close();
  canvas.drawPath(path, paint);
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
