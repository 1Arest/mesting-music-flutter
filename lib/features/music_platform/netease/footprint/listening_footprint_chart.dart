import 'dart:math' as math;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../themes/beta_appearance.dart';
import 'official_footprint.dart';
import '../../../themes/music_typography.dart';

/// A null value is an unavailable official bucket. It is deliberately different
/// from the valid zero-duration baseline, both visually and in accessibility.
class FootprintChartBar {
  const FootprintChartBar({
    required this.id,
    required this.label,
    required this.caption,
    required this.seconds,
  });
  final String id, label, caption;
  final int? seconds;
}

/// One chart geometry serves seven days, a month and source-returned years.
/// The whole plot supports scrubbing, so thirty-one narrow bars do not depend
/// on pixel-precise tapping. Each bucket also has an accessible selection action.
class FootprintDurationChart extends StatelessWidget {
  const FootprintDurationChart({
    required this.bars,
    required this.selected,
    required this.onSelected,
    super.key,
  });
  final List<FootprintChartBar> bars;
  final String? selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    if (bars.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context), scheme = theme.colorScheme;
    final red = BetaAppearance.navigation(theme.brightness);
    final maximum = math.max(
      60,
      bars.fold<int>(0, (v, bar) => math.max(v, bar.seconds ?? 0)),
    );
    final scale = (MediaQuery.textScalerOf(context).scale(12) / 12).clamp(
      1.0,
      1.7,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            '最高 ${officialDuration(maximum)}',
            style: TextStyle(
              fontSize: MusicTypography.smallCaptionSize,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 174,
          child: LayoutBuilder(
            builder: (context, constraints) {
              void selectAt(double x) {
                final index = (x / constraints.maxWidth * bars.length)
                    .floor()
                    .clamp(0, bars.length - 1);
                onSelected(bars[index].id);
              }

              return GestureDetector(
                key: const ValueKey('footprint-chart-scrub'),
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) => selectAt(d.localPosition.dx),
                onHorizontalDragUpdate: (d) => selectAt(d.localPosition.dx),
                child: CustomPaint(
                  painter: _FootprintGrid(
                    scheme.outlineVariant.withValues(alpha: .4),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final bar in bars)
                        Expanded(
                          child: Semantics(
                            key: ValueKey('footprint-bar-${bar.id}'),
                            button: true,
                            selected: selected == bar.id,
                            label:
                                '${bar.caption}，${bar.seconds == null ? '官方未返回数据' : officialDuration(bar.seconds!)}',
                            onTap: () => onSelected(bar.id),
                            child: ExcludeSemantics(
                              child: Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: bars.length > 12 ? 2 : 6,
                                ),
                                child: Align(
                                  alignment: Alignment.bottomCenter,
                                  child: bar.seconds == null
                                      ? Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 2,
                                          ),
                                          child: Icon(
                                            CupertinoIcons.minus,
                                            size: 8,
                                            color: scheme.onSurfaceVariant,
                                          ),
                                        )
                                      : FractionallySizedBox(
                                          widthFactor: bars.length > 12
                                              ? .86
                                              : .65,
                                          heightFactor: math.max(
                                            .013,
                                            bar.seconds! / maximum,
                                          ),
                                          child: DecoratedBox(
                                            decoration: BoxDecoration(
                                              color: red.withValues(
                                                alpha: selected == bar.id
                                                    ? 1
                                                    : .4,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(
                                                    bars.length > 12 ? 2.5 : 5,
                                                  ),
                                            ),
                                          ),
                                        ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 9),
        SizedBox(
          height: 18 * scale,
          child: Row(
            children: [
              for (final bar in bars)
                Expanded(
                  child: ExcludeSemantics(
                    child: Text(
                      bar.label,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style: TextStyle(
                        fontSize: MusicTypography.smallCaptionSize,
                        fontWeight: MusicTypography.bodyWeight,
                        color: selected == bar.id
                            ? scheme.onSurface
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FootprintGrid extends CustomPainter {
  const _FootprintGrid(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = .5;
    for (var i = 0; i <= 3; i++) {
      final y = size.height * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_FootprintGrid oldDelegate) => oldDelegate.color != color;
}
