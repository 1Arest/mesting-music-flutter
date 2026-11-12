import '../../../shared/widgets/artwork_scroll_frontier.dart';
import '../../../shared/widgets/music_activity_indicator.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/liquid_glass_sheet.dart';
import '../../themes/music_theme_tokens.dart';
import '../app_update_providers.dart';
import '../../../core/platform/distribution_channel.dart';
import '../../../shared/widgets/beta_glass_popover.dart';
import 'beta_app_update_sheet.dart';
import '../../themes/music_typography.dart';

const appUpdateSheetContentKey = ValueKey<String>('app-update-sheet-content');
bool _updateSheetOpen = false;

/// Manual entry is immediately visible, including a slow/failed first request.
/// Reopening an active download attaches to its existing owner instead of
/// replacing it with a second check or another download task.
Future<void> checkForUpdatesAndShowSheet(
  BuildContext context,
  WidgetRef ref,
) async {
  final state = ref.read(appUpdateControllerProvider);
  if (!state.busy && state.downloadedPath == null && state.receivedBytes == 0) {
    unawaited(
      ref.read(appUpdateControllerProvider.notifier).check(manual: true),
    );
  }
  await showAppUpdateSheet(context);
}

Future<void> showAppUpdateSheet(BuildContext context) async {
  if (_updateSheetOpen) return;
  final container = ProviderScope.containerOf(context, listen: false);
  final state = container.read(appUpdateControllerProvider);
  final current = state.currentVersion;
  final manifest = state.manifest;
  final mandatory =
      current != null && manifest != null && manifest.isMandatoryFor(current);
  _updateSheetOpen = true;
  try {
    if (DistributionChannel.isBeta) {
      await showModalBottomSheet<void>(
        context: context,
        useRootNavigator: true,
        useSafeArea: true,
        isScrollControlled: true,
        isDismissible: !mandatory,
        enableDrag: !mandatory,
        showDragHandle: false,
        backgroundColor: Colors.transparent,
        elevation: 0,
        barrierColor: Colors.black.withValues(alpha: .32),
        sheetAnimationStyle: AnimationStyle(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 360),
          reverseDuration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 240),
        ),
        builder: (_) => const Padding(
          padding: EdgeInsets.fromLTRB(10, 0, 10, 10),
          child: BetaGlassMenuSurface(radius: 34, child: BetaAppUpdateSheet()),
        ),
      );
      return;
    }
    await showLiquidGlassBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      isScrollControlled: true,
      isDismissible: !mandatory,
      enableDrag: !mandatory,
      barrierColor: Colors.black.withValues(alpha: .62),
      builder: (_) => const AppUpdateSheet(),
    );
  } finally {
    _updateSheetOpen = false;
  }
}

