import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Animates one recording's artwork/labels without moving the transport
/// buttons or rebuilding the optical capsule. It owns presentation only;
/// gestures, playback requests and track identity remain with the caller.
class PlaybackPillTrackMotion extends StatefulWidget {
  const PlaybackPillTrackMotion({
    required this.trackId,
    required this.dragOffset,
    required this.dragging,
    required this.child,
    this.forward = true,
    super.key,
  });
  final String trackId;
  final double dragOffset;
  final bool dragging;
  final bool forward;
  final Widget child;

  @override
  State<PlaybackPillTrackMotion> createState() =>
      _PlaybackPillTrackMotionState();
}

class _PlaybackPillTrackMotionState extends State<PlaybackPillTrackMotion>
    with TickerProviderStateMixin {
  late final _drag = AnimationController.unbounded(vsync: this);
  late final _change = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
    value: 1,
  )..addStatusListener(_changed);
  Widget? _outgoing;
  double _outgoingStart = 0;
  bool _forward = true;

  void _changed(AnimationStatus status) {
    if (status == AnimationStatus.completed && _outgoing != null && mounted) {
      setState(() => _outgoing = null);
    }
  }

  @override
  void didUpdateWidget(covariant PlaybackPillTrackMotion oldWidget) {
    super.didUpdateWidget(oldWidget);
    final reduced = MediaQuery.disableAnimationsOf(context);
    if (widget.trackId != oldWidget.trackId) {
      // Continue from the actual painted drag offset. A delayed audio request
      // may complete while the cancellation spring is already returning home.
      _outgoingStart = _drag.value;
      _drag.stop();
      _drag.value = 0;
      _forward = widget.forward;
      _outgoing = reduced ? null : oldWidget.child;
      if (reduced) {
        _change.value = 1;
      } else {
        _change.forward(from: 0);
      }
    } else if (widget.dragging) {
      // A fresh gesture takes ownership immediately, including during a prior
      // track transition. Old content never remains an interactive/a11y target.
      _outgoing = null;
      _change.stop();
      _drag.stop();
      _drag.value = reduced ? 0 : widget.dragOffset;
    } else if (oldWidget.dragging ||
        oldWidget.dragOffset != widget.dragOffset) {
      if (reduced) {
        _drag.value = 0;
      } else {
        _drag.animateTo(
          0,
          duration: const Duration(milliseconds: 210),
          curve: Curves.easeOutCubic,
        );
      }
    }
  }

  @override
  void dispose() {
    _change.dispose();
    _drag.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ClipRect(
    child: LayoutBuilder(
      builder: (context, constraints) {
        final distance = math.min(84.0, constraints.maxWidth * .6);
        return AnimatedBuilder(
          animation: Listenable.merge([_drag, _change]),
          child: widget.child,
          builder: (context, child) {
            if (_outgoing == null) {
              return Transform.translate(
                key: const ValueKey('pill-track-follow'),
                offset: Offset(_drag.value, 0),
                child: child,
              );
            }
            final p = Curves.easeOutCubic.transform(_change.value);
            final sign = _forward ? -1.0 : 1.0;
            return Stack(
              alignment: Alignment.centerLeft,
              children: [
                ExcludeSemantics(
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: 1 - p,
                      child: Transform.translate(
                        key: const ValueKey('pill-track-outgoing'),
                        offset: Offset(
                          ui.lerpDouble(_outgoingStart, sign * distance, p)!,
                          0,
                        ),
                        child: _outgoing,
                      ),
                    ),
                  ),
                ),
                Opacity(
                  opacity: p,
                  child: Transform.translate(
                    key: const ValueKey('pill-track-incoming'),
                    offset: Offset(-sign * distance * (1 - p), 0),
                    child: child,
                  ),
                ),
              ],
            );
          },
        );
      },
    ),
  );
}
