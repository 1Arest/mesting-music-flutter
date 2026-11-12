import 'package:flutter/material.dart';
import '../../shared/widgets/beta_glass_controls.dart';

/// A bounded, non-scrolling grid. The owning page keeps one vertical viewport;
/// the shared glass button owns press cancellation, focus and accessibility.
class StyleOptionGrid extends StatelessWidget {
  const StyleOptionGrid({
    required this.values,
    required this.labels,
    required this.selected,
    required this.onSelected,
    required this.keyPrefix,
    this.preview,
    super.key,
  });
  final List<String> values, labels;
  final String selected, keyPrefix;
  final ValueChanged<String>? onSelected;
  final Widget Function(String value)? preview;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final columns = bounds.maxWidth >= 600 ? 3 : 2;
      final width = (bounds.maxWidth - 12 * (columns - 1)) / columns;
      final height = (preview == null ? 64.0 : 144.0) + (scale - 1) * 34;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (var i = 0; i < values.length; i++)
            Semantics(
              selected: selected == values[i],
              child: BetaGlassButton(
                key: ValueKey('$keyPrefix-${values[i]}'),
                width: width,
                height: height,
                borderRadius: 18,
                horizontalPadding: 12,
                accent: selected == values[i],
                label: '${labels[i]}${selected == values[i] ? '，已选择' : ''}',
                onPressed: onSelected == null
                    ? null
                    : () => onSelected!(values[i]),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (preview != null) ...[
                      SizedBox(
                        height: 76,
                        child: IgnorePointer(child: preview!(values[i])),
                      ),
                      const SizedBox(height: 10),
                    ],
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (selected == values[i]) ...[
                          Icon(
                            Icons.check_circle_rounded,
                            size: 17,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 5),
                        ],
                        Flexible(
                          child: Text(
                            labels[i],
                            maxLines: 2,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 14, height: 1.2),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    },
  );
}
