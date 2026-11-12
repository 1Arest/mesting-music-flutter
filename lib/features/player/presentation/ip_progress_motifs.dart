import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../themes/music_theme_preset.dart';

/// Small silhouettes extend beyond the rail while staying inside its horizontal
/// bounds. Positions are anchored to the complete track, so seeking reveals
/// motifs without making them slide or bunch up. The slider owns all gestures.
void paintIpProgressMotifs(
  Canvas canvas, {
  required MusicThemeIp ip,
  required Rect track,
  required Rect active,
  required TextDirection direction,
}) {
  if (active.width < 2 ||
      !switch (ip) {
        MusicThemeIp.classic || MusicThemeIp.shinchan => false,
        _ => true,
      }) {
    return;
  }
  canvas.save();
  canvas.clipRect(
    Rect.fromLTRB(
      active.left,
      track.center.dy - 10,
      active.right,
      track.center.dy + 10,
    ),
  );
  final centerY = track.center.dy;
  // Decorative rail treatments supplement each IP's distinct silhouette.
  if (ip == MusicThemeIp.myMelody) {
    final seam = Paint()
      ..color = Colors.white.withValues(alpha: .65)
      ..strokeWidth = .7;
    canvas.drawLine(
      Offset(active.left, centerY - 1.8),
      Offset(active.right, centerY - 1.8),
      seam,
    );
    canvas.drawLine(
      Offset(active.left, centerY + 1.8),
      Offset(active.right, centerY + 1.8),
      seam,
    );
  }
  if (ip == MusicThemeIp.hachiware) {
    canvas.save();
    canvas.clipRect(active);
    final stripe = Paint()
      ..color = Colors.white.withValues(alpha: .42)
      ..strokeWidth = 2;
    for (var distance = 8.0; distance < track.width; distance += 12) {
      final x = direction == TextDirection.ltr
          ? track.left + distance
          : track.right - distance;
      canvas.drawLine(
        Offset(x - 2, centerY + 3),
        Offset(x + 2, centerY - 3),
        stripe,
      );
    }
    canvas.restore();
  }
  var index = 0;
  for (double distance = 20; distance < track.width - 8; distance += 46) {
    final x = direction == TextDirection.ltr
        ? track.left + distance
        : track.right - distance;
    if (x + 10 < active.left || x - 10 > active.right) {
      index++;
      continue;
    }
    canvas.save();
    canvas.translate(x, centerY);
    switch (ip) {
      case MusicThemeIp.helloKitty:
        _kittyBow(canvas);
      case MusicThemeIp.kuromi:
        index.isEven ? _kuromiSkull(canvas) : _kuromiDiamond(canvas);
      case MusicThemeIp.myMelody:
        _bow(canvas);
      case MusicThemeIp.cinnamoroll:
        _cloud(canvas);
      case MusicThemeIp.chiikawa:
        _mochi(canvas);
      case MusicThemeIp.hachiware:
        index.isEven ? _catEars(canvas) : _fish(canvas);
      case MusicThemeIp.usagi:
        index.isEven ? _rabbitEars(canvas) : _carrot(canvas);
      case MusicThemeIp.puppyWhite:
        _paw(canvas, const Color(0xFFFDFEFF), const Color(0xFF718692));
      case MusicThemeIp.puppyGray:
        index.isEven
            ? _bone(canvas)
            : _paw(canvas, const Color(0xFFFFE9BB), const Color(0xFF9D754B));
      case MusicThemeIp.sleepingKirby:
        if (index % 3 == 0) {
          _crescent(canvas);
        } else {
          _star(
            canvas,
            index.isEven ? const Color(0xFFFFE57D) : const Color(0xFFEAFAFF),
          );
        }
      default:
        break;
    }
    canvas.restore();
    index++;
  }
  canvas.restore();
}

void _shape(Canvas c, Path path, Color color, Color border) {
  c.drawPath(path, Paint()..color = color);
  c.drawPath(
    path,
    Paint()
      ..color = border
      ..strokeWidth = .8
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke,
  );
}

void _oval(Canvas c, Rect rect, Color color, {Color? border}) {
  c.drawOval(rect, Paint()..color = color);
  if (border != null) {
    c.drawOval(
      rect,
      Paint()
        ..color = border
        ..strokeWidth = .7
        ..style = PaintingStyle.stroke,
    );
  }
}

