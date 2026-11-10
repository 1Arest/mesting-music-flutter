import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/physics.dart';
import 'beta_page_route_observer.dart';
import 'beta_swipe_pages.dart';
import 'beta_tab_motion.dart';

/// Nested branch routes remain current in their own Navigator. This additional
/// visibility signal prevents a retained tab from owning the active search bar.
class BetaTabVisibility extends InheritedWidget {
  const BetaTabVisibility({
    required this.visible,
    this.motionSettled = true,
    this.location,
    required super.child,
    super.key,
  });
  final bool visible;
  final bool motionSettled;
  final String? location;
  static bool of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<BetaTabVisibility>()
          ?.visible ??
      true;
  static bool settledOf(BuildContext context) {
    final visibility = context
        .dependOnInheritedWidgetOfExactType<BetaTabVisibility>();
    return visibility == null ||
        (visibility.visible && visibility.motionSettled);
  }

  @override
  bool updateShouldNotify(BetaTabVisibility oldWidget) =>
      visible != oldWidget.visible ||
      // Hidden consumers already see false from both visibility queries.
      // Their location/settling changes become relevant when selected again;
      // broadcasting them now rebuilt every previously visited tab per switch.
      (visible &&
          (motionSettled != oldWidget.motionSettled ||
              location != oldWidget.location));
}

/// Keeps visited branches while moving only their paint transforms. Ordinary
/// shortcuts use two endpoints. A burst retains any already visible tile until
/// it leaves the viewport; a new destination enters from outside the viewport,
/// so selecting a third tab cannot replace a partly visible page in one frame.
class BetaRootTabViewport extends StatefulWidget {
  const BetaRootTabViewport({
    required this.index,
    required this.children,
    this.locations,
    super.key,
  });
  final int index;
  final List<Widget> children;
  final List<String>? locations;
  @override
  State<BetaRootTabViewport> createState() => BetaRootTabViewportState();
}

