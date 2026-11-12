import '../../music_platform/presentation/song_actions_sheet.dart';
import '../../../shared/widgets/song_list_tools.dart';
import '../../../shared/models/track.dart';
import '../../../shared/widgets/artwork_scroll_frontier.dart';
import '../../../shared/widgets/beta_content_insets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/widgets/artwork_image.dart';
import '../../../shared/widgets/artwork_reveal_boundary.dart';
import '../../../shared/widgets/automatic_song_paging.dart';
import '../../../shared/widgets/beta_glass_controls.dart';
import '../../../shared/widgets/beta_swipe_pages.dart';
import '../../library/presentation/favorite_toggle_button.dart';
import '../../player/presentation/beta_playback_actions.dart';
import '../../themes/beta_appearance.dart';
import '../../music_platform/data/platform_category_search.dart';
import '../../music_platform/platform_category_search_providers.dart';
import '../../music_platform/platform_artist_portrait.dart';
import '../search_providers.dart';
import 'apple_search_results.dart';
import '../../music_platform/platform_backend_providers.dart';
import '../../music_platform/netease/netease_user_page.dart';
import '../../themes/music_typography.dart';

/// One compact category rail above a lazy result pane. Queries and paging live
/// outside widgets; a pane owns its own scroll controller even during a rapid
/// A→B→A exit/entry, so two animated children never attach to the same controller.
class BetaCategorySearchResults extends ConsumerStatefulWidget {
  const BetaCategorySearchResults({super.key});
  @override
  ConsumerState<BetaCategorySearchResults> createState() =>
      _BetaCategorySearchResultsState();
}

