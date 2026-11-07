import 'dart:math' as math;

import 'package:flutter/material.dart';

const _playingEqualizerPhases = <double>[0, .17, .39, .62, .81];
const _playingEqualizerAmplitudes = <double>[.68, 1, .78, .94, .62];

@visibleForTesting
double playingEqualizerBarHeight({
  required double progress,
  required int index,
  required double canvasHeight,
}) {
  assert(index >= 0 && index < _playingEqualizerPhases.length);
  final wave =
      (math.sin((progress + _playingEqualizerPhases[index]) * math.pi * 2) +
          1) /
      2;
  return canvasHeight * (.24 + wave * .64 * _playingEqualizerAmplitudes[index]);
}

class PlayingEqualizer extends StatefulWidget {
  const PlayingEqualizer({
    required this.animate,
    this.color = const Color(0xFF4F65D1),
    this.size = 22,
    super.key,
  });

  final bool animate;
  final Color color;
  final double size;

  @override
  State<PlayingEqualizer> createState() => _PlayingEqualizerState();
}

class _PlayingEqualizerState extends State<PlayingEqualizer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 720),
      value: .12,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant PlayingEqualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animate != widget.animate) {
      _syncAnimation();
    }
  }

  void _syncAnimation() {
    if (widget.animate && !_reduceMotion) {
      if (!_controller.isAnimating) {
        _controller.repeat();
      }
      return;
    }
    _controller
      ..stop()
      ..value = .12;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.animate ? '正在播放' : '播放已暂停',
      child: RepaintBoundary(
        key: const ValueKey('playing-equalizer-repaint-boundary'),
        child: CustomPaint(
          painter: _PlayingEqualizerPainter(
            animation: _controller,
            color: widget.color,
          ),
          child: SizedBox.square(dimension: widget.size),
        ),
      ),
    );
  }
}

class _PlayingEqualizerPainter extends CustomPainter {
  _PlayingEqualizerPainter({
    required Animation<double> animation,
    required this.color,
  }) : _animation = animation,
       super(repaint: animation);

  final Animation<double> _animation;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final barWidth = math.max(1.5, size.width * .085);
    final gap = barWidth * .72;
    final contentWidth =
        _playingEqualizerPhases.length * barWidth +
        (_playingEqualizerPhases.length - 1) * gap;
    final startX = (size.width - contentWidth) / 2;
    final centerY = size.height / 2;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    for (var index = 0; index < _playingEqualizerPhases.length; index += 1) {
      final height = playingEqualizerBarHeight(
        progress: _animation.value,
        index: index,
        canvasHeight: size.height,
      );
      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(
            startX + index * (barWidth + gap) + barWidth / 2,
            centerY,
          ),
          width: barWidth,
          height: height,
        ),
        Radius.circular(barWidth / 2),
      );
      canvas.drawRRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _PlayingEqualizerPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate._animation != _animation;
  }
}