void _bow(Canvas c) {
  const edge = Color(0xFFC74888);
  final loops = Path()
    ..moveTo(0, 0)
    ..cubicTo(-9, -8, -10, 8, 0, 1)
    ..cubicTo(10, 8, 9, -8, 0, 0)
    ..close();
  final tails = Path()
    ..moveTo(-1, 1)
    ..lineTo(-4, 6)
    ..lineTo(0, 4)
    ..lineTo(3, 6)
    ..lineTo(2, 1)
    ..close();
  _shape(c, tails, const Color(0xFFFFC5DE), edge);
  _shape(c, loops, const Color(0xFFFFEDF5), edge);
  _oval(
    c,
    const Rect.fromLTWH(-1.7, -1.7, 3.4, 3.4),
    const Color(0xFFF18DB9),
    border: edge,
  );
}

void _kittyBow(Canvas c) {
  // Rounded red loops and a round knot echo Kitty's original head bow.
  // Unlike Melody's ribbon, this bow has no hanging tails.
  const red = Color(0xFFEE3155);
  const edge = Color(0xFFA92B45);
  final loops = Path()
    ..moveTo(-.8, 0)
    ..cubicTo(-9, -9, -10, 9, -.8, 1)
    ..lineTo(.8, 1)
    ..cubicTo(10, 9, 9, -9, .8, 0)
    ..close();
  // A pale rim separates the red bow from the red track at small sizes.
  c.drawPath(
    loops,
    Paint()
      ..color = const Color(0xFFFFE7EC)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeJoin = StrokeJoin.round,
  );
  _shape(c, loops, red, edge);
  _oval(c, const Rect.fromLTWH(-2, -2.1, 4, 4.2), red, border: edge);
  c.drawLine(
    const Offset(-5.7, -2),
    const Offset(-4, -2.7),
    Paint()
      ..color = const Color(0xFFFFA6B9)
      ..strokeWidth = .8
      ..strokeCap = StrokeCap.round,
  );
}

void _kuromiSkull(Canvas c) {
  const pink = Color(0xFFFFA0CE);
  const ink = Color(0xFF503454);
  final skull = Path()
    ..moveTo(-3.6, 1.8)
    ..cubicTo(-8.8, -5.8, 8.8, -5.8, 3.6, 1.8)
    ..lineTo(3.6, 5.4)
    ..lineTo(1.6, 5.4)
    ..lineTo(1.6, 3.2)
    ..lineTo(.7, 3.2)
    ..lineTo(.7, 5.4)
    ..lineTo(-.7, 5.4)
    ..lineTo(-.7, 3.2)
    ..lineTo(-1.6, 3.2)
    ..lineTo(-1.6, 5.4)
    ..lineTo(-3.6, 5.4)
    ..close();
  _shape(c, skull, pink, ink);
  for (final mirror in [-1.0, 1.0]) {
    final eye = Path()
      ..moveTo(mirror * 3.7, -1.8)
      ..quadraticBezierTo(mirror * 3, 1.6, mirror * 1.2, -.2)
      ..close();
    c.drawPath(eye, Paint()..color = ink);
  }
}

void _kuromiDiamond(Canvas c) {
  final diamond = Path()
    ..moveTo(0, -5)
    ..lineTo(4, 0)
    ..lineTo(0, 5)
    ..lineTo(-4, 0)
    ..close();
  _shape(c, diamond, const Color(0xFF52365E), const Color(0xFFF9A3D3));
  c.drawLine(
    const Offset(-1.7, -.5),
    const Offset(0, -2.8),
    Paint()
      ..color = const Color(0xFFBD91D2)
      ..strokeWidth = .8
      ..strokeCap = StrokeCap.round,
  );
}

void _cloud(Canvas c) {
  final p = Path()
    ..moveTo(-7, 2)
    ..cubicTo(-12, 0, -8, -6, -4, -4)
    ..cubicTo(-3, -9, 5, -8, 5, -3)
    ..cubicTo(11, -5, 12, 3, 6, 3)
    ..lineTo(-7, 3)
    ..close();
  _shape(c, p, const Color(0xFFF8FDFF), const Color(0xFF68B9DA));
  c.drawArc(
    const Rect.fromLTWH(-5, 2, 9, 6),
    0,
    math.pi * .9,
    false,
    Paint()
      ..color = const Color(0xFFCDF1FC)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1,
  );
}

void _mochi(Canvas c) {
  final p = Path()
    ..moveTo(-7, 3)
    ..cubicTo(-10, -9, 10, -9, 7, 3)
    ..quadraticBezierTo(0, 5, -7, 3)
    ..close();
  _shape(c, p, const Color(0xFFFFF9EF), const Color(0xFFD8999D));
  final cheek = Paint()
    ..color = const Color(0xFFF2A9B5)
    ..strokeWidth = 1
    ..strokeCap = StrokeCap.round;
  for (final x in [-4.5, -2.7, 2.7, 4.5]) {
    c.drawLine(Offset(x - .3, 0), Offset(x + .3, -1.5), cheek);
  }
}