class AppUpdateSheet extends ConsumerWidget {
  const AppUpdateSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appUpdateControllerProvider);
    final controller = ref.read(appUpdateControllerProvider.notifier);
    final manifest = state.manifest;
    final current = state.currentVersion;
    if (manifest == null || current == null) return const SizedBox.shrink();
    final mandatory = manifest.isMandatoryFor(current);
    final tokens = context.musicThemeTokens;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    return PopScope(
      canPop: !mandatory,
      child: Material(
        key: appUpdateSheetContentKey,
        type: MaterialType.transparency,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .84,
          ),
          child: SingleChildScrollView(
            physics: const ArtworkFrontierPhysics(
              parent: BouncingScrollPhysics(),
            ),
            padding: EdgeInsets.fromLTRB(20, 14, 20, bottomInset + 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: tokens.textMuted.withValues(alpha: .26),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 54,
                      height: 54,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF5268D7), Color(0xFF3F9FB0)],
                        ),
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x32465CC7),
                            blurRadius: 18,
                            offset: Offset(0, 8),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.system_update_rounded,
                        color: Colors.white,
                        size: 27,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  manifest.title,
                                  style: TextStyle(
                                    color: tokens.textPrimary,
                                    fontSize: MusicTypography.sectionTitleSize,
                                    fontWeight: MusicTypography.titleWeight,
                                    letterSpacing: -.5,
                                  ),
                                ),
                              ),
                              if (mandatory) ...[
                                const SizedBox(width: 8),
                                const _MandatoryBadge(),
                              ],
                            ],
                          ),
                          const SizedBox(height: 5),
                          Text(
                            'v${manifest.versionName} · ${manifest.sizeLabel}',
                            style: TextStyle(
                              color: tokens.textSecondary,
                              fontSize: MusicTypography.smallCaptionSize,
                              fontWeight: MusicTypography.bodyWeight,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!mandatory)
                      IconButton(
                        key: const ValueKey('app-update-close'),
                        onPressed: state.busy
                            ? null
                            : () => Navigator.pop(context),
                        tooltip: '稍后更新',
                        icon: const Icon(Icons.close_rounded),
                        color: tokens.textSecondary,
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.fromLTRB(15, 14, 15, 12),
                  decoration: BoxDecoration(
                    color: tokens.glassSubtle,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: tokens.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '本次更新',
                        style: TextStyle(
                          color: tokens.textPrimary,
                          fontSize: MusicTypography.captionSize,
                          fontWeight: MusicTypography.bodyWeight,
                        ),
                      ),
                      const SizedBox(height: 9),
                      for (final note in manifest.releaseNotes)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 7),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 5,
                                height: 5,
                                margin: const EdgeInsets.only(top: 5),
                                decoration: const BoxDecoration(
                                  color: Color(0xFF5268D7),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 9),
                              Expanded(
                                child: Text(
                                  note,
                                  style: TextStyle(
                                    color: tokens.textSecondary,
                                    fontSize: MusicTypography.smallCaptionSize,
                                    height: 1.45,
                                    fontWeight: MusicTypography.bodyWeight,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                if (state.phase == AppUpdatePhase.downloading ||
                    state.phase == AppUpdatePhase.verifying ||
                    state.phase == AppUpdatePhase.paused ||
                    (state.phase == AppUpdatePhase.failed &&
                        state.receivedBytes > 0)) ...[
                  const SizedBox(height: 18),
                  _DownloadProgress(state: state, tokens: tokens),
                ],
                if (state.phase == AppUpdatePhase.permissionRequired) ...[
                  const SizedBox(height: 14),
                  _InlineMessage(
                    icon: Icons.admin_panel_settings_outlined,
                    text: '首次更新需要允许 Mesting 音乐安装此来源的应用，授权后返回并再次点击继续。',
                    tokens: tokens,
                  ),
                ],
                if (state.errorMessage case final error?) ...[
                  const SizedBox(height: 14),
                  _InlineMessage(
                    icon: Icons.error_outline_rounded,
                    text: error,
                    tokens: tokens,
                    error: true,
                  ),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  height: 52,
                  child: FilledButton.icon(
                    key: const ValueKey('app-update-primary'),
                    onPressed: _primaryEnabled(state)
                        ? () => _performPrimaryAction(ref, state)
                        : null,
                    icon: _primaryIcon(state),
                    label: Text(
                      _primaryLabel(state),
                      style: const TextStyle(
                        fontWeight: MusicTypography.titleWeight,
                      ),
                    ),
                  ),
                ),
                if (!mandatory && !state.busy) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    key: const ValueKey('app-update-later'),
                    onPressed: () async {
                      await controller.snooze();
                      if (context.mounted) Navigator.pop(context);
                    },
                    child: const Text('稍后提醒我'),
                  ),
                ],
                const SizedBox(height: 5),
                Text(
                  '当前版本 v${current.versionName} · '
                  '下载后会校验文件与应用签名，安装仍由 Android 系统确认',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: tokens.textMuted,
                    fontSize: MusicTypography.smallCaptionSize,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool _primaryEnabled(AppUpdateState state) {
    if (state.phase == AppUpdatePhase.downloading) return true;
    return !state.busy && state.phase != AppUpdatePhase.installLaunched;
  }

  Widget _primaryIcon(AppUpdateState state) {
    if (state.phase == AppUpdatePhase.downloading) {
      return const Icon(Icons.pause_rounded);
    }
    if (state.busy) {
      return const SizedBox.square(
        dimension: 18,
        child: MusicActivityIndicator(independent: true, strokeWidth: 2.2),
      );
    }
    return Icon(switch (state.phase) {
      AppUpdatePhase.permissionRequired => Icons.admin_panel_settings_rounded,
      AppUpdatePhase.readyToInstall => Icons.install_mobile_rounded,
      AppUpdatePhase.paused => Icons.play_arrow_rounded,
      AppUpdatePhase.failed when state.downloadedPath != null =>
        Icons.install_mobile_rounded,
      AppUpdatePhase.installLaunched => Icons.check_rounded,
      _ => Icons.download_rounded,
    });
  }

  String _primaryLabel(AppUpdateState state) {
    return switch (state.phase) {
      AppUpdatePhase.downloading =>
        '暂停下载 ${((state.progress ?? 0) * 100).round()}%',
      AppUpdatePhase.verifying => '正在校验安装包',
      AppUpdatePhase.paused => '继续下载 ${((state.progress ?? 0) * 100).round()}%',
      AppUpdatePhase.permissionRequired => '授权后继续安装',
      AppUpdatePhase.readyToInstall => '继续安装',
      AppUpdatePhase.launchingInstaller => '正在打开系统安装页面',
      AppUpdatePhase.installLaunched => '已打开系统安装页面',
      AppUpdatePhase.failed when state.downloadedPath != null => '重新尝试安装',
      AppUpdatePhase.failed when state.receivedBytes > 0 =>
        '继续下载 ${((state.progress ?? 0) * 100).round()}%',
      AppUpdatePhase.failed => '重新下载',
      _ => '立即更新',
    };
  }

  Future<void> _performPrimaryAction(
    WidgetRef ref,
    AppUpdateState state,
  ) async {
    final controller = ref.read(appUpdateControllerProvider.notifier);
    if (state.phase == AppUpdatePhase.downloading) {
      await controller.pauseDownload();
      return;
    }
    if (state.phase == AppUpdatePhase.permissionRequired) {
      await controller.continueInstall();
      if (ref.read(appUpdateControllerProvider).phase ==
          AppUpdatePhase.permissionRequired) {
        await controller.openInstallPermission();
      }
      return;
    }
    if (state.downloadedPath != null) {
      await controller.continueInstall();
      return;
    }
    await controller.downloadAndInstall();
  }
}

class _MandatoryBadge extends StatelessWidget {
  const _MandatoryBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFC24A34).withValues(alpha: .13),
        borderRadius: BorderRadius.circular(99),
      ),
      child: const Text(
        '必须更新',
        style: TextStyle(
          color: Color(0xFFC24A34),
          fontSize: MusicTypography.smallCaptionSize,
          fontWeight: MusicTypography.bodyWeight,
        ),
      ),
    );
  }
}

