import 'package:flutter/material.dart';
import 'official_report_extras.dart';

/// The official report compares its leading languages in three vertical
/// columns. Keep the server's percentages (which need not total 100), while
/// using the application's own grouped surfaces, blue accent and typography.
class OfficialReportLanguageChart extends StatelessWidget {
  const OfficialReportLanguageChart({required this.languages, super.key});
  final List<OfficialReportItem> languages;

  @override
  Widget build(BuildContext context) {
    final rows = languages.take(3).toList();
    final scheme = Theme.of(context).colorScheme;
    final maximum = rows.fold<double>(
      0,
      (n, row) => (row.percent ?? 0) > n ? row.percent! : n,
    );
    final textScale = MediaQuery.textScalerOf(context).scale(16) / 16;
    final chartHeight = 116.0 + ((textScale - 1) * 28).clamp(0, 56);
    return Container(
      key: const ValueKey('footprint-language-chart'),
      padding: const EdgeInsets.fromLTRB(14, 20, 14, 16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var index = 0; index < rows.length; index++) ...[
            if (index > 0) const SizedBox(width: 12),
            Expanded(
              child: Semantics(
                label: '${rows[index].title} ${_percent(rows[index].percent)}',
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        _percent(rows[index].percent),
                        key: ValueKey('footprint-language-percent-$index'),
                        style: TextStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.w600,
                          color: scheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      rows[index].title,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      height: chartHeight,
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: FractionallySizedBox(
                          key: ValueKey('footprint-language-column-$index'),
                          widthFactor: .65,
                          heightFactor: maximum > 0
                              ? ((rows[index].percent ?? 0) / maximum).clamp(
                                  .06,
                                  1,
                                )
                              : .06,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  scheme.primary.withValues(alpha: .88),
                                  scheme.primary.withValues(alpha: .20),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _percent(double? value) =>
      value == null ? '—' : '${value.toStringAsFixed(value % 1 == 0 ? 0 : 1)}%';
}
