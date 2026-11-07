import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/widgets/beta_glass_controls.dart';
import '../../../shared/widgets/beta_icon_button.dart';
import '../../themes/beta_appearance.dart';
import '../app_update_providers.dart';
import '../domain/release_history.dart';
import 'apple_download_progress.dart';
import 'release_notes_sheet.dart';

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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
    return PopScope(
      canPop: !mandatory,
      child: Material(
        type: MaterialType.transparency,
        key: const ValueKey('app-update-sheet-content'),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .86,
          ),
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              24,
              10,
              24,
              24 + MediaQuery.viewPaddingOf(context).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 5,
                    decoration: BoxDecoration(
                      color: scheme.onSurface.withValues(alpha: .2),
                      borderRadius: BorderRadius.circular(9),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '版本更新',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    BetaIconButton(
                      tooltip: '关闭版本更新',
                      onPressed: mandatory
                          ? null
                          : () => Navigator.pop(context),
                      icon: Icon(
                        CupertinoIcons.xmark_circle_fill,
                        color: scheme.onSurface.withValues(alpha: .45),
                        size: 29,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Align(
                  alignment: Alignment.centerLeft,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Image.asset(
                      'assets/branding/mesting-app-icon.png',
                      width: 64,
                      height: 64,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 27,
                      fontWeight: FontWeight.w800,
                      height: 1.18,
                      letterSpacing: -.5,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  checking
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
                      : '下载完成并校验后，由系统确认覆盖升级。',
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                if (checking)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: BetaActivityIndicator(color: blue, radius: 12),
                  ),
                if (installed != null) ...[
                  if (checking) const SizedBox(height: 20),
                  _detail(context, '当前版本', installed.versionName),
                ],
                if (manifest != null && !checking && !current) ...[
                  _detail(context, '新版本', manifest.versionName),
                  _detail(context, '安装包大小', manifest.sizeLabel),
                  if (manifest.releaseNotes.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    const Text(
                      '本次更新',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final note in manifest.releaseNotes)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 7),
                        child: Text(
                          note,
                          style: TextStyle(
                            fontSize: 15,
                            height: 1.45,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                  if (state.receivedBytes > 0 ||
                      phase == AppUpdatePhase.downloading ||
                      verifying) ...[
                    const SizedBox(height: 22),
                    AppleDownloadProgress(
                      key: const ValueKey('app-update-progress'),
                      receivedBytes: state.receivedBytes,
                      totalBytes: state.totalBytes,
                    ),
                  ],
                ],
                if (notesVersion != null && !checking)
                  Align(
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
                  ),
                const SizedBox(height: 24),
                BetaGlassButton(
                  key: const ValueKey('app-update-primary'),
                  blue: true,
                  height: 54,
                  loading: waiting,
                  label: primary,
                  onPressed: () => _primary(state),
                  child: Text(primary),
                ),
                if (manifest != null &&
                    !mandatory &&
                    !checking &&
                    !current &&
                    !waiting &&
                    phase != AppUpdatePhase.downloading) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    key: const ValueKey('app-update-later'),
                    onPressed: () async {
                      await ref
                          .read(appUpdateControllerProvider.notifier)
                          .snooze();
                      if (context.mounted) Navigator.pop(context);
                    },
                    child: Text(
                      '稍后提醒我',
                      style: TextStyle(fontSize: 15, color: blue),
                    ),
                  ),
                ],
              ],
            ),
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
            fontSize: 15,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );
}
