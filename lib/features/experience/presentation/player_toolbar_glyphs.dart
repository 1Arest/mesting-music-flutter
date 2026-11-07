import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/audio/playback_mode.dart';
import 'apple_audio_glyphs.dart';

enum PlayerToolbarTool { lyrics, output, queue }

/// Code-native vectors calibrated to the user's toolbar reference. The same
/// 40dp canvas gives every tool a stable optical center and a 48dp outer target.
/// Route metadata and playback state are supplied by the caller, not guessed
/// by this purely visual component.
class PlayerToolbarGlyph extends StatelessWidget {
  const PlayerToolbarGlyph({
    required this.tool,
    this.active = false,
    this.headphones = false,
    this.local = false,
    this.order = const PlaybackOrder(),
    super.key,
  });
  final PlayerToolbarTool tool;
  final bool active, headphones, local;
  final PlaybackOrder order;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CustomPaint(
      size: const Size.square(40),
      painter: _ToolbarPainter(tool, active, headphones, local, order),
    ),
  );
}

class _ToolbarPainter extends CustomPainter {
  _ToolbarPainter(
    this.tool,
    this.active,
    this.headphones,
    this.local,
    this.order,
  );
  final PlayerToolbarTool tool;
  final bool active, headphones, local;
  final PlaybackOrder order;
  static const ink = Color(0xFFB5C7D7);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 40, size.height / 40);
    final paint = Paint()
      ..isAntiAlias = true
      ..color = ink;
    if (active) {
      paint.color = const Color(0xFF93ADBF);
      canvas.drawCircle(const Offset(20, 20), 17, paint);
    }
    switch (tool) {
      case PlayerToolbarTool.lyrics:
        paint.color = active ? const Color(0xFF233C50) : ink;
        final bubble = Path()
          ..addRRect(
            RRect.fromRectAndRadius(
              const Rect.fromLTWH(11, 11, 18, 16),
              const Radius.circular(4.5),
            ),
          )
          ..moveTo(15, 25)
          ..lineTo(14, 30)
          ..lineTo(21, 25)
          ..close();
        canvas.drawPath(bubble, paint);
        paint.color = active ? ink : const Color(0xFF233C50);
        for (final x in [15.0, 21.0]) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(x, 15, 3.3, 4),
              const Radius.circular(1),
            ),
            paint,
          );
          canvas.drawPath(
            Path()
              ..moveTo(x + 3.3, 18)
              ..quadraticBezierTo(x + 3.3, 22, x, 22)
              ..lineTo(x, 20.4)
              ..quadraticBezierTo(x + 1.8, 20.4, x + 1.8, 18)
              ..close(),
            paint,
          );
        }
      case PlayerToolbarTool.output:
        // The device contours fill almost all of their native 40dp canvas;
        // lyrics/queue occupy about 22dp. Normalize optical size here, leaving
        // the larger output-card/list glyphs and the 48dp hit target alone.
        canvas.save();
        canvas.translate(8, 8);
        paintAppleAudioGlyph(
          canvas,
          const Size.square(24),
          local
              ? AppleAudioGlyphKind.phone
              : headphones
              ? AppleAudioGlyphKind.earphones
              : AppleAudioGlyphKind.route,
          ink,
        );
        canvas.restore();
      case PlayerToolbarTool.queue:
        paint
          ..color = ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8
          ..strokeCap = StrokeCap.round;
        for (final y in [14.0, 20.0, 26.0]) {
          canvas.drawCircle(Offset(9.3, y), .8, paint);
          canvas.drawLine(Offset(14, y), Offset(y == 14 ? 24 : 29, y), paint);
        }
        if (order.shuffle || order.repeat != PlaybackRepeat.off) {
          paint
            ..style = PaintingStyle.fill
            ..color = const Color(0xFF385369);
          canvas.drawCircle(const Offset(30, 10), 7.1, paint);
          paint
            ..color = ink
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.3;
          // Single-repeat owns the next-track behavior even while shuffle is
          // enabled. Do not hide its "1" behind the shuffle badge.
          if (order.shuffle && order.repeat != PlaybackRepeat.one) {
            canvas.drawPath(
              Path()
                ..moveTo(26, 7.3)
                ..cubicTo(29.5, 7.3, 30.2, 12.7, 34, 12.7)
                ..moveTo(26, 12.7)
                ..cubicTo(29.5, 12.7, 30.2, 7.3, 34, 7.3),
              paint,
            );
            canvas.drawPath(
              Path()
                ..moveTo(32.3, 5.8)
                ..lineTo(34, 7.3)
                ..lineTo(32.3, 8.7)
                ..moveTo(32.3, 11.3)
                ..lineTo(34, 12.7)
                ..lineTo(32.3, 14.1),
              paint,
            );
          } else {
            canvas.drawArc(
              const Rect.fromLTWH(26, 6.5, 8, 7),
              -.6,
              math.pi * .86,
              false,
              paint,
            );
            canvas.drawArc(
              const Rect.fromLTWH(26, 6.5, 8, 7),
              math.pi - .6,
              math.pi * .86,
              false,
              paint,
            );
            canvas.drawPath(
              Path()
                ..moveTo(33.8, 6.4)
                ..lineTo(34.1, 9)
                ..lineTo(31.5, 8.8)
                ..moveTo(26.2, 13.6)
                ..lineTo(25.9, 11)
                ..lineTo(28.5, 11.2),
              paint,
            );
            if (order.repeat == PlaybackRepeat.one) {
              canvas.drawLine(
                const Offset(30, 8.3),
                const Offset(30, 11.6),
                paint,
              );
            }
          }
        }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ToolbarPainter old) =>
      tool != old.tool ||
      active != old.active ||
      headphones != old.headphones ||
      local != old.local ||
      order != old.order;
}
