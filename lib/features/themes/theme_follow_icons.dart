import 'package:flutter/material.dart';

enum ThemeFollowIconKind { progressStyle, progressCharacter }

class ThemeFollowIcon extends StatelessWidget {
  const ThemeFollowIcon({required this.kind, super.key});

  final ThemeFollowIconKind kind;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final iconKey = switch (kind) {
      ThemeFollowIconKind.progressStyle => const ValueKey(
        'follow-theme-progress-style-icon',
      ),
      ThemeFollowIconKind.progressCharacter => const ValueKey(
        'follow-theme-progress-character-icon',
      ),
    };
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: CustomPaint(
          key: iconKey,
          size: const Size.square(28),
          painter: switch (kind) {
            ThemeFollowIconKind.progressStyle => _ThemeSwatchPainter(dark),
            ThemeFollowIconKind.progressCharacter => _TrackCompanionPainter(
              dark,
            ),
          },
        ),
      ),
    );
  }
}

abstract class _ThemeFollowIconPainter extends CustomPainter {
  const _ThemeFollowIconPainter(this.dark);

  final bool dark;

  Rect iconBounds(Size size) => Offset.zero & size;

  RRect iconSurface(Size size) => RRect.fromRectAndRadius(
    iconBounds(size).deflate(.7),
    Radius.circular(size.shortestSide * .31),
  );

  void paintSurface(Canvas canvas, Size size) {
    final bounds = iconBounds(size);
    final surface = iconSurface(size);
    canvas.drawRRect(
      surface,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? const [Color(0xFF29223D), Color(0xFF151D2C)]
              : const [Color(0xFFF6F1FF), Color(0xFFEAF8FA)],
        ).createShader(bounds),
    );
    canvas.drawRRect(
      surface,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = .8
        ..color = dark ? const Color(0x3DFFFFFF) : const Color(0x246D5EEA),
    );
  }

  @override
  bool shouldRepaint(covariant _ThemeFollowIconPainter oldDelegate) {
    return oldDelegate.dark != dark || oldDelegate.runtimeType != runtimeType;
  }
}

class _ThemeSwatchPainter extends _ThemeFollowIconPainter {
  const _ThemeSwatchPainter(super.dark);

  @override
  void paint(Canvas canvas, Size size) {
    paintSurface(canvas, size);
    final scale = size.shortestSide / 28;
    final pivot = Offset(8.8 * scale, 21 * scale);
    final swatches = <({double angle, Color start, Color end})>[
      (
        angle: -.52,
        start: const Color(0xFF8296F2),
        end: const Color(0xFF4A86D8),
      ),
      (
        angle: -.18,
        start: const Color(0xFF8F73F4),
        end: const Color(0xFF6D5EEA),
      ),
      (
        angle: .18,
        start: const Color(0xFF48C8C2),
        end: const Color(0xFF55A8E8),
      ),
    ];

    for (final swatch in swatches) {
      canvas.save();
      canvas.translate(pivot.dx, pivot.dy);
      canvas.rotate(swatch.angle);
      final rect = Rect.fromLTWH(
        -2.4 * scale,
        -16.1 * scale,
        10.4 * scale,
        17.3 * scale,
      );
      final card = RRect.fromRectAndRadius(rect, Radius.circular(3.1 * scale));
      canvas.drawRRect(
        card,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [swatch.start, swatch.end],
          ).createShader(rect),
      );
      canvas.drawRRect(
        card,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = .7 * scale
          ..color = Colors.white.withValues(alpha: dark ? .42 : .72),
      );
      canvas.drawCircle(
        Offset(2.8 * scale, -11.6 * scale),
        .9 * scale,
        Paint()..color = Colors.white.withValues(alpha: .72),
      );
      canvas.restore();
    }

    canvas.drawCircle(
      pivot,
      2.25 * scale,
      Paint()..color = dark ? const Color(0xFF17151F) : Colors.white,
    );
    canvas.drawCircle(
      pivot,
      2.25 * scale,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = .8 * scale
        ..color = const Color(0xFF6557D7),
    );

