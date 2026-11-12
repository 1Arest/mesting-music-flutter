import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../themes/beta_appearance.dart';
import '../../themes/music_typography.dart';

/// Calendar presentation only. Completion and today's focus are independent:
/// green confirms a saved sign-in, while a blue outline identifies today.
class PlatformRewardDay extends StatelessWidget {
  const PlatformRewardDay({
    required this.number,
    required this.month,
    required this.checked,
    required this.today,
    required this.future,
    this.unconfirmed = false,
    super.key,
  });

  final int number, month;
  final bool checked, today, future, unconfirmed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final green = BetaAppearance.success(scheme.brightness);
    return Semantics(
      label:
          '$month月$number日，${today ? '今天，' : ''}'
          '${checked
              ? '已签到'
              : future
              ? '未到日期'
              : unconfirmed
              ? '暂无确认记录'
              : '未签到'}',
      child: ExcludeSemantics(
        child: Center(
          child: Container(
            key: ValueKey('reward-day-$number'),
            width: 44,
            height: 48,
            decoration: BoxDecoration(
              color: checked
                  ? BetaAppearance.successSurface(scheme.brightness)
                  : null,
              borderRadius: BorderRadius.circular(14),
              border: today
                  ? Border.all(color: scheme.primary, width: 1.5)
                  : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '$number',
                      maxLines: 1,
                      softWrap: false,
                      style: TextStyle(
                        fontSize: MusicTypography.calloutSize,
                        height: 1.05,
                        fontWeight: MusicTypography.bodyWeight,
                        color: checked
                            ? green
                            : future
                            ? scheme.onSurfaceVariant.withValues(alpha: .65)
                            : scheme.onSurface,
                      ),
                    ),
                  ),
                ),
                if (checked) ...[
                  const SizedBox(height: 2),
                  Icon(CupertinoIcons.check_mark, size: 14, color: green),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
