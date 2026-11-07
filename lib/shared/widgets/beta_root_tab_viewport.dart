import 'package:flutter/material.dart';
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

/// Keeps branch state while painting at most the two actual slide endpoints.
/// A shortcut to a distant tab never slides through unrelated intermediate pages.
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
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 360),
    value: 1,
  )..addStatusListener(_status);

  double get _progress => Curves.easeInOutCubic.transform(_controller.value);
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
    _geometry.retarget(widget.index, _progress);
    _visited.add(widget.index);
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
      _geometry.settle();
    } else {
      _controller.forward(from: 0);
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
                    child: AnimatedBuilder(
                      animation: endpoints.contains(i)
                          ? _controller
                          : kAlwaysCompleteAnimation,
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
                      builder: (_, child) => Transform.translate(
                        offset: Offset(
                          (_geometry.positions(_progress)[i] ?? 0) *
                              constraints.maxWidth,
                          0,
                        ),
                        child: child,
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