class _DownloadProgress extends StatelessWidget {
  const _DownloadProgress({required this.state, required this.tokens});

  final AppUpdateState state;
  final MusicThemeTokens tokens;

  @override
  Widget build(BuildContext context) {
    final received = state.receivedBytes / (1024 * 1024);
    final total = state.totalBytes / (1024 * 1024);
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: state.progress == null
              ? const Center(child: MusicActivityIndicator(independent: true))
              : LinearProgressIndicator(
                  key: const ValueKey('app-update-progress'),
                  value: state.progress,
                  minHeight: 7,
                  backgroundColor: tokens.textPrimary.withValues(alpha: .08),
                ),
        ),
        const SizedBox(height: 7),
        Row(
          children: [
            Text(
              '${received.toStringAsFixed(1)} / ${total.toStringAsFixed(1)} MB',
              style: TextStyle(
                color: tokens.textMuted,
                fontSize: MusicTypography.smallCaptionSize,
              ),
            ),
            const Spacer(),
            Text(
              '${((state.progress ?? 0) * 100).round()}%',
              style: TextStyle(
                color: tokens.textSecondary,
                fontSize: MusicTypography.smallCaptionSize,
                fontWeight: MusicTypography.bodyWeight,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          state.phase == AppUpdatePhase.paused
              ? '下载已暂停，进度已保存在本机'
              : '下载进度会保存在本机，关闭应用后可继续',
          style: TextStyle(
            color: tokens.textMuted,
            fontSize: MusicTypography.smallCaptionSize,
            fontWeight: MusicTypography.bodyWeight,
          ),
        ),
      ],
    );
  }
}

class _InlineMessage extends StatelessWidget {
  const _InlineMessage({
    required this.icon,
    required this.text,
    required this.tokens,
    this.error = false,
  });

  final IconData icon;
  final String text;
  final MusicThemeTokens tokens;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final color = error ? const Color(0xFFC24A34) : const Color(0xFF5B8FD9);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: .16)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: tokens.textSecondary,
                fontSize: MusicTypography.smallCaptionSize,
                height: 1.45,
                fontWeight: MusicTypography.bodyWeight,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
