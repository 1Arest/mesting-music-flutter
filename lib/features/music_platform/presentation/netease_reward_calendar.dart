import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/diagnostics/diagnostic_activity.dart';
import '../../../shared/widgets/beta_content_insets.dart';
import '../../../shared/widgets/beta_glass_controls.dart';
import '../../../shared/widgets/beta_page_motion.dart';
import '../../../shared/widgets/music_notice.dart';
import '../../../shared/widgets/quiet_pull_to_refresh.dart';
import '../../themes/beta_appearance.dart';
import '../domain/platform_rewards.dart' show rewardDateKey;
import '../netease/netease_rewards.dart';
import '../netease/netease_rewards_provider.dart';
import '../netease/ad_probe/netease_ad_probe_page.dart';
import '../retained_kugou_scope.dart';
import 'platform_reward_day.dart';
import '../../themes/music_typography.dart';

/// Calendar and free-listening welfare share one account-owned controller.
/// The calendar displays only authoritative days or previously confirmed local
/// receipts; an absent historical endpoint never fills earlier days as signed.
class NeteaseRewardCalendar extends ConsumerWidget {
  const NeteaseRewardCalendar({this.embedded = false, super.key});
  final bool embedded;

  Future<void> _inspect(BuildContext context, WidgetRef ref) async {
    final state = ref.read(neteaseRewardsProvider);
    if (state.ownerId == null ||
        state.loading ||
        state.action != null ||
        ref.read(diagnosticActivityProvider)) {
      return;
    }
    // Keep automatic sign-in/reward writes suspended for this explicit read-only
    // page, including OS export/return. This does not change the saved setting.
    final activity = ref.read(diagnosticActivityProvider.notifier);
    activity.setRunning(true);
    try {
      await Navigator.of(
        context,
      ).push(betaContentRoute<void>(const NeteaseAdProbePage()));
    } finally {
      activity.setRunning(false);
    }
  }