void _catEars(Canvas c) {
  final p = Path()
    ..moveTo(-6, 2)
    ..lineTo(-6, -6)
    ..lineTo(-1, -2)
    ..lineTo(1, -2)
    ..lineTo(6, -6)
    ..lineTo(6, 2)
    ..close();
  _shape(c, p, const Color(0xFFE7F5FF), const Color(0xFF4C8CC2));
  final blue = Path()
    ..moveTo(-6, -6)
    ..lineTo(-1, -2)
    ..lineTo(-6, -1)
    ..close()
    ..moveTo(6, -6)
    ..lineTo(1, -2)
    ..lineTo(6, -1)
    ..close();
  c.drawPath(blue, Paint()..color = const Color(0xFF84BCE4));
}

void _fish(Canvas c) {
  const color = Color(0xFFF1FBFF);
  final p = Path()
    ..moveTo(5, 0)
    ..quadraticBezierTo(0, -6, -5, 0)
    ..quadraticBezierTo(0, 6, 5, 0)
    ..lineTo(9, -3)
    ..lineTo(9, 3)
    ..close();
  _shape(c, p, color, const Color(0xFF568CC0));
  _oval(c, const Rect.fromLTWH(-3, -1.2, 1.7, 1.7), const Color(0xFF568CC0));
}

void _rabbitEars(Canvas c) {
  for (final x in [-3.0, 3.0]) {
    c.save();
    c.translate(x, -2);
    c.rotate(x < 0 ? -.12 : .12);
    _oval(
      c,
      const Rect.fromLTWH(-2, -7, 4, 11),
      const Color(0xFFFFF6D2),
      border: const Color(0xFFC39B46),
    );
    _oval(c, const Rect.fromLTWH(-.7, -5, 1.4, 6), const Color(0xFFF6B4BD));
    c.restore();
  }
}

void _carrot(Canvas c) {
  final p = Path()
    ..moveTo(-3, -3)
    ..quadraticBezierTo(3, -5, 4, -1)
    ..lineTo(-1, 6)
    ..close();
  _shape(c, p, const Color(0xFFFFBA70), const Color(0xFFD08B43));
  c.drawPath(
    Path()
      ..moveTo(1, -3)
      ..lineTo(0, -7)
      ..moveTo(1, -3)
      ..lineTo(5, -6),
    Paint()
      ..color = const Color(0xFF88AD67)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round,
  );
}

void _paw(Canvas c, Color fill, Color border) {
  _oval(c, const Rect.fromLTWH(-3, 0, 6, 5), fill, border: border);
  for (final p in const [
    Offset(-4, -1),
    Offset(-1.5, -3),
    Offset(1.5, -3),
    Offset(4, -1),
  ]) {
    _oval(
      c,
      Rect.fromCenter(center: p, width: 2.5, height: 3),
      fill,
      border: border,
    );
  }
}

void _bone(Canvas c) {
  final p = Path()
    ..moveTo(-4, -2)
    ..cubicTo(-9, -8, -12, -1, -7, 0)
    ..cubicTo(-12, 5, -5, 8, -4, 2)
    ..lineTo(4, 2)
    ..cubicTo(9, 8, 12, 1, 7, 0)
    ..cubicTo(12, -5, 5, -8, 4, -2)
    ..close();
  _shape(c, p, const Color(0xFFFFF1D5), const Color(0xFFAB8159));
}

void _star(Canvas c, Color fill) {
  final p = Path();
  for (var i = 0; i < 10; i++) {
    final a = -math.pi / 2 + i * math.pi / 5;
    final r = i.isEven ? 5.4 : 2.4;
    final point = Offset(math.cos(a) * r, math.sin(a) * r);
    i == 0 ? p.moveTo(point.dx, point.dy) : p.lineTo(point.dx, point.dy);
  }
  _shape(c, p..close(), fill, const Color(0xFF9D7BC3));
}

void _crescent(Canvas c) {
  final moon = Path.combine(
    PathOperation.difference,
    Path()..addOval(const Rect.fromLTWH(-5, -6, 10, 10)),
    Path()..addOval(const Rect.fromLTWH(-1.5, -8, 9, 10)),
  );
  _shape(c, moon, const Color(0xFFFFECB0), const Color(0xFFB99BCF));
}
