import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import '../../features/experience/presentation/beta_bottom_bar.dart';
import '../../core/haptics/app_haptics.dart';

const betaMenuOpenDuration = Duration(milliseconds: 400);
const betaMenuCloseDuration = Duration(milliseconds: 240);
const double betaMenuAnchorGap = 8;
const double _menuSeparationProgress = .72;

/// The pill's actual optical material, shared by playback and editing menus.
/// Every popover owns one premium layer; nested surfaces would lose refraction.
class BetaGlassMenuSurface extends StatelessWidget {
  const BetaGlassMenuSurface({
    required this.child,
    this.radius = 24,
    this.visibility = 1,
    this.grouped = false,
    super.key,
  });
  final Widget child;
  final double radius;
  final double visibility;
  final bool grouped;
  @override
  Widget build(BuildContext context) => GlassContainer(
    key: const ValueKey('beta13-glass-menu-surface'),
    quality: GlassQuality.premium,
    useOwnLayer: !grouped,
    settings: betaMusicPillGlass(context).copyWith(
      blur: betaMusicPillGlass(context).blur + 2,
      visibility: visibility,
    ),
    shape: LiquidRoundedRectangle(borderRadius: radius),
    clipBehavior: Clip.hardEdge,
    child: Material(type: MaterialType.transparency, child: child),
  );
}

/// The menu and its short liquid neck share one premium optical layer. It
/// measures the actual menu once, then changes paint transforms only: a tick
/// never rebuilds its rows, the source page, or the audio owner. In Impeller the
/// grouped SDFs blend before separating; Skia keeps the same bounded geometry
/// and the package's existing optical fallback. No opacity wraps live glass.
class BetaLiquidMenu extends StatefulWidget {
  const BetaLiquidMenu({
    required this.animation,
    required this.layout,
    required this.child,
    super.key,
  });
  final Animation<double> animation;
  final BetaMenuLayout layout;
  final Widget child;

  @override
  State<BetaLiquidMenu> createState() => _BetaLiquidMenuState();
}

class _BetaLiquidMenuState extends State<BetaLiquidMenu> {
  bool _connected = true;

  @override
  void initState() {
    super.initState();
    _connected = widget.animation.value < _menuSeparationProgress;
    widget.animation.addListener(_connectionChanged);
  }

  @override
  void didUpdateWidget(covariant BetaLiquidMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animation != widget.animation) {
      oldWidget.animation.removeListener(_connectionChanged);
      widget.animation.addListener(_connectionChanged);
    }
    _connected = widget.animation.value < _menuSeparationProgress;
  }

  void _connectionChanged() {
    final connected = widget.animation.value < _menuSeparationProgress;
    // Only rebuild at the separation boundary. Motion ticks continue to be
    // render transforms, and the menu rows retain their existing elements.
    if (connected != _connected) setState(() => _connected = connected);
  }

  @override
  void dispose() {
    widget.animation.removeListener(_connectionChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    final settings = betaMusicPillGlass(context);
    final foreground = reduced
        ? kAlwaysCompleteAnimation
        : widget.animation.drive(
            CurveTween(
              curve: const Interval(.22, .76, curve: Curves.easeOutCubic),
            ),
          );
    return AdaptiveLiquidGlassLayer(
      quality: GlassQuality.premium,
      settings: settings.copyWith(blur: settings.blur + 2),
      blendAmount: 16,
      child: _LiquidMenuMotion(
        key: const ValueKey('beta105-liquid-menu-flow'),
        animation: widget.animation,
        layout: widget.layout,
        reduced: reduced,
        children: [
          BetaGlassMenuSurface(
            grouped: true,
            child: FadeTransition(opacity: foreground, child: widget.child),
          ),
          for (final part in ['source', 'neck'])
            IgnorePointer(
              // A .001px oval is still an SDF primitive: smooth union can
              // turn it into a visible dot and a bump along the menu rim.
              // Detach the two optical surfaces after separation, rather
              // than merely scaling them down. Reverse reattaches them at
              // the same boundary, preserving the liquid return trajectory.
              child: !_connected || reduced
                  ? const SizedBox.square(dimension: 32)
                  : GlassContainer(
                      key: ValueKey('beta105-liquid-$part'),
                      quality: GlassQuality.premium,
                      shape: const LiquidOval(),
                      child: const SizedBox.square(dimension: 32),
                    ),
            ),
        ],
      ),
    );
  }
}

