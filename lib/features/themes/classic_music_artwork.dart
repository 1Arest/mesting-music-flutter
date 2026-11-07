import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 经典音乐空间的代码绘制背景。
///
/// 不依赖角色图片，在浅色与深色模式下都保留唱片、声波与柔光的音乐感。
class ClassicMusicArtwork extends StatelessWidget {
  const ClassicMusicArtwork({
    required this.dark,
    required this.accent,
    this.opacity = 1,
    super.key,
  });

  final bool dark;
  final Color accent;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final base = dark ? const Color(0xFF0B1020) : const Color(0xFFFFFBF4);
    final secondary = dark ? const Color(0xFF241B3F) : const Color(0xFFF2E9FF);
    return Opacity(
      opacity: opacity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [base, secondary, Color.lerp(secondary, accent, .18)!],
            stops: const [0, .56, 1],
          ),
        ),
        child: CustomPaint(
          painter: _ClassicArtworkPainter(dark: dark, accent: accent),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _ClassicArtworkPainter extends CustomPainter {
  const _ClassicArtworkPainter({required this.dark, required this.accent});

  final bool dark;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final shortest = math.min(size.width, size.height);
    final glow = Paint()
      ..shader =
          RadialGradient(
            colors: [
              accent.withValues(alpha: dark ? .25 : .19),
              accent.withValues(alpha: 0),
            ],
          ).createShader(
            Rect.fromCircle(
              center: Offset(size.width * .76, size.height * .22),
              radius: shortest * .52,
            ),
          );
    canvas.drawRect(Offset.zero & size, glow);

    final discCenter = Offset(size.width * .76, size.height * .31);
    final discRadius = shortest * .18;
    final disc = Paint()
      ..color = (dark ? const Color(0xFF060912) : const Color(0xFF283044))
          .withValues(alpha: dark ? .78 : .88);
    canvas.drawCircle(discCenter, discRadius, disc);
    final groove = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: dark ? .08 : .12);
    for (var ring = .34; ring < .94; ring += .12) {
      canvas.drawCircle(discCenter, discRadius * ring, groove);
    }
    canvas.drawCircle(
      discCenter,
      discRadius * .25,
      Paint()..color = accent.withValues(alpha: .88),
    );

    final wave = Path();
    final wavePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(1.4, shortest * .004)
      ..color = (dark ? Colors.white : const Color(0xFF353A52)).withValues(
        alpha: dark ? .20 : .18,
      );
    for (var row = 0; row < 4; row++) {
      wave.reset();
      for (var point = 0; point <= 40; point++) {
        final progress = point / 40;
        final x = size.width * (.06 + progress * .88);
        final y =
            size.height * (.58 + row * .065) +
            math.sin(progress * math.pi * (3.2 + row * .35)) *
                shortest *
                (.018 + row * .003);
        point == 0 ? wave.moveTo(x, y) : wave.lineTo(x, y);
      }
      canvas.drawPath(wave, wavePaint);
    }

    final barPaint = Paint()
      ..color = accent.withValues(alpha: dark ? .68 : .54);
    const heights = [.28, .52, .76, .44, .88, .63, .36, .70, .47];
    final barWidth = size.width * .018;
    for (var index = 0; index < heights.length; index++) {
      final height = shortest * .13 * heights[index];
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width * .08 + index * barWidth * 1.75,
          size.height * .84 - height,
          barWidth,
          height,
        ),
        Radius.circular(barWidth),
      );
      canvas.drawRRect(rect, barPaint);
    }

    final speck = Paint()
      ..color = (dark ? Colors.white : accent).withValues(alpha: .22);
    for (var index = 0; index < 18; index++) {
      final x = ((index * 47) % 97) / 97 * size.width;
      final y = ((index * 71) % 101) / 101 * size.height;
      canvas.drawCircle(Offset(x, y), 1.2 + index % 3, speck);
    }
  }

  @override
  bool shouldRepaint(covariant _ClassicArtworkPainter oldDelegate) =>
      oldDelegate.dark != dark || oldDelegate.accent != accent;
}
