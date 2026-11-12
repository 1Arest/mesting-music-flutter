import '../../music_platform/presentation/song_actions_sheet.dart';
import '../../../shared/widgets/song_list_tools.dart';
import '../../../shared/widgets/artwork_scroll_frontier.dart';
import '../../../shared/widgets/beta_content_insets.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/audio/playback_providers.dart';
import '../../player/presentation/beta_playback_actions.dart';
import '../../../shared/models/track.dart';
import '../../../shared/widgets/track_artwork.dart';
import '../../../shared/widgets/automatic_song_paging.dart';
import '../../library/presentation/favorite_toggle_button.dart';
import '../../music_platform/presentation/platform_feedback.dart';
import '../search_providers.dart';
import '../../themes/music_typography.dart';
import '../../../shared/widgets/liquid_glass_sheet.dart';
import '../../music_platform/music_platform_providers.dart';
import '../../../shared/models/song_search_facts.dart';

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
              fontSize: MusicTypography.sectionTitleSize,
              fontWeight: MusicTypography.titleWeight,
            ),
          ),
          const Spacer(),
          Text(
            state.sourceChoices.isNotEmpty
                ? '已加载 $count 首'
                : '共 ${state.total ?? count} 首',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
    return AutomaticSongPaging(
      songListId: 'search:songs:${state.query.trim().toLowerCase()}',
      enabled: state.hasMore && !state.isLoadingMore && state.moreError == null,
      onLoadMore: ref.read(musicSearchControllerProvider.notifier).loadMore,
      child: CustomScrollView(
        key: PageStorageKey('search-results-${state.query}'),
        controller: controller,
        physics: const ArtworkFrontierPhysics(parent: BouncingScrollPhysics()),
        slivers: [
          for (final warning in state.warnings)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 4),
                child: Text(warning, style: theme.textTheme.bodySmall),
              ),
            ),
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
                  key: ValueKey(group.tracks[index].id),
                  track: group.tracks[index],
                  contextTracks: group.tracks,
                  sources:
                      state.sourceChoices[group.tracks[index].id] ?? const [],
                  facts: state.songFacts,
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
                      child: Text(
                        '已显示全部搜索结果',
                        style: TextStyle(fontSize: MusicTypography.captionSize),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchSongRow extends ConsumerWidget {
  const _SearchSongRow({
    required this.track,
    required this.contextTracks,
    this.sources = const [],
    this.facts = const {},
    super.key,
  });
  final Track track;
  final List<Track> contextTracks;
  final List<Track> sources;
  final Map<String, SongSearchFacts> facts;

  String _source(Track value) =>
      value.source == TrackSource.netease ? '网易云' : '酷狗';

  Future<void> _chooseSource(BuildContext context, WidgetRef ref) async {
    final query = ref.read(musicSearchControllerProvider).query;
    final owner = ref.read(platformAccountProvider).value;
    final identity = (owner?.ownerId, owner?.token);
    final selected = await showLiquidGlassBottomSheet<Track>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      builder: (sheet) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(padding: EdgeInsets.all(20), child: Text('选择音源')),
          for (final value in sources)
            ListTile(
              title: Text(
                [
                  _source(value),
                  facts[value.id]?.label ?? '',
                ].where((s) => s.isNotEmpty).join(' · '),
              ),
              subtitle: Text('${value.artist} · ${value.album}'),
              trailing: value.id == track.id
                  ? const Icon(Icons.check_rounded)
                  : null,
              onTap: () => Navigator.of(sheet).pop(value),
            ),
          const SizedBox(height: 20),
        ],
      ),
    );
    if (!context.mounted ||
        selected == null ||
        ref.read(musicSearchControllerProvider).query != query) {
      return;
    }
    final now = ref.read(platformAccountProvider).value;
    if ((now?.ownerId, now?.token) != identity) return;
    // A stale sheet cannot insert a song after its account/query was replaced.
    if (!(ref.read(musicSearchControllerProvider).sourceChoices[track.id] ??
            const <Track>[])
        .any((t) => t.id == selected.id)) {
      return;
    }
    ref
        .read(musicSearchControllerProvider.notifier)
        .chooseSongSource(track.id, selected);
    await playBetaSelection(context, ref, selected);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(
      currentTrackProvider.select((current) => current.id == track.id),
    );
    final theme = Theme.of(context);
    // At narrow accessibility sizes, keep all 48dp action targets while giving
    // the source label enough width to remain readable in the song details.
    final stackedActions =
        sources.length > 1 &&
        MediaQuery.sizeOf(context).width < 360 &&
        MediaQuery.textScalerOf(context).scale(14) > 21;
    final actions = <Widget>[
      if (sources.length > 1)
        IconButton(
          tooltip: '选择音源（${sources.length}）',
          onPressed: () => _chooseSource(context, ref),
          icon: const Icon(Icons.library_music_outlined, size: 21),
        ),
      FavoriteToggleButton(track: track, compact: true),
      SongActionsButton(track: track),
    ];
    return SongListEntry(
      track: track,
      tracks: contextTracks,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () async {
            try {
              SongListTools.remember(context, track);
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
                                    fontSize: MusicTypography.calloutSize,
                                    fontWeight: MusicTypography.bodyWeight,
                                    color: active
                                        ? theme.colorScheme.primary
                                        : theme.colorScheme.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                if (sources.isNotEmpty)
                                  Text(
                                    [
                                      _source(track),
                                      facts[track.id]?.label ?? '',
                                    ].where((s) => s.isNotEmpty).join(' · '),
                                    // Provenance and access status remain
                                    // readable at accessibility font sizes.
                                    style: TextStyle(
                                      fontSize: MusicTypography.footnoteSize,
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                Text(
                                  [
                                    track.artist,
                                    track.album,
                                  ].where((s) => s.isNotEmpty).join(' · '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: MusicTypography.footnoteSize,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (stackedActions)
                          SizedBox(
                            width: 96,
                            child: Wrap(
                              alignment: WrapAlignment.end,
                              children: actions,
                            ),
                          )
                        else
                          ...actions,
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
