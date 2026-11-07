import 'package:flutter/material.dart';

/// Only overflowing navigation titles animate. Text is measured once per
/// geometry/text change; frames translate a stable child without relayout.
class OverflowMarquee extends StatefulWidget {
  const OverflowMarquee(this.text, {required this.style, super.key});
  final String text;
  final TextStyle style;
  @override
  State<OverflowMarquee> createState() => _OverflowMarqueeState();
}

class _OverflowMarqueeState extends State<OverflowMarquee>
    with SingleTickerProviderStateMixin {
  late final _motion = AnimationController(vsync: this);
  double _distance = -1;
  bool _reduce = false;
  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  void _configure(double distance, bool reduce) {
    if (_distance == distance && _reduce == reduce) return;
    _distance = distance;
    _reduce = reduce;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _motion.stop();
      _motion.value = 0;
      if (_distance > 0 && !_reduce) {
        _motion.duration = Duration(
          milliseconds: 2400 + (_distance / 30 * 1000).round(),
        );
        _motion.repeat();
      }
    });
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      // Measure the same inherited family and spacing that Text will render.
      final style = DefaultTextStyle.of(context).style.merge(widget.style);
      final painter = TextPainter(
        text: TextSpan(text: widget.text, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
      )..layout();
      final distance = (painter.width - bounds.maxWidth).clamp(
        0.0,
        double.infinity,
      );
      _configure(distance, MediaQuery.disableAnimationsOf(context));
      return Semantics(
        label: widget.text,
        header: true,
        child: ExcludeSemantics(
          child: ClipRect(
            child: SizedBox(
              height: painter.height,
              child: AnimatedBuilder(
                animation: _motion,
                child: OverflowBox(
                  alignment: Alignment.centerLeft,
                  maxWidth: double.infinity,
                  child: Text(
                    widget.text,
                    maxLines: 1,
                    softWrap: false,
                    style: style,
                  ),
                ),
                builder: (_, child) {
                  final dwell = _motion.duration == null
                      ? .2
                      : 1200 / _motion.duration!.inMilliseconds;
                  final t = ((_motion.value - dwell) / (1 - 2 * dwell)).clamp(
                    0.0,
                    1.0,
                  );
                  return Transform.translate(
                    offset: Offset(-distance * t, 0),
                    child: child,
                  );
                },
              ),
            ),
          ),
        ),
      );
    },
  );
}
