import '../../../shared/widgets/beta_page_motion.dart';
import '../../../shared/widgets/beta_content_insets.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/beta_glass_controls.dart';
import '../../../shared/widgets/music_notice.dart';
import '../../../shared/widgets/quiet_pull_to_refresh.dart';
import '../domain/platform_rewards.dart';
import '../platform_rewards_provider.dart';
import '../platform_backend_providers.dart';
import '../netease/netease_rewards.dart';
import '../netease/netease_rewards_provider.dart';
import 'platform_reward_verification.dart';
import 'platform_reward_day.dart';
import '../../themes/beta_appearance.dart';
import 'unified_reward_page.dart';
import '../../themes/music_typography.dart';

/// Findable on My immediately below the unified account presentation.
class PlatformRewardEntry extends ConsumerWidget {
  const PlatformRewardEntry({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(platformRewardsProvider);
    final netease = ref.watch(usesNeteaseProvider);
    final neteaseState = ref.watch(neteaseRewardsProvider);
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(22),
      child: ListTile(
        key: const ValueKey('open-platform-reward-calendar'),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        leading: Icon(CupertinoIcons.calendar, color: scheme.primary, size: 28),
        title: const Text(
          '签到与会员',
          style: TextStyle(fontWeight: MusicTypography.titleWeight),
        ),
        subtitle: Text(
          netease
              ? neteaseState.ownerId == null
                    ? '使用网易云账号查看签到与免费听'
                    : neteaseState.action == NeteaseRewardAction.signIn
                    ? '正在签到…'
                    : neteaseState.action == NeteaseRewardAction.ad
                    ? '广告领取，本次已确认 ${neteaseState.confirmedAds} 次'
                    : '打卡记录与免费听时长'
              : state.ownerId == null
              ? '使用酷狗账号查看签到日历'
              : state.action == RewardAction.signIn
              ? '正在签到…'
              : state.action == RewardAction.ad
              ? '广告领取 ${state.adCount}/8'
              : state.needsVerification
              ? '签到需要安全验证'
              : '打卡记录与会员到期时间',
        ),
        trailing: Icon(
          CupertinoIcons.chevron_right,
          size: 17,
          color: scheme.onSurfaceVariant,
        ),
        onTap: () {
          Navigator.of(context, rootNavigator: true).push(
            MestingPageRoute<void>(builder: (_) => const UnifiedRewardPage()),
          );
        },
      ),
    );
  }
}

class PlatformRewardCalendar extends ConsumerWidget {
  const PlatformRewardCalendar({this.embedded = false, super.key});
  final bool embedded;