/// Flow caches its child transforms during paint. The premium glass ancestor
/// gathers SDF geometry *before* that paint, so Flow exposes the last frame's
/// transform (identity on first entry). That painted the ghost at (0, 0).
/// This render boundary derives transforms from the same animation at query
/// time, for SDF sampling, paint, hit testing and semantics alike. Layout and
/// the menu subtree stay unchanged on animation ticks.
class _LiquidMenuMotion extends MultiChildRenderObjectWidget {
  const _LiquidMenuMotion({
    required this.animation,
    required this.layout,
    required this.reduced,
    required super.children,
    super.key,
  });
  final Animation<double> animation;
  final BetaMenuLayout layout;
  final bool reduced;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderLiquidMenu(animation, layout, reduced);
  @override
  void updateRenderObject(
    BuildContext context,
    _RenderLiquidMenu renderObject,
  ) => renderObject.update(animation, layout, reduced);
}

class _MenuParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderLiquidMenu extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _MenuParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _MenuParentData> {
  _RenderLiquidMenu(this.animation, this._menuLayout, this.reduced);
  Animation<double> animation;
  BetaMenuLayout _menuLayout;
  bool reduced;
  double? _cachedProgress;
  List<Rect>? _cachedBounds;
  void update(
    Animation<double> next,
    BetaMenuLayout nextLayout,
    bool nextReduced,
  ) {
    if (animation != next) {
      if (attached) animation.removeListener(markNeedsPaint);
      animation = next;
      if (attached) animation.addListener(markNeedsPaint);
    }
    if (_menuLayout.shouldRelayout(nextLayout)) markNeedsLayout();
    _menuLayout = nextLayout;
    reduced = nextReduced;
    _cachedBounds = null;
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    animation.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    animation.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _MenuParentData) {
      child.parentData = _MenuParentData();
    }
  }

  @override
  void performLayout() {
    _cachedBounds = null;
    size = constraints.biggest;
    var index = 0;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      child.layout(
        index++ == 0
            ? _menuLayout.getConstraintsForChild(constraints)
            : const BoxConstraints.tightFor(width: 32, height: 32),
        parentUsesSize: true,
      );
    }
  }

  List<Rect> _bounds() {
    final progress = reduced ? 1.0 : animation.value.clamp(0.0, 1.0);
    if (_cachedBounds != null && _cachedProgress == progress) {
      return _cachedBounds!;
    }
    _cachedProgress = progress;
    final menuSize = firstChild!.size;
    final target = _menuLayout.getPositionForChild(size, menuSize) & menuSize;
    final start = _menuLayout.sourceBounds(size, menuSize);
    // One position function in both directions makes an interrupted opening
    // reverse continuously, without switching curves or replaying a new route.
    final raw = progress;
    final t = Curves.easeOutCubic.transform(raw);
    final rect = Rect.lerp(start, target, t)!;

    // The seam thins to zero before the menu reaches its final gap. The reverse
    // trajectory reconnects the meniscus before the menu merges into its source.
    final join = reduced
        ? 0.0
        : (1 - raw / _menuSeparationProgress).clamp(0.0, 1.0);
    final source = start.center;
    final edge = Offset(
      source.dx.clamp(
        rect.left + rect.width * .2,
        rect.right - rect.width * .2,
      ),
      _menuLayout.above ? rect.bottom : rect.top,
    );
    final neck = Rect.fromCenter(
      center: Offset.lerp(source, edge, .5)!,
      width: math.max(.001, 30 * join),
      height: math.max(.001, ((edge.dy - source.dy).abs() + 24) * join),
    );
    return _cachedBounds = [
      rect,
      Rect.fromCenter(
        center: source,
        width: math.max(.001, start.width * join),
        height: math.max(
          .001,
          (_menuLayout.fromInnerEdge ? start.height : 22) * join,
        ),
      ),
      neck,
    ];
  }

  Matrix4 _transform(RenderBox child) {
    var index = 0;
    for (var node = firstChild; node != child; node = childAfter(node!)) {
      index++;
    }
    final rect = _bounds()[index];
    return Matrix4.identity()
      ..translateByDouble(rect.left, rect.top, 0, 1)
      ..scaleByDouble(
        rect.width / child.size.width,
        rect.height / child.size.height,
        1,
        1,
      );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) =>
      transform.multiply(_transform(child));
  @override
  void paint(PaintingContext context, Offset offset) {
    // Draw source and neck first, then the real menu as in the original Flow.
    final ordered = [childAfter(firstChild!)!, lastChild!, firstChild!];
    for (final child in ordered) {
      context.pushTransform(
        needsCompositing,
        offset,
        _transform(child),
        (context, offset) => context.paintChild(child, offset),
      );
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      result.addWithPaintTransform(
        transform: _transform(firstChild!),
        position: position,
        hitTest: (result, position) =>
            firstChild!.hitTest(result, position: position),
      );
}

/// One motion contract for editing and playback menus. The trigger-facing edge
/// stays anchored as the glass stretches into place with a small spring settle.
/// Dismissal uses a shorter, non-overshooting contraction toward the same edge.
class BetaGlassMenuTransition extends StatefulWidget {
  const BetaGlassMenuTransition({
    required this.animation,
    required this.origin,
    required this.child,
    super.key,
  });

  final Animation<double> animation;
  final Alignment origin;
  final Widget child;

  @override
  State<BetaGlassMenuTransition> createState() =>
      _BetaGlassMenuTransitionState();
}

class _BetaGlassMenuTransitionState extends State<BetaGlassMenuTransition> {
  late CurvedAnimation _stretch;
  late CurvedAnimation _reveal;

  void _bindAnimation() {
    _stretch = CurvedAnimation(
      parent: widget.animation,
      curve: const _MenuSpringCurve(),
      reverseCurve: Curves.easeInOutCubic,
    );
    _reveal = CurvedAnimation(
      parent: widget.animation,
      curve: const Interval(0, .45, curve: Curves.easeOutCubic),
      reverseCurve: Curves.easeOutCubic,
    );
  }

  @override
  void initState() {
    super.initState();
    _bindAnimation();
  }

  @override
  void didUpdateWidget(covariant BetaGlassMenuTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animation != widget.animation) {
      _stretch.dispose();
      _reveal.dispose();
      _bindAnimation();
    }
  }

  @override
  void dispose() {
    _stretch.dispose();
    _reveal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    // Premium glass reads the scene BEHIND the menu. An ancestor opacity layer
    // instead gives Impeller a transparent offscreen texture whose origin is
    // the menu's bounds, while the shader still uses the scene's coordinates.
    // The resulting double offset is the displaced black rectangle reported on
    // Android. Keep optics in the scene pass; fade only the foreground content.
    // GlassContainer already owns its renderer's scale-safe repaint boundary.
    return BetaGlassMenuSurface(
      child: AnimatedBuilder(
        animation: widget.animation,
        child: FadeTransition(
          opacity: reduceMotion ? kAlwaysCompleteAnimation : _reveal,
          child: widget.child,
        ),
        builder: (context, child) {
          final stretch = reduceMotion ? 1.0 : _stretch.value;
          return ClipRect(
            child: Align(
              alignment: widget.origin,
              widthFactor: .82 + .18 * stretch,
              heightFactor: .16 + .84 * stretch,
              child: child,
            ),
          );
        },
      ),
    );
  }
}

