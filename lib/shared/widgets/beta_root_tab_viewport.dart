import 'package:flutter/material.dart';

/// Nested branch routes remain current in their own Navigator. This additional
/// visibility signal prevents a retained tab from owning the active search bar.
class BetaTabVisibility extends InheritedWidget {
  const BetaTabVisibility({
    required this.visible,
    this.location,
    required super.child,
    super.key,
  });
  final bool visible;
  final String? location;
  static bool of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<BetaTabVisibility>()
          ?.visible ??
      true;
  @override
  bool updateShouldNotify(BetaTabVisibility oldWidget) =>
      visible != oldWidget.visible;
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
        if (mounted) _move();
      });
      return;
    }
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.jumpToPage(widget.index);
    } else {
      _controller.animateToPage(
        widget.index,
        duration: const Duration(milliseconds: 360),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = ModalRoute.isCurrentOf(context) ?? true;
    return PageView(
      key: const ValueKey('beta-root-tab-viewport'),
      controller: _controller,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        for (var i = 0; i < widget.children.length; i++)
          _RetainedTab(
            key: ValueKey(i),
            visible: current && widget.index == i,
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
    required this.child,
    this.location,
    super.key,
  });
  final bool visible;
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
      location: widget.location,
      child: TickerMode(enabled: widget.visible, child: widget.child),
    );
  }
}
