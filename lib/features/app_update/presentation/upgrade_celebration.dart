import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../shared/widgets/beta_success_feedback.dart';

/// A transient, pointer-transparent overlay. It reuses the real login HUD;
/// the party painter has a bounded particle count and no image/dependency.
Future<bool> showUpgradeCelebration(BuildContext context) async {
  final overlay =
      Navigator.maybeOf(context, rootNavigator: true)?.overlay ??
      Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null || !overlay.mounted) return false;
  final complete = Completer<void>();
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => IgnorePointer(
      key: const ValueKey('upgrade-celebration-overlay'),
      child: Stack(
        children: [
          const Positioned.fill(child: SafeArea(child: UpgradeConfetti())),
          BetaLoginSuccess(
            message: '更新成功',
            onComplete: () {
              if (!complete.isCompleted) complete.complete();
            },
          ),
        ],
      ),
    ),
  );
  overlay.insert(entry);
  try {
    await complete.future.timeout(const Duration(seconds: 3), onTimeout: () {});
    return entry.mounted;
  } finally {
    entry.remove();
    entry.dispose();
  }
}

class UpgradeConfetti extends StatefulWidget {
  const UpgradeConfetti({super.key});
  @override
  State<UpgradeConfetti> createState() => _UpgradeConfettiState();
}

class _UpgradeConfettiState extends State<UpgradeConfetti>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2000),
  );
  late final _painter = _ConfettiPainter(_motion);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!MediaQuery.disableAnimationsOf(context) &&
        !_motion.isAnimating &&
        _motion.value == 0) {
      _motion.forward();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _motion.value < 1 &&
        !MediaQuery.disableAnimationsOf(context)) {
      _motion.forward();
    } else {
      _motion.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MediaQuery.disableAnimationsOf(context)
      ? const SizedBox.shrink()
      : ExcludeSemantics(
          child: RepaintBoundary(child: CustomPaint(painter: _painter)),
        );
}

class _PaperFragment {
  _PaperFragment(math.Random random, this.direction, this.color)
    : distance = .38 + random.nextDouble() * .62,
      tilt = random.nextDouble() * 2 * math.pi,
      spin = (random.nextBool() ? 1 : -1) * (2 + random.nextDouble() * 8),
      flutter = 7 + random.nextDouble() * 9,
      lifetime = .72 + random.nextDouble() * .28,
      shape = _outline(random);

  final Offset direction;
  final Color color;
  final double distance, tilt, spin, flutter, lifetime;
  final Path shape;

  static Path _outline(math.Random random) {
    final corners = 3 + random.nextInt(3);
    final radius = 1.7 + random.nextDouble() * 3.5;
    final stretch = .65 + random.nextDouble() * .55;
    final points = List.generate(corners, (index) {
      final angle = (index + random.nextDouble() * .42) * 2 * math.pi / corners;
      final reach = radius * (.6 + random.nextDouble() * .5);
      return Offset(math.cos(angle) * reach, math.sin(angle) * reach * stretch);
    });
    return Path()..addPolygon(points, true);
  }
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.motion)
    : fragments = _makeFragments(),
      super(repaint: motion);

  final Animation<double> motion;
  final List<_PaperFragment> fragments;
  final Paint _pen = Paint();
  static const _colors = [
    Color(0xFFFF6282),
    Color(0xFFFFD26C),
    Color(0xFF72C2FF),
    Color(0xFF90E8C4),
    Color(0xFFC3A0FF),
  ];

  static List<_PaperFragment> _makeFragments() {
    final random = math.Random();
    const count = 66;
    final phase = random.nextDouble() * 2 * math.pi;
    // Cover the full circle, with a slight angular jitter and independent
    // velocities so the pieces form a loose burst rather than parallel bands.
    return List.generate(count, (index) {
      final angle =
          phase + (index + random.nextDouble() * .9) * 2 * math.pi / count;
      return _PaperFragment(
        random,
        Offset(math.cos(angle), math.sin(angle)),
        _colors[random.nextInt(_colors.length)],
      );
    });
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = motion.value;
    if (t <= 0 || t >= 1) return;
    final origin = Offset(
      size.width / 2,
      BetaLoginSuccess.cardTop + BetaLoginSuccess.cardSize / 2,
    );
    final spread = math.min(size.width * .48, 240.0);
    // A quick outward impulse eases off before gravity and flutter take over.
    final impulse = 1 - math.exp(-8 * t);
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (final fragment in fragments) {
      if (t >= fragment.lifetime) continue;
      final travel = impulse * fragment.distance;
      final direction = fragment.direction;
      final drift = Offset(
        math.sin(t * 14 + fragment.tilt) * fragment.flutter * t,
        math.min(size.height * .46, 300.0) * t * t,
      );
      // Compress upward travel to the room above the card on short screens.
      final verticalSpread = direction.dy < 0
          ? math.min(spread, origin.dy * .91)
          : spread;
      final position =
          origin +
          Offset(
            direction.dx * spread * travel,
            direction.dy * verticalSpread * travel,
          ) +
          drift;
      canvas.save();
      canvas.translate(position.dx, position.dy);
      canvas.rotate(fragment.tilt + t * fragment.spin);
      canvas.scale(
        math.max(.16, math.cos(fragment.tilt + t * fragment.spin * 1.8).abs()),
        1,
      );
      final fade = 1 - Curves.easeIn.transform(t / fragment.lifetime);
      _pen.color = fragment.color.withValues(alpha: fade);
      canvas.drawPath(fragment.shape, _pen);
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.motion != motion;
}
