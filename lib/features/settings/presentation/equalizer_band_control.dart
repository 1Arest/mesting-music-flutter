import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../themes/music_typography.dart';

/// Reserve gain width using the device's full range, so changing sign or value
/// never wraps the readout and moves the slider. Narrow/large-type layouts put
/// the labels above a full-width drag target instead of squeezing the control.
class EqualizerBandControl extends StatelessWidget {
  const EqualizerBandControl({
    required this.index,
    required this.frequency,
    required this.value,
    required this.minimum,
    required this.maximum,
    required this.onChanged,
    required this.onChangeEnd,
    super.key,
  });

  final int index;
  final String frequency;
  final double value, minimum, maximum;
  final ValueChanged<double>? onChanged, onChangeEnd;

  String _gain(double value) =>
      '${value > 0 ? '+' : ''}${value.toStringAsFixed(1)} dB';

  double _width(BuildContext context, String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final width = painter.width.ceilToDouble() + 4;
    painter.dispose();
    return width;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final baseStyle = DefaultTextStyle.of(context).style;
    final frequencyStyle = baseStyle.merge(
      const TextStyle(
        fontSize: MusicTypography.footnoteSize,
        fontWeight: MusicTypography.bodyWeight,
      ),
    );
    final gainStyle = baseStyle.merge(
      TextStyle(
        fontSize: MusicTypography.captionSize,
        color: scheme.onSurfaceVariant,
      ),
    );
    final gainWidth = [
      minimum,
      maximum,
      0.0,
    ].map((v) => _width(context, _gain(v), gainStyle)).reduce(math.max);
    final frequencyWidth = math.max(
      55.0,
      _width(context, frequency, frequencyStyle),
    );
    final frequencyLabel = Text(frequency, style: frequencyStyle, maxLines: 1);
    final gainLabel = SizedBox(
      width: gainWidth,
      child: Text(
        _gain(value),
        style: gainStyle,
        maxLines: 1,
        textAlign: TextAlign.right,
      ),
    );
    final slider = Semantics(
      label: '$frequency 频段增益',
      child: SliderTheme(
        data: SliderTheme.of(context).copyWith(
          trackHeight: 2,
          trackShape: const RectangularSliderTrackShape(),
          activeTrackColor: scheme.primary,
          inactiveTrackColor: scheme.outlineVariant,
          thumbColor: scheme.primary,
          disabledThumbColor: scheme.onSurfaceVariant,
          // Preserve the existing 6dp visual point and 48dp drag target.
          thumbShape: const RoundSliderThumbShape(
            enabledThumbRadius: 3,
            disabledThumbRadius: 3,
            elevation: 0,
            pressedElevation: 0,
          ),
          overlayShape: SliderComponentShape.noOverlay,
          showValueIndicator: ShowValueIndicator.never,
        ),
        child: SizedBox(
          height: 48,
          child: Slider(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            key: ValueKey('music-equalizer-band-$index'),
            value: value.clamp(minimum, maximum),
            min: minimum,
            max: maximum,
            semanticFormatterCallback: (v) => '${v.toStringAsFixed(1)} 分贝',
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
          ),
        ),
      ),
    );
    return LayoutBuilder(
      builder: (context, bounds) {
        if (bounds.maxWidth - frequencyWidth - gainWidth < 120) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: 8,
                runSpacing: 4,
                children: [frequencyLabel, gainLabel],
              ),
              slider,
            ],
          );
        }
        return Row(
          children: [
            SizedBox(width: frequencyWidth, child: frequencyLabel),
            Expanded(child: slider),
            gainLabel,
          ],
        );
      },
    );
  }
}