  Future<void> _act(
    BuildContext context,
    Future<RewardOutcome> Function() action,
  ) async {
    final result = await action();
    if (!context.mounted) return;
    showMusicNotice(
      context,
      icon: result.success ? Icons.check_rounded : Icons.warning_amber_rounded,
      title: result.message,
      message: '',
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(platformRewardsProvider);
    final controller = ref.read(platformRewardsProvider.notifier);
    final scheme = Theme.of(context).colorScheme;
    final ink = scheme.onSurface;
    final muted = scheme.onSurfaceVariant;
    final completedInk = BetaAppearance.success(scheme.brightness);
    final day = state.snapshot?.now ?? DateTime.now();
    final days = DateTime(day.year, day.month + 1, 0).day;
    final leading = DateTime(day.year, day.month, 1).weekday - 1;
    final prefix = '${day.year}-${day.month.toString().padLeft(2, '0')}-';
    final signed = state.signedDates
        .where(
          (key) =>
              key.startsWith(prefix) && key.compareTo(rewardDateKey(day)) <= 0,
        )
        .toSet();
    final enabled =
        state.ownerId != null && state.action == null && !state.loading;
    Widget action(
      RewardAction kind,
      String label,
      IconData icon,
      Future<RewardOutcome> Function() operation,
    ) => BetaGlassButton(
      onPressed: () => _act(context, operation),
      interactionEnabled: enabled,
      height: 48,
      fontSize: MusicTypography.subheadlineSize,
      horizontalPadding: 12,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (state.action == kind)
            const SizedBox(
              width: 17,
              height: 17,
              child: CupertinoActivityIndicator(),
            )
          else
            Icon(icon, size: 18),
          const SizedBox(width: 7),
          Text(
            state.action == kind
                ? (kind == RewardAction.signIn ? '签到中' : '领取中')
                : label,
          ),
        ],
      ),
    );
    return Scaffold(
      key: const ValueKey('platform-reward-calendar'),
      backgroundColor: scheme.surface,
      appBar: embedded
          ? null
          : AppBar(
              title: const Text(
                '签到日历',
                style: TextStyle(
                  fontSize: MusicTypography.bodySize,
                  fontWeight: MusicTypography.titleWeight,
                ),
              ),
              centerTitle: true,
              backgroundColor: scheme.surface,
              surfaceTintColor: Colors.transparent,
            ),
      body: state.ownerId == null
          ? const Center(child: Text('请先登录酷狗账号；切换音乐平台不会清除已保存的登录'))
          : QuietPullToRefresh(
              enabled: !state.loading && state.action == null,
              onRefresh: controller.refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  22,
                  20,
                  22,
                  embedded ? BetaContentInsets.musicBottomOf(context, 180) : 40,
                ),
                children: [
                  // Material 3 stretch composites the scroll contents into an
                  // isolated ImageFilter pass. Paint the real page surface in
                  // that pass before the glass buttons sample their backdrop;
                  // the Scaffold's surface lives outside it and is unavailable
                  // during overscroll. This retains the same optical material.
                  Container(
                    color: scheme.surface,
                    alignment: Alignment.center,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${day.year} 年 ${day.month} 月',
                                  style: TextStyle(
                                    fontSize: MusicTypography.titleSize,
                                    fontWeight: MusicTypography.titleWeight,
                                    color: ink,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: '刷新签到记录',
                                onPressed: state.loading
                                    ? null
                                    : controller.refresh,
                                icon: state.loading
                                    ? const CupertinoActivityIndicator()
                                    : const Icon(
                                        CupertinoIcons.arrow_clockwise,
                                      ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          Wrap(
                            spacing: 8,
                            runSpacing: 10,
                            children: [
                              action(
                                RewardAction.signIn,
                                '签到',
                                CupertinoIcons.check_mark_circled,
                                () => controller.signIn(
                                  verify: (challenge) =>
                                      showPlatformRewardVerification(
                                        context,
                                        ref,
                                        challenge,
                                      ),
                                ),
                              ),
                              action(
                                RewardAction.listen,
                                '听歌领取',
                                CupertinoIcons.headphones,
                                controller.listen,
                              ),
                              action(
                                RewardAction.ad,
                                '广告领取',
                                CupertinoIcons.play_rectangle,
                                controller.ads,
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '自动签到异常时，可在这里手动重试',
                            style: TextStyle(
                              fontSize: MusicTypography.captionSize,
                              color: muted,
                            ),
                          ),
                          if (state.action == RewardAction.ad)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '已确认 ${state.adCount}/8 次${state.adWaiting ? '，等待下一次领取' : ''}',
                                      style: TextStyle(
                                        color: muted,
                                        fontSize: MusicTypography.footnoteSize,
                                      ),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: controller.stopAds,
                                    child: const Text('停止领取'),
                                  ),
                                ],
                              ),
                            ),
                          if (state.message != null && state.action == null)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Semantics(
                                liveRegion: true,
                                child: Text(
                                  state.message!,
                                  style: TextStyle(
                                    color: muted,
                                    fontSize: MusicTypography.footnoteSize,
                                  ),
                                ),
                              ),
                            ),
                          if (state.snapshot?.recordsAvailable == false ||
                              (!state.loading && state.snapshot == null))
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Text(
                                '平台签到记录暂未加载，已保留本机确认的记录。下拉可重试。',
                                style: TextStyle(
                                  color: scheme.error,
                                  fontSize: MusicTypography.footnoteSize,
                                ),
                              ),
                            ),
                          const SizedBox(height: 28),
                          Row(
                            children: [
                              for (final label in [
                                '一',
                                '二',
                                '三',
                                '四',
                                '五',
                                '六',
                                '日',
                              ])
                                Expanded(
                                  child: Center(
                                    child: Text(
                                      label,
                                      style: TextStyle(
                                        color: muted,
                                        fontSize: MusicTypography.footnoteSize,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: ((leading + days + 6) ~/ 7) * 7,
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 7,
                                  mainAxisExtent: 58,
                                ),
                            itemBuilder: (context, index) {
                              final number = index - leading + 1;
                              if (number < 1 || number > days) {
                                return const SizedBox.shrink();
                              }
                              final date = DateTime(
                                day.year,
                                day.month,
                                number,
                              );
                              final checked = signed.contains(
                                rewardDateKey(date),
                              );
                              final future = number > day.day;
                              final today = number == day.day;
                              return PlatformRewardDay(
                                number: number,
                                month: day.month,
                                checked: checked,
                                today: today,
                                future: future,
                              );
                            },
                          ),
                          const SizedBox(height: 24),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Expanded(
                                child: Text(
                                  '本月已签到',
                                  style: TextStyle(
                                    color: muted,
                                    fontSize: MusicTypography.subheadlineSize,
                                  ),
                                ),
                              ),
                              Text(
                                '${signed.length}',
                                style: TextStyle(
                                  color: completedInk,
                                  fontWeight: MusicTypography.titleWeight,
                                  fontSize: MusicTypography.titleSize,
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text(
                                  ' / $days 天',
                                  style: TextStyle(
                                    color: muted,
                                    fontSize: MusicTypography.subheadlineSize,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          LinearProgressIndicator(
                            value: signed.length / days,
                            minHeight: 5,
                            borderRadius: BorderRadius.circular(4),
                            color: completedInk,
                            backgroundColor: scheme.surfaceContainerHighest,
                          ),
                          const SizedBox(height: 28),
                          _InsetGroup(
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text(
                                '自动签到',
                                style: TextStyle(
                                  fontSize: MusicTypography.calloutSize,
                                  fontWeight: MusicTypography.bodyWeight,
                                ),
                              ),
                              subtitle: const Text(
                                '登录后自动领取每日会员',
                                style: TextStyle(
                                  fontSize: MusicTypography.captionSize,
                                ),
                              ),
                              trailing: CupertinoSwitch(
                                key: const ValueKey('reward-auto-sign-in'),
                                activeTrackColor: scheme.primary,
                                value: state.autoSignIn,
                                onChanged: (value) async {
                                  try {
                                    await controller.setAutoSignIn(value);
                                  } on Object {
                                    if (context.mounted) {
                                      showMusicNotice(
                                        context,
                                        icon: Icons.warning_amber_rounded,
                                        title: '设置未保存，请重试',
                                        message: '',
                                      );
                                    }
                                  }
                                },
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          _InsetGroup(
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text(
                                '自动广告领取',
                                style: TextStyle(
                                  fontSize: MusicTypography.calloutSize,
                                  fontWeight: MusicTypography.bodyWeight,
                                ),
                              ),
                              subtitle: const Text(
                                '启动后自动领取，切换音乐平台仍生效',
                                style: TextStyle(
                                  fontSize: MusicTypography.captionSize,
                                ),
                              ),
                              trailing: CupertinoSwitch(
                                key: const ValueKey('reward-auto-ads'),
                                activeTrackColor: scheme.primary,
                                value: state.autoAds,
                                onChanged: (value) async {
                                  try {
                                    await controller.setAutoAds(value);
                                  } on Object {
                                    if (context.mounted) {
                                      showMusicNotice(
                                        context,
                                        icon: Icons.warning_amber_rounded,
                                        title: '设置未保存，请重试',
                                        message: '',
                                      );
                                    }
                                  }
                                },
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            '会员到期时间',
                            style: TextStyle(
                              color: muted,
                              fontSize: MusicTypography.subheadlineSize,
                              fontWeight: MusicTypography.bodyWeight,
                            ),
                          ),
                          const SizedBox(height: 10),
                          _InsetGroup(
                            child: Column(
                              children: [
                                for (final type in ['tvip', 'svip'])
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 10,
                                    ),
                                    child: _MembershipRow(
                                      label: type == 'tvip' ? '畅听会员' : '概念会员',
                                      value: _expiry(state, type, day),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  String _expiry(PlatformRewardState state, String type, DateTime now) {
    final snapshot = state.snapshot;
    if (snapshot == null ||
        (!snapshot.membershipsAvailable && snapshot.memberships.isEmpty)) {
      return '暂未获取';
    }
    final entries = snapshot.memberships.where((e) => e.type == type);
    if (entries.isEmpty || !entries.first.active) return '未开通';
    final end = entries.first.expires;
    if (end == null) return '已开通，未提供到期时间';
    final duration = end.difference(now);
    final relative = duration.isNegative
        ? '已到期'
        : duration.inDays > 0
        ? '${duration.inDays}天后到期'
        : duration.inHours > 0
        ? '${duration.inHours}小时后到期'
        : '即将到期';
    return '$relative\n${rewardDateKey(end)} ${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}';
  }
}

/// Full expiry dates need their own line on narrow or large-text layouts.
class _MembershipRow extends StatelessWidget {
  const _MembershipRow({required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final scheme = Theme.of(context).colorScheme;
      final stacked =
          bounds.maxWidth < 290 ||
          MediaQuery.textScalerOf(context).scale(13) > 17;
      final title = Text(
        label,
        style: TextStyle(
          color: scheme.onSurface,
          fontSize: MusicTypography.subheadlineSize,
          fontWeight: MusicTypography.bodyWeight,
        ),
      );
      final expiry = Text(
        value,
        textAlign: stacked ? TextAlign.start : TextAlign.end,
        style: TextStyle(
          color: scheme.onSurfaceVariant,
          fontSize: MusicTypography.footnoteSize,
        ),
      );
      return stacked
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [title, const SizedBox(height: 8), expiry],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: title),
                const SizedBox(width: 16),
                Expanded(child: expiry),
              ],
            );
    },
  );
}

class _InsetGroup extends StatelessWidget {
  const _InsetGroup({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(22),
    ),
    child: child,
  );
}
