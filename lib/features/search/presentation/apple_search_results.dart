import '../../../shared/widgets/artwork_scroll_frontier.dart';
import '../../../shared/widgets/beta_content_insets.dart';
import '../../../shared/widgets/beta_popup_menu_button.dart';
import '../../music_platform/netease/fallback/netease_source_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/audio/playback_providers.dart';
import '../../player/presentation/beta_playback_actions.dart';
import '../../../shared/models/track.dart';
import '../../../shared/widgets/track_artwork.dart';
import '../../../shared/widgets/music_notice.dart';
import '../../../shared/widgets/automatic_song_paging.dart';
import '../../auth/account_capabilities.dart';
import '../../library/presentation/favorite_toggle_button.dart';
import '../../music_platform/presentation/platform_comments_page.dart';
import '../../music_platform/presentation/platform_feedback.dart';
import '../search_providers.dart';

/// A single lazy scroll view owns pagination and row construction. Avoid a
/// shrink-wrapped list inside another list: later search pages can contain
/// hundreds of rows and must not rebuild/decode all their covers at once.
class AppleSearchResults extends ConsumerWidget {
  const AppleSearchResults({
    required this.state,
    required this.controller,
    super.key,
  });
  final MusicSearchState state;
  final ScrollController controller;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    Widget section(String name, int count) => Padding(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 12),
      child: Row(
        children: [
          Text(
            name,
            style: theme.textTheme.titleLarge?.copyWith(
              fontSize: 23,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          Text('共 ${state.total ?? count} 首', style: theme.textTheme.bodySmall),
        ],
      ),
    );
    return AutomaticSongPaging(
      enabled: state.hasMore && !state.isLoadingMore && state.moreError == null,
      onLoadMore: ref.read(musicSearchControllerProvider.notifier).loadMore,
      child: CustomScrollView(
        key: PageStorageKey('search-results-${state.query}'),
        controller: controller,
        physics: const ArtworkFrontierPhysics(parent: BouncingScrollPhysics()),
        slivers: [
          if (state.errorMessage != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  children: [
                    Text(state.errorMessage!),
                    TextButton(
                      onPressed: ref
                          .read(musicSearchControllerProvider.notifier)
                          .retry,
                      child: const Text('重新搜索'),
                    ),
                  ],
                ),
              ),
            ),
          for (final group in [
            (name: '本地音乐', tracks: state.localTracks),
            (name: '歌曲', tracks: state.onlineTracks),
          ])
            if (group.tracks.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: section(group.name, group.tracks.length),
              ),
              SliverList.builder(
                itemCount: group.tracks.length,
                itemBuilder: (_, index) => _SearchSongRow(
                  track: group.tracks[index],
                  contextTracks: group.tracks,
                ),
              ),
            ],
          if (!state.hasResults && state.errorMessage == null)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('没有找到相关歌曲，试试其他关键词。'),
              ),
            ),
          SliverToBoxAdapter(
            child: Padding(
              padding: BetaContentInsets.musicPaddingOf(
                context,
                EdgeInsets.fromLTRB(22, 16, 22, 190),
              ),
              child: state.isLoadingMore
                  ? const Center(child: CupertinoActivityIndicator())
                  : state.moreError != null
                  ? TextButton(
                      onPressed: ref
                          .read(musicSearchControllerProvider.notifier)
                          .loadMore,
                      child: Text(state.moreError ?? '重新加载'),
                    )
                  : state.onlineTracks.isEmpty || state.hasMore
                  ? const SizedBox.shrink()
                  : const Center(
                      child: Text('已显示全部搜索结果', style: TextStyle(fontSize: 12)),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchSongRow extends ConsumerWidget {
  const _SearchSongRow({required this.track, required this.contextTracks});
  final Track track;
  final List<Track> contextTracks;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(
      currentTrackProvider.select((current) => current.id == track.id),
    );
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () async {
          try {
            await playBetaSelection(context, ref, track);
          } catch (error) {
            if (context.mounted) showPlatformFailure(context, error);
          }
        },
        child: Padding(
          padding: const EdgeInsets.only(left: 22, right: 10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: TrackArtwork(track: track, width: 52, height: 52),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(minHeight: 76),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: theme.dividerColor.withValues(alpha: .16),
                        width: .5,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                track.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: active
                                      ? theme.colorScheme.primary
                                      : theme.colorScheme.onSurface,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                [
                                  track.artist,
                                  track.album,
                                ].where((s) => s.isNotEmpty).join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      FavoriteToggleButton(track: track, compact: true),
                      BetaPopupMenuButton<String>(
                        tooltip: '歌曲操作',
                        icon: Icon(
                          CupertinoIcons.ellipsis,
                          size: 21,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        onSelected: (action) async {
                          if (action == 'source') {
                            await showNeteaseTrackSources(context, ref, track);
                            return;
                          }
                          if (action == 'comments') {
                            await openPlatformSongComments(context, ref, track);
                            return;
                          }
                          try {
                            final added = await ref
                                .read(audioHandlerProvider)
                                .appendToUpcomingQueue(track);
                            if (context.mounted) {
                              showMusicNotice(
                                context,
                                icon: CupertinoIcons.text_badge_plus,
                                title: added ? '已加入播放队列' : '已在播放队列',
                                message: '',
                              );
                            }
                          } catch (error) {
                            if (context.mounted) {
                              showPlatformFailure(context, error);
                            }
                          }
                        },
                        itemBuilder: (_) => [
                          if (track.source == TrackSource.netease)
                            const PopupMenuItem(
                              value: 'source',
                              child: Text('选择音乐来源'),
                            ),
                          if (ref.read(showPlatformFeaturesProvider) &&
                              track.source == TrackSource.kugou)
                            const PopupMenuItem(
                              value: 'comments',
                              child: Row(
                                children: [
                                  Icon(CupertinoIcons.text_bubble, size: 20),
                                  SizedBox(width: 12),
                                  Text('歌曲评论'),
                                ],
                              ),
                            ),
                          const PopupMenuItem(
                            value: 'queue',
                            child: Row(
                              children: [
                                Icon(CupertinoIcons.text_badge_plus, size: 20),
                                SizedBox(width: 12),
                                Text('加入播放队列'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
