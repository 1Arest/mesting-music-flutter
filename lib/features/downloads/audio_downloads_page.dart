import '../music_platform/presentation/song_actions_sheet.dart';
import '../../shared/widgets/song_list_tools.dart';
import '../../shared/widgets/beta_content_insets.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/models/track.dart';
import '../../shared/widgets/beta_swipe_pages.dart';
import '../../shared/widgets/audio_resolving_wave.dart';
import '../app_update/presentation/apple_download_progress.dart';
import '../../shared/widgets/beta_glass_controls.dart';
import '../../shared/widgets/beta_page_motion.dart';
import '../../shared/widgets/track_artwork.dart';
import '../music_platform/music_platform_providers.dart';
import '../music_platform/data/music_platform_api.dart';
import '../music_platform/presentation/platform_design.dart';
import '../music_platform/presentation/platform_feedback.dart';
import '../experience/presentation/editorial_widgets.dart';
import '../player/presentation/beta_playback_actions.dart';
import 'audio_downloads.dart';
import 'audio_download_quality.dart';
import 'audio_download_storage.dart';
import '../../shared/widgets/music_notice.dart';
import '../../shared/widgets/music_list_footer.dart';

Future<void> enqueueAudioDownload(
  BuildContext context,
  WidgetRef ref,
  Track track,
) async {
  await enqueueAudioDownloads(context, ref, [track]);
}

/// Every entry (single track and collection) goes through the same selection,
/// directory grant, and retained-account check before adding durable tasks.
Future<void> enqueueAudioDownloads(
  BuildContext context,
  WidgetRef ref,
  List<Track> tracks,
) async {
  try {
    if (tracks.isEmpty) return;
    final account = ref.read(platformAccountProvider).value;
    final owner = account?.ownerId;
    if (owner == null) throw const MusicPlatformException('请先登录对应音乐平台');
    final quality = await chooseAudioDownloadQuality(context, tracks);
    if (!context.mounted || quality == null) return;
    final directory = await const AudioDownloadStorage().ensureDirectory();
    if (!context.mounted || directory == null) return;
    final current = ref.read(platformAccountProvider).value;
    if (current?.ownerId != owner || current?.token != account?.token) return;
    final manager = ref.read(audioDownloadManagerProvider);
    manager.enqueueAll(tracks, quality: quality);
    showMusicNotice(
      context,
      icon: Icons.check_rounded,
      title: '已加入下载队列',
      message: '可在下载管理中查看',
    );
  } catch (e) {
    if (context.mounted) showPlatformFailure(context, e);
  }
}

void openAudioDownloads(BuildContext context, {bool downloadedOnly = false}) =>
    Navigator.of(context).push(
      betaContentRoute<void>(
        AudioDownloadsPage(downloadedOnly: downloadedOnly),
      ),
    );

/// Playback order is exactly the order visible under 已下载. A missing document
/// is reported before replacing the queue, never silently replaced by a CDN URL.
class AudioDownloadsPage extends ConsumerStatefulWidget {
  const AudioDownloadsPage({this.downloadedOnly = false, super.key});
  final bool downloadedOnly;
  @override
  ConsumerState<AudioDownloadsPage> createState() => _AudioDownloadsPageState();
}

