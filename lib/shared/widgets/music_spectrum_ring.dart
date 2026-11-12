import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/audio/music_rhythm.dart';

final _directions = List.generate(72, (index) {
  final angle = index * math.pi * 2 / 72 - math.pi / 2;
  return Offset(math.cos(angle), math.sin(angle));
}, growable: false);

/// Mirror the frequency range so the low end meets cleanly at the top.
/// Loudness sets the expansion and independent bands shape the contour.
void paintMusicSpectrumRing(
  Canvas canvas, {
  required Offset center,
  required double radius,
  required double reach,
  required double stroke,
  required MusicRhythmFrame frame,
}) {
  if (radius <= 0) return;
  final active = frame.available && frame.level > .015;
  final paint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = stroke
    ..color = const Color(0xFF97D9DD).withValues(alpha: active ? .48 : .7);
  canvas.drawCircle(center, radius, paint);
  if (!active) return;

  final points = List<Offset>.generate(_directions.length, (index) {
    final progress = index / _directions.length;
    final band = 1 - (2 * progress - 1).abs();
    final energy =
        .22 * frame.level +
        .60 * frame.bandAt(band) +
        .18 * frame.pulse * (1 - band);
    return center + _directions[index] * (radius + reach * energy);
  }, growable: false);
  final first = (points.last + points.first) / 2;
  final contour = Path()..moveTo(first.dx, first.dy);
  for (var i = 0; i < points.length; i++) {
    final p = points[i];
    final middle = (p + points[(i + 1) % points.length]) / 2;
    contour.quadraticBezierTo(p.dx, p.dy, middle.dx, middle.dy);
  }
  contour.close();
  final bounds = Rect.fromCircle(center: center, radius: radius + reach);
  canvas.drawPath(
    contour,
    paint
      ..strokeWidth = stroke * 3.2
      ..color = const Color(
        0xFF75DED7,
      ).withValues(alpha: .12 + frame.pulse * .16),
  );
  canvas.drawPath(
    contour,
    paint
      ..strokeWidth = stroke * (1.35 + frame.peak * .35)
      ..color = Colors.white
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFBFB3FF), Color(0xFF6BE6D3), Color(0xFF91BFFF)],
      ).createShader(bounds),
  );
}
