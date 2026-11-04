import '../../../shared/widgets/beta_page_motion.dart';
import '../../../shared/widgets/beta_content_insets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../platform_backend_providers.dart';
import '../presentation/platform_design.dart';
import '../presentation/platform_feedback.dart';
import '../listening_sync/listening_sync_models.dart';
import 'netease_features_page.dart';
import 'netease_features_repository.dart';
import 'netease_fallback.dart';
import 'netease_listening_reporter.dart';
import 'netease_source_settings_panel.dart';
import 'netease_account_source_info.dart';
import '../../../shared/widgets/beta_glass_controls.dart';
import 'footprint/official_footprint_page.dart';
import 'diagnostics/netease_listening_audit_page.dart';

class NeteasePlaybackSettingsPage extends ConsumerStatefulWidget {
  const NeteasePlaybackSettingsPage({super.key});
  @override
  ConsumerState<NeteasePlaybackSettingsPage> createState() =>
      _PlaybackSettingsState();
}

class _PlaybackSettingsState
    extends ConsumerState<NeteasePlaybackSettingsPage> {
  @override
  Widget build(BuildContext context) {
    if (!ref.watch(usesNeteaseProvider)) {
      return const PlatformPageFrame(
        title: '网易云播放设置',
        child: Center(child: Text('请返回并切换到网易云账号')),
      );
    }
    final rows = ref.watch(neteaseListeningJournalProvider).value ?? const [];
    final nativeEnabled = ref
        .watch(neteaseMusicRepositoryProvider)
        .nativeLogEnabled;
    final heldNative = rows
        .where(
          (r) =>
              (r.state == ListeningSyncState.open ||
                  r.state == ListeningSyncState.queued) &&
              holdNeteaseNativeRecord(r, nativeLogEnabled: nativeEnabled),
        )
        .length;
    final accepted = rows
        .where((r) => r.state == ListeningSyncState.accepted)
        .length;
    final uncertain = rows
        .where(
          (r) =>
              r.state == ListeningSyncState.unknown ||
              r.state == ListeningSyncState.dispatched,
        )
        .length;
    final confirmed = rows
        .where(
          (r) =>
              r.kind == 'netease-startplay' &&
              r.payload['cloudConfirmed'] == true,
        )
        .length;
    final pendingSeconds = rows
        .where(
          (r) =>
              r.kind == 'netease-scrobble' &&
              !holdNeteaseNativeRecord(r, nativeLogEnabled: nativeEnabled) &&
              (r.state == ListeningSyncState.queued ||
                  r.state == ListeningSyncState.open),
        )
        .fold<int>(0, (sum, r) => sum + (r.number('heardMs') ~/ 1000));
    return PlatformPageFrame(
      title: '网易云播放与同步',
      child: ListView(
        padding: BetaContentInsets.musicPaddingOf(
          context,
          EdgeInsets.fromLTRB(22, 12, 22, 190),
        ),
        children: [
          SwitchListTile.adaptive(
            title: const Text('备用音源'),
            subtitle: const Text('原曲不可播放或仅可试听时尝试补源，严格匹配同一录音版本'),
            value: ref.watch(neteaseFallbackEnabledProvider),
            onChanged: (value) async {
              try {
                await ref
                    .read(neteaseFallbackEnabledProvider.notifier)
                    .setEnabled(value);
              } catch (e) {
                if (context.mounted) showPlatformFailure(context, e);
              }
            },
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              '$neteaseAutomaticSourceOrder。酷狗账号补源使用独立保存的酷狗登录，公开备用音源只接收歌曲信息。实际音质以返回文件为准。',
            ),
          ),
          const NeteaseSourceSettingsPanel(),
          SwitchListTile.adaptive(
            title: const Text('网易云播放记录上报'),
            subtitle: const Text('实际开始播放后同步最近播放；时长仅累计真实收听，暂停、缓冲与拖动不计入'),
            value: ref.watch(neteaseListeningEnabledProvider),
            onChanged: (value) async {
              try {
                await ref
                    .read(neteaseListeningEnabledProvider.notifier)
                    .setEnabled(value);
              } catch (e) {
                if (context.mounted) showPlatformFailure(context, e);
              }
            },
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              '接口已接收 $accepted 条 · 云端最近播放已确认 $confirmed 条 · 请求结果未确认 $uncertain 条\n云端记录可能延迟；累计听歌时长以网易云处理为准。未确认的写入不会自动重复发送。',
            ),
          ),
          ListTile(
            key: const ValueKey('netease-official-footprint'),
            title: const Text('云村听歌足迹'),
            subtitle: const Text('官方今日、当前月及历史总时长 · 历史月报核对'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MestingPageRoute<void>(
                builder: (_) => const OfficialFootprintPage(),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              '待结束或待发送的真实收听约 ${pendingSeconds ~/ 60} 分钟。仅补发确定未发送的记录，已接收或结果未确认的不会重复发送。历史月份能否补回以网易云处理为准；本机统计继续保留。',
            ),
          ),
          BetaGlassButton(
            // Held candidate rows are intentionally excluded from pending time.
            onPressed: !ref.watch(neteaseListeningEnabledProvider)
                ? null
                : () async {
                    await ref
                        .read(neteaseListeningReporterProvider)
                        ?.recoverPending();
                  },
            child: const Text('同步确定未发送的记录'),
          ),
          if (heldNative > 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text('候选版遗留的 $heldNative 条待核对记录已保留，不会自动重发或计入待同步时长。'),
            ),
          const SizedBox(height: 16),
          BetaGlassButton(
            key: const ValueKey('netease-monthly-audit'),
            onPressed: () => Navigator.of(context).push(
              MestingPageRoute<void>(
                builder: (_) => const NeteaseListeningAuditPage(),
              ),
            ),
            child: const Text('按月听歌上报诊断'),
          ),
          for (final feed in [
            NeteaseFeed.recentSongs,
            NeteaseFeed.recentPlaylists,
            NeteaseFeed.recentAlbums,
            NeteaseFeed.week,
            NeteaseFeed.allTime,
          ])
            ListTile(
              title: Text(NeteaseFeaturesRepository.titles[feed]!),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => openNeteaseFeed(context, feed),
            ),
        ],
      ),
    );
  }
}
