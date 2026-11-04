import 'package:flutter/material.dart';
import '../../music_platform/platform_browse_cache.dart';
import '../../music_platform/presentation/retained_platform_snapshot.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/models/track.dart';
import '../../history/listening_history_providers.dart';
import '../../library/library_providers.dart';
import '../../music_platform/music_platform_providers.dart';
import '../../music_platform/platform_catalog_providers.dart';
import '../../music_platform/presentation/platform_discovery_page.dart';
import '../../music_platform/presentation/platform_design.dart';
import '../../search/search_providers.dart';
import '../../themes/music_theme_tokens.dart';
import 'editorial_widgets.dart';
import '../../music_platform/presentation/platform_recommendations_page.dart';
import '../../music_platform/data/platform_recommendations.dart';
import '../../music_platform/data/platform_explore.dart';
import '../../music_platform/platform_explore_providers.dart';
import 'music_home_catalogues.dart';
import '../../music_platform/platform_backend_providers.dart';
import '../../music_platform/netease/netease_features_page.dart';

/// Home and discovery share presentation primitives, never the same content
/// composition. All recommendation data still comes from the concept adapter.
class MusicLandingPage extends ConsumerWidget {
  const MusicLandingPage({this.discovery = false, super.key});
  final bool discovery;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(usesNeteaseProvider)) return const NeteaseDiscoveryPage();
    if (discovery) return const PlatformRecommendationHome();
    final daily = ref.watch(platformDailyProvider);
    final newSongs = ref.watch(platformNewSongsProvider);
    final discoverySongs = ref.watch(platformDiscoveryProvider);
    final signedIn = ref.watch(platformAccountProvider).value != null;
    final recent = ref.watch(recentPlaybackProvider);
    final favorites = ref.watch(favoriteTracksProvider);
    final featured = ref.watch(platformFeaturedProvider);
    return PlatformStyle(
      child: EditorialScroll(
        onRefresh: () => refreshBrowse(ref, [
          () => ref.refresh(platformDailyProvider.future),
          () => ref.refresh(platformNewSongsProvider.future),
          () => ref.refresh(platformDiscoveryProvider.future),
          () => ref.refresh(platformFeaturedProvider.future),
          if (ref.exists(platformExploreProvider(PlatformExploreKind.rank)))
            () => ref.refresh(
              platformExploreProvider(PlatformExploreKind.rank).future,
            ),
        ]),
        children: [
          const EditorialHeader('发现'),
          if (!discovery) ...[
            EditorialSection(
              '为你精选',
              onTap: () => context.push('/music?view=daily'),
            ),
            RetainedPlatformSnapshot(
              value: daily,
              artwork: (tracks) => tracks.map((track) => track.coverAsset),
              loading: () => const PlatformFeedbackState(loading: true),
              error: (_, _) => EditorialEmpty(
                '推荐暂时未能加载',
                onRetry: () => ref.invalidate(platformDailyProvider),
              ),
              data: (tracks) => tracks.isEmpty
                  ? const EditorialEmpty('今天的推荐还在路上')
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final width = (constraints.maxWidth * .7).clamp(
                          240.0,
                          330.0,
                        );
                        return EditorialShelf(
                          height: width * 1.13 + 8,
                          children: [
                            EditorialCover(
                              cover: tracks.first.coverAsset,
                              track: tracks.first,
                              title: '每日推荐',
                              subtitle: signedIn ? '跟随你的音乐口味' : '来自酷狗的每日推荐',
                              width: width,
                              feature: true,
                              onTap: () => context.push('/music?view=daily'),
                            ),
                            EditorialCover(
                              cover:
                                  favorites.value?.firstOrNull?.coverAsset ??
                                  tracks.last.coverAsset,
                              title: '我的喜欢',
                              subtitle:
                                  '${ref.watch(favoriteCollectionCountProvider)} 首珍藏的旋律',
                              width: width,
                              feature: true,
                              onTap: () =>
                                  context.push('/music?view=favorites'),
                            ),
                          ],
                        );
                      },
                    ),
            ),
            EditorialSection(
              '最近播放',
              onTap: () => context.push('/music/library?view=recent'),
            ),
            recent.when(
              loading: () => const PlatformFeedbackState(loading: true),
              error: (_, _) => const EditorialEmpty('最近播放暂时无法读取'),
              data: (items) => items.isEmpty
                  ? const EditorialEmpty('播放第一首歌后，在这里继续聆听。')
                  : EditorialShelf(
                      children: [
                        for (final item in items.take(12))
                          EditorialCover(
                            cover: item.track.coverAsset,
                            track: item.track,
                            title: item.track.title,
                            subtitle: item.track.artist,
                            onTap: () => playEditorialTrack(
                              context,
                              ref,
                              item.track,
                              items.map((e) => e.track).toList(),
                            ),
                          ),
                      ],
                    ),
            ),
          ] else ...[
            const EditorialSection('新鲜上架'),
            RetainedPlatformSnapshot(
              value: newSongs,
              artwork: (tracks) => tracks.map((track) => track.coverAsset),
              loading: () => const PlatformFeedbackState(loading: true),
              error: (_, _) => EditorialEmpty(
                '新歌暂时无法加载',
                onRetry: () => ref.invalidate(platformNewSongsProvider),
              ),
              data: (tracks) => tracks.isEmpty
                  ? const EditorialEmpty('暂无新歌')
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final width = (constraints.maxWidth - 62).clamp(
                          250.0,
                          480.0,
                        );
                        return EditorialShelf(
                          height: width * .78 + 72,
                          children: [
                            for (final track in tracks.take(6))
                              SizedBox(
                                width: width,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      track.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: context
                                            .musicThemeTokens
                                            .textPrimary,
                                        fontSize: 22,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      track.artist,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: context
                                            .musicThemeTokens
                                            .textSecondary,
                                        fontSize: 16,
                                        height: 1.7,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    EditorialCover(
                                      cover: track.coverAsset,
                                      track: track,
                                      title: track.title,
                                      subtitle: '新歌推荐',
                                      width: width,
                                      feature: true,
                                      height: width * .78,
                                      onTap: () => playEditorialTrack(
                                        context,
                                        ref,
                                        track,
                                        tracks,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        );
                      },
                    ),
            ),
            const EditorialSection('此刻值得听'),
            _SongGroups(
              value: discoverySongs,
              retry: () => ref.invalidate(platformDiscoveryProvider),
            ),
          ],
          if (!discovery) ...[
            const PlatformRecommendedSection(
              title: '猜你喜欢',
              kind: PlatformRecommendationKind.discover,
            ),
            EditorialSection(
              '新歌首发',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const PlatformRecommendationDetail(
                    title: '新歌首发',
                    newSongs: true,
                  ),
                ),
              ),
            ),
            _SongGroups(
              value: newSongs,
              retry: () => ref.invalidate(platformNewSongsProvider),
            ),
            const MusicHomeCatalogueShelf(PlatformExploreKind.rank),
          ],
          EditorialSection(
            discovery ? '精选歌单' : '发现你的下一张歌单',
            onTap: () =>
                openMusicHomeCatalogue(context, PlatformExploreKind.playlist),
          ),
          RetainedPlatformSnapshot(
            value: featured,
            artwork: (rows) => rows.map(
              (row) =>
                  '${row['sizable_cover'] ?? row['imgurl'] ?? row['pic'] ?? ''}'
                      .replaceAll('{size}', '400'),
            ),
            loading: () => const PlatformFeedbackState(loading: true),
            error: (_, _) => EditorialEmpty(
              '歌单暂时无法加载',
              onRetry: () => ref.invalidate(platformFeaturedProvider),
            ),
            data: (rows) {
              final lists = rows
                  .where(
                    (e) => '${e['global_collection_id'] ?? e['gid'] ?? ''}'
                        .isNotEmpty,
                  )
                  .toList();
              if (lists.isEmpty) return const EditorialEmpty('暂时没有精选歌单');
              return EditorialShelf(
                height: 246,
                children: [
                  for (final row in lists)
                    EditorialCover(
                      cover:
                          '${row['sizable_cover'] ?? row['imgurl'] ?? row['pic'] ?? ''}'
                              .replaceAll('{size}', '400'),
                      title: '${row['name'] ?? row['specialname'] ?? '精选歌单'}',
                      width: 174,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => PlatformPublicPlaylistPage(
                            id: '${row['global_collection_id'] ?? row['gid']}',
                            cover:
                                '${row['sizable_cover'] ?? row['imgurl'] ?? row['pic'] ?? ''}'
                                    .replaceAll('{size}', '400'),
                            name:
                                '${row['name'] ?? row['specialname'] ?? '精选歌单'}',
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          if (!discovery) ...[
            const PlatformFmSection(),
            for (final kind in musicHomeCatalogueOrder.skip(1))
              MusicHomeCatalogueShelf(kind),
            EditorialSection(
              '听见你的这一年',
              onTap: () => context.push('/music/replay'),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => context.push('/music/replay'),
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.history_rounded,
                        size: 34,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 18),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '我的听歌回顾',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            SizedBox(height: 6),
                            Text('每一段旋律，都留下自己的足迹'),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded),
                    ],
                  ),
                ),
              ),
            ),
          ] else ...[
            const EditorialSection('热门歌曲'),
            RetainedPlatformSnapshot(
              value: ref.watch(hotMusicControllerProvider),
              artwork: (snapshot) =>
                  snapshot.tracks.map((track) => track.coverAsset),
              loading: () => const PlatformFeedbackState(loading: true),
              error: (_, _) => EditorialEmpty(
                '榜单暂时无法加载',
                onRetry: () => ref.invalidate(hotMusicControllerProvider),
              ),
              data: (snapshot) => Column(
                children: [
                  for (final (index, track) in snapshot.tracks.take(10).indexed)
                    EditorialTrackRow(
                      track: track,
                      contextTracks: snapshot.tracks,
                      rank: index + 1,
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SongGroups extends StatelessWidget {
  const _SongGroups({required this.value, required this.retry});
  final AsyncValue<List<Track>> value;
  final VoidCallback retry;
  @override
  Widget build(BuildContext context) => RetainedPlatformSnapshot(
    value: value,
    artwork: (tracks) => tracks.map((track) => track.coverAsset),
    loading: () => const PlatformFeedbackState(loading: true),
    error: (_, _) => EditorialEmpty('歌曲暂时无法加载', onRetry: retry),
    data: (tracks) => tracks.isEmpty
        ? const EditorialEmpty('暂时没有歌曲')
        : LayoutBuilder(
            builder: (context, constraints) {
              // Fixed groups keep horizontal browsing independent of page rebuilds.
              // Reserve extra height for larger system fonts instead of clipping.
              final extra = (MediaQuery.textScalerOf(context).scale(34) - 34)
                  .clamp(0.0, 80.0);
              return SizedBox(
                height: 288 + extra * 4,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: (tracks.length / 4).ceil().clamp(1, 5),
                  itemBuilder: (context, page) => SizedBox(
                    width: (constraints.maxWidth * .94).clamp(290.0, 560.0),
                    child: Column(
                      children: [
                        for (final track in tracks.skip(page * 4).take(4))
                          EditorialTrackRow(
                            track: track,
                            contextTracks: tracks,
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
  );
}
