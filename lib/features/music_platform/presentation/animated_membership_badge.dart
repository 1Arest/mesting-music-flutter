import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../shared/widgets/beta_root_tab_viewport.dart';
import '../../../shared/widgets/beta_music_chrome_scope.dart';
import '../domain/membership_badge.dart';

/// One bounded paint island: the border flows, a diagonal sheen traverses the
/// face and brightness breathes. Text/geometry never move or rebuild per tick.
class AnimatedMembershipBadge extends StatefulWidget {
  const AnimatedMembershipBadge({required this.tier, super.key});
  final MembershipBadgeTier tier;
  @override
  State<AnimatedMembershipBadge> createState() =>
      _AnimatedMembershipBadgeState();
}

class _AnimatedMembershipBadgeState extends State<AnimatedMembershipBadge>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3000),
  );
  bool _foreground = true;
  BetaMusicChromeController? _chrome;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  void _sync() {
    final visible =
        _foreground &&
        _chrome?.covered != true &&
        TickerMode.valuesOf(context).enabled &&
        BetaTabVisibility.of(context) &&
        (ModalRoute.isCurrentOf(context) ?? true);
    final animate = visible && !MediaQuery.disableAnimationsOf(context);
    if (animate && !_motion.isAnimating) _motion.repeat();
    if (!animate && _motion.isAnimating) _motion.stop();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final chrome = BetaMusicChromeScope.maybeOf(context);
    if (_chrome != chrome) {
      _chrome?.removeListener(_sync);
      _chrome = chrome;
      _chrome?.addListener(_sync);
    }
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (mounted) _sync();
  }

  @override
  void dispose() {
    _chrome?.removeListener(_sync);
    WidgetsBinding.instance.removeObserver(this);
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label = switch (widget.tier) {
      MembershipBadgeTier.vip => 'VIP',
      MembershipBadgeTier.svip => 'SVIP',
      MembershipBadgeTier.supreme => '至尊SVIP',
    };
    return Semantics(
      label: widget.tier == MembershipBadgeTier.supreme
          ? '至尊SVIP，本地会员展示'
          : '官方$label',
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _MembershipPlate(_motion),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.workspace_premium_rounded,
                  size: 17,
                  color: Color(0xFFFFE4A0),
                ),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFFFFE4A0),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MembershipPlate extends CustomPainter {
  _MembershipPlate(this.motion) : super(repaint: motion);
  final Animation<double> motion;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final border = RRect.fromRectAndRadius(
      rect.deflate(.8),
      const Radius.circular(8),
    );
    final paint = Paint()..isAntiAlias = true;
    final phase = motion.value;
    final breath = (1 + math.sin(phase * math.pi * 2)) / 2;
    paint.shader = LinearGradient(
      colors: [
        const Color(0xFF302315),
        Color.lerp(const Color(0xFF51402A), const Color(0xFF70512A), breath)!,
        const Color(0xFF261D14),
      ],
    ).createShader(rect);
    canvas.drawRRect(border, paint);
    paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..shader = SweepGradient(
        transform: GradientRotation(phase * math.pi * 2),
        colors: const [
          Color(0xFF9A6A29),
          Color(0xFFFFE7A6),
          Color(0xFFD69B3B),
          Color(0xFF9A6A29),
        ],
      ).createShader(rect);
    canvas.drawRRect(border, paint);
    canvas.save();
    canvas.clipRRect(border);
    final x = (-.7 + phase * 2.4) * size.width;
    paint
      ..style = PaintingStyle.fill
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: const [Color(0x00FFF0BC), Color(0x55FFF0BC), Color(0x00FFF0BC)],
      ).createShader(Rect.fromLTWH(x, 0, size.width * .5, size.height));
    canvas.drawRect(rect, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MembershipPlate oldDelegate) =>
      oldDelegate.motion != motion;
}
