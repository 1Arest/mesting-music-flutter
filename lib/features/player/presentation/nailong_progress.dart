import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../themes/music_theme_preset.dart';
import 'ip_progress_decoration.dart';

/// The approved transparent belly-laugh clip; no video player or audio session.
/// Flutter's multiframe image stream displays its first frame even when paused,
/// and preserves its current frame when playback, the route or lifecycle pauses.
class NailongProgressCompanion extends StatefulWidget {
  const NailongProgressCompanion({required this.playing, super.key});
  final bool playing;
  @override
  State<NailongProgressCompanion> createState() =>
      _NailongProgressCompanionState();
}

class _NailongProgressCompanionState extends State<NailongProgressCompanion>
    with WidgetsBindingObserver {
  bool _foreground = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (mounted) {
      setState(() => _foreground = state == AppLifecycleState.resumed);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TickerMode(
    enabled: widget.playing && _foreground,
    child: Image.asset(
      'assets/images/theme_gallery/nailong-laugh.webp',
      key: const ValueKey('nailong-laugh-character'),
      cacheHeight: 192,
      fit: BoxFit.contain,
      gaplessPlayback: true,
      excludeFromSemantics: true,
      errorBuilder: (context, error, stack) => Image.asset(
        companionAssetForIp(MusicThemeIp.nailong)!,
        fit: BoxFit.contain,
      ),
    ),
  );
}

/// Animate only the selected laugh rail. Its Slider child and gesture/semantic
/// contract are reused, and all other IPs retain their existing track shapes.
class IpProgressSliderTheme extends StatefulWidget {
  const IpProgressSliderTheme({
    required this.ip,
    required this.playing,
    required this.data,
    required this.child,
    super.key,
  });
  final MusicThemeIp ip;
  final bool playing;
  final SliderThemeData data;
  final Widget child;
  @override
  State<IpProgressSliderTheme> createState() => _IpProgressSliderThemeState();
}

class _IpProgressSliderThemeState extends State<IpProgressSliderTheme>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4800),
  );
  bool _foreground = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
  }

  void _sync() {
    final enabled =
        widget.ip == MusicThemeIp.nailong &&
        widget.playing &&
        _foreground &&
        TickerMode.valuesOf(context).enabled &&
        !MediaQuery.disableAnimationsOf(context);
    if (enabled) {
      if (!_motion.isAnimating) _motion.repeat();
    } else {
      _motion.stop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant IpProgressSliderTheme oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _sync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _motion,
    child: widget.child,
    builder: (context, child) => SliderTheme(
      data: widget.ip == MusicThemeIp.nailong
          ? widget.data.copyWith(
              trackShape: IpProgressTrackShape(
                ip: widget.ip,
                motionPhase: _motion.value * math.pi * 2,
              ),
            )
          : widget.data,
      child: child!,
    ),
  );
}

void paintNailongProgressRail(
  Canvas canvas,
  Rect track,
  Rect active,
  TextDirection direction,
  double phase,
) {
  final y = track.center.dy;
  double wave(double x, double shift) =>
      math.sin((x - track.left) / 15 + phase * 2 + shift) * .9;
  final path = Path()..moveTo(active.left, y - 3);
  for (double x = active.left; x < active.right; x += 3) {
    path.lineTo(x, y - 3 + wave(x, 0));
  }
  path.lineTo(active.right, y - 3 + wave(active.right, 0));
  path.lineTo(active.right, y + 3 + wave(active.right, 1));
  for (double x = active.right; x > active.left; x -= 3) {
    path.lineTo(x, y + 3 + wave(x, 1));
  }
  path.close();
  canvas.save();
  canvas.clipRect(Rect.fromLTRB(active.left, y - 12, active.right, y + 12));
  canvas.drawPath(
    path,
    Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFFFFE28A), Color(0xFFF5BC3E), Color(0xFFE8AA25)],
      ).createShader(track),
  );
  var index = 0;
  for (double d = 18; d < track.width; d += 43) {
    final x = direction == TextDirection.ltr ? track.left + d : track.right - d;
    if (x + 10 < active.left || x - 10 > active.right) {
      index++;
      continue;
    }
    final squeeze = math.sin(phase * 3 + index * 1.7);
    final center = Offset(x, y + math.sin(phase * 3 + index * 1.7) * 1.1);
    final rect = Rect.fromCenter(
      center: center,
      width: 14 + squeeze * 2.3,
      height: 8 - squeeze * 1.8,
    );
    canvas.drawOval(rect, Paint()..color = const Color(0xFFFFF3D3));
    canvas.drawOval(
      rect,
      Paint()
        ..color = const Color(0xFFD9A448)
        ..style = PaintingStyle.stroke
        ..strokeWidth = .65,
    );
    canvas.drawPath(
      Path()
        ..moveTo(center.dx - 2.5, center.dy - .9)
        ..quadraticBezierTo(
          center.dx,
          center.dy + 1.1,
          center.dx + 2.5,
          center.dy - .9,
        ),
      Paint()
        ..color = const Color(0xFFD2A45E)
        ..strokeWidth = .7
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
    index++;
  }
  final end = direction == TextDirection.ltr ? active.right : active.left;
  final sign = direction == TextDirection.ltr ? -1 : 1;
  for (var i = 0; i < 3; i++) {
    final p = Offset(
      end + sign * (17 + i * 10),
      y - 10 - (2 - i) * .8 + math.sin(phase * 3 + i * 1.9) * 1.2,
    );
    canvas.drawCircle(
      p,
      1.2 + i * .25,
      Paint()..color = const Color(0xFFFFE5A8).withValues(alpha: .8),
    );
  }
  canvas.restore();
}
