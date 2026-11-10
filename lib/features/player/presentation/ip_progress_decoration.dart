import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../themes/mesting_palette.dart';
import '../../themes/music_theme_preset.dart';
import 'shinchan_progress_walker.dart';
import 'ip_progress_motifs.dart';
import 'nailong_progress.dart';
import 'uploaded_progress_portrait.dart';

const _helloKittyAsset =
    'assets/images/theme_gallery/hello-kitty-progress-head.png';
const _kuromiAsset = 'assets/images/theme_gallery/kuromi-progress-head.png';

const double ipProgressTrackHeight = 6;
const double ipProgressLeadingDotDiameter = 9;

Color progressTrackColorForIp(MusicThemeIp ip) => switch (ip) {
  MusicThemeIp.nailong => const Color(0xFFE8AA25),
  MusicThemeIp.classic => const Color(0xFF5F75DE),
  MusicThemeIp.shinchan => const Color(0xFFF2A72E),
  MusicThemeIp.helloKitty => MestingPalette.dangerBright,
  MusicThemeIp.kuromi => const Color(0xFF9B6BE8),
  MusicThemeIp.myMelody => const Color(0xFFEA69A7),
  MusicThemeIp.usagi => const Color(0xFFD5AC47),
  MusicThemeIp.chiikawa => const Color(0xFFE89B9C),
  MusicThemeIp.hachiware => const Color(0xFF5D9FD9),
  MusicThemeIp.puppyWhite => const Color(0xFF8495A2),
  MusicThemeIp.puppyGray => const Color(0xFFB58C54),
  MusicThemeIp.cinnamoroll => const Color(0xFF37A9D6),
  MusicThemeIp.sleepingKirby => const Color(0xFFB283D9),
};

Size progressCompanionSize(MusicThemeIp ip, {double shinchanWidth = 56}) =>
    switch (ip) {
      // Match Shinchan's 236px opaque height in a 502px-wide sprite.
      // Account for the 282px opaque body inside Nailong's 301px canvas.
      MusicThemeIp.nailong => Size(
        shinchanWidth * 236 / 502 * 301 / 282 * 194 / 301,
        shinchanWidth * 236 / 502 * 301 / 282,
      ),
      MusicThemeIp.helloKitty => const Size(24, 24),
      MusicThemeIp.kuromi => const Size(24, 24),
      MusicThemeIp.shinchan => ShinchanProgressWalker.sizeForWidth(56),
      MusicThemeIp.classic => Size.zero,
      MusicThemeIp.cinnamoroll => const Size(36, 24),
      MusicThemeIp.puppyWhite || MusicThemeIp.puppyGray => const Size(30, 24),
      _ => const Size(28, 28),
    };

/// Heads replace the thumb at its center; full bodies stand on the rail's top.
/// Use the actual slider geometry rather than a player-specific negative inset.
double progressCompanionTop(
  MusicThemeIp ip, {
  double trackCenterY = 24,
  double trackHeight = ipProgressTrackHeight,
  Size? companionSize,
}) {
  final size = companionSize ?? progressCompanionSize(ip);
  return switch (ip) {
    MusicThemeIp.helloKitty => trackCenterY - size.height / 2,
    // Kuromi's long ears sit above the face. Its PNG canvas midpoint therefore
    // leaves the perceived head below the rail; use a 3dp optical lift at 24dp.
    MusicThemeIp.kuromi => trackCenterY - size.height * .625,
    MusicThemeIp.shinchan ||
    MusicThemeIp.nailong => trackCenterY - trackHeight / 2 - size.height,
    MusicThemeIp.classic => 0,
    // The hat and bubbles raise the PNG bounds above Kirby's main body.
    // Lift by 3.9dp at 28dp so the body, rather than that canvas, is centered.
    MusicThemeIp.sleepingKirby => trackCenterY - size.height * .64,
    // Tall ears use an optical lift so the face remains close to the rail.
    MusicThemeIp.myMelody ||
    MusicThemeIp.usagi => trackCenterY - size.height * .64,
    _ => trackCenterY - size.height / 2,
  };
}

double progressCompanionLeft({
  required double progress,
  required double availableWidth,
  required double companionWidth,
}) {
  // The painted center, rather than the transparent image bounds, is the
  // progress anchor. The player's horizontal inset safely contains overhang.
  return progress.clamp(0.0, 1.0) * availableWidth - companionWidth / 2;
}

/// Draws an IP-specific rail without changing the Slider's drag or semantics.
///
/// The character remains a separate widget so playback motion can be paused
/// independently while the rail stays cheap to repaint.
class IpProgressTrackShape extends SliderTrackShape with BaseSliderTrackShape {
  const IpProgressTrackShape({required this.ip, this.motionPhase = 0});

  final double motionPhase;

  final MusicThemeIp ip;

