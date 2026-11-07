import 'package:flutter/material.dart';
import 'beta_page_route_observer.dart';
import 'beta_swipe_pages.dart';

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
      motionSettled != oldWidget.motionSettled ||
      location != oldWidget.location;
}

/// Retargets from the actual scroll position. PageController cancels the old
/// activity immediately; branch Navigators retain state without stacking old
/// route transitions. Only pages inside the viewport participate in painting.
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
  State<BetaRootTabViewport> createState() => _BetaRootTabViewportState();
}

class _BetaRootTabViewportState extends State<BetaRootTabViewport> {
  late final _controller = PageController(initialPage: widget.index);
  bool _scheduled = false;
  bool _moving = false;
  int _movement = 0;
  @override
  void didUpdateWidget(covariant BetaRootTabViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) _move();
  }

  void _move() {
    if (!_controller.hasClients) {
      if (_scheduled) return;
      _scheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scheduled = false;
        if (mounted) setState(_move);
      });
      return;
    }
    if (MediaQuery.disableAnimationsOf(context)) {
      _moving = false;
      _controller.jumpToPage(widget.index);
    } else {
      final movement = ++_movement;
      _moving = true;
      _controller
          .animateToPage(
            widget.index,
            duration: const Duration(milliseconds: 360),
            curve: Curves.easeInOutCubic,
          )
          .whenComplete(() {
            if (mounted && movement == _movement) {
              setState(() => _moving = false);
            }
          });
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
    return PageView(
      key: const ValueKey('beta-root-tab-viewport'),
      controller: _controller,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        for (var i = 0; i < widget.children.length; i++)
          _RetainedTab(
            key: ValueKey(i),
            visible: current && widget.index == i,
            motionSettled: !_moving,
            location: widget.locations?[i],
            child: widget.children[i],
          ),
      ],
    );
  }
}

class _RetainedTab extends StatefulWidget {
  const _RetainedTab({
    required this.visible,
    required this.motionSettled,
    required this.child,
    this.location,
    super.key,
  });
  final bool visible;
  final bool motionSettled;
  final Widget child;
  final String? location;
  @override
  State<_RetainedTab> createState() => _RetainedTabState();
}

class _RetainedTabState extends State<_RetainedTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return BetaTabVisibility(
      visible: widget.visible,
      motionSettled: widget.motionSettled,
      location: widget.location,
      child: NotificationListener<ScrollNotification>(
        onNotification: (event) {
          if (event.metrics.axis != Axis.vertical) return false;
          // Relay before PageView increments notification depth. Retained,
          // hidden tabs must never change the visible capsule's geometry.
          if (widget.visible && event.depth == 0) {
            BetaActivePageScrollNotification(event).dispatch(context);
          }
          return true;
        },
        child: TickerMode(enabled: widget.visible, child: widget.child),
      ),
    );
  }
}
