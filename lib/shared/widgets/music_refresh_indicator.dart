import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/platform/distribution_channel.dart';
import 'artwork_reveal_boundary.dart';
import 'music_activity_indicator.dart';
import 'music_loading_scope.dart';

/// Retains the existing scrollable, gesture thresholds and refresh callback.
/// In Beta, Material owns only the pull gesture. The enclosing content viewport
/// paints one Apple indicator; a standalone page paints its own identical one.
class MusicRefreshIndicator extends StatefulWidget {
  const MusicRefreshIndicator({
    required this.onRefresh,
    required this.child,
    this.notificationPredicate = defaultScrollNotificationPredicate,
    super.key,
  });
  final RefreshCallback onRefresh;
  final Widget child;
  final ScrollNotificationPredicate notificationPredicate;
  @override
  State<MusicRefreshIndicator> createState() => _MusicRefreshIndicatorState();
}

class _MusicRefreshIndicatorState extends State<MusicRefreshIndicator> {
  final Object _lease = Object();
  ArtworkRevealController? _viewport;
  bool _visible = false;
  bool _active = true;
  bool _leadingPull = false;
  RefreshIndicatorStatus? _phase;
  Future<void>? _refresh;
  RenderBox? _renderBox() {
    if (!mounted || !_active) return null;
    final render = context.findRenderObject();
    return render is RenderBox ? render : null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final viewport = ArtworkRevealBoundary.of(context);
    if (viewport == _viewport) return;
    _viewport?.refreshActivity(_lease, false);
    _viewport = viewport;
    if (_visible) _viewport?.refreshActivity(_lease, true, box: _renderBox);
  }

  void _status(RefreshIndicatorStatus? status) {
    _phase = status;
    _synchronizeVisibility();
  }

  bool _notification(ScrollNotification notification) {
    if (!widget.notificationPredicate(notification)) return false;
    if (notification is ScrollStartNotification) _leadingPull = false;
    if (notification is ScrollUpdateNotification &&
        notification.dragDetails != null) {
      // RefreshIndicator enters `drag` as soon as a gesture starts at the
      // leading edge, even when the finger is about to scroll toward later
      // songs. Paint the top indicator only after an actual leading pull.
      _leadingPull =
          notification.metrics.pixels < notification.metrics.minScrollExtent;
      _synchronizeVisibility();
    }
    return true;
  }

  void _synchronizeVisibility() {
    final visible =
        (_phase == RefreshIndicatorStatus.drag && _leadingPull) ||
        _phase == RefreshIndicatorStatus.armed ||
        _phase == RefreshIndicatorStatus.snap ||
        _phase == RefreshIndicatorStatus.refresh;
    if (_visible == visible || !mounted) return;
    _viewport?.refreshActivity(_lease, visible, box: _renderBox);
    setState(() => _visible = visible);
  }

  Future<void> _run() {
    if (_refresh != null) return _refresh!;
    final future = Future<void>.sync(widget.onRefresh);
    _refresh = future;
    // Identity guards stop an old completion from affecting a later gesture.
    unawaited(
      future.then<void>(
        (_) {
          if (identical(_refresh, future)) _refresh = null;
        },
        onError: (Object error, StackTrace stack) {
          if (identical(_refresh, future)) _refresh = null;
        },
      ),
    );
    return future;
  }

  @override
  void deactivate() {
    _active = false;
    _viewport?.refreshActivity(_lease, false);
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    _active = true;
    if (_visible) _viewport?.refreshActivity(_lease, true, box: _renderBox);
  }

  @override
  void dispose() {
    _viewport?.refreshActivity(_lease, false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!DistributionChannel.isBeta) {
      return RefreshIndicator(
        onRefresh: widget.onRefresh,
        notificationPredicate: widget.notificationPredicate,
        child: widget.child,
      );
    }
    return MusicLoadingScope(
      covered: _visible,
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          AnimatedPadding(
            padding: EdgeInsets.only(top: _visible ? 64 : 0),
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            child: RefreshIndicator.noSpinner(
              onRefresh: _run,
              onStatusChange: _status,
              notificationPredicate: _notification,
              child: widget.child,
            ),
          ),
          if (_visible && _viewport == null)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: EdgeInsets.only(top: 18),
                    child: Center(
                      child: MusicActivityIndicator(independent: true),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