  @override
  bool get isRounded => true;

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
  }) {
    final height = sliderTheme.trackHeight ?? 0;
    if (height <= 0) return;

    final trackRect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    final inactiveColor = ColorTween(
      begin: sliderTheme.disabledInactiveTrackColor,
      end: sliderTheme.inactiveTrackColor,
    ).evaluate(enableAnimation)!;
    final activeColor = ColorTween(
      begin: sliderTheme.disabledActiveTrackColor,
      end: sliderTheme.activeTrackColor,
    ).evaluate(enableAnimation)!;
    final radius = Radius.circular(trackRect.height / 2);
    final track = RRect.fromRectAndRadius(trackRect, radius);
    final canvas = context.canvas;

    canvas.drawRRect(
      track,
      Paint()
        ..shader = LinearGradient(
          colors: [_inactiveTint(ip).withValues(alpha: .24), inactiveColor],
        ).createShader(trackRect),
    );
    canvas.drawRRect(
      track,
      Paint()
        ..color = Colors.white.withValues(alpha: .12)
        ..style = PaintingStyle.stroke
        ..strokeWidth = .8,
    );

    final splitX = thumbCenter.dx.clamp(trackRect.left, trackRect.right);
    final activeRect = textDirection == TextDirection.ltr
        ? Rect.fromLTRB(trackRect.left, trackRect.top, splitX, trackRect.bottom)
        : Rect.fromLTRB(
            splitX,
            trackRect.top,
            trackRect.right,
            trackRect.bottom,
          );
    if (activeRect.width <= 0) return;

    if (ip == MusicThemeIp.nailong) {
      paintNailongProgressRail(
        canvas,
        trackRect,
        activeRect,
        textDirection,
        motionPhase,
      );
      return;
    }
    final activeTrack = RRect.fromRectAndRadius(activeRect, radius);
    canvas.drawRRect(
      activeTrack,
      Paint()
        ..shader = LinearGradient(
          colors: [_activeStart(ip), activeColor, _activeEnd(ip)],
          stops: const [0, .58, 1],
        ).createShader(activeRect),
    );

    canvas.save();
    canvas.clipRRect(activeTrack);
    switch (ip) {
      case MusicThemeIp.classic:
        break;
      case MusicThemeIp.shinchan:
        _paintCrayonRoad(canvas, activeRect);
      case MusicThemeIp.helloKitty:
        _paintRibbonStitches(canvas, activeRect);
      case MusicThemeIp.kuromi:
        _paintKuromiDiamonds(canvas, activeRect);
      default:
        break;
    }
    canvas.restore();
    paintIpProgressMotifs(
      canvas,
      ip: ip,
      track: trackRect,
      active: activeRect,
      direction: textDirection,
    );
  }

  void _paintCrayonRoad(Canvas canvas, Rect rect) {
    final paint = Paint()
      ..color = const Color(0xFFFFF4C7).withValues(alpha: .82)
      ..strokeWidth = 1.15
      ..strokeCap = StrokeCap.round;
    for (double x = rect.left + 7; x < rect.right - 2; x += 12) {
      canvas.drawLine(
        Offset(x - 1.8, rect.center.dy + 1.4),
        Offset(x + 1.8, rect.center.dy - 1.4),
        paint,
      );
    }
  }

  void _paintRibbonStitches(Canvas canvas, Rect rect) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: .86)
      ..strokeWidth = 1.15
      ..strokeCap = StrokeCap.round;
    for (double x = rect.left + 6; x < rect.right - 2; x += 11) {
      canvas.drawLine(
        Offset(x, rect.center.dy),
        Offset(x + 3.2, rect.center.dy),
        paint,
      );
    }
  }

  void _paintKuromiDiamonds(Canvas canvas, Rect rect) {
    final paint = Paint()
      ..color = const Color(0xFFFFB5DC).withValues(alpha: .9);
    for (double x = rect.left + 8; x < rect.right - 2; x += 14) {
      final center = Offset(x, rect.center.dy);
      final diamond = Path()
        ..moveTo(center.dx, center.dy - 1.7)
        ..lineTo(center.dx + 2.2, center.dy)
        ..lineTo(center.dx, center.dy + 1.7)
        ..lineTo(center.dx - 2.2, center.dy)
        ..close();
      canvas.drawPath(diamond, paint);
    }
  }

  Color _inactiveTint(MusicThemeIp ip) => switch (ip) {
    MusicThemeIp.nailong => const Color(0xFFFFE28A),
    MusicThemeIp.classic => const Color(0xFF5F75DE),
    MusicThemeIp.shinchan => const Color(0xFFFFD35B),
    MusicThemeIp.helloKitty => MestingPalette.dangerSoft,
    MusicThemeIp.kuromi => const Color(0xFF5E427F),
    MusicThemeIp.myMelody => const Color(0xFFFFB6D5),
    MusicThemeIp.usagi => const Color(0xFFFFE8A4),
    MusicThemeIp.chiikawa => const Color(0xFFFFD4D5),
    MusicThemeIp.hachiware => const Color(0xFFADE2FA),
    MusicThemeIp.puppyWhite => const Color(0xFFDCE9EE),
    MusicThemeIp.puppyGray => const Color(0xFFF2D6A4),
    MusicThemeIp.cinnamoroll => const Color(0xFFAFE9F9),
    MusicThemeIp.sleepingKirby => const Color(0xFFF7BDDC),
  };

  Color _activeStart(MusicThemeIp ip) => switch (ip) {
    MusicThemeIp.nailong => const Color(0xFFFFE28A),
    MusicThemeIp.classic => const Color(0xFF7187F1),
    MusicThemeIp.shinchan => const Color(0xFFFFD65A),
    MusicThemeIp.helloKitty => MestingPalette.dangerBright,
    MusicThemeIp.kuromi => const Color(0xFF7654BE),
    MusicThemeIp.myMelody => const Color(0xFFFFB6D5),
    MusicThemeIp.usagi => const Color(0xFFFFE8A4),
    MusicThemeIp.chiikawa => const Color(0xFFFFD4D5),
    MusicThemeIp.hachiware => const Color(0xFFADE2FA),
    MusicThemeIp.puppyWhite => const Color(0xFFDCE9EE),
    MusicThemeIp.puppyGray => const Color(0xFFF2D6A4),
    MusicThemeIp.cinnamoroll => const Color(0xFFAFE9F9),
    MusicThemeIp.sleepingKirby => const Color(0xFFF7BDDC),
  };

  Color _activeEnd(MusicThemeIp ip) => switch (ip) {
    MusicThemeIp.nailong => const Color(0xFFE8AA25),
    MusicThemeIp.classic => const Color(0xFF5368D2),
    MusicThemeIp.shinchan => const Color(0xFFEF782D),
    MusicThemeIp.helloKitty => MestingPalette.danger,
    MusicThemeIp.kuromi => const Color(0xFFD85BA5),
    MusicThemeIp.myMelody => const Color(0xFFD94D94),
    MusicThemeIp.usagi => const Color(0xFFC49935),
    MusicThemeIp.chiikawa => const Color(0xFFD77487),
    MusicThemeIp.hachiware => const Color(0xFF4783C8),
    MusicThemeIp.puppyWhite => const Color(0xFF6F8594),
    MusicThemeIp.puppyGray => const Color(0xFFA07945),
    MusicThemeIp.cinnamoroll => const Color(0xFF248CBE),
    MusicThemeIp.sleepingKirby => const Color(0xFF9870CF),
  };
}