  Future<void> _act(
    BuildContext context,
    WidgetRef ref,
    Future<NeteaseRewardResult> Function() operation,
  ) async {
    final owner = ref.read(neteaseRewardsProvider).ownerId;
    final epoch = ref.read(retainedNeteaseEpochProvider);
    final result = await operation();
    if (!context.mounted ||
        owner != ref.read(neteaseRewardsProvider).ownerId ||
        epoch != ref.read(retainedNeteaseEpochProvider)) {
      return;
    }
    showMusicNotice(
      context,
      icon: result.success ? Icons.check_rounded : Icons.warning_amber_rounded,
      title: result.message,
      message: '',
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(neteaseRewardsProvider);
    final controller = ref.read(neteaseRewardsProvider.notifier);
    final scheme = Theme.of(context).colorScheme;
    final diagnostic = ref.watch(diagnosticActivityProvider);
    final enabled =
        state.ownerId != null &&
        state.action == null &&
        !state.loading &&
        !diagnostic;
    final day = state.snapshot?.now ?? ref.read(neteaseRewardClockProvider)();
    final days = DateTime(day.year, day.month + 1, 0).day;
    final leading = DateTime(day.year, day.month, 1).weekday - 1;
    final prefix = '${day.year}-${day.month.toString().padLeft(2, '0')}-';
    final signed = state.signedDates
        .where(
          (key) =>
              key.startsWith(prefix) && key.compareTo(rewardDateKey(day)) <= 0,
        )
        .toSet();
    Widget body;
    if (state.sessionLoading) {
      body = const Center(child: Text('正在读取网易云登录…'));
    } else if (state.sessionError) {
      body = Center(
        child: BetaGlassButton(
          onPressed: () => ref.invalidate(retainedNeteaseRewardProvider),
          child: const Text('登录读取失败，点击重试'),
        ),
      );
    } else if (state.ownerId == null) {
      body = const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('请先登录网易云账号；已保存的酷狗登录可继续用于签到'),
        ),
      );
    } else {
      body = QuietPullToRefresh(
        enabled: !state.loading && state.action == null,
        onRefresh: controller.refresh,
        child: ListView(
          key: const PageStorageKey('netease-reward-scroll'),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            22,
            20,
            22,
            embedded ? BetaContentInsets.musicBottomOf(context, 180) : 40,
          ),
          children: [
            // Paint the sampled surface within the overscroll filter, as on the
            // Kugou tab, so the shared optical glass stays complete while pulled.
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
                            style: const TextStyle(
                              fontSize: MusicTypography.titleSize,
                              fontWeight: MusicTypography.titleWeight,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: '刷新网易云签到与免费听',
                          onPressed: state.loading || state.action != null
                              ? null
                              : controller.refresh,
                          icon: state.loading
                              ? const CupertinoActivityIndicator()
                              : const Icon(CupertinoIcons.arrow_clockwise),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: BetaGlassButton(
                        key: const ValueKey('netease-reward-sign-in'),
                        label: '网易云每日签到',
                        interactionEnabled: enabled,
                        onPressed: () =>
                            unawaited(_act(context, ref, controller.signIn)),
                        height: 48,
                        horizontalPadding: 16,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (state.action == NeteaseRewardAction.signIn)
                              const CupertinoActivityIndicator(radius: 8)
                            else
                              const Icon(
                                CupertinoIcons.check_mark_circled,
                                size: 18,
                              ),
                            const SizedBox(width: 8),
                            Text(
                              state.action == NeteaseRewardAction.signIn
                                  ? '签到中'
                                  : signed.contains(rewardDateKey(day))
                                  ? '今日已签到'
                                  : '签到',
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '自动签到异常时，可在这里手动核对与重试',
                      style: TextStyle(
                        fontSize: MusicTypography.captionSize,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    if (state.message != null &&
                        state.action != NeteaseRewardAction.ad) ...[
                      const SizedBox(height: 12),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          state.message!,
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: MusicTypography.footnoteSize,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 28),
                    Row(
                      children: [
                        for (final label in ['一', '二', '三', '四', '五', '六', '日'])
                          Expanded(
                            child: Center(
                              child: Text(
                                label,
                                style: TextStyle(
                                  fontSize: MusicTypography.footnoteSize,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    GridView.builder(
                      key: const ValueKey('netease-reward-days'),
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
                        return PlatformRewardDay(
                          number: number,
                          month: day.month,
                          checked: signed.contains(
                            rewardDateKey(
                              DateTime(day.year, day.month, number),
                            ),
                          ),
                          today: number == day.day,
                          future: number > day.day,
                          unconfirmed:
                              !(number == day.day &&
                                  state.snapshot?.signedToday == false),
                        );
                      },
                    ),
                    const SizedBox(height: 18),
                    Text(
                      '本月已确认 ${signed.length} 天',
                      style: TextStyle(
                        fontSize: MusicTypography.headingSize,
                        fontWeight: MusicTypography.titleWeight,
                        color: BetaAppearance.success(scheme.brightness),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '日历显示本机已确认的日期与平台今日签到状态；其他日期不代表平台未签到。',
                      style: TextStyle(
                        fontSize: MusicTypography.captionSize,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 22),
                    _RewardInset(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  '自动签到',
                                  style: TextStyle(
                                    fontSize: MusicTypography.calloutSize,
                                    fontWeight: MusicTypography.bodyWeight,
                                  ),
                                ),
                              ),
                              CupertinoSwitch(
                                key: const ValueKey(
                                  'netease-reward-auto-sign-in',
                                ),
                                activeTrackColor: scheme.primary,
                                value: state.autoSignIn,
                                onChanged: (value) async {
                                  try {
                                    await controller.setAutoSignIn(value);
                                  } catch (_) {
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
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '使用已保存的网易云账号，每天自动尝试一次。',
                            style: TextStyle(
                              fontSize: MusicTypography.captionSize,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    _FreeListenCard(
                      state: state,
                      enabled: enabled,
                      onClaim: () =>
                          unawaited(_act(context, ref, controller.ads)),
                      onStop: controller.stopAds,
                    ),
                    const SizedBox(height: 16),
                    BetaGlassButton(
                      key: const ValueKey('netease-ad-probe-open'),
                      height: 52,
                      interactionEnabled: enabled,
                      onPressed: () => unawaited(_inspect(context, ref)),
                      child: const Text('广告配置诊断'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Scaffold(
      key: const ValueKey('netease-reward-calendar'),
      backgroundColor: scheme.surface,
      appBar: embedded ? null : AppBar(title: const Text('网易云签到与免费听')),
      body: body,
    );
  }
}

/// The quota and daily milestone are platform facts. Batch-confirmed claims
/// are displayed separately and never substituted for the server's ad count.
class _FreeListenCard extends StatelessWidget {
  const _FreeListenCard({
    required this.state,
    required this.enabled,
    required this.onClaim,
    required this.onStop,
  });
  final NeteaseRewardState state;
  final bool enabled;
  final VoidCallback onClaim, onStop;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final free = state.snapshot?.freeListen;
    final running = state.action == NeteaseRewardAction.ad;
    final count = free?.adCount, target = free?.adTarget;
    final progress = count != null && target != null && target > 0
        ? (count / target).clamp(0.0, 1.0)
        : null;
    final seconds = free?.remainingSeconds;
    String duration() {
      if (seconds == null) return '暂未获取';
      final hours = seconds ~/ 3600;
      final minutes = (seconds % 3600) ~/ 60;
      final rest = seconds % 60;
      return '${hours > 0 ? '$hours时' : ''}${minutes.toString().padLeft(2, '0')}分${rest.toString().padLeft(2, '0')}秒';
    }

    return _RewardInset(
      key: const ValueKey('netease-free-listen-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '免费听时长剩余',
            style: TextStyle(
              fontSize: MusicTypography.subheadlineSize,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            duration(),
            key: const ValueKey('netease-free-listen-balance'),
            style: const TextStyle(
              fontSize: MusicTypography.titleSize,
              fontWeight: MusicTypography.titleWeight,
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              BetaGlassButton(
                key: const ValueKey('netease-reward-claim-time'),
                onPressed: onClaim,
                interactionEnabled: enabled,
                height: 48,
                horizontalPadding: 15,
                child: const Text('领时长'),
              ),
              BetaGlassButton(
                key: const ValueKey('netease-reward-claim-ad'),
                onPressed: running ? onStop : onClaim,
                interactionEnabled: running || enabled,
                height: 48,
                horizontalPadding: 15,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      running
                          ? CupertinoIcons.stop_circle
                          : CupertinoIcons.play_rectangle,
                      size: 18,
                    ),
                    const SizedBox(width: 7),
                    Text(running ? '停止领取' : '广告领取'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            free?.todayFree == true
                ? '今日免费听已确认'
                : free?.progressTitle != null
                ? free!.progressTitle!
                : count != null && target != null && target > 0
                ? '今日领取进度 $count/$target'
                : '今日领取进度暂未获取',
            style: const TextStyle(
              fontSize: MusicTypography.subheadlineSize,
              fontWeight: MusicTypography.bodyWeight,
            ),
          ),
          if (free?.progressSubtitle != null) ...[
            const SizedBox(height: 8),
            Text(
              free!.progressSubtitle!,
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: MusicTypography.captionSize,
              ),
            ),
          ],
          if (free?.milestones.isNotEmpty == true) ...[
            const SizedBox(height: 12),
            for (final task in free!.milestones)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      task.done == true
                          ? CupertinoIcons.check_mark_circled_solid
                          : task.done == false
                          ? CupertinoIcons.circle
                          : CupertinoIcons.question_circle,
                      size: 18,
                      color: task.done == true
                          ? BetaAppearance.success(scheme.brightness)
                          : scheme.onSurfaceVariant,
                      semanticLabel: task.done == true
                          ? '平台已完成'
                          : task.done == false
                          ? '平台未完成'
                          : '平台未提供完成状态',
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        '${task.label}${task.count == null ? '' : ' · 已确认 ${task.count} 次'}',
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: MusicTypography.footnoteSize,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          if (progress != null) ...[
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: progress,
              minHeight: 5,
              borderRadius: BorderRadius.circular(4),
            ),
          ],
          if (free?.adLimit != null) ...[
            const SizedBox(height: 8),
            Text(
              '平台今日最多领取 ${free!.adLimit} 次',
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: MusicTypography.captionSize,
              ),
            ),
          ],
          if (running || state.confirmedAds > 0) ...[
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              child: Text(
                '本次已确认 ${state.confirmedAds} 次${state.adWaiting
                    ? '，等待下一次领取'
                    : running
                    ? '，正在领取'
                    : ''}',
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: MusicTypography.footnoteSize,
                ),
              ),
            ),
          ],
          if (state.freeListenStale || free == null) ...[
            const SizedBox(height: 10),
            Text(
              free == null ? '免费听信息暂未获取，下拉可重试。' : '当前显示上次读取的时长，尚未更新。',
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: MusicTypography.captionSize,
              ),
            ),
          ],
          if (free?.message != null) ...[
            const SizedBox(height: 10),
            Text(
              free!.message!,
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: MusicTypography.captionSize,
              ),
            ),
          ],
          if (!running && state.message != null) ...[
            const SizedBox(height: 12),
            Text(
              state.message!,
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: MusicTypography.footnoteSize,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RewardInset extends StatelessWidget {
  const _RewardInset({required this.child, super.key});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(22),
    ),
    child: child,
  );
}
