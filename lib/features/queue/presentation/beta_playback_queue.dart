import '../../../shared/widgets/song_list_tools.dart';
import '../../../shared/models/track.dart';
import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/audio/playback_mode.dart';
import '../../../core/audio/playback_providers.dart';
import '../../../shared/widgets/artwork_image.dart';
import '../../../shared/widgets/music_notice.dart';
import '../../music_platform/presentation/platform_feedback.dart';
import 'queue_track_duration.dart';

/// Shared sheet/player presentation. Never regroup rows into an order different
/// from the handler's authoritative queue, including automatic recommendations.
class BetaPlaybackQueue extends ConsumerStatefulWidget {
  const BetaPlaybackQueue({
    this.immersive = false,
    this.onClose,
    this.bottomClearance = 18,
    super.key,
  });
  final bool immersive;
  final VoidCallback? onClose;

  /// Only the full queue route has floating music chrome. Sheets and the
  /// player's inline queue keep their own existing viewport and safe area.
  final double bottomClearance;
  @override
  ConsumerState<BetaPlaybackQueue> createState() => _BetaPlaybackQueueState();
}

class _BetaPlaybackQueueState extends ConsumerState<BetaPlaybackQueue> {
  List<String>? _dragIds;
  @override
  Widget build(BuildContext context) {
    final immersive = widget.immersive;
    final onClose = widget.onClose;
    final handler = ref.watch(audioHandlerProvider);
    final items =
        ref.watch(upcomingQueueProvider).value ?? handler.upcomingQueue;
    final tracks = items
        .map((item) => handler.trackForId(item.id))
        .whereType<Track>()
        .toList(growable: false);
    final order =
        ref.watch(playbackOrderProvider).value ?? handler.playbackOrder;
    final colors = Theme.of(context).colorScheme;
    final ink = immersive ? Colors.white : colors.onSurface;
    final muted = immersive ? Colors.white70 : colors.onSurfaceVariant;
    Future<void> act(
      Future<void> Function() operation, [
      String Function()? text,
    ]) async {
      try {
        await operation();
        if (context.mounted && text != null) {
          showMusicNotice(
            context,
            icon: Icons.check_rounded,
            title: text(),
            message: '',
          );
        }
      } catch (error) {
        if (context.mounted) showPlatformFailure(context, error);
      }
    }

    Widget modeButton(
      String key,
      String label,
      IconData icon,
      bool selected,
      VoidCallback tap,
    ) => Semantics(
      button: true,
      toggled: selected,
      label: label,
      child: Tooltip(
        message: label,
        child: CupertinoButton(
          key: ValueKey(key),
          onPressed: tap,
          padding: EdgeInsets.zero,
          minimumSize: const Size(48, 48),
          child: Container(
            width: 46,
            height: 38,
            decoration: BoxDecoration(
              // The glyph communicates the mode. Keep the same neutral
              // surface/ink across every shuffle and repeat state.
              color: ink.withValues(alpha: .08),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: ink, size: 23),
          ),
        ),
      ),
    );
    return SongListTools(
      listId: 'playback-queue',
      bottom: widget.bottomClearance,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, immersive ? 10 : 4, 20, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    immersive ? '待播列表' : '播放列表',
                    style: TextStyle(
                      color: ink,
                      fontSize: 25,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (onClose != null)
                  CupertinoButton(
                    key: const ValueKey('beta-queue-close'),
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(48, 48),
                    onPressed: onClose,
                    child: Icon(
                      CupertinoIcons.xmark_circle_fill,
                      color: muted,
                      size: 30,
                    ),
                  ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${items.length} 首待播放',
                    style: TextStyle(color: muted, fontSize: 13),
                  ),
                ),
                modeButton(
                  'player-shuffle',
                  order.shuffle ? '随机播放已开启，点击关闭' : '顺序播放，点击开启随机播放',
                  order.shuffle
                      ? CupertinoIcons.shuffle
                      : CupertinoIcons.arrow_up_arrow_down,
                  order.shuffle,
                  () => unawaited(
                    act(
                      () => handler.setShuffleEnabled(
                        !handler.playbackOrder.shuffle,
                      ),
                      () => handler.playbackOrder.shuffle
                          ? '已开启随机播放'
                          : '已关闭随机播放，恢复顺序播放',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                modeButton(
                  'player-repeat',
                  '${order.repeat.label}，点击切换循环方式',
                  order.repeat == PlaybackRepeat.one
                      ? CupertinoIcons.repeat_1
                      : order.repeat == PlaybackRepeat.all
                      ? CupertinoIcons.repeat
                      : CupertinoIcons.arrow_turn_down_right,
                  order.repeat != PlaybackRepeat.off,
                  () => unawaited(
                    act(
                      handler.cycleRepeat,
                      () => '已切换为${handler.playbackOrder.repeat.label}',
                    ),
                  ),
                ),
              ],
            ),
            Expanded(
              child: items.isEmpty
                  ? Center(
                      child: Text('暂无待播歌曲', style: TextStyle(color: muted)),
                    )
                  : ReorderableListView.builder(
                      key: const ValueKey('player-inline-queue'),
                      buildDefaultDragHandles: false,
                      padding: EdgeInsets.only(
                        top: 8,
                        bottom: widget.bottomClearance,
                      ),
                      proxyDecorator: (child, _, animation) => Material(
                        color: immersive
                            ? const Color(0xF0242529)
                            : colors.surfaceContainerHigh,
                        elevation: 6,
                        shadowColor: Colors.black26,
                        borderRadius: BorderRadius.circular(14),
                        child: child,
                      ),
                      onReorderStart: (index) =>
                          _dragIds = items.map((item) => item.id).toList(),
                      onReorder: (oldIndex, newIndex) {
                        // Rebase by identity: playback may advance while a drag is active.
                        final snapshot =
                            _dragIds ?? items.map((item) => item.id).toList();
                        _dragIds = null;
                        if (oldIndex >= snapshot.length) return;
                        final moved = snapshot.removeAt(oldIndex);
                        if (newIndex > oldIndex) newIndex--;
                        newIndex = newIndex.clamp(0, snapshot.length);
                        snapshot.insert(newIndex, moved);
                        final live = handler.upcomingQueue;
                        final liveIds = live.map((item) => item.id).toSet();
                        final candidates = snapshot
                            .skip(newIndex + 1)
                            .where(liveIds.contains);
                        final nextId = candidates.isEmpty
                            ? null
                            : candidates.first;
                        final from = live.indexWhere(
                          (item) => item.id == moved,
                        );
                        final before = nextId == null
                            ? live.length
                            : live.indexWhere((item) => item.id == nextId);
                        if (from >= 0 && before >= 0) {
                          unawaited(
                            act(() => handler.reorderUpcoming(from, before)),
                          );
                        }
                      },
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final item = items[index];
                        final track = handler.trackForId(item.id);
                        Future<void> moveBy(int delta) async {
                          final live = handler.upcomingQueue;
                          final from = live.indexWhere(
                            (entry) => entry.id == item.id,
                          );
                          final to = from + delta;
                          if (from >= 0 && to >= 0 && to < live.length) {
                            await handler.reorderUpcoming(
                              from,
                              to > from ? to + 1 : to,
                            );
                          }
                        }

                        final row = Dismissible(
                          key: ValueKey('pending-${item.id}'),
                          direction: DismissDirection.endToStart,
                          // Confirm the mutation before dismissing; failure leaves the row.
                          confirmDismiss: (_) async {
                            try {
                              return await handler.removeFromUpcomingQueue(
                                item.id,
                              );
                            } catch (error) {
                              if (context.mounted) {
                                showPlatformFailure(context, error);
                              }
                              return false;
                            }
                          },
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 22),
                            decoration: BoxDecoration(
                              color: colors.error,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              CupertinoIcons.trash,
                              color: colors.onError,
                              size: 24,
                            ),
                          ),
                          child: Semantics(
                            label:
                                '${index == 0 ? '下一首' : '待播放'}，${item.title}，${item.artist ?? '未知歌手'}',
                            customSemanticsActions: {
                              const CustomSemanticsAction(
                                label: '从待播列表移除',
                              ): () => unawaited(
                                act(() async {
                                  await handler.removeFromUpcomingQueue(
                                    item.id,
                                  );
                                }),
                              ),
                              if (index > 0)
                                const CustomSemanticsAction(
                                  label: '上移一首',
                                ): () =>
                                    unawaited(act(() => moveBy(-1))),
                              if (index + 1 < items.length)
                                const CustomSemanticsAction(
                                  label: '下移一首',
                                ): () =>
                                    unawaited(act(() => moveBy(1))),
                            },
                            child: CupertinoButton(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              onPressed: () {
                                if (track != null) {
                                  SongListTools.remember(context, track);
                                }
                                unawaited(
                                  act(() => handler.playTrack(item.id)),
                                );
                              },
                              child: Row(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(9),
                                    child: ArtworkImage(
                                      uri:
                                          track?.coverAsset ??
                                          item.artUri?.toString() ??
                                          '',
                                      width: 48,
                                      height: 48,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: ink,
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          '${item.artist ?? '未知歌手'}${handler.isAutomaticallyQueued(item.id) ? ' · 自动推荐' : ''}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: muted,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  QueueTrackDuration(
                                    track: track,
                                    mediaDuration: item.duration,
                                    style: TextStyle(
                                      color: muted,
                                      fontSize: 11,
                                    ),
                                  ),
                                  ReorderableDragStartListener(
                                    key: ValueKey('queue-drag-${item.id}'),
                                    index: index,
                                    child: SizedBox(
                                      width: 48,
                                      height: 48,
                                      child: Icon(
                                        CupertinoIcons.line_horizontal_3,
                                        color: muted,
                                        size: 21,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                        return track == null
                            ? row
                            : SongListEntry(
                                key: ValueKey('queue-entry-${item.id}'),
                                track: track,
                                tracks: tracks,
                                child: row,
                              );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
