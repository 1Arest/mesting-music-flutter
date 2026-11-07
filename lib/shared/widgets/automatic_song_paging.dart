import 'package:flutter/material.dart';
import 'song_list_tools.dart';

/// Prefetch near the end and fill an initially short viewport. The owning
/// repository/controller still owns pagination, errors and account generations.
class AutomaticSongPaging extends StatefulWidget {
  const AutomaticSongPaging({
    required this.enabled,
    required this.onLoadMore,
    required this.child,
    this.fillInitialViewport = true,
    this.songListId,
    this.songListBottom,
    super.key,
  });
  final bool enabled;
  final Future<void> Function() onLoadMore;
  final Widget child;
  final String? songListId;
  final double? songListBottom;

  /// Detail pages that prepare a complete first screen can wait for an actual
  /// scroll before requesting another batch. Existing catalogue behavior is
  /// unchanged unless the owner explicitly opts out of layout-time filling.
  final bool fillInitialViewport;
  @override
  State<AutomaticSongPaging> createState() => _AutomaticSongPagingState();
}

class _AutomaticSongPagingState extends State<AutomaticSongPaging> {
  ScrollMetrics? _metrics;
  bool _scheduled = false, _inFlight = false;
  void _schedule() {
    if (_scheduled ||
        !widget.enabled ||
        _inFlight ||
        !TickerMode.valuesOf(context).enabled) {
      return;
    }
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _scheduled = false;
      if (!mounted ||
          !TickerMode.valuesOf(context).enabled ||
          !widget.enabled ||
          _inFlight ||
          _metrics == null ||
          _metrics!.extentAfter > 480) {
        return;
      }
      _inFlight = true;
      try {
        await widget.onLoadMore();
      } finally {
        _inFlight = false;
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  // New content emits fresh ScrollMetricsNotification after layout. An enabled
  // flag changing during rebuild must not reuse the old short-list geometry
  // and accidentally request another page before the new extent is measured.

  @override
  Widget build(BuildContext context) => SongListTools(
    listId: widget.songListId,
    bottom: widget.songListBottom,
    loadMore: widget.onLoadMore,
    hasMore: widget.enabled,
    child: NotificationListener<ScrollMetricsNotification>(
      onNotification: (event) {
        if (event.depth == 0 && event.metrics.axis == Axis.vertical) {
          _metrics = event.metrics;
          if (widget.fillInitialViewport) _schedule();
        }
        return false;
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: (event) {
          if (event.depth == 0 && event.metrics.axis == Axis.vertical) {
            _metrics = event.metrics;
            if (widget.fillInitialViewport ||
                event is ScrollUpdateNotification &&
                    (event.scrollDelta ?? 0) > 0) {
              _schedule();
            }
          }
          return false;
        },
        child: widget.child,
      ),
    ),
  );
}
