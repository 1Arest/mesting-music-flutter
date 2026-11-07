import '../music_platform/qishui/qishui_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/models/track.dart';
import '../../shared/widgets/beta_glass_controls.dart';
import '../../shared/widgets/liquid_glass_sheet.dart';
import '../music_platform/data/music_platform_api.dart';
import '../music_platform/data/platform_quality_catalog.dart';
import '../music_platform/domain/platform_audio_quality.dart';
import '../music_platform/music_platform_providers.dart';
import '../music_platform/platform_backend_providers.dart';
import '../music_platform/netease/netease_fallback.dart';

/// Unlike playback's local-SVIP attempt list, download choices come only from
/// this recording's actual resource metadata. Entitlement/address resolution is
/// checked again by the worker, since platform permission can expire in queue.
final downloadSongQualitiesProvider = FutureProvider.autoDispose
    .family<Set<PlatformAudioQuality>, String>((ref, id) async {
      final account = await ref.watch(platformAccountProvider.future);
      if (account == null) throw const MusicPlatformException('请先登录对应音乐平台');
      if (id.startsWith('qishui_')) {
        return ref.watch(qishuiRepositoryProvider).qualities(id);
      }
      if (id.startsWith('netease_')) {
        return ref.watch(neteaseMusicRepositoryProvider).qualities(id);
      }
      if (!id.startsWith('kugou_')) {
        throw const MusicPlatformException('此歌曲不支持在线音质下载');
      }
      return PlatformQualityCatalog.parse(
        await ref
            .watch(musicPlatformApiProvider)
            .get(
              '/audio',
              query: {'hash': id.substring(6)},
              expectedSession: account,
            ),
      );
    });

Future<PlatformAudioQuality?> chooseAudioDownloadQuality(
  BuildContext context,
  List<Track> tracks,
) => showLiquidGlassBottomSheet<PlatformAudioQuality>(
  context: context,
  useSafeArea: true,
  isScrollControlled: true,
  builder: (_) => _DownloadQualitySheet(tracks),
);

class _DownloadQualitySheet extends ConsumerStatefulWidget {
  const _DownloadQualitySheet(this.tracks);
  final List<Track> tracks;
  @override
  ConsumerState<_DownloadQualitySheet> createState() =>
      _DownloadQualitySheetState();
}

class _DownloadQualitySheetState extends ConsumerState<_DownloadQualitySheet> {
  late Future<Set<PlatformAudioQuality>> _choices;
  @override
  void initState() {
    super.initState();
    _choices = _load();
  }

  Future<Set<PlatformAudioQuality>> _load() async {
    Set<PlatformAudioQuality>? common;
    var next = 0;
    // Batch actions offer the intersection, so every selected song supports
    // the requested tier. At most three metadata reads run concurrently.
    Future<void> worker() async {
      while (mounted && next < widget.tracks.length) {
        final track = widget.tracks[next++];
        final provider = downloadSongQualitiesProvider(track.id);
        final subscription = ref.listenManual(provider, (_, _) {});
        try {
          Set<PlatformAudioQuality> options;
          try {
            options = await ref.read(provider.future);
          } catch (_) {
            if (track.source != TrackSource.netease ||
                !ref.read(neteaseFallbackEnabledProvider)) {
              rethrow;
            }
            options = {};
          }
          // Official metadata may advertise only preview/no tiers. These four
          // are selectable requests for alternate sources, not a promise of
          // entitlement or actual availability. The queue still tries official
          // first and requires a user choice before using any other resolver.
          if (track.source == TrackSource.netease &&
              ref.read(neteaseFallbackEnabledProvider)) {
            options = {...options, ...PlatformAudioQuality.values.take(4)};
          }
          common = common == null
              ? {...options}
              : common!.intersection(options);
        } finally {
          subscription.close();
        }
      }
    }

    await Future.wait(
      List.generate(widget.tracks.length.clamp(0, 3), (_) => worker()),
    );
    return common ?? {};
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .75,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '选择下载音质',
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              widget.tracks.length == 1
                  ? widget.tracks.first.title
                  : '${widget.tracks.length} 首歌曲 · 共同支持的音质',
            ),
            const SizedBox(height: 16),
            FutureBuilder<Set<PlatformAudioQuality>>(
              future: _choices,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(
                    child: BetaActivityIndicator(label: '正在读取歌曲音质'),
                  );
                }
                if (snapshot.hasError) {
                  return Column(
                    children: [
                      const Text('暂时无法读取歌曲音质，请重试'),
                      BetaGlassButton(
                        onPressed: () {
                          for (final track in widget.tracks) {
                            ref.invalidate(
                              downloadSongQualitiesProvider(track.id),
                            );
                          }
                          setState(() => _choices = _load());
                        },
                        child: const Text('重新读取'),
                      ),
                    ],
                  );
                }
                final choices = snapshot.data ?? {};
                if (choices.isEmpty) {
                  return const Text('暂无共同支持的音质，可尝试逐曲下载或稍后重试');
                }
                final netease =
                    widget.tracks.first.source == TrackSource.netease;
                final order = netease
                    ? PlatformAudioQuality.neteaseOrder
                    : PlatformAudioQuality.values.where((q) => !q.neteaseOnly);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final quality in order.where(choices.contains))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: BetaGlassButton(
                          key: ValueKey('download-quality-${quality.code}'),
                          onPressed: () => Navigator.of(context).pop(quality),
                          child: Center(
                            child: Text(
                              netease ? quality.neteaseLabel : quality.label,
                            ),
                          ),
                        ),
                      ),
                    const Text(
                      '优先下载官方完整版；官方不可用时可手动选择其他下载音源。实际格式与音质将再次核验。',
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
          ],
        ),
      ),
    ),
  );
}