    final sparkle = Path()
      ..moveTo(22.2 * scale, 3.8 * scale)
      ..lineTo(23.15 * scale, 6.15 * scale)
      ..lineTo(25.5 * scale, 7.1 * scale)
      ..lineTo(23.15 * scale, 8.05 * scale)
      ..lineTo(22.2 * scale, 10.4 * scale)
      ..lineTo(21.25 * scale, 8.05 * scale)
      ..lineTo(18.9 * scale, 7.1 * scale)
      ..lineTo(21.25 * scale, 6.15 * scale)
      ..close();
    canvas.drawPath(
      sparkle,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF8EA0F2), Color(0xFF7A68EB)],
        ).createShader(iconBounds(size)),
    );
  }
}

class _TrackCompanionPainter extends _ThemeFollowIconPainter {
  const _TrackCompanionPainter(super.dark);

  @override
  void paint(Canvas canvas, Size size) {
    paintSurface(canvas, size);
    final scale = size.shortestSide / 28;
    final bounds = iconBounds(size);

    final rearTrack = Path()
      ..moveTo(3.2 * scale, 19.8 * scale)
      ..cubicTo(
        7.2 * scale,
        14.4 * scale,
        11 * scale,
        21.7 * scale,
        15.2 * scale,
        18.4 * scale,
      )
      ..cubicTo(
        19.1 * scale,
        15.4 * scale,
        21.5 * scale,
        17.2 * scale,
        24.8 * scale,
        13.7 * scale,
      );
    canvas.drawPath(
      rearTrack,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.2 * scale
        ..strokeCap = StrokeCap.round
        ..shader = const LinearGradient(
          colors: [Color(0x556D5EEA), Color(0x5548C8C2)],
        ).createShader(bounds),
    );
    canvas.drawPath(
      rearTrack,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.15 * scale
        ..strokeCap = StrokeCap.round
        ..shader = const LinearGradient(
          colors: [Color(0xFF8D72F1), Color(0xFF4FC8C2)],
        ).createShader(bounds),
    );

    canvas.drawCircle(
      Offset(3.45 * scale, 19.65 * scale),
      1.35 * scale,
      Paint()..color = const Color(0xFF8D72F1),
    );
    canvas.drawCircle(
      Offset(24.65 * scale, 13.85 * scale),
      1.35 * scale,
      Paint()..color = const Color(0xFF4FC8C2),
    );

    final bodyBounds = Rect.fromLTWH(
      8.2 * scale,
      11.8 * scale,
      11.6 * scale,
      11.2 * scale,
    );
    final body = Path()
      ..moveTo(8.8 * scale, 22.1 * scale)
      ..cubicTo(
        9.4 * scale,
        17.1 * scale,
        11.1 * scale,
        15.5 * scale,
        14 * scale,
        15.5 * scale,
      )
      ..cubicTo(
        16.9 * scale,
        15.5 * scale,
        18.6 * scale,
        17.1 * scale,
        19.2 * scale,
        22.1 * scale,
      )
      ..cubicTo(
        16.9 * scale,
        23.3 * scale,
        11.1 * scale,
        23.3 * scale,
        8.8 * scale,
        22.1 * scale,
      )
      ..close();
    canvas.drawPath(
      body,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF8D72F1), Color(0xFF4FBBDD)],
        ).createShader(bodyBounds),
    );
    canvas.drawPath(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = .7 * scale
        ..color = Colors.white.withValues(alpha: .64),
    );

    final headCenter = Offset(14 * scale, 10.2 * scale);
    canvas.drawCircle(
      headCenter,
      3.65 * scale,
      Paint()
        ..shader =
            const RadialGradient(
              center: Alignment(-.25, -.3),
              colors: [Color(0xFFDDEBFF), Color(0xFF8EA0F2)],
            ).createShader(
              Rect.fromCircle(center: headCenter, radius: 3.65 * scale),
            ),
    );
    canvas.drawCircle(
      headCenter,
      3.65 * scale,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = .7 * scale
        ..color = Colors.white.withValues(alpha: .72),
    );

    final beatPaint = Paint()
      ..color = dark ? const Color(0xBFFFFFFF) : const Color(0xB93D3751)
      ..strokeWidth = 1.15 * scale
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(21.4 * scale, 5.1 * scale),
      Offset(21.4 * scale, 8.2 * scale),
      beatPaint,
    );
    canvas.drawLine(
      Offset(24 * scale, 3.8 * scale),
      Offset(24 * scale, 8.2 * scale),
      beatPaint,
    );
  }
}
