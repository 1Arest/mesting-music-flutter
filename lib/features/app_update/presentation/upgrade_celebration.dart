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
          const Positioned.fill(child: UpgradeConfetti()),
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
          child: RepaintBoundary(
            child: CustomPaint(painter: _ConfettiPainter(_motion)),
          ),
        );
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.motion) : super(repaint: motion);
  final Animation<double> motion;
  static const _colors = [
    Color(0xFFFF6282),
    Color(0xFFFFD26C),
    Color(0xFF72C2FF),
    Color(0xFF90E8C4),
    Color(0xFFC3A0FF),
  ];
  @override
  void paint(Canvas canvas, Size size) {
    final t = motion.value;
    if (t <= 0 || t >= 1) return;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final pen = Paint();
    for (var i = 0; i < 80; i++) {
      final seed = (i * .618034) % 1;
      final left = i.isEven;
      final x =
          size.width *
          ((left ? .06 : .94) + (left ? 1 : -1) * t * (.42 + seed * .75));
      final y = size.height * (.78 - t * (1.55 + seed * .65) + t * t * 1.9);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(i * 2.4 + t * (i.isEven ? 9 : -8));
      pen.color = _colors[i % _colors.length].withValues(
        alpha: (1 - t * t).clamp(0, 1),
      );
      if (i % 4 == 0) {
        canvas.drawCircle(Offset.zero, 2.2 + seed, pen);
      } else {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset.zero,
              width: 4 + seed * 3,
              height: (7 + seed * 5) * (.4 + math.cos(t * 12 + i).abs() * .6),
            ),
            const Radius.circular(1),
          ),
          pen,
        );
      }
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.motion != motion;
}
