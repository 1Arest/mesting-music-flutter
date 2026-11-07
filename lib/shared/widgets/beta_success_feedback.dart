import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Shared drawn mark for compact comment notices and the central login HUD.
class BetaSuccessMark extends StatelessWidget {
  const BetaSuccessMark({
    this.size = 26,
    this.animated = true,
    this.color,
    super.key,
  });
  final double size;
  final Color? color;

  /// Operational notices show the complete mark immediately. The dedicated
  /// login HUD retains its independent animation unless explicitly requested.
  final bool animated;
  @override
  Widget build(BuildContext context) => !animated
      ? CustomPaint(size: Size.square(size), painter: _MarkPainter(1, color))
      : TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 900),
          builder: (_, value, _) => CustomPaint(
            size: Size.square(size),
            painter: _MarkPainter(value, color),
          ),
        );
}

class _MarkPainter extends CustomPainter {
  _MarkPainter(this.progress, this.color);
  final double progress;
  final Color? color;
  @override
  void paint(Canvas canvas, Size size) {
    final pen = Paint()
      ..color = color ?? const Color(0xFF2CB780)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * .035
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawArc(
      Rect.fromLTWH(
        size.width * .07,
        size.height * .07,
        size.width * .86,
        size.height * .86,
      ),
      -math.pi / 2,
      math.pi * 2 * (progress * 1.7).clamp(0, 1),
      false,
      pen,
    );
    final path = Path()
      ..moveTo(size.width * .35, size.height * .52)
      ..lineTo(size.width * .46, size.height * .63)
      ..lineTo(size.width * .68, size.height * .39);
    final metric = path.computeMetrics().first;
    canvas.drawPath(
      metric.extractPath(0, metric.length * ((progress - .3) / .7).clamp(0, 1)),
      pen..strokeWidth = size.width * .045,
    );
  }

  @override
  bool shouldRepaint(_MarkPainter old) =>
      old.progress != progress || old.color != color;
}

class BetaLoginSuccess extends StatefulWidget {
  const BetaLoginSuccess({required this.onComplete, super.key});
  final VoidCallback onComplete;
  @override
  State<BetaLoginSuccess> createState() => _BetaLoginSuccessState();
}

class _BetaLoginSuccessState extends State<BetaLoginSuccess>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
    reverseDuration: const Duration(milliseconds: 220),
  );
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _motion.forward();
    _timer = Timer(const Duration(milliseconds: 1800), () async {
      if (!mounted) return;
      await _motion.reverse();
      if (mounted) widget.onComplete();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = MediaQuery.disableAnimationsOf(context);
    _motion.reverseDuration = reduced
        ? Duration.zero
        : const Duration(milliseconds: 220);
    if (reduced) _motion.value = 1;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    label: '登录成功',
    excludeSemantics: true,
    child: SafeArea(
      // Only the compact HUD paints here. The coordinator supplies the
      // already-mounted guide and lets pointers reach its Next/Skip actions.
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          // The confirmed reference places a 104dp square below the guide
          // header's 64dp row, in the upper central breathing space.
          padding: const EdgeInsets.only(top: 76),
          child: FadeTransition(
            opacity: _motion,
            child: ScaleTransition(
              scale: Tween(begin: .9, end: 1.0).animate(
                CurvedAnimation(
                  parent: _motion,
                  curve: Curves.easeOutCubic,
                  reverseCurve: Curves.easeInCubic,
                ),
              ),
              child: RepaintBoundary(
                child: Container(
                  key: const ValueKey('beta10-login-success'),
                  width: 104,
                  height: 104,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xF20D1012),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const RepaintBoundary(child: BetaSuccessMark(size: 42)),
                      const SizedBox(height: 8),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          '登录成功',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                decoration: TextDecoration.none,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