class _BetaCategorySearchResultsState
    extends ConsumerState<BetaCategorySearchResults> {
  // A query-empty landing removes this result surface. A new search therefore
  // gets a fresh bucket even for the same text, while category/temporary route
  // changes retain offsets in this still-mounted session.
  final _storage = PageStorageBucket();
  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(
      categorySearchProvider.select((s) => s.selected),
    );
    final netease = ref.watch(usesNeteaseProvider);
    final query = ref.watch(
      musicSearchControllerProvider.select((s) => s.query),
    );
    final kinds = [
      for (final kind in PlatformSearchKind.values)
        if (kind != PlatformSearchKind.users || netease) kind,
    ];
    final selectedIndex = kinds.indexOf(selected);
    final ink = Theme.of(context).colorScheme.onSurface;
    final accent = BetaAppearance.accent(Theme.of(context).brightness);
    return PageStorage(
      bucket: _storage,
      child: Column(
        children: [
          Material(
            color: Theme.of(context).colorScheme.surface,
            child: Row(
              children: [
                for (final kind in kinds)
                  Expanded(
                    child: Semantics(
                      selected: selected == kind,
                      button: true,
                      child: InkWell(
                        key: ValueKey('search-kind-${kind.name}'),
                        onTap: () {
                          ref
                              .read(categorySearchProvider.notifier)
                              .select(kind);
                        },
                        child: Column(
                          children: [
                            SizedBox(
                              height: 48,
                              child: Center(
                                child: Text(
                                  kind.label,
                                  style: TextStyle(
                                    fontSize: MusicTypography.subheadlineSize,
                                    fontWeight: MusicTypography.bodyWeight,
                                    color: selected == kind
                                        ? accent
                                        : ink.withValues(alpha: .8),
                                  ),
                                ),
                              ),
                            ),
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 220),
                              height: 3,
                              width: selected == kind ? 28 : 0,
                              decoration: BoxDecoration(
                                color: accent,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1, thickness: .5),
          Expanded(
            // Share the download viewport: one retained pane per visited
            // category, with swipe/click selection and active-scroll ownership.
            // A new query/platform owns fresh controllers and reveal gates.
            child: BetaSwipePages(
              key: ValueKey(('search-pages', query, netease)),
              index: selectedIndex < 0 ? 0 : selectedIndex,
              length: kinds.length,
              onChanged: (index) => ref
                  .read(categorySearchProvider.notifier)
                  .select(kinds[index]),
              itemBuilder: (_, index) => ArtworkRevealBoundary(
                key: ValueKey(kinds[index]),
                child: _CategoryPane(kind: kinds[index]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryPane extends ConsumerStatefulWidget {
  const _CategoryPane({required this.kind});
  final PlatformSearchKind kind;
  @override
  ConsumerState<_CategoryPane> createState() => _CategoryPaneState();
}

class _CategoryPaneState extends ConsumerState<_CategoryPane> {
  final _scroll = ScrollController();
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(
      musicSearchControllerProvider.select((s) => s.query),
    );
    if (widget.kind == PlatformSearchKind.songs) {
      final songs = ref.watch(musicSearchControllerProvider);
      return Stack(
        children: [
          if (!songs.isLoading || songs.hasResults)
            Positioned.fill(
              child: AppleSearchResults(state: songs, controller: _scroll),
            ),
          if (songs.isLoading)
            Align(
              alignment: songs.hasResults
                  ? Alignment.topRight
                  : Alignment.center,
              child: const Padding(
                padding: EdgeInsets.all(18),
                child: BetaActivityIndicator(
                  key: ValueKey('search-query-progress'),
                ),
              ),
            ),
        ],
      );
    }
    final categoryState = ref.watch(categorySearchProvider);
    final active = categoryState.selected == widget.kind;
    final slice =
        categoryState.pages[widget.kind] ?? const CategorySearchSlice();
    final list =
        widget.kind == PlatformSearchKind.artists ||
        widget.kind == PlatformSearchKind.lyrics ||
        widget.kind == PlatformSearchKind.users;
    Widget tail() => Padding(
      padding: BetaContentInsets.musicPaddingOf(
        context,
        EdgeInsets.fromLTRB(22, 20, 22, 190),
      ),
      child: slice.loading
          ? const ArtworkPendingContent(
              child: Center(child: BetaActivityIndicator()),
            )
          : slice.error != null
          ? Center(
              child: TextButton(
                onPressed: ref.read(categorySearchProvider.notifier).loadMore,
                child: Text(slice.error!),
              ),
            )
          : slice.items.isEmpty
          ? Text('没有找到相关${widget.kind.label}，试试其他关键词。')
          : const SizedBox.shrink(),
    );
    return AutomaticSongPaging(
      songListId: 'search:${widget.kind.name}:${query.trim().toLowerCase()}',
      enabled: active && slice.more && !slice.loading && slice.error == null,
      onLoadMore: ref.read(categorySearchProvider.notifier).loadMore,
      child: CustomScrollView(
        controller: _scroll,
        key: PageStorageKey('category-$query-${widget.kind.name}'),
        physics: const ArtworkFrontierPhysics(parent: BouncingScrollPhysics()),
        slivers: [
          if (slice.total != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 14, 22, 6),
                child: Text(
                  '共 ${slice.total} ${widget.kind == PlatformSearchKind.artists || widget.kind == PlatformSearchKind.users
                      ? '位'
                      : widget.kind == PlatformSearchKind.lyrics
                      ? '首'
                      : '张'}',
                  textAlign: TextAlign.right,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
          if (list)
            SliverList.builder(
              itemCount: slice.items.length,
              itemBuilder: (_, index) {
                final hit = slice.items[index];
                return hit.user != null
                    ? NeteaseSearchUserRow(user: hit.user!)
                    : _ResultRow(hit: hit);
              },
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
              sliver: SliverLayoutBuilder(
                builder: (context, constraints) => SliverGrid.builder(
                  itemCount: slice.items.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: constraints.crossAxisExtent >= 650
                        ? (constraints.crossAxisExtent / 210).floor()
                        : 2,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 16,
                    mainAxisExtent:
                        (constraints.crossAxisExtent -
                                14 *
                                    ((constraints.crossAxisExtent >= 650
                                            ? (constraints.crossAxisExtent /
                                                      210)
                                                  .floor()
                                            : 2) -
                                        1)) /
                            (constraints.crossAxisExtent >= 650
                                ? (constraints.crossAxisExtent / 210).floor()
                                : 2) +
                        76 * MediaQuery.textScalerOf(context).scale(1),
                  ),
                  itemBuilder: (_, index) =>
                      _ResultTile(hit: slice.items[index]),
                ),
              ),
            ),
          SliverToBoxAdapter(child: tail()),
        ],
      ),
    );
  }
}

void _open(BuildContext context, PlatformSearchHit hit) => context.push(
  '/music/catalog/${hit.kind.name}/${Uri.encodeComponent(hit.id)}',
  extra: hit,
);

class _ResultTile extends StatelessWidget {
  const _ResultTile({required this.hit});
  final PlatformSearchHit hit;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => _open(context, hit),
    borderRadius: BorderRadius.circular(12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: ArtworkImage(uri: hit.cover, fit: BoxFit.cover),
          ),
        ),
        const SizedBox(height: 9),
        Text(
          hit.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: MusicTypography.subheadlineSize,
            fontWeight: MusicTypography.bodyWeight,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          hit.kind == PlatformSearchKind.playlists
              ? (hit.count == null ? '歌单' : '${hit.count} 首歌曲')
              : hit.subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ),
  );
}

class _ResultRow extends ConsumerWidget {
  const _ResultRow({required this.hit});
  final PlatformSearchHit hit;
  void _play(BuildContext context, WidgetRef ref) {
    SongListTools.remember(context, hit.track!);
    playBetaSelection(context, ref, hit.track!);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artist = hit.kind == PlatformSearchKind.artists;
    final portrait = artist && hit.cover.isEmpty
        ? ref.watch(artistPortraitProvider(hit.id)).value ?? ''
        : hit.cover;
    final row = InkWell(
      onTap: () => artist ? _open(context, hit) : _play(context, ref),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 10, 14, 10),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(artist ? 30 : 9),
              child: ArtworkImage(uri: portrait, width: 56, height: 56),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hit.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: MusicTypography.calloutSize,
                      fontWeight: MusicTypography.bodyWeight,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    artist
                        ? '歌手'
                        : (hit.lyric.isEmpty ? hit.subtitle : hit.lyric),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            if (hit.track != null)
              FavoriteToggleButton(track: hit.track!, compact: true),
            if (hit.track != null) SongActionsButton(track: hit.track!),
          ],
        ),
      ),
    );
    return hit.track == null
        ? row
        : SongListEntry(
            track: hit.track!,
            tracks: ref
                .watch(categorySearchProvider)
                .current
                .items
                .map((item) => item.track)
                .whereType<Track>()
                .toList(),
            child: row,
          );
  }
}
