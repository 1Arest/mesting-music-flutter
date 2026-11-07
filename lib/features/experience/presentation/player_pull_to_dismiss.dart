import 'package:flutter/material.dart';
import 'player_dismiss_motion.dart';

/// The handle owns dismissal; artwork, lyric scrolling and adjustable controls
/// never compete with this vertical drag. AnimatedBuilder keeps the live
/// player subtree stable throughout the gesture on every display refresh rate.
class PlayerPullToDismiss extends StatefulWidget {
  const PlayerPullToDismiss({
    required this.child,
    required this.onDismiss,
    this.onProgress,
    super.key,
  });
  final Widget child;
  final VoidCallback onDismiss;
  final ValueChanged<double>? onProgress;
  @override
  State<PlayerPullToDismiss> createState() => _PlayerPullToDismissState();
}

class _PlayerPullToDismissState extends State<PlayerPullToDismiss>
    with SingleTickerProviderStateMixin {
  late final AnimationController _offset = AnimationController.unbounded(
    vsync: this,
  );
  bool _closing = false;
  PlayerDismissMotion? _routeMotion;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    final motion = route is PlayerDismissRoute
        ? (route as PlayerDismissRoute).playerDismissMotion
        : null;
    if (motion == _routeMotion) return;
    _routeMotion?.controller.removeListener(_reportRouteProgress);
    _routeMotion = motion;
    motion?.controller.addListener(_reportRouteProgress);
  }

  void _reportRouteProgress() {
    if (!mounted) return;
    final motion = _routeMotion!;
    // 1-controller.value is also high at the start of an entrance. Reporting
    // it unconditionally painted the whole bottom bar over the rising player.
    // Reveal belongs only to a dismissal or a finger-owned cancel/complete.
    final entering =
        !motion.dragDriven &&
        motion.controller.status == AnimationStatus.forward;
    widget.onProgress?.call(entering ? 0 : motion.progress);
  }

  @override
  void initState() {
    super.initState();
    _offset.addListener(
      () => widget.onProgress?.call(
        (_offset.value / (MediaQuery.sizeOf(context).height * .55)).clamp(
          0.0,
          1.0,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _routeMotion?.controller.removeListener(_reportRouteProgress);
    _offset.dispose();
    super.dispose();
  }

  void update(DragUpdateDetails details) {
    if (_closing) return;
    final motion = _routeMotion;
    if (motion != null) {
      motion.update(details.delta.dy, MediaQuery.sizeOf(context).height);
      return;
    }
    _offset.stop();
    _offset.value = (_offset.value + details.delta.dy).clamp(
      0,
      MediaQuery.sizeOf(context).height,
    );
  }

  Future<void> finish([double speed = 0, bool cancelled = false]) async {
    if (_closing) return;
    final height = MediaQuery.sizeOf(context).height;
    final motion = _routeMotion;
    if (motion != null) {
      await motion.finish(
        speed: speed,
        height: height,
        cancelled: cancelled,
        reduceMotion: MediaQuery.disableAnimationsOf(context),
        onDismiss: widget.onDismiss,
      );
      return;
    }
    final close =
        !cancelled &&
        (_offset.value > height * .18 || (_offset.value > 16 && speed > 650));
    _closing = close;
    try {
      await _offset
          .animateTo(
            close ? height : 0,
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : Duration(milliseconds: close ? 240 : 280),
            curve: Curves.easeOutCubic,
          )
          .orCancel;
    } on TickerCanceled {
      return;
    }
    if (mounted && close) widget.onDismiss();
  }

  @override
  Widget build(BuildContext context) => _DismissHandleScope(
    state: this,
    child: AnimatedBuilder(
      animation: _offset,
      child: widget.child,
      builder: (context, child) => Transform.translate(
        offset: Offset(0, _offset.value),
        child: ClipRRect(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(_offset.value > 0 ? 24 : 0),
          ),
          child: child,
        ),
      ),
    ),
  );
}

class _DismissHandleScope extends InheritedWidget {
  const _DismissHandleScope({required this.state, required super.child});
  final _PlayerPullToDismissState state;
  @override
  bool updateShouldNotify(_DismissHandleScope oldWidget) =>
      state != oldWidget.state;
}

class PlayerDismissHandle extends StatelessWidget {
  const PlayerDismissHandle({required this.onTap, super.key});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final state = context
        .dependOnInheritedWidgetOfExactType<_DismissHandleScope>()!
        .state;
    return Semantics(
      label: '向下拖动收起播放器',
      button: true,
      child: GestureDetector(
        key: const ValueKey('player-dismiss-handle'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onVerticalDragUpdate: state.update,
        onVerticalDragEnd: (details) =>
            state.finish(details.primaryVelocity ?? 0),
        onVerticalDragCancel: () => state.finish(0, true),
        child: SizedBox(
          width: 112,
          height: 36,
          child: Center(
            child: Container(
              width: 48,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.white38,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
