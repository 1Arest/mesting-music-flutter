import 'dart:math' as math;
import 'dart:ui' show ImageFilter;
import '../../shared/widgets/track_artwork.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/audio/playback_providers.dart';
import 'personal_style.dart';

/// One low-cost repaint layer behind controls. No FFT or fabricated beat data.
/// Route visibility, reduced motion and lifecycle all gate its single ticker.
class ListeningAtmosphereLayer extends ConsumerStatefulWidget {
  const ListeningAtmosphereLayer({super.key});
  @override
  ConsumerState<ListeningAtmosphereLayer> createState() => _AtmosphereState();
}

class _AtmosphereState extends ConsumerState<ListeningAtmosphereLayer>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final _motion = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 12),
  );
  bool _foreground = true;
  bool _running = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
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
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(personalStyleProvider);
    if (s.atmosphere == ListeningAtmosphere.off) {
      _motion.stop();
      _running = false;
      return const SizedBox.shrink();
    }
    final track = ref.watch(currentTrackProvider);
    final playing = ref.watch(playbackStateProvider).value?.playing ?? false;
    final active =
        s.atmosphere != ListeningAtmosphere.off &&
        playing &&
        s.strength > 0 &&
        _foreground &&
        TickerMode.valuesOf(context).enabled &&
        !MediaQuery.disableAnimationsOf(context) &&
        (ModalRoute.isCurrentOf(context) ?? true);
    final visible =
        _foreground &&
        TickerMode.valuesOf(context).enabled &&
        !MediaQuery.disableAnimationsOf(context) &&
        (ModalRoute.isCurrentOf(context) ?? true);
    if (active) {
      if (!_running) _motion.repeat();
    } else if (_running && visible && !playing) {
      // Ease through a small final phase on pause, then stop completely.
      _motion.animateTo(
        (_motion.value + .015).clamp(0.0, 1.0),
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
    } else if (!visible || s.strength <= 0) {
      _motion.stop();
    }
    _running = active;
    return IgnorePointer(
      child: ExcludeSemantics(
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: _motion,
            child: s.atmosphere == ListeningAtmosphere.glow
                ? RepaintBoundary(
                    child: ImageFiltered(
                      imageFilter: ImageFilter.blur(sigmaX: 45, sigmaY: 45),
                      child: TrackArtwork(
                        track: track,
                        decodeWidth: 64,
                        decodeHeight: 64,
                        fit: BoxFit.cover,
                      ),
                    ),
                  )
                : null,
            builder: (context, cover) => Stack(
              fit: StackFit.expand,
              children: [
                if (cover != null)
                  Opacity(
                    opacity: s.strength * .35,
                    child: Transform.translate(
                      offset: Offset(
                        math.sin(_motion.value * math.pi * 2) * 18,
                        0,
                      ),
                      child: cover,
                    ),
                  ),
                CustomPaint(painter: _AtmospherePainter(s, _motion.value)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AtmospherePainter extends CustomPainter {
  _AtmospherePainter(this.style, this.phase);
  final PersonalStyle style;
  final double phase;
  @override
  void paint(Canvas c, Size s) {
    final wave = (math.sin(phase * math.pi * 2) + 1) / 2;
    final color = style.accent;
    final p = Paint()
      ..color = color.withValues(alpha: style.strength * (.08 + wave * .06));
    if (style.atmosphere == ListeningAtmosphere.stars) {
      final random = math.Random(42);
      for (var i = 0; i < 24; i++) {
        p.color = Colors.white.withValues(
          alpha: style.strength * (.12 + wave * .3),
        );
        c.drawCircle(
          Offset(random.nextDouble() * s.width, random.nextDouble() * s.height),
          .8 + random.nextDouble(),
          p,
        );
      }
    } else if (style.atmosphere == ListeningAtmosphere.record) {
      p.style = PaintingStyle.stroke;
      p.strokeWidth = 2;
      for (var i = 0; i < 3; i++) {
        c.drawCircle(
          Offset(s.width / 2, s.height * .3),
          s.width * (.3 + i * .035 + wave * .015),
          p,
        );
      }
    } else {
      final rect = Offset.zero & s;
      c.drawRect(
        rect,
        Paint()
          ..shader = RadialGradient(
            center: Alignment(math.sin(phase * math.pi * 2) * .6, -.3),
            radius: 1.1,
            colors: [
              color.withValues(alpha: style.strength * .32),
              Colors.transparent,
            ],
          ).createShader(rect),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AtmospherePainter old) =>
      old.phase != phase || old.style != style;
}