/// A lightly damped growth, calibrated to the supplied Music menu reference.
/// These are application parameters, not claims about Apple's private physics.
class _MenuSpringCurve extends Curve {
  const _MenuSpringCurve();
  @override
  double transformInternal(double t) =>
      1 - math.exp(-9 * t) * (math.cos(11 * t) + 9 / 11 * math.sin(11 * t));
}

/// Dialogs containing live glass must not inherit Material's default fade:
/// that fade creates the same offscreen sampling problem as an opacity-wrapped
/// menu. A short translation keeps the real scene visible to the shader.
Future<T?> showBetaGlassDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  String label = '关闭',
}) async {
  final reduced = MediaQuery.disableAnimationsOf(context);
  final route = RawDialogRoute<T>(
    barrierDismissible: barrierDismissible,
    barrierLabel: label,
    barrierColor: Colors.black.withValues(alpha: .36),
    transitionDuration: reduced
        ? Duration.zero
        : const Duration(milliseconds: 220),
    pageBuilder: (dialog, _, _) =>
        Theme(data: Theme.of(context), child: builder(dialog)),
    transitionBuilder: (_, animation, _, child) => reduced
        ? child
        : SlideTransition(
            position:
                Tween<Offset>(
                  begin: const Offset(0, .025),
                  end: Offset.zero,
                ).animate(
                  CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                  ),
                ),
            child: child,
          ),
  );
  final result = await Navigator.of(context, rootNavigator: true).push(route);
  await route.completed;
  return result;
}

/// Positions from the measured trigger, then animates only the bounded menu.
/// The underlying capsule stays in place. Await route.completed so a selected
/// action opens its next surface only after the downward dismissal finishes.
Future<T?> showBetaGlassPopover<T>({
  required BuildContext context,
  required Rect anchor,
  required WidgetBuilder builder,
  double width = 300,
  String label = '关闭菜单',
  bool fromInnerEdge = false,
}) async {
  appHaptic(context, AppHapticEvent.impact);
  final media = MediaQuery.of(context);
  final layout = BetaMenuLayout(
    anchor: anchor,
    media: media,
    width: width,
    fromInnerEdge: fromInnerEdge,
  );
  final route = _BetaGlassPopoverRoute<T>(
    label: label,
    reduceMotion: media.disableAnimations,
    pageBuilder: (dialog, animation, _) => Theme(
      data: Theme.of(context),
      child: BetaLiquidMenu(
        animation: animation,
        layout: layout,
        child: builder(dialog),
      ),
    ),
  );
  final value = await Navigator.of(context, rootNavigator: true).push<T>(route);
  await route.completed;
  return value;
}

