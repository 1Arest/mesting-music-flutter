import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/widgets/beta_glass_controls.dart';
import '../../../shared/widgets/beta_icon_button.dart';
import '../../themes/beta_appearance.dart';
import '../app_update_providers.dart';
import '../domain/release_history.dart';
import 'update_download_card.dart';
import 'release_notes_sheet.dart';
import '../../themes/music_typography.dart';

/// Presentation only: one controller owns checking, download, pause and install.
/// A missing release is a visible checking/current/error state, never an empty
/// drawer. The platform's absent release notes are intentionally not fabricated.
class BetaAppUpdateSheet extends ConsumerStatefulWidget {
  const BetaAppUpdateSheet({super.key});
  @override
  ConsumerState<BetaAppUpdateSheet> createState() => _BetaAppUpdateSheetState();
}

class _BetaAppUpdateSheetState extends ConsumerState<BetaAppUpdateSheet>
    with WidgetsBindingObserver {
  final _notesScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _notesScroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        mounted &&
        ref.read(appUpdateControllerProvider).phase ==
            AppUpdatePhase.permissionRequired) {
      ref.read(appUpdateControllerProvider.notifier).continueInstall();
    }
  }

  Future<void> _primary(AppUpdateState state) async {
    final controller = ref.read(appUpdateControllerProvider.notifier);
    if (state.phase == AppUpdatePhase.upToDate) {
      Navigator.pop(context);
      return;
    }
    if (state.phase == AppUpdatePhase.downloading) {
      await controller.pauseDownload();
      return;
    }
    if (state.phase == AppUpdatePhase.permissionRequired) {
      await controller.continueInstall();
      if (!mounted) return;
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
    if (state.manifest == null) {
      await controller.check(manual: true);
      return;
    }
    await controller.downloadAndInstall();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appUpdateControllerProvider);
    final installed =
        state.currentVersion ?? ref.watch(appVersionProvider).value;
    final manifest = state.manifest;
    final phase = state.phase;
    final scheme = Theme.of(context).colorScheme;
    final blue = BetaAppearance.accent(Theme.of(context).brightness);
    final checking =
        phase == AppUpdatePhase.idle || phase == AppUpdatePhase.checking;
    final verifying = phase == AppUpdatePhase.verifying;
    final waiting =
        checking || verifying || phase == AppUpdatePhase.launchingInstaller;
    final current = phase == AppUpdatePhase.upToDate;
    final notesVersion = !current && manifest != null
        ? manifest.versionName
        : installed?.versionName;
    final releaseNotes = !current && manifest?.releaseNotes.isNotEmpty == true
        ? manifest!.releaseNotes
        : notesForMusicVersion(notesVersion ?? '');
    final title = checking
        ? '正在检查更新'
        : current
        ? '已是最新版本'
        : phase == AppUpdatePhase.failed
        ? '更新暂未完成'
        : verifying
        ? '正在校验安装包'
        : phase == AppUpdatePhase.permissionRequired
        ? '允许安装更新'
        : phase == AppUpdatePhase.installLaunched
        ? '已打开系统安装'
        : phase == AppUpdatePhase.readyToInstall
        ? '更新已准备好'
        : phase == AppUpdatePhase.downloading
        ? '正在下载更新'
        : phase == AppUpdatePhase.paused
        ? '下载已暂停'
        : '发现新版本';
    final primary = checking
        ? '正在检查'
        : current
        ? '完成'
        : verifying
        ? '正在校验'
        : phase == AppUpdatePhase.downloading
        ? '暂停下载'
        : phase == AppUpdatePhase.launchingInstaller
        ? '正在打开安装'
        : phase == AppUpdatePhase.permissionRequired
        ? '允许安装'
        : state.downloadedPath != null
        ? '安装更新'
        : manifest == null
        ? '重新检查'
        : phase == AppUpdatePhase.failed
        ? '重试下载'
        : state.receivedBytes > 0
        ? '继续下载'
        : '下载并更新';
    final mandatory =
        manifest != null &&
        installed != null &&
        manifest.isMandatoryFor(installed);
    final showProgress =
        manifest != null &&
        !checking &&
        !current &&
        (state.receivedBytes > 0 ||
            phase == AppUpdatePhase.downloading ||
            verifying);
    final notesEntry = notesVersion == null || checking
        ? null
        : Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: const ValueKey('app-update-view-notes'),
              onPressed: () => showMusicReleaseNotes(
                context,
                version: notesVersion,
                notes: releaseNotes,
              ),
              child: const Text('查看此次更新'),
            ),
          );
    final copy = checking
        ? '正在获取最新发布信息，请稍候。'
        : current
        ? 'Mesting Music 已保持最新。'
        : phase == AppUpdatePhase.failed
        ? state.errorMessage ?? '请检查网络后重试，下载进度会保留。'
        : phase == AppUpdatePhase.permissionRequired
        ? '请允许 Mesting Music 安装应用更新，返回后继续。'
        : phase == AppUpdatePhase.installLaunched
        ? '请在系统安装页面完成确认，或返回后再次安装。'
        : verifying
        ? '下载已完成，正在确认文件完整性。'
        : '下载完成并校验后，由系统确认覆盖升级。';
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(24, 10, 16, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 5,
              decoration: BoxDecoration(
                color: scheme.onSurface.withValues(alpha: .22),
                borderRadius: BorderRadius.circular(9),
              ),
            ),
          ),
          const SizedBox(height: 7),
          Row(
            children: [
              const Expanded(
                child: Text(
                  '版本更新',
                  style: TextStyle(
                    fontSize: MusicTypography.headingSize,
                    fontWeight: MusicTypography.titleWeight,
                  ),
                ),
              ),
              if (mandatory)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    '必须更新',
                    style: TextStyle(
                      fontSize: MusicTypography.captionSize,
                      color: scheme.error,
                    ),
                  ),
                ),
              BetaIconButton(
                tooltip: '关闭版本更新',
                onPressed: mandatory ? null : () => Navigator.pop(context),
                icon: Icon(
                  CupertinoIcons.xmark_circle_fill,
                  color: scheme.onSurface.withValues(alpha: .45),
                  size: 27,
                ),
              ),
            ],
          ),
        ],
      ),
    );
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(15),
                child: Image.asset(
                  'assets/branding/mesting-app-icon.png',
                  width: 54,
                  height: 54,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Mesting Music',
                      style: TextStyle(
                        fontSize: MusicTypography.sectionTitleSize,
                        fontWeight: MusicTypography.titleWeight,
                        letterSpacing: -.4,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: MusicTypography.subheadlineSize,
                          fontWeight: MusicTypography.titleWeight,
                          color: phase == AppUpdatePhase.failed
                              ? scheme.error
                              : blue,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (checking) BetaActivityIndicator(color: blue, radius: 10),
            ],
          ),
          const SizedBox(height: 14),
          if (manifest != null && !checking && !current) ...[
            Text(
              '当前版本 ${installed?.versionName ?? "—"}  →  ${manifest.versionName}',
              style: TextStyle(
                fontSize: MusicTypography.footnoteSize,
                height: 1.45,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              '安装包 ${manifest.sizeLabel}',
              style: TextStyle(
                fontSize: MusicTypography.footnoteSize,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ] else if (installed != null)
            _detail(context, '当前版本', installed.versionName),
          if (!showProgress || verifying || phase == AppUpdatePhase.failed)
            Padding(
              padding: const EdgeInsets.only(top: 9),
              child: Text(
                copy,
                style: TextStyle(
                  fontSize: MusicTypography.footnoteSize,
                  height: 1.45,
                  color: phase == AppUpdatePhase.failed
                      ? scheme.error
                      : scheme.onSurfaceVariant,
                ),
              ),
            ),
          if (manifest != null &&
              !checking &&
              !current &&
              manifest.releaseNotes.isNotEmpty) ...[
            const SizedBox(height: 16),
            DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: .36),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: scheme.onSurface.withValues(alpha: .06),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(15, 14, 15, 5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      '本次更新',
                      style: TextStyle(
                        fontSize: MusicTypography.bodySize,
                        fontWeight: MusicTypography.titleWeight,
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Keep the original server-supplied strings in full. Only
                    // this content region scrolls; actions remain reachable.
                    for (final note in manifest.releaseNotes)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 9),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 7),
                              child: Container(
                                width: 4,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: scheme.onSurfaceVariant,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Text(
                                note,
                                style: TextStyle(
                                  fontSize: MusicTypography.subheadlineSize,
                                  height: 1.48,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ?notesEntry,
                  ],
                ),
              ),
            ),
          ] else ...[
            ?notesEntry,
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
    final progress = showProgress
        ? Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
            child: UpdateDownloadCard(state: state),
          )
        : const SizedBox.shrink();
    final footer = Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        14,
        24,
        16 + MediaQuery.viewPaddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BetaGlassButton(
            key: const ValueKey('app-update-primary'),
            blue: true,
            height: 52,
            loading: waiting,
            label: primary,
            onPressed: () => _primary(state),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (phase == AppUpdatePhase.downloading ||
                    phase == AppUpdatePhase.paused) ...[
                  Icon(
                    phase == AppUpdatePhase.downloading
                        ? CupertinoIcons.pause_fill
                        : CupertinoIcons.play_fill,
                    size: 15,
                  ),
                  const SizedBox(width: 9),
                ],
                Flexible(child: Text(primary)),
              ],
            ),
          ),
          if (manifest != null &&
              !mandatory &&
              !checking &&
              !current &&
              !waiting &&
              phase != AppUpdatePhase.downloading) ...[
            const SizedBox(height: 4),
            TextButton(
              key: const ValueKey('app-update-later'),
              onPressed: () async {
                await ref.read(appUpdateControllerProvider.notifier).snooze();
                if (context.mounted) {
                  Navigator.pop(context);
                }
              },
              child: Text(
                '稍后提醒我',
                style: TextStyle(
                  fontSize: MusicTypography.subheadlineSize,
                  color: blue,
                ),
              ),
            ),
          ],
          if (showProgress) ...[
            const SizedBox(height: 10),
            Text(
              phase == AppUpdatePhase.paused
                  ? '下载进度已保留，可随时继续'
                  : '下载进度已保留，安装需系统确认',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: MusicTypography.captionSize,
                height: 1.4,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
    return PopScope(
      canPop: !mandatory,
      child: Material(
        type: MaterialType.transparency,
        key: const ValueKey('app-update-sheet-content'),
        child: Container(
          // One translucent backing inside the existing premium glass lens:
          // artwork cannot wash out release notes as in the previous sheet.
          decoration: BoxDecoration(
            color: scheme.surface.withValues(
              alpha: Theme.of(context).brightness == Brightness.dark
                  ? .86
                  : .92,
            ),
            borderRadius: BorderRadius.circular(34),
          ),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .86,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact =
                  constraints.maxHeight < 600 ||
                  MediaQuery.textScalerOf(context).scale(1) > 1.4;
              // On short/large-text displays, all content scrolls together so no
              // fixed telemetry panel can consume the entire usable viewport.
              if (compact) {
                return SingleChildScrollView(
                  key: const ValueKey('update-sheet-compact-scroll'),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [header, content, progress, footer],
                  ),
                );
              }
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  header,
                  Flexible(
                    child: Scrollbar(
                      controller: _notesScroll,
                      thumbVisibility: true,
                      radius: const Radius.circular(3),
                      thickness: 3,
                      child: SingleChildScrollView(
                        key: const ValueKey('update-notes-scroll'),
                        controller: _notesScroll,
                        child: content,
                      ),
                    ),
                  ),
                  progress,
                  footer,
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _detail(BuildContext context, String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    // Keep a version and its label together. Wrap only when accessibility text
    // really needs another line, rather than pushing the version to the edge.
    child: Wrap(
      spacing: 12,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: MusicTypography.subheadlineSize,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: MusicTypography.subheadlineSize,
            fontWeight: MusicTypography.bodyWeight,
          ),
        ),
      ],
    ),
  );
}
