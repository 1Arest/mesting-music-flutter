import 'package:flutter/widgets.dart';

/// Pull gesture only. The caller owns loading/error presentation so a page
/// with an existing header spinner never adds a second floating indicator.
class QuietPullToRefresh extends StatefulWidget {
  const QuietPullToRefresh({
    required this.onRefresh,
    required this.child,
    this.enabled = true,
    super.key,
  });
  final Future<void> Function() onRefresh;
  final Widget child;
  final bool enabled;
  @override
  State<QuietPullToRefresh> createState() => _QuietPullToRefreshState();
}

class _QuietPullToRefreshState extends State<QuietPullToRefresh> {
  double _distance = 0;
  bool _triggered = false, _inFlight = false;
  Future<void> _refresh() async {
    _inFlight = true;
    try {
      await widget.onRefresh();
    } finally {
      _inFlight = false;
    }
  }

  bool _scroll(ScrollNotification notice) {
    if (notice.depth != 0) return false;
    if (notice is ScrollStartNotification && notice.dragDetails != null) {
      _distance = 0;
      _triggered = false;
    }
    if (!widget.enabled || _triggered || _inFlight) return false;
    final delta = notice is OverscrollNotification && notice.dragDetails != null
        ? notice.overscroll
        : notice is ScrollUpdateNotification &&
              notice.dragDetails != null &&
              notice.metrics.pixels < notice.metrics.minScrollExtent
        ? notice.scrollDelta ?? 0
        : 0.0;
    if (notice.metrics.pixels <= notice.metrics.minScrollExtent) {
      _distance = (_distance - delta).clamp(0, 160);
      if (_distance >= 64) {
        _triggered = true;
        _refresh();
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollNotification>(
        onNotification: _scroll,
        child: widget.child,
      );
}
