import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/audio/music_rhythm.dart';
import '../../../shared/widgets/music_spectrum_ring.dart';
import '../../themes/profile_effect_style.dart';

/// Shares the same scene between the profile header and the outfit preview.
void paintProfileAccent(
  Canvas canvas,
  Size size,
  Rect avatar,
  ProfileEffectStyle style,
  double phase,
  MusicRhythmFrame frame,
) {
  final center = avatar.center;
  final radius = avatar.shortestSide / 2 + 6;
  if (style == ProfileEffectStyle.rhythm) {
    paintMusicSpectrumRing(
      canvas,
      center: center,
      radius: radius,
      reach: (avatar.shortestSide * .105).clamp(5.0, 14.0),
      stroke: 1.55,
      frame: frame,
    );
    return;
  }

  final stars = style == ProfileEffectStyle.orbit;
  final tint = stars ? const Color(0xFFD4CAFF) : const Color(0xFFFFD189);
  final pen = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.6
    ..color = tint.withValues(alpha: .9);
  canvas.drawCircle(center, radius, pen);
  if (stars) {
    for (var i = 0; i < 2; i++) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius + 3 + i * 3),
        phase * math.pi * 2 + i * math.pi,
        math.pi * .74,
        false,
        pen..color = tint.withValues(alpha: .42 - i * .12),
      );
    }
  }

  // Distribute seeds across the width and phase without allocating particles
  // as the ambient scene loops. Each shape descends from above the header.
  final top = math.max(0.0, avatar.top - 86);
  final bottom = math.min(size.height, avatar.bottom + 64);
  if (bottom <= top) return;
  final fill = Paint();
  canvas.save();
  canvas.clipRect(Rect.fromLTRB(0, top, size.width, bottom));
  for (var i = 0; i < (stars ? 16 : 20); i++) {
    final t = (phase + i * .618034) % 1;
    final x = size.width * (.06 + .88 * ((i * .754878) % 1));
    final y = top - 8 + t * (bottom - top + 16);
    final drift = (stars ? 16 * t : 17 * math.sin(t * math.pi * 2 + i));
    final p = Offset(x + drift, y);
    final alpha = math.sin(t * math.pi) * (i.isEven ? .86 : .62);
    final core = 1.45 + i % 4 * .49;
    if (stars) {
      canvas.drawLine(
        p - Offset(5 + i % 4, 12 + i % 4 * 2),
        p,
        pen
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 1.15
          ..color = tint.withValues(alpha: alpha * .47),
      );
      final diamond = Path()
        ..moveTo(p.dx, p.dy - core * 1.9)
        ..quadraticBezierTo(p.dx + core * .4, p.dy, p.dx + core, p.dy)
        ..quadraticBezierTo(p.dx, p.dy + core * .5, p.dx, p.dy + core * 1.9)
        ..quadraticBezierTo(p.dx - core * .4, p.dy, p.dx - core, p.dy)
        ..quadraticBezierTo(p.dx, p.dy - core * .5, p.dx, p.dy - core * 1.9)
        ..close();
      canvas.drawPath(diamond, fill..color = tint.withValues(alpha: alpha));
    } else {
      canvas.drawCircle(
        p,
        core * 2.6,
        fill..color = tint.withValues(alpha: alpha * .13),
      );
      canvas.drawCircle(p, core, fill..color = tint.withValues(alpha: alpha));
    }
  }
  canvas.restore();
}

/// Notes have finite lives and spawn only from a new measured PCM onset.
class ProfileRhythmNotes extends StatefulWidget {
  const ProfileRhythmNotes({
    required this.frame,
    required this.avatarRect,
    super.key,
  });

  final MusicRhythmFrame frame;
  final Rect? Function() avatarRect;

  @override
  State<ProfileRhythmNotes> createState() => _ProfileRhythmNotesState();
}

const _noteLife = Duration(milliseconds: 1760);
typedef _Note = ({int birthMs, int seed, double force});

class _ProfileRhythmNotesState extends State<ProfileRhythmNotes>
    with SingleTickerProviderStateMixin {
  final _elapsed = Stopwatch()..start();
  final _notes = <_Note>[];
  late final _fall = AnimationController(vsync: this, duration: _noteLife);

  @override
  void didUpdateWidget(covariant ProfileRhythmNotes oldWidget) {
    super.didUpdateWidget(oldWidget);
    final frame = widget.frame;
    if (!frame.available) {
      _notes.clear();
      _fall.stop();
      return;
    }
    if (frame.onset == oldWidget.frame.onset || frame.pulse < .18) return;
    final now = _elapsed.elapsedMilliseconds;
    _notes.removeWhere(
      (note) => now - note.birthMs >= _noteLife.inMilliseconds,
    );
    if (_notes.length >= 12) _notes.removeAt(0);
    _notes.add((birthMs: now, seed: frame.onset, force: frame.pulse));
    _fall.forward(from: 0);
  }

  @override
  void dispose() {
    _fall.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _NotesPainter(_fall, _elapsed, _notes, widget.avatarRect),
  );
}

class _NotesPainter extends CustomPainter {
  _NotesPainter(this.animation, this.clock, this.notes, this.avatarRect)
    : super(repaint: animation);

  final Animation<double> animation;
  final Stopwatch clock;
  final List<_Note> notes;
  final Rect? Function() avatarRect;

  @override
  void paint(Canvas canvas, Size size) {
    final avatar = avatarRect();
    if (avatar == null || avatar.bottom <= 0 || avatar.top >= size.height) {
      return;
    }
    final now = clock.elapsedMilliseconds;
    final pen = Paint()..strokeCap = StrokeCap.round;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (final note in notes) {
      final progress = (now - note.birthMs) / _noteLife.inMilliseconds;
      if (progress >= 1) continue;
      final side = note.seed.isEven ? -1.0 : 1.0;
      final startX = avatar.center.dx + side * (avatar.width * .57 + 6);
      final x =
          (startX + side * (14 * progress + 8 * math.sin(progress * math.pi)))
              .clamp(10.0, math.max(10.0, size.width - 10));
      final y = avatar.top - 15 + (avatar.height + 67) * progress;
      final alpha = math.min(1.0, progress * 12) * (1 - progress * progress);
      final scale = .88 + note.force * .45;
      canvas.save();
      canvas.translate(x.toDouble(), y);
      canvas.rotate(side * (.12 + progress * .28));
      canvas.scale(scale);
      pen.color =
          (note.seed.isEven ? const Color(0xFF8FE8D8) : const Color(0xFFD6CAFF))
              .withValues(alpha: alpha * .96);
      pen.style = PaintingStyle.fill;
      canvas.drawOval(const Rect.fromLTWH(-5, 0, 6.8, 4.6), pen);
      pen.style = PaintingStyle.stroke;
      pen.strokeWidth = 1.65;
      canvas.drawLine(const Offset(1, 2), const Offset(1, -9), pen);
      canvas.drawPath(
        Path()
          ..moveTo(1, -9)
          ..quadraticBezierTo(1.6, -6.2, 5.4, -5.8)
          ..quadraticBezierTo(6.7, -4, 5.2, -1.9),
        pen,
      );
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_NotesPainter oldDelegate) => true;
}