class _AudioDownloadsPageState extends ConsumerState<AudioDownloadsPage> {
  late bool _downloaded = widget.downloadedOnly;
  bool _busy = false;
  final _storage = const AudioDownloadStorage();
  Future<void> _act(Future<void> Function() operation) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await operation();
    } catch (e) {
      if (mounted) showPlatformFailure(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _play(List<AudioDownloadTask> tasks, {bool all = false}) =>
      _act(() async {
        final owner = ref.read(platformAccountProvider).value?.ownerId;
        final tracks = <Track>[];
        for (final task in tasks) {
          if (task.owner != owner) return;
          if (!await _storage.readable(task.uri)) {
            throw MusicPlatformException(
              '“${task.track.title}”文件已被移动或授权失效，请重新授权或下载',
            );
          }
          tracks.add(downloadedPlaybackTrack(task));
        }
        if (!mounted ||
            tracks.isEmpty ||
            ref.read(platformAccountProvider).value?.ownerId != owner) {
          return;
        }
        await playBetaSelection(
          context,
          ref,
          tracks.first,
          playAll: all ? tracks : null,
        );
      });
  Future<void> _menu(AudioDownloadTask task) => showSongActions(
    context,
    ref,
    downloadedPlaybackTrack(task),
    prepareForQueue: () async {
      if (!await _storage.readable(task.uri)) {
        throw StateError('文件已被移动或授权失效，请重新授权');
      }
      return downloadedPlaybackTrack(task);
    },
    extras: [
      SongMenuExtraAction('播放', CupertinoIcons.play_fill, () => _play([task])),
      SongMenuExtraAction(
        '导出音乐文件',
        CupertinoIcons.share,
        () => _act(() => _storage.export(task.uri, task.track)),
      ),
      SongMenuExtraAction(
        '打开所在文件夹',
        CupertinoIcons.folder,
        () => _act(() => _storage.openDirectory(uri: task.uri)),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final manager = ref.watch(audioDownloadManagerProvider);
    final owner = ref.watch(platformAccountProvider).value?.ownerId;
    return PlatformPageFrame(
      title: '下载管理',
      child: ListenableBuilder(
        listenable: manager.collectionChanges,
        builder: (context, _) {
          if (manager.restoring) {
            return const PlatformFeedbackState(loading: true);
          }
          if (manager.restoreError != null) {
            return PlatformFeedbackState(
              message: '下载记录暂时无法读取',
              retry: () => ref.invalidate(audioDownloadManagerProvider),
            );
          }
          final tasks = manager.tasks
              .where((t) => t.owner == owner)
              .toList()
              .reversed
              .toList();
          final completed = tasks
              .where((t) => t.phase == AudioDownloadPhase.completed)
              .toList();
          // Completion is a successful document publish, never network 100%.
          final pending = tasks
              .where((t) => t.phase != AudioDownloadPhase.completed)
              .toList();
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 12, 22, 12),
                child: CupertinoSlidingSegmentedControl<bool>(
                  groupValue: _downloaded,
                  children: const {
                    true: Padding(
                      padding: EdgeInsets.all(8),
                      child: Text('已下载'),
                    ),
                    false: Padding(
                      padding: EdgeInsets.all(8),
                      child: Text('下载任务'),
                    ),
                  },
                  onValueChanged: (value) {
                    if (value != null) setState(() => _downloaded = value);
                  },
                ),
              ),
              Expanded(
                child: BetaSwipePages(
                  index: _downloaded ? 0 : 1,
                  length: 2,
                  onChanged: (index) {
                    if (_downloaded != (index == 0)) {
                      setState(() => _downloaded = index == 0);
                    }
                  },
                  itemBuilder: (context, index) => _list(
                    manager,
                    completed,
                    index == 0 ? completed : pending,
                    downloaded: index == 0,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _list(
    AudioDownloadManager manager,
    List<AudioDownloadTask> completed,
    List<AudioDownloadTask> visible, {
    required bool downloaded,
  }) => SongListTools(
    listId: 'downloads:$downloaded',
    child: CustomScrollView(
      key: PageStorageKey('audio-downloads-$downloaded'),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  key: downloaded
                      ? const ValueKey('download-actions-row')
                      : null,
                  children: [
                    Expanded(
                      child: BetaGlassButton(
                        key: downloaded
                            ? const ValueKey('downloaded-play-all')
                            : null,
                        red: true,
                        height: 52,
                        horizontalPadding: 5,
                        loading: _busy,
                        onPressed: completed.isEmpty || _busy
                            ? null
                            : () => _play(completed, all: true),
                        child: const Text(
                          '播放全部',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: BetaGlassButton(
                        label: '打开下载文件夹',
                        height: 52,
                        horizontalPadding: 5,
                        onPressed: _busy
                            ? null
                            : () => _act(() => _storage.openDirectory()),
                        child: const Text(
                          '打开目录',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: BetaGlassButton(
                        label: '选择下载目录',
                        height: 52,
                        horizontalPadding: 5,
                        onPressed: _busy
                            ? null
                            : () => _act(() async {
                                await _storage.directory(choose: true);
                              }),
                        child: const Text(
                          '选择目录',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  '已完成 ${completed.length} 首 · 更改目录只影响后续下载',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        if (visible.isEmpty)
          SliverToBoxAdapter(
            child: EditorialEmpty(
              downloaded ? '还没有已下载的音乐。\n从歌曲更多菜单下载后，即可离线播放。' : '暂无下载任务',
            ),
          ),
        SliverList.builder(
          itemCount: visible.length,
          itemBuilder: (context, index) => ListenableBuilder(
            listenable: manager.taskChanges(visible[index].id),
            builder: (context, _) {
              final task =
                  manager.taskById(visible[index].id) ?? visible[index];
              final done = task.phase == AudioDownloadPhase.completed;
              final resolving = task.phase == AudioDownloadPhase.resolving;
              final active = task.phase == AudioDownloadPhase.downloading;
              final canCancel = {
                AudioDownloadPhase.queued,
                AudioDownloadPhase.resolving,
                AudioDownloadPhase.downloading,
              }.contains(task.phase);
              final label = switch (task.phase) {
                AudioDownloadPhase.queued => '等待下载',
                AudioDownloadPhase.resolving => '正在解析音源',
                AudioDownloadPhase.downloading => '正在下载',
                AudioDownloadPhase.saving => '正在保存',
                AudioDownloadPhase.completed =>
                  '已下载 · ${formatDownloadBytes(task.received)}',
                AudioDownloadPhase.failed => task.error,
                AudioDownloadPhase.cancelled => '已取消',
                AudioDownloadPhase.paused =>
                  '已暂停 · ${formatDownloadBytes(task.received)}',
              };
              final row = Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 4,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      onTap: done && !_busy
                          ? () {
                              SongListTools.remember(context, task.track);
                              _play([task]);
                            }
                          : null,
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: TrackArtwork(
                          track: task.track,
                          width: 52,
                          height: 52,
                        ),
                      ),
                      title: Text(
                        task.track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${task.track.artist}\n${task.requestedQuality == null ? '' : '${task.track.source == TrackSource.netease ? task.requestedQuality!.neteaseLabel : task.requestedQuality!.label} · '}$label',
                      ),
                      isThreeLine: true,
                      trailing: done
                          ? IconButton(
                              tooltip: '下载文件操作',
                              icon: const Icon(Icons.more_vert_rounded),
                              onPressed: _busy ? null : () => _menu(task),
                            )
                          : task.phase == AudioDownloadPhase.paused
                          ? IconButton(
                              tooltip: '继续下载',
                              icon: const Icon(CupertinoIcons.play_fill),
                              onPressed: () => manager.resume(task.id),
                            )
                          : active || resolving
                          ? IconButton(
                              tooltip: '暂停下载',
                              icon: const Icon(CupertinoIcons.pause_fill),
                              onPressed: () => manager.pause(task.id),
                            )
                          : canCancel
                          ? IconButton(
                              tooltip: '取消下载',
                              icon: const Icon(CupertinoIcons.xmark_circle),
                              onPressed: () => manager.cancel(task.id),
                            )
                          : task.phase == AudioDownloadPhase.failed ||
                                task.phase == AudioDownloadPhase.cancelled
                          ? IconButton(
                              tooltip: '重新下载',
                              icon: const Icon(CupertinoIcons.arrow_clockwise),
                              onPressed: () async {
                                final folder = await _storage.ensureDirectory();
                                if (folder != null && mounted) {
                                  manager.retry(task.id);
                                }
                              },
                            )
                          : null,
                    ),
                    if (resolving)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: AudioResolvingWave(),
                      ),
                    if (active ||
                        task.phase == AudioDownloadPhase.saving ||
                        task.phase == AudioDownloadPhase.paused)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: AppleDownloadProgress(
                          receivedBytes: task.received,
                          totalBytes: task.total,
                          semanticLabel: '音频下载进度',
                        ),
                      ),
                  ],
                ),
              );
              if (done) {
                return SongListEntry(
                  track: task.track,
                  tracks: completed.map((task) => task.track).toList(),
                  child: row,
                );
              }
              if (task.phase == AudioDownloadPhase.saving) return row;
              return Dismissible(
                key: ValueKey('download-dismiss-${task.id}'),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 28),
                  color: Theme.of(context).colorScheme.error,
                  child: const Icon(CupertinoIcons.delete, color: Colors.white),
                ),
                confirmDismiss: (_) async => manager.remove(task.id),
                child: row,
              );
            },
          ),
        ),
        SliverToBoxAdapter(
          child: Column(
            children: [
              if (visible.isNotEmpty) const MusicListEnd(),
              SizedBox(height: BetaContentInsets.musicBottomOf(context, 12)),
            ],
          ),
        ),
      ],
    ),
  );
}