/// Read-only presentation state also lets diagnostics verify the painted
/// endpoint instead of treating a successful route request as a rendered page.
class BetaRootTabViewportState extends State<BetaRootTabViewport>
    with SingleTickerProviderStateMixin {
  late final _geometry = BetaTabMotion(widget.index);
  late final _visited = <int>{widget.index};
  late final _controller = AnimationController.unbounded(
    vsync: this,
    duration: const Duration(milliseconds: 360),
    value: 1,
  )..addStatusListener(_status);

  double get _progress => _controller.value;
  int get selectedIndex => widget.index;
  bool get motionSettled => !_controller.isAnimating;
  Set<int> get paintedIndices => {
    for (final entry in _geometry.positions(_progress).entries)
      if (entry.value.abs() < 1) entry.key,
  };

  void _status(AnimationStatus status) {
    if (status == AnimationStatus.completed && mounted) {
      setState(_geometry.settle);
    }
  }

  @override
  void didUpdateWidget(covariant BetaRootTabViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index == widget.index) return;
    final interrupted = _controller.isAnimating;
    // Every tile moves as one strip. Preserve its actual screen velocity when
    // retargeting instead of restarting an ease-in curve at zero velocity.
    final velocity = _geometry.distance * _controller.velocity;
    _geometry.retarget(widget.index, _progress);
    _visited.add(widget.index);
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
      _geometry.settle();
    } else {
      _controller.stop();
      _controller.value = 0;
      if (interrupted && _geometry.distance.abs() > .000001) {
        final safeVelocity = _geometry.safeVelocity(velocity);
        _controller.animateWith(
          SpringSimulation(
            const SpringDescription(mass: 1, stiffness: 400, damping: 40),
            0,
            1,
            safeVelocity / _geometry.distance,
            tolerance: const Tolerance(distance: .0001, velocity: .001),
          ),
        );
      } else if (_geometry.distance.abs() > .000001) {
        _controller.animateTo(
          1,
          duration: const Duration(milliseconds: 360),
          curve: Curves.easeInOutCubic,
        );
      } else {
        _geometry.settle();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final routes = BetaPageRouteObserver.maybeOf(context);
    return routes == null
        ? _viewport(context, null)
        : ListenableBuilder(
            listenable: routes,
            builder: (context, _) => _viewport(context, routes),
          );
  }

  Widget _viewport(BuildContext context, BetaPageRouteObserver? routes) {
    final current =
        routes?.isTopPage(ModalRoute.of(context)) ??
        (ModalRoute.isCurrentOf(context) ?? true);
    final endpoints = _geometry.positions(_progress).keys.toSet();
    return ClipRect(
      key: const ValueKey('beta-root-tab-viewport'),
      child: LayoutBuilder(
        builder: (context, constraints) => Stack(
          fit: StackFit.expand,
          children: [
            for (var i = 0; i < widget.children.length; i++)
              if (_visited.contains(i))
                KeyedSubtree(
                  key: ValueKey(i),
                  child: Offstage(
                    offstage: !endpoints.contains(i),
                    child: _TabPaintMotion(
                      animation: endpoints.contains(i)
                          ? _controller
                          : kAlwaysCompleteAnimation,
                      geometry: _geometry,
                      index: i,
                      // Keep the actual page below a stable paint boundary.
                      // Motion changes its transform, not its widget/layout tree.
                      child: RepaintBoundary(
                        child: _RetainedTab(
                          visible: current && widget.index == i,
                          motionSettled: motionSettled,
                          location: widget.locations?[i],
                          child: widget.children[i],
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

/// Transform changes belong to painting. Updating Transform widgets through
/// AnimatedBuilder also ran two element update paths per tick; keeping the
/// matrix here preserves live glass's applyPaintTransform queries and hit tests
/// without rebuilding or laying out either retained page during motion.
class _TabPaintMotion extends SingleChildRenderObjectWidget {
  const _TabPaintMotion({
    required this.animation,
    required this.geometry,
    required this.index,
    required super.child,
  });
  final Animation<double> animation;
  final BetaTabMotion geometry;
  final int index;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderTabPaintMotion(animation, geometry, index);
  @override
  void updateRenderObject(
    BuildContext context,
    _RenderTabPaintMotion renderObject,
  ) => renderObject.update(animation, geometry, index);
}

class _RenderTabPaintMotion extends RenderProxyBox {
  _RenderTabPaintMotion(this.animation, this.geometry, this.index);
  Animation<double> animation;
  BetaTabMotion geometry;
  int index;
  double get _dx => geometry.position(index, animation.value) * size.width;
  void _changed() {
    markNeedsPaint();
    markNeedsSemanticsUpdate();
  }

  void update(Animation<double> next, BetaTabMotion motion, int tab) {
    if (animation != next) {
      if (attached) animation.removeListener(_changed);
      animation = next;
      if (attached) animation.addListener(_changed);
    }
    geometry = motion;
    index = tab;
    _changed();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    animation.addListener(_changed);
  }

  @override
  void detach() {
    animation.removeListener(_changed);
    super.detach();
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) =>
      transform.translateByDouble(_dx, 0, 0, 1);
  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) return;
    context.pushTransform(
      needsCompositing,
      offset,
      Matrix4.translationValues(_dx, 0, 0),
      (context, offset) => context.paintChild(child!, offset),
    );
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      child != null &&
      result.addWithPaintOffset(
        offset: Offset(_dx, 0),
        position: position,
        hitTest: (result, local) => child!.hitTest(result, position: local),
      );
}

class _RetainedTab extends StatefulWidget {
  const _RetainedTab({
    required this.visible,
    required this.motionSettled,
    required this.child,
    this.location,
  });
  final bool visible;
  final bool motionSettled;
  final Widget child;
  final String? location;
  @override
  State<_RetainedTab> createState() => _RetainedTabState();
}

class _RetainedTabState extends State<_RetainedTab> {
  @override
  Widget build(BuildContext context) {
    return BetaTabVisibility(
      visible: widget.visible,
      motionSettled: widget.motionSettled,
      location: widget.location,
      child: NotificationListener<ScrollNotification>(
        onNotification: (event) {
          if (event.metrics.axis != Axis.vertical) return false;
          // Relay the branch's own scroll before nesting changes its depth. Retained,
          // hidden tabs must never change the visible capsule's geometry.
          if (widget.visible && event.depth == 0) {
            BetaActivePageScrollNotification(event).dispatch(context);
          }
          return true;
        },
        child: TickerMode(
          enabled: widget.visible,
          child: ExcludeFocus(
            excluding: !widget.visible,
            child: ExcludeSemantics(
              excluding: !widget.visible,
              child: IgnorePointer(
                ignoring: !widget.visible,
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