class _BetaGlassPopoverRoute<T> extends RawDialogRoute<T> {
  _BetaGlassPopoverRoute({
    required super.pageBuilder,
    required String label,
    required this.reduceMotion,
  }) : super(
         barrierDismissible: true,
         barrierLabel: label,
         barrierColor: Colors.black.withValues(alpha: .08),
         transitionDuration: reduceMotion
             ? Duration.zero
             : betaMenuOpenDuration,
         transitionBuilder: (_, _, _, child) => child,
       );

  final bool reduceMotion;

  @override
  Duration get reverseTransitionDuration =>
      reduceMotion ? Duration.zero : betaMenuCloseDuration;
}

/// Also used by selection toolbars, whose anchors are supplied by EditableText.
class BetaMenuLayout extends SingleChildLayoutDelegate {
  const BetaMenuLayout({
    required this.anchor,
    required this.media,
    required this.width,
    this.gap = betaMenuAnchorGap,
    this.fromInnerEdge = false,
    this.viewportOrigin = Offset.zero,
  });
  final Rect anchor;
  final MediaQueryData media;
  final double width;
  final double gap;
  final bool fromInnerEdge;

  /// Text-selection toolbars live under a moving CompositedTransformFollower.
  /// Their visible screen rectangle can start outside that follower's origin.
  final Offset viewportOrigin;

  /// The source stays inside the trigger's lens, on the side facing the menu.
  /// Selection toolbars retain their original centre-based geometry.
  Rect sourceBounds(Size parentSize, Size menuSize) {
    if (!fromInnerEdge) {
      return Rect.fromCenter(
        center: anchor.center,
        width: math.min(menuSize.width * .65, math.max(36, anchor.width * .48)),
        height: math.min(30, math.max(16, anchor.height * .48)),
      );
    }
    final target = getPositionForChild(parentSize, menuSize) & menuSize;
    final direction = target.center - anchor.center;
    final angle = math.atan2(direction.dy, direction.dx);
    final centre =
        anchor.center +
        Offset(
          math.cos(angle) * math.max(0, anchor.width / 2 - 10),
          math.sin(angle) * math.max(0, anchor.height / 2 - 9),
        );
    return Rect.fromCenter(
      center: centre,
      width: math.min(16, anchor.width * .34),
      height: math.min(12, anchor.height * .25),
    );
  }

  double get top => viewportOrigin.dy + media.padding.top + 12;
  double get bottom =>
      viewportOrigin.dy +
      media.size.height -
      math.max(media.viewInsets.bottom, media.padding.bottom) -
      12;
  bool get above =>
      anchor.top - top >= bottom - anchor.bottom || anchor.top - top > 260;

  /// Match the real trigger even when the menu is clamped against screen edges.
  Alignment get motionOrigin {
    final menuWidth = math.max(1.0, math.min(width, media.size.width - 24));
    final left = (anchor.center.dx - menuWidth / 2).clamp(
      viewportOrigin.dx + 12.0,
      viewportOrigin.dx + math.max(12.0, media.size.width - menuWidth - 12),
    );
    return Alignment(
      ((anchor.center.dx - left) / menuWidth * 2 - 1).clamp(-1.0, 1.0),
      above ? 1 : -1,
    );
  }

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints(
        maxWidth: math.max(0, math.min(width, constraints.maxWidth - 24)),
        maxHeight: math.max(
          0,
          math.min(
            math.max(0, bottom - top),
            math.max(
              48,
              above ? anchor.top - top - gap : bottom - anchor.bottom - gap,
            ),
          ),
        ),
      );
  @override
  Offset getPositionForChild(Size size, Size childSize) => Offset(
    (anchor.center.dx - childSize.width / 2).clamp(
      viewportOrigin.dx + 12.0,
      viewportOrigin.dx + math.max(12, media.size.width - childSize.width - 12),
    ),
    (above ? anchor.top - childSize.height - gap : anchor.bottom + gap).clamp(
      top,
      math.max(top, bottom - childSize.height),
    ),
  );
  @override
  bool shouldRelayout(BetaMenuLayout old) =>
      anchor != old.anchor ||
      media != old.media ||
      width != old.width ||
      gap != old.gap ||
      fromInnerEdge != old.fromInnerEdge ||
      viewportOrigin != old.viewportOrigin;
}
