import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/widgets/beta_glass_controls.dart';
import '../../../shared/widgets/music_activity_indicator.dart';
import '../../../shared/widgets/track_artwork.dart';
import '../../downloads/audio_downloads.dart';
import '../../downloads/audio_downloads_page.dart';
import '../music_platform_providers.dart';

/// Mine observes the existing durable manager and filters by the current owner.
/// It never reconstructs a task or starts a second download worker. Per-byte
/// ticks remain inside the manager page rather than rebuilding the Mine header.
class QishuiMineDownloads extends ConsumerWidget {
  const QishuiMineDownloads({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final manager = ref.watch(audioDownloadManagerProvider);
    final owner = ref.watch(platformAccountProvider).value?.ownerId;
    return ListenableBuilder(
      listenable: manager.collectionChanges,
      builder: (context, _) {
        if (manager.restoring) {
          return const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: MusicActivityIndicator(label: '正在读取下载记录')),
            ),
          );
        }
        final tasks = manager.tasks
            .where((task) => task.owner == owner)
            .toList()
            .reversed
            .toList();
        return SliverMainAxisGroup(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                child: BetaGlassButton(
                  onPressed: () => openAudioDownloads(context),
                  child: const Text('打开下载管理'),
                ),
              ),
            ),
            if (manager.restoreError != null)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('下载记录暂时无法读取，请在下载管理中重试。'),
                ),
              )
            else if (tasks.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('还没有汽水下载记录。'),
                ),
              )
            else
              SliverList.builder(
                itemCount: tasks.length,
                itemBuilder: (context, index) {
                  final task = tasks[index];
                  final completed = task.phase == AudioDownloadPhase.completed;
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 6,
                    ),
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
                      '${task.track.artist} · ${completed ? '已下载' : '下载任务'}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Icon(
                      completed
                          ? Icons.download_done_rounded
                          : Icons.downloading_rounded,
                    ),
                    onTap: () =>
                        openAudioDownloads(context, downloadedOnly: completed),
                  );
                },
              ),
          ],
        );
      },
    );
  }
}
