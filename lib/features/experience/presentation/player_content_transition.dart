import 'package:flutter/material.dart';

/// One incoming and at most one outgoing surface share the existing transport.
/// Rapid cover/lyrics/queue changes replace the old departing surface rather
/// than accumulating AnimatedSwitcher's unbounded set of outgoing children.
/// Reversing to the outgoing child reuses its element and current opacity.
class PlayerContentTransition extends StatefulWidget {
  const PlayerContentTransition({
    required this.child,
    this.duration = const Duration(milliseconds: 360),
    this.direction = 1,
    super.key,
  });
  final Widget child;
  final Duration duration;
  final double direction;
  @override
  State<PlayerContentTransition> createState() =>
      _PlayerContentTransitionState();
}

class _PlayerContentTransitionState extends State<PlayerContentTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: widget.duration,
    value: 1,
  )..addStatusListener(_status);
  late Widget _current = widget.child;
  Widget? _outgoing;
  var _serial = 0, _currentId = 0;
  int? _outgoingId;
  double _currentStart = 1, _outgoingStart = 0;

  double get _incomingAlpha =>
      _currentStart +
      (1 - _currentStart) * Curves.easeOutCubic.transform(_motion.value);
  double get _outgoingAlpha {
    // Match the previous AnimatedSwitcher reverseDuration and reverse curve:
    // its parent runs from 1 to 0 over 280ms (easeIn(1 - t), not 1 - easeIn(t)).
    // Keeping an almost-opaque old lyrics surface for 360ms adds needless GPU
    // compositing and also changes the established fade's visual timing.
    final progress = (_motion.value * widget.duration.inMicroseconds / 280000)
        .clamp(0.0, 1.0);
    return _outgoingStart * Curves.easeInCubic.transform(1 - progress);
  }

  void _status(AnimationStatus status) {
    if (status == AnimationStatus.completed && mounted && _outgoing != null) {
      setState(() {
        _outgoing = null;
        _outgoingId = null;
      });
    }
  }

  @override
  void didUpdateWidget(covariant PlayerContentTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    _motion.duration = widget.duration;
    if (Widget.canUpdate(_current, widget.child)) {
      _current = widget.child;
      return;
    }
    final currentAlpha = _incomingAlpha;
    final outgoingAlpha = _outgoingAlpha;
    final reversed =
        _outgoing != null && Widget.canUpdate(_outgoing!, widget.child);
    final previous = _current, previousId = _currentId;
    _currentId = reversed ? _outgoingId! : ++_serial;
    _current = widget.child;
    _currentStart = reversed ? outgoingAlpha : 0;
    _outgoing = previous;
    _outgoingId = previousId;
    _outgoingStart = currentAlpha;
    if (MediaQuery.disableAnimationsOf(context)) {
      _outgoing = null;
      _outgoingId = null;
      _motion.value = 1;
    } else {
      _motion.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  Widget _surface(Widget child, int id, {required bool outgoing}) {
    // Keeping this entire wrapper keyed allows an interrupted reverse to move
    // the same lyrics/list element between stack slots without remounting it.
    return _PlayerTransitionSurface(
      key: ValueKey(id),
      outgoing: outgoing,
      opacity: outgoing ? _outgoingAlpha : _incomingAlpha,
      direction: widget.direction,
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _motion,
    builder: (context, _) => Stack(
      alignment: Alignment.center,
      fit: StackFit.passthrough,
      children: [
        if (_outgoing != null)
          _surface(_outgoing!, _outgoingId!, outgoing: true),
        _surface(_current, _currentId, outgoing: false),
      ],
    ),
  );
}

class _PlayerTransitionSurface extends StatelessWidget {
  const _PlayerTransitionSurface({
    required this.outgoing,
    required this.opacity,
    required this.direction,
    required this.child,
    super.key,
  });
  final bool outgoing;
  final double opacity, direction;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final distance = 1 - opacity;
    return IgnorePointer(
      ignoring: outgoing,
      child: ExcludeSemantics(
        excluding: outgoing,
        child: TickerMode(
          enabled: !outgoing,
          child: Opacity(
            opacity: opacity.clamp(0, 1),
            child: FractionalTranslation(
              translation: Offset(
                (outgoing ? -1 : 1) * direction * .045 * distance,
                .018 * distance,
              ),
              child: Transform.scale(
                scale: 1 - .015 * distance,
                child: RepaintBoundary(child: child),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
