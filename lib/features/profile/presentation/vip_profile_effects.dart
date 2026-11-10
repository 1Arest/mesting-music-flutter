import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

const vipGold = Color(0xFFF5C96D);

/// One clock drives the avatar, reflected petals and identity highlights.
/// Particles have deterministic lifetimes, so a long session never accumulates
/// objects. Painting is isolated from the scrolling library below the header.
class VipProfileEffects extends StatefulWidget {
  const VipProfileEffects({
    required this.enabled,
    required this.avatarKey,
    required this.child,
    super.key,
  });
  final bool enabled;
  final VipEffectAnchorHandle avatarKey;
  final Widget child;

  @override
  State<VipProfileEffects> createState() => _VipProfileEffectsState();
}

class _VipProfileEffectsState extends State<VipProfileEffects>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _paintKey = VipEffectAnchorHandle();
  final _geometryChanges = ValueNotifier<int>(0);
  late final _clock = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 8),
  );
  bool _foreground = true;
  bool _headerVisible = true;
  bool _visibilityCheckPending = false;

  @override
  void initState() {
    super.initState();
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant VipProfileEffects oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _sync();
  }

  void _sync() {
    final animate =
        widget.enabled &&
        _foreground &&
        _headerVisible &&
        TickerMode.valuesOf(context).enabled &&
        !MediaQuery.disableAnimationsOf(context);
    if (animate && !_clock.isAnimating) _clock.repeat();
    if (!animate && _clock.isAnimating) _clock.stop();
  }

  Rect? _avatarRect() {
    final avatar = widget.avatarKey.box;
    final surface = _paintKey.box;
    if (avatar is! RenderBox ||
        surface is! RenderBox ||
        !avatar.attached ||
        !surface.attached ||
        !avatar.hasSize) {
      return null;
    }
    return (avatar.localToGlobal(Offset.zero) -
            surface.localToGlobal(Offset.zero)) &
        avatar.size;
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth == 0 && !_visibilityCheckPending) {
      _visibilityCheckPending = true;
      // Scroll updates can arrive before the viewport has laid out its new
      // slivers. Read attachment and position after that layout has completed.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _visibilityCheckPending = false;
        if (!mounted) return;
        final rect = _avatarRect();
        _headerVisible = rect != null && rect.bottom + 180 > 0;
        _geometryChanges.value++;
        _sync();
      });
    }
    return false;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clock.dispose();
    _geometryChanges.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    return _VipMotion(
      animation: _clock,
      reduced: reduced,
      child: NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: Stack(
          fit: StackFit.expand,
          children: [
            widget.child,
            if (widget.enabled)
              Positioned.fill(
                child: IgnorePointer(
                  child: ExcludeSemantics(
                    child: RepaintBoundary(
                      child: VipEffectAnchor(
                        handle: _paintKey,
                        child: CustomPaint(
                          painter: VipProfilePainter(
                            animation: _clock,
                            geometryChanges: _geometryChanges,
                            avatarRect: _avatarRect,
                            reduced: reduced,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class VipEffectAnchorHandle {
  RenderBox? box;
}

class VipEffectAnchor extends SingleChildRenderObjectWidget {
  const VipEffectAnchor({
    required this.handle,
    required super.child,
    super.key,
  });
  final VipEffectAnchorHandle handle;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _VipAnchorBox(handle);
  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderProxyBox renderObject,
  ) {
    final anchor = renderObject as _VipAnchorBox;
    if (identical(anchor.handle, handle)) return;
    anchor.handle.box = null;
    anchor.handle = handle;
    if (anchor.attached) handle.box = anchor;
  }
}

class _VipAnchorBox extends RenderProxyBox {
  _VipAnchorBox(this.handle);
  VipEffectAnchorHandle handle;
  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    handle.box = this;
  }

  @override
  void detach() {
    if (identical(handle.box, this)) handle.box = null;
    super.detach();
  }
}

class _VipMotion extends InheritedWidget {
  const _VipMotion({
    required this.animation,
    required this.reduced,
    required super.child,
  });
  final Animation<double> animation;
  final bool reduced;
  static _VipMotion of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_VipMotion>()!;
  @override
  bool updateShouldNotify(_VipMotion oldWidget) =>
      animation != oldWidget.animation || reduced != oldWidget.reduced;
}

/// The child retains its own wrapping, semantics and accessibility text scale.
class VipGoldText extends StatelessWidget {
  const VipGoldText({required this.child, super.key});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final motion = _VipMotion.of(context);
    final base = Theme.of(context).brightness == Brightness.dark
        ? vipGold
        : const Color(0xFF94600F);
    return AnimatedBuilder(
      animation: motion.animation,
      child: child,
      builder: (context, child) => ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (rect) {
          final x = rect.width * (-1.2 + 3.4 * motion.animation.value);
          return ui.Gradient.linear(
            Offset(x, 0),
            Offset(x + rect.width * .65, rect.height),
            motion.reduced
                ? [base, base]
                : [
                    base,
                    const Color(0xFFE8AE43),
                    const Color(0xFFFFF8D8),
                    const Color(0xFFE8AE43),
                    base,
                  ],
            motion.reduced ? null : const [0, .25, .5, .75, 1],
          );
        },
        child: child,
      ),
    );
  }
}

class VipProfilePainter extends CustomPainter {
  VipProfilePainter({
    required this.animation,
    required Listenable geometryChanges,
    required this.avatarRect,
    required this.reduced,
  }) : super(repaint: Listenable.merge([animation, geometryChanges]));
  final Animation<double> animation;
  final Rect? Function() avatarRect;
  final bool reduced;

  @override
  void paint(Canvas canvas, Size size) {
    final avatar = avatarRect();
    if (avatar == null || avatar.bottom < -180 || avatar.top > size.height) {
      return;
    }
    final center = avatar.center;
    final radius = avatar.shortestSide / 2 + 6;
    final phase = reduced ? .15 : animation.value;
    final pulse = .5 + .5 * math.sin(phase * math.pi * 8);
    final ring = Rect.fromCircle(center: center, radius: radius);
    canvas.drawCircle(
      center,
      radius + 2 + pulse * 3,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..color = vipGold.withValues(alpha: .23 + pulse * .18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..shader = SweepGradient(
          colors: [
            const Color(0xFFBB7D23),
            vipGold,
            const Color(0xFFFFF3C3),
            vipGold,
            const Color(0xFFBB7D23),
          ],
          transform: GradientRotation(phase * math.pi * 2),
        ).createShader(ring),
    );
    for (var i = 0; i < 3; i++) {
      final p = (phase * 3 + i / 3) % 1;
      canvas.drawCircle(
        center,
        radius + p * 19,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = vipGold.withValues(alpha: reduced ? 0 : (1 - p) * .35),
      );
    }
    if (reduced || avatar.top < 0) return;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    // Every beam travels from the ring to the top wall, flashes on impact,
    // then reflects diagonally before becoming a slow, rotating pink petal.
    for (var i = 0; i < 14; i++) {
      final t = (phase + i / 14) % 1;
      final seed = i * 2.399963;
      final start =
          center +
          Offset(
            math.sin(seed) * radius * .75,
            -radius * (.45 + .45 * math.cos(seed).abs()),
          );
      final hit = Offset(
        (center.dx + math.sin(seed * 1.7) * size.width * .42).clamp(
          12.0,
          size.width - 12,
        ),
        3,
      );
      if (t < .24) {
        final p = t / .24;
        final head = Offset.lerp(start, hit, p)!;
        final tail = Offset.lerp(start, hit, (p - .16).clamp(0.0, 1.0))!;
        canvas.drawLine(
          tail,
          head,
          Paint()
            ..strokeCap = StrokeCap.round
            ..strokeWidth = 2
            ..shader = ui.Gradient.linear(tail, head, [
              vipGold.withValues(alpha: 0),
              const Color(0xFFFFF2C2),
            ]),
        );
        canvas.drawCircle(
          head,
          2,
          Paint()
            ..color = const Color(0xFFFFF0BB)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
        );
      } else {
        final p = (t - .24) / .76;
        final reflected = Offset(
          math.sin(seed) * 34 * math.min(p / .1, 1),
          20 * math.min(p / .1, 1),
        );
        final point =
            hit +
            reflected +
            Offset(
              math.sin(p * math.pi * 2 + seed) * 22 * p,
              p * p * (center.dy + 150),
            );
        final opacity = math.min(p * 10, 1.0) * (1 - p);
        if (p < .1) {
          canvas.drawCircle(
            hit,
            p * 110,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.2
              ..color = const Color(0xFFFFD5E7).withValues(alpha: 1 - p * 10),
          );
        }
        _petal(
          canvas,
          point,
          seed + p * 5,
          3 + i % 3,
          const Color(0xFFFFA6CD).withValues(alpha: opacity * .85),
        );
      }
    }
    canvas.restore();
  }

  void _petal(
    Canvas canvas,
    Offset position,
    double rotation,
    double scale,
    Color color,
  ) {
    canvas.save();
    canvas.translate(position.dx, position.dy);
    canvas.rotate(rotation);
    final path = Path()
      ..moveTo(0, -scale * 1.6)
      ..cubicTo(scale * 1.5, -scale, scale, scale, 0, scale * 1.6)
      ..cubicTo(-scale, scale, -scale * 1.5, -scale, 0, -scale * 1.6);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, .25),
    );
    canvas.drawLine(
      Offset(0, -scale),
      Offset(0, scale * .8),
      Paint()
        ..color = const Color(0xFFFFE3EF).withValues(alpha: color.a * .6)
        ..strokeWidth = .6,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(VipProfilePainter oldDelegate) =>
      animation != oldDelegate.animation ||
      avatarRect != oldDelegate.avatarRect ||
      reduced != oldDelegate.reduced;
}
