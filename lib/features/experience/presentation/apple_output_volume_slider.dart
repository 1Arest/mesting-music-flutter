import 'package:flutter/material.dart';

/// Dialog-only volume presentation. Slider keeps framework keyboard/semantics
/// and drag cancellation; callers retain the one native system-volume owner.
class AppleOutputVolumeSlider extends StatelessWidget {
  const AppleOutputVolumeSlider({
    required this.value,
    required this.ink,
    required this.onChanged,
    required this.onChangeEnd,
    super.key,
  });
  final double value;
  final Color ink;
  final ValueChanged<double>? onChanged, onChangeEnd;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 48,
    child: SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 7,
        trackShape: const RoundedRectSliderTrackShape(),
        activeTrackColor: ink.withValues(alpha: .82),
        inactiveTrackColor: ink.withValues(alpha: .16),
        disabledActiveTrackColor: ink.withValues(alpha: .25),
        disabledInactiveTrackColor: ink.withValues(alpha: .1),
        thumbColor: Colors.white,
        thumbShape: const _VolumeThumb(),
        overlayShape: SliderComponentShape.noOverlay,
        showValueIndicator: ShowValueIndicator.never,
        trackGap: 0,
      ),
      child: Slider(
        value: value.clamp(0, 1),
        semanticFormatterCallback: (value) => '${(value * 100).round()}%',
        onChanged: onChanged,
        onChangeEnd: onChangeEnd,
      ),
    ),
  );
}

class _VolumeThumb extends SliderComponentShape {
  const _VolumeThumb();
  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => const Size(20, 16);
  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final amount = activationAnimation.value;
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: center,
        width: 20 + 3 * amount,
        height: 16 + 2 * amount,
      ),
      const Radius.circular(10),
    );
    context.canvas.drawShadow(Path()..addRRect(rect), Colors.black26, 2, true);
    context.canvas.drawRRect(rect, Paint()..color = Colors.white);
    context.canvas.drawRRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = .6
        ..color = const Color(0x24000000),
    );
  }
}
