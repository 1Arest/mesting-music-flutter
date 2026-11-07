import '../../music_platform/qishui/qishui_signer_settings_page.dart';
import '../../music_platform/qishui/qishui_providers.dart';
import '../../music_platform/qishui/qishui_account_page.dart';
import 'music_network_diagnostics_page.dart';
import '../../../shared/widgets/artwork_scroll_frontier.dart';
import '../../music_platform/presentation/platform_account_page.dart';
import '../../music_platform/presentation/platform_login_options_page.dart';
import '../../auth/presentation/beta_login_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/platform/distribution_channel.dart';
import '../../music_platform/music_platform_providers.dart';
import '../../app_update/app_update_providers.dart';
import '../../app_update/domain/app_update_models.dart';
import '../../app_update/presentation/app_update_sheet.dart';
import '../../app_update/presentation/release_history_page.dart';
import '../../themes/music_theme_tokens.dart';
import '../../themes/theme_gallery_page.dart';
import '../../../shared/widgets/mesting_loading_indicator.dart';
import '../../../shared/widgets/music_notice.dart';
import '../../../shared/widgets/beta_glass_controls.dart';
import '../../auth/presentation/beta_onboarding_page.dart';
import '../../auth/presentation/beta_welcome_page.dart';
import 'haptic_settings_page.dart';
import 'frame_diagnostics_page.dart';
import '../../music_platform/listening_sync_page.dart';
import 'music_equalizer_page.dart';
import 'music_sleep_timer_sheet.dart';
import '../../music_platform/presentation/music_effects_page.dart';
import '../../music_platform/platform_backend_providers.dart';
import '../../music_platform/netease/netease_playback_settings_page.dart';
import '../../themes/music_typography.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final platform = ref.watch(platformAccountProvider).value;
    final appVersion = ref.watch(appVersionProvider);
    final updateState = ref.watch(appUpdateControllerProvider);
    final topInset = MediaQuery.paddingOf(context).top;

    return CustomScrollView(
      physics: const ArtworkFrontierPhysics(parent: BouncingScrollPhysics()),
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            16,
            topInset + 12,
            16,
            DistributionChannel.isBeta
                ? 210 +
                      MediaQuery.viewPaddingOf(context).bottom +
                      2 *
                          (MediaQuery.textScalerOf(context).scale(24) - 24)
                              .clamp(0, 28)
                : 42,
          ),
          sliver: SliverList.list(
            children: [
              const DressUpAssetWarmup(),
              const _SettingsHeader(),
              const SizedBox(height: 24),
              const _SettingsSectionLabel('外观'),
              _SettingsSurface(
                child: Column(
                  children: [
                    _SettingsTile(
                      key: const ValueKey('settings-theme'),
                      icon: Icons.palette_outlined,
                      iconColor: const Color(0xFF745CC7),
                      title: '装扮',
                      subtitle: DistributionChannel.isBeta
                          ? '启动页、播放器、背景与进度条'
                          : '皮肤、IP 主题、图标与启动页',
                      highlighted: true,
                      onTap: () => showDressUpCenterSheet(context),
                    ),
                    if (DistributionChannel.isBeta)
                      _SettingsTile(
                        key: const ValueKey('settings-haptics'),
                        icon: Icons.vibration_rounded,
                        iconColor: const Color(0xFF527FD3),
                        title: '震动与触感',
                        subtitle: '关键操作反馈、强度与体验',
                        onTap: () =>
                            Navigator.of(context, rootNavigator: true).push(
                              betaEntryRoute<void>(const HapticSettingsPage()),
                            ),
                      ),
                    if (DistributionChannel.isBeta) const _SettingsDivider(),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              _SettingsSectionLabel(
                DistributionChannel.isBeta ? '账号与同步' : '账号',
              ),
              _SettingsSurface(
                child: Column(
                  children: [
                    _SettingsTile(
                      key: const ValueKey('settings-account-management'),
                      icon: Icons.manage_accounts_outlined,
                      iconColor: const Color(0xFF527FD3),
                      title: '账号管理',
                      subtitle: platform == null
                          ? '登录音乐平台，管理当前账号'
                          : '${platform.platformLabel}账号 · 已登录',
                      onTap: () => platform == null
                          ? openBetaLogin(context, redirect: '/music/settings')
                          : Navigator.of(context).push(
                              betaEntryRoute<void>(
                                PlatformAccountPage(
                                  platform: platform.platform,
                                ),
                              ),
                            ),
                    ),
                    const _SettingsDivider(),
                    _SettingsTile(
                      icon: Icons.swap_horiz_rounded,
                      iconColor: const Color(0xFF527FD3),
                      title: '切换音乐平台',
                      subtitle: '分别保留各音乐平台的登录与播放记录',
                      onTap: () => Navigator.of(context).push(
                        betaEntryRoute<void>(const MusicPlatformSwitchPage()),
                      ),
                    ),
                    const _SettingsDivider(),
                    _SettingsTile(
                      icon: Icons.cloud_sync_outlined,
                      iconColor: const Color(0xFF527FD3),
                      title: ref.watch(usesQishuiProvider)
                          ? '汽水账号资料'
                          : ref.watch(usesNeteaseProvider)
                          ? '网易云播放与同步'
                          : '酷狗播放同步',
                      subtitle: ref.watch(usesQishuiProvider)
                          ? '查看汽水账号资料与登录状态'
                          : '播放历史、真实听歌时长与同步状态',
                      onTap: () => Navigator.of(context).push(
                        betaEntryRoute<void>(
                          ref.read(usesQishuiProvider)
                              ? const QishuiAccountPage()
                              : ref.read(usesNeteaseProvider)
                              ? const NeteasePlaybackSettingsPage()
                              : const ListeningSyncPage(),
                        ),
                      ),
                    ),
                    const _SettingsDivider(),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              if (DistributionChannel.isBeta &&
                  ref.watch(qishuiNavigationProvider)) ...[
                const _SettingsSectionLabel('汽水音乐'),
                _SettingsSurface(
                  child: _SettingsTile(
                    key: const ValueKey('settings-qishui-signer'),
                    icon: Icons.key_rounded,
                    iconColor: const Color(0xFF527FD3),
                    title: '汽水签名服务',
                    subtitle: '自建助手地址、访问令牌与连接测试',
                    onTap: () =>
                        Navigator.of(context, rootNavigator: true).push(
                          betaEntryRoute<void>(
                            const QishuiSignerSettingsPage(),
                          ),
                        ),
                  ),
                ),
                const SizedBox(height: 18),
              ],
              if (DistributionChannel.isBeta) ...[
                const _SettingsSectionLabel('播放'),
                _SettingsSurface(
                  child: Column(
                    children: [
                      _SettingsTile(
                        key: const ValueKey('settings-equalizer'),
                        icon: Icons.graphic_eq_rounded,
                        iconColor: const Color(0xFF527FD3),
                        title: '本地均衡器',
                        subtitle: '频段增益、预设与自定义声音',
                        onTap: () =>
                            Navigator.of(context, rootNavigator: true).push(
                              betaEntryRoute<void>(const MusicEqualizerPage()),
                            ),
                      ),
                      const _SettingsDivider(),
                      if (!ref.watch(usesNeteaseProvider))
                        _SettingsTile(
                          key: const ValueKey('settings-effects'),
                          icon: Icons.surround_sound_outlined,
                          iconColor: const Color(0xFF527FD3),
                          title: '音效',
                          subtitle: ref.watch(usesQishuiProvider)
                              ? '汽水官版音效与账号权益'
                              : ref.watch(usesNeteaseProvider)
                              ? '本地均衡器与声音预设'
                              : '社区、耳机与明星音效',
                          onTap: () =>
                              Navigator.of(context, rootNavigator: true).push(
                                betaEntryRoute<void>(const MusicEffectsPage()),
                              ),
                        ),
                      const _SettingsDivider(),
                      _SettingsTile(
                        key: const ValueKey('settings-sleep-timer'),
                        icon: Icons.bedtime_outlined,
                        iconColor: const Color(0xFF527FD3),
                        title: '定时关闭',
                        subtitle: '倒计时或播完当前歌曲后停止',
                        onTap: () => showMusicSleepTimer(context, ref),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
              ],
              _SettingsSectionLabel(
                DistributionChannel.isBeta ? '关于与更新' : '应用',
              ),
              _SettingsSurface(
                child: Column(
                  children: [
                    if (DistributionChannel.isBeta) ...[
                      _SettingsTile(
                        key: const ValueKey('settings-network-diagnostics'),
                        icon: Icons.network_check_rounded,
                        iconColor: const Color(0xFF527FD3),
                        title: '连接与播放诊断',
                        subtitle: '查看本次启动的连接结果并复制记录',
                        onTap: () => Navigator.of(context).push(
                          betaEntryRoute<void>(
                            const MusicNetworkDiagnosticsPage(),
                          ),
                        ),
                      ),
                      const _SettingsDivider(),
                      _SettingsTile(
                        icon: Icons.speed_rounded,
                        iconColor: const Color(0xFF527FD3),
                        title: '流畅度诊断',
                        subtitle: '采集页面切换与底部控件的逐帧耗时',
                        onTap: () => Navigator.of(context).push(
                          betaEntryRoute<void>(const FrameDiagnosticsPage()),
                        ),
                      ),
                      const _SettingsDivider(),
                    ],
                    _SettingsTile(
                      key: const ValueKey('settings-check-update'),
                      icon: Icons.system_update_rounded,
                      iconColor: const Color(0xFF4A86D8),
                      title: '版本更新',
                      subtitle: _updateSubtitle(appVersion, updateState),
                      loading: updateState.phase == AppUpdatePhase.checking,
                      highlighted:
                          updateState.phase == AppUpdatePhase.available,
                      onTap: DistributionChannel.isBeta
                          ? () => checkForUpdatesAndShowSheet(context, ref)
                          : updateState.busy
                          ? null
                          : () => _checkForUpdates(context, ref),
                    ),
                    const _SettingsDivider(),
                    if (DistributionChannel.isBeta) ...[
                      _SettingsTile(
                        key: const ValueKey('settings-release-history'),
                        icon: Icons.history_rounded,
                        iconColor: const Color(0xFF4A86D8),
                        title: '更新说明',
                        subtitle: '查看本次更新与历史版本内容',
                        onTap: () => Navigator.of(context).push(
                          betaEntryRoute<void>(const MusicReleaseHistoryPage()),
                        ),
                      ),
                      const _SettingsDivider(),
                    ],
                    if (DistributionChannel.isBeta)
                      _SettingsTile(
                        key: const ValueKey('settings-guide'),
                        icon: Icons.auto_stories_outlined,
                        iconColor: const Color(0xFFDE5757),
                        title: '使用指南',
                        subtitle: '重新探索 Mesting Music 的操作与外观',
                        // The tour covers the shell, including its floating
                        // controls. System SafeArea cannot reserve app chrome.
                        onTap: () =>
                            Navigator.of(context, rootNavigator: true).push(
                              betaEntryRoute(
                                Builder(
                                  builder: (guideContext) => BetaOnboardingPage(
                                    replay: true,
                                    onFinish: () =>
                                        Navigator.of(guideContext).pop(),
                                  ),
                                ),
                              ),
                            ),
                      ),

                    if (DistributionChannel.isBeta) ...[
                      const _SettingsDivider(),
                      _SettingsTile(
                        key: const ValueKey('settings-open-source'),
                        icon: Icons.description_outlined,
                        iconColor: const Color(0xFF6F83D8),
                        title: '开源许可与致谢',
                        subtitle: '查看依赖许可与开源项目',
                        // Legal attribution belongs to settings, keeping every
                        // dedicated login method focused on authentication.
                        onTap: () => showLicensePage(
                          context: context,
                          applicationName: 'Mesting Music',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static String _updateSubtitle(
    AsyncValue<AppVersionInfo> version,
    AppUpdateState update,
  ) {
    if (update.phase == AppUpdatePhase.checking) return '';
    if (update.phase == AppUpdatePhase.downloading) {
      return '正在下载新版本 ${((update.progress ?? 0) * 100).round()}%';
    }
    if (update.phase == AppUpdatePhase.verifying) return '下载完成，正在校验安装包';
    if (update.phase == AppUpdatePhase.paused ||
        (update.phase == AppUpdatePhase.failed && update.receivedBytes > 0)) {
      return '新版本已下载 ${((update.progress ?? 0) * 100).round()}%，点击继续';
    }
    if (update.phase == AppUpdatePhase.readyToInstall ||
        update.phase == AppUpdatePhase.permissionRequired) {
      return '新版本已下载完成，点击继续安装';
    }
    if (update.phase == AppUpdatePhase.available && update.manifest != null) {
      return '发现新版本 v${update.manifest!.versionName}，点击查看';
    }
    return version.when(
      data: (value) => '当前版本 v${value.versionName} · 点击检查',
      loading: () => '',
      error: (_, _) => '点击检查最新版本',
    );
  }

  static Future<void> _checkForUpdates(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final result = await ref
        .read(appUpdateControllerProvider.notifier)
        .check(manual: true);
    if (!context.mounted) return;
    if (result?.updateAvailable == true) {
      await showAppUpdateSheet(context);
      return;
    }
    final state = ref.read(appUpdateControllerProvider);
    if (state.phase == AppUpdatePhase.upToDate) {
      showMusicNotice(context, icon: null, title: '已是最新版本', message: '');
      return;
    }
    showMusicNotice(
      context,
      icon: Icons.error_outline_rounded,
      title: '检查更新失败',
      message: state.errorMessage ?? '请稍后重试',
    );
  }
}

class _SettingsHeader extends StatelessWidget {
  const _SettingsHeader();

  @override
  Widget build(BuildContext context) {
    final tokens = context.musicThemeTokens;
    return Row(
      children: [
        if (DistributionChannel.isBeta)
          BetaGlassBackButton(
            key: const ValueKey('settings-back'),
            onPressed: () {
              context.canPop() ? context.pop() : context.go('/music/recommend');
            },
          )
        else
          Tooltip(
            message: '返回',
            child: Material(
              color: tokens.glassStrong,
              borderRadius: BorderRadius.circular(17),
              child: InkWell(
                key: const ValueKey('settings-back'),
                onTap: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go('/music/recommend');
                  }
                },
                borderRadius: BorderRadius.circular(17),
                child: Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(17),
                    border: Border.all(color: tokens.borderStrong),
                  ),
                  child: Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: tokens.textPrimary,
                    size: 21,
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '设置',
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: MusicTypography.titleSize,
                  height: 1.05,
                  fontWeight: MusicTypography.titleWeight,
                  letterSpacing: -.7,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                '外观、播放、账号与应用偏好',
                style: TextStyle(
                  color: tokens.textSecondary,
                  fontSize: MusicTypography.smallCaptionSize,
                  fontWeight: MusicTypography.bodyWeight,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SettingsSectionLabel extends StatelessWidget {
  const _SettingsSectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 5, bottom: 9),
      child: Text(
        label,
        style: TextStyle(
          color: context.musicThemeTokens.textPrimary,
          fontSize: MusicTypography.captionSize,
          fontWeight: MusicTypography.bodyWeight,
        ),
      ),
    );
  }
}

class _SettingsSurface extends StatelessWidget {
  const _SettingsSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = context.musicThemeTokens;
    return ClipRRect(
      borderRadius: BorderRadius.circular(23),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tokens.glassStrong,
          borderRadius: BorderRadius.circular(23),
          border: Border.all(color: tokens.borderStrong),
          boxShadow: [
            BoxShadow(
              color: tokens.shadow.withValues(alpha: .52),
              blurRadius: 22,
              offset: const Offset(0, 9),
            ),
          ],
        ),
        child: child,
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.highlighted = false,
    this.loading = false,
    super.key,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool highlighted;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final tokens = context.musicThemeTokens;
    final content = Container(
      constraints: const BoxConstraints(minHeight: 76),
      padding: const EdgeInsets.fromLTRB(15, 12, 13, 12),
      decoration: highlighted
          ? BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  iconColor.withValues(alpha: .15),
                  tokens.glassSubtle.withValues(alpha: .4),
                ],
              ),
            )
          : null,
      child: Row(
        children: [
          Container(
            width: 45,
            height: 45,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: .13),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: iconColor.withValues(alpha: .13)),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontSize: MusicTypography.subheadlineSize,
                    fontWeight: MusicTypography.bodyWeight,
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: tokens.textSecondary,
                      fontSize: MusicTypography.smallCaptionSize,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (loading)
            const MestingLoadingIndicator(
              key: ValueKey('settings-tile-loading-animation'),
              size: 30,
              semanticLabel: '正在读取版本信息',
            )
          else if (onTap != null)
            Icon(
              Icons.chevron_right_rounded,
              color: tokens.textMuted,
              size: 23,
            ),
        ],
      ),
    );

    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap, child: content),
    );
  }
}

class _SettingsDivider extends StatelessWidget {
  const _SettingsDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 73),
      child: Divider(
        height: 1,
        thickness: .7,
        color: context.musicThemeTokens.border,
      ),
    );
  }
}
