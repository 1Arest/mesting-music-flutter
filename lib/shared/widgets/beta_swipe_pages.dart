import 'package:flutter/material.dart';

/// Scroll ownership crosses a horizontal viewport explicitly. A hidden page
/// cannot compact the common glass bar; the active page's vertical scroll can.
class BetaActivePageScrollNotification extends Notification {
  const BetaActivePageScrollNotification(this.scroll);
  final ScrollNotification scroll;
}

/// Existing TabBarViews retain their own controllers. This relay adds scroll
/// ownership without another viewport or another copy of the content tree.
class BetaTabScrollRelay extends StatelessWidget {
  const BetaTabScrollRelay({
    required this.controller,
    required this.index,
    required this.child,
    super.key,
  });
  final TabController controller;
  final int index;
  final Widget child;
  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollNotification>(
        onNotification: (event) {
          if (event.metrics.axis != Axis.vertical) return false;
          if (controller.index == index && event.depth == 0) {
            BetaActivePageScrollNotification(event).dispatch(context);
          }
          return true;
        },
        child: child,
      );
}

class BetaSwipePages extends StatefulWidget {
  const BetaSwipePages({
    required this.index,
    required this.length,
    required this.onChanged,
    required this.itemBuilder,
    this.swipeEnabled = true,
    super.key,
  });
  final int index, length;
  final ValueChanged<int> onChanged;
  final IndexedWidgetBuilder itemBuilder;

  /// Temporarily unavailable source slots keep their identity without letting
  /// a drag select an empty page. Programmatic selection remains available.
  final bool swipeEnabled;

  @override
  State<BetaSwipePages> createState() => _BetaSwipePagesState();
}

class _BetaSwipePagesState extends State<BetaSwipePages> {
  late final PageController _pages;
  late int _reportedIndex;
  int? _target;
  int _motion = 0;
  @override
  void initState() {
    super.initState();
    _pages = PageController(initialPage: widget.index);
    // Capture the mounted index eagerly. A lazy initializer first read in
    // didUpdateWidget would see the *new* index and swallow the first click.
    _reportedIndex = widget.index;
  }

  @override
  void didUpdateWidget(covariant BetaSwipePages oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index &&
        (widget.index != _reportedIndex || _target != null) &&
        _pages.hasClients) {
      final motion = ++_motion;
      _target = widget.index;
      // Re-target the same controller, including during an unfinished swipe.
      if (MediaQuery.disableAnimationsOf(context)) {
        _pages.jumpToPage(widget.index);
        _target = null;
        return;
      }
      _pages
          .animateToPage(
            widget.index,
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
          )
          .whenComplete(() {
            if (mounted && motion == _motion) _target = null;
          });
    }
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollNotification>(
        onNotification: (event) {
          if (event.depth != 0 || event.metrics.axis != Axis.horizontal) {
            return false;
          }
          if (event is ScrollStartNotification && event.dragDetails != null) {
            // A finger takes ownership immediately, including midway through a
            // multi-page click animation. Intermediate programmatic pages never
            // replace the user's selected destination or start their searches.
            ++_motion;
            _target = null;
          }
          if (event is ScrollEndNotification && _target == null) {
            final settled = _pages.page?.round();
            if (settled != null && settled != widget.index) {
              widget.onChanged(settled);
            }
          }
          return false;
        },
        child: PageView.builder(
          controller: _pages,
          physics: widget.swipeEnabled
              ? null
              : const NeverScrollableScrollPhysics(),
          itemCount: widget.length,
          onPageChanged: (index) {
            _reportedIndex = index;
            if (_target == null) widget.onChanged(index);
          },
          itemBuilder: (context, index) => _RetainedPage(
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification.metrics.axis != Axis.vertical) return false;
                if (index == widget.index && notification.depth == 0) {
                  BetaActivePageScrollNotification(
                    notification,
                  ).dispatch(context);
                }
                return true;
              },
              child: TickerMode(
                enabled: index == widget.index,
                child: widget.itemBuilder(context, index),
              ),
            ),
          ),
        ),
      );
}

class _RetainedPage extends StatefulWidget {
  const _RetainedPage({required this.child});
  final Widget child;
  @override
  State<_RetainedPage> createState() => _RetainedPageState();
}

class _RetainedPageState extends State<_RetainedPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
