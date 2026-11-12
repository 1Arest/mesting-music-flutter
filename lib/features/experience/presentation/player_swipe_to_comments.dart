import 'package:flutter/material.dart';

/// Only the artwork page opts in. Child scroll views, horizontal sliders and
/// the existing dismiss handle retain their own gesture recognizers.
class PlayerSwipeToComments extends StatefulWidget {
  const PlayerSwipeToComments({
    required this.enabled,
    required this.onOpenComments,
    required this.child,
    super.key,
  });

  final bool enabled;
  final Future<void> Function() onOpenComments;
  final Widget child;

  @override
  State<PlayerSwipeToComments> createState() => _PlayerSwipeToCommentsState();
}

class _PlayerSwipeToCommentsState extends State<PlayerSwipeToComments> {
  Offset? _start;
  Offset _travel = Offset.zero;
  bool _opening = false;
  bool _cancelled = false;

  void _reset() {
    _start = null;
    _travel = Offset.zero;
  }

  Future<void> _finish(double velocity) async {
    final travel = _travel;
    _reset();
    // Pointer cancellation may reach the listener after the recognizer's end
    // callback. Let the current pointer event finish before committing a route.
    await Future<void>.value();
    if (!mounted || _cancelled) return;
    final upward = -travel.dy;
    if (!widget.enabled ||
        _opening ||
        ModalRoute.of(context)?.isCurrent == false ||
        upward <= travel.dx.abs() * 1.25 ||
        !(upward >= 64 || (upward >= 32 && velocity <= -700))) {
      return;
    }
    _opening = true;
    try {
      await widget.onOpenComments();
    } finally {
      _opening = false;
    }
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: (_) => _cancelled = false,
    // An accepted drag can report cancellation through onEnd, not onCancel.
    onPointerCancel: (_) {
      _cancelled = true;
      _reset();
    },
    child: GestureDetector(
      key: const ValueKey('player-swipe-to-comments'),
      behavior: HitTestBehavior.translucent,
      onVerticalDragStart: widget.enabled
          ? (details) {
              _start = details.globalPosition;
              _travel = Offset.zero;
            }
          : null,
      onVerticalDragUpdate: widget.enabled
          ? (details) {
              if (_start case final start?) {
                _travel = details.globalPosition - start;
              }
            }
          : null,
      onVerticalDragEnd: widget.enabled
          ? (details) => _finish(details.primaryVelocity ?? 0)
          : null,
      onVerticalDragCancel: widget.enabled ? _reset : null,
      child: widget.child,
    ),
  );
}