class IpProgressCompanion extends StatefulWidget {
  const IpProgressCompanion({
    required this.ip,
    required this.playing,
    this.shinchanWidth = 56,
    super.key,
  }) : assert(ip != MusicThemeIp.classic && ip != MusicThemeIp.shinchan);

  final MusicThemeIp ip;
  final bool playing;
  final double shinchanWidth;

  @override
  State<IpProgressCompanion> createState() => _IpProgressCompanionState();
}

class _IpProgressCompanionState extends State<IpProgressCompanion>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant IpProgressCompanion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playing != widget.playing || oldWidget.ip != widget.ip) {
      _syncAnimation();
    }
  }

  void _syncAnimation() {
    if (widget.playing && !_reduceMotion && widget.ip != MusicThemeIp.nailong) {
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      _controller.stop();
      if (_reduceMotion) _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = progressCompanionSize(
      widget.ip,
      shinchanWidth: widget.shinchanWidth,
    );
    return RepaintBoundary(
      key: ValueKey('ip-progress-companion-${widget.ip.name}'),
      child: SizedBox.fromSize(
        size: size,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final phase = _controller.value * math.pi * 2;
            return switch (widget.ip) {
              MusicThemeIp.nailong => NailongProgressCompanion(
                playing: widget.playing,
              ),
              MusicThemeIp.helloKitty => _HelloKittyCompanion(phase: phase),
              MusicThemeIp.kuromi => _KuromiCompanion(phase: phase),
              _ => Transform.rotate(
                angle: math.sin(phase) * .025,
                child: UploadedProgressPortrait(ip: widget.ip),
              ),
            };
          },
        ),
      ),
    );
  }
}

/// Head-only art: no medallion, ribbons, crest or extra leading-dot decoration.
class _HelloKittyCompanion extends StatelessWidget {
  const _HelloKittyCompanion({required this.phase});
  final double phase;
  @override
  Widget build(BuildContext context) => Transform.rotate(
    angle: math.sin(phase) * .025,
    child: Image.asset(
      _helloKittyAsset,
      key: const ValueKey('hello-kitty-progress-character'),
      fit: BoxFit.contain,
    ),
  );
}

class _KuromiCompanion extends StatelessWidget {
  const _KuromiCompanion({required this.phase});
  final double phase;
  @override
  Widget build(BuildContext context) => Transform.rotate(
    angle: math.sin(phase) * .025,
    child: Image.asset(
      _kuromiAsset,
      key: const ValueKey('kuromi-progress-character'),
      fit: BoxFit.contain,
    ),
  );
}
