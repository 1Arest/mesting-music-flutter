import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../themes/music_typography.dart';

/// Stable preset geometry keeps the frequency sliders under a stationary grid.
/// Selection changes only paint: every chip reserves the same checkmark slot.
class EqualizerPresetPicker extends StatelessWidget {
  const EqualizerPresetPicker({
    required this.names,
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final Iterable<String> names;
  final String selected;
  final ValueChanged<String>? onSelected;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final theme = Theme.of(context);
      final style = theme.textTheme.labelLarge!
          .merge(theme.chipTheme.labelStyle)
          .copyWith(fontSize: MusicTypography.footnoteSize);
      var labelWidth = 0.0;
      for (final name in names) {
        final painter = TextPainter(
          text: TextSpan(text: name, style: style),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();
        labelWidth = math.max(labelWidth, painter.width);
        painter.dispose();
      }
      const gap = 8.0;
      // The longest localized label, chip padding and a permanent 16dp icon
      // determine the column count. Larger system type naturally uses fewer
      // columns instead of clipping names or shrinking accessibility text.
      final minimumWidth = labelWidth + 48;
      final columns = math.max(
        1,
        ((constraints.maxWidth + gap) / (minimumWidth + gap)).floor(),
      );
      final width = (constraints.maxWidth - (columns - 1) * gap) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final name in names)
            SizedBox(
              width: width,
              child: ChoiceChip(
                key: ValueKey('equalizer-preset-$name'),
                label: Text(name),
                labelStyle: style,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                avatarBoxConstraints: const BoxConstraints.tightFor(
                  width: 16,
                  height: 16,
                ),
                selected: selected == name,
                showCheckmark: false,
                avatar: Opacity(
                  opacity: selected == name ? 1 : 0,
                  child: const Icon(Icons.check_rounded, size: 16),
                ),
                onSelected: onSelected == null
                    ? null
                    : (_) => onSelected!(name),
              ),
            ),
        ],
      );
    },
  );
}
