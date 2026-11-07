import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/models/track.dart';
import '../../../shared/widgets/beta_page_motion.dart';
import '../../music_platform/data/platform_explore.dart';
import '../../music_platform/data/platform_recommendations.dart';
import '../../music_platform/platform_backend_providers.dart';
import '../../music_platform/platform_catalog_providers.dart';
import '../../music_platform/platform_explore_providers.dart';
import '../../music_platform/platform_recommendation_providers.dart';
import '../../music_platform/netease/netease_features_page.dart';
import '../../music_platform/netease/netease_features_repository.dart';
import '../../music_platform/presentation/platform_collection_play.dart';
import '../../music_platform/presentation/platform_mode_play.dart';
import '../../music_platform/presentation/platform_design.dart';
import '../../music_platform/presentation/platform_recommendations_page.dart';
import '../../music_platform/presentation/platform_search_landing.dart'
    show PlatformExploreSongsPage;
import '../../music_platform/presentation/retained_platform_snapshot.dart';
import 'editorial_widgets.dart';
import 'music_home_catalogues.dart';
import '../../themes/music_typography.dart';

/// The first shelf groups actual listening modes, rather than substituting a
/// local favorites list for a platform recommendation. Each card subscribes to
/// its own bounded preview and retains that preview during refresh.
class MusicDiscoveryHighlights extends ConsumerWidget {
  const MusicDiscoveryHighlights({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final netease = ref.watch(usesNeteaseProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const EditorialSection('为你精选'),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = (constraints.maxWidth * .72).clamp(240.0, 330.0);
            final height =
                width * 1.08 +
                (MediaQuery.textScalerOf(context).scale(28) - 28).clamp(
                  0.0,
                  56.0,
                );
            return EditorialShelf(
              height: height + 8,
              children: [
                _ModeCard(width: width, height: height, mode: _Mode.daily),
                _RankCard(width: width, height: height),
                if (netease)
                  _ModeCard(width: width, height: height, mode: _Mode.heart),
                _ModeCard(width: width, height: height, mode: _Mode.fm),
              ],
            );
          },
        ),
      ],
    );
  }
}

enum _Mode { daily, fm, heart }

class _ModeCard extends ConsumerWidget {
  const _ModeCard({
    required this.width,
    required this.height,
    required this.mode,
  });
  final double width, height;
  final _Mode mode;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final netease = ref.watch(usesNeteaseProvider);
    final title = switch (mode) {
      _Mode.daily => '每日推荐',
      _Mode.heart => '心动模式',
      _Mode.fm => netease ? '私人 FM' : '猜你喜欢',
    };
    final play = PlatformModePlayButton(
      mode: switch (mode) {
        _Mode.daily => PlatformHighlightMode.daily,
        _Mode.heart => PlatformHighlightMode.heart,
        _Mode.fm => PlatformHighlightMode.fm,
      },
      title: title,
    );
    final provider = mode == _Mode.daily
        ? platformDailyProvider
        : platformFmProvider;
    final value = mode == _Mode.heart
        ? ref
              .watch(neteaseFeedPreviewProvider(NeteaseFeed.intelligence))
              .whenData(
                (batch) => batch.items
                    .map((item) => item.track)
                    .whereType<Track>()
                    .toList(),
              )
        : ref.watch(provider);
    void open() {
      if (mode == _Mode.heart) {
        openNeteaseFeed(context, NeteaseFeed.intelligence);
        return;
      }
      Navigator.of(context).push(
        MestingPageRoute<void>(
          builder: (_) => PlatformRecommendationDetail(
            title: title,
            kind: mode == _Mode.fm ? PlatformRecommendationKind.fm : null,
          ),
        ),
      );
    }

    return RetainedPlatformSnapshot(
      value: value,
      artwork: (tracks) => tracks.map((t) => t.coverAsset),
      loading: () => _ModeFallback(
        title: title,
        width: width,
        height: height,
        subtitle: '正在读取推荐',
        onTap: open,
        coverAction: play,
      ),
      error: (_, _) => _ModeFallback(
        title: title,
        width: width,
        height: height,
        subtitle: '打开后重试',
        onTap: open,
        coverAction: play,
      ),
      data: (tracks) => tracks.isEmpty
          ? _ModeFallback(
              title: title,
              width: width,
              height: height,
              subtitle: mode == _Mode.heart ? '从喜欢的音乐继续探索' : '打开查看推荐',
              onTap: open,
              coverAction: play,
            )
          : EditorialCover(
              cover: tracks.first.coverAsset,
              track: tracks.first,
              title: title,
              subtitle: mode == _Mode.heart
                  ? '熟悉的旋律，新的心动'
                  : mode == _Mode.fm
                  ? '跟随你的音乐口味'
                  : '每天发现新的好音乐',
              feature: true,
              width: width,
              height: height,
              onTap: open,
              coverAction: play,
            ),
    );
  }
}

class _ModeFallback extends StatelessWidget {
  const _ModeFallback({
    required this.title,
    required this.subtitle,
    required this.width,
    required this.height,
    required this.onTap,
    this.coverAction,
  });
  final String title, subtitle;
  final double width, height;
  final VoidCallback onTap;
  final Widget? coverAction;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: height,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF734B67), Color(0xFF243947)],
          ),
        ),
        child: Stack(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                20,
                coverAction == null ? 20 : 66,
                20,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.music_note_rounded,
                    size: 44,
                    color: Colors.white70,
                  ),
                  const Spacer(),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: MusicTypography.footnoteSize,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: MusicTypography.sectionTitleSize,
                      fontWeight: MusicTypography.titleWeight,
                    ),
                  ),
                ],
              ),
            ),
            if (coverAction != null)
              Positioned(right: 8, bottom: 8, child: coverAction!),
          ],
        ),
      ),
    ),
  );
}

class _RankCard extends ConsumerWidget {
  const _RankCard({required this.width, required this.height});
  final double width, height;
  @override
  Widget build(BuildContext context, WidgetRef ref) => RetainedPlatformSnapshot(
    value: ref.watch(platformExploreProvider(PlatformExploreKind.rank)),
    artwork: (items) => items.map((i) => i.cover),
    loading: () => _fallback(context),
    error: (_, _) => _fallback(context),
    data: (items) {
      if (items.isEmpty) return _fallback(context);
      final item = items.first;
      return EditorialCover(
        key: const ValueKey('discovery-ranking-highlight'),
        cover: item.cover,
        title: '榜单推荐',
        subtitle: item.title,
        width: width,
        height: height,
        feature: true,
        coverAction: PlatformCollectionPlayButton(item: item),
        onTap: () => Navigator.of(context).push(
          MestingPageRoute<void>(
            builder: (_) => PlatformExploreSongsPage(item: item),
          ),
        ),
      );
    },
  );
  Widget _fallback(BuildContext context) => _ModeFallback(
    title: '榜单推荐',
    subtitle: '发现正在流行的音乐',
    width: width,
    height: height,
    onTap: () => openMusicHomeCatalogue(context, PlatformExploreKind.rank),
  );
}

/// Three-song columns provide the official feed's compact horizontal browsing
/// rhythm. This consumes existing platform recommendations and keeps their order.
class MusicDiscoverySongGroups extends ConsumerWidget {
  const MusicDiscoverySongGroups({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final netease = ref.watch(usesNeteaseProvider);
    final provider = netease ? platformFmProvider : platformDiscoveryProvider;
    final title = netease ? '为你推荐的歌曲' : '猜你喜欢的歌';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EditorialSection(
          title,
          onTap: () => Navigator.of(context).push(
            MestingPageRoute<void>(
              builder: (_) => PlatformRecommendationDetail(
                title: title,
                kind: netease
                    ? PlatformRecommendationKind.fm
                    : PlatformRecommendationKind.discover,
              ),
            ),
          ),
        ),
        RetainedPlatformSnapshot(
          value: ref.watch(provider),
          artwork: (tracks) => tracks.map((t) => t.coverAsset),
          loading: () => const PlatformFeedbackState(loading: true),
          error: (_, _) => EditorialEmpty(
            '推荐暂时无法加载',
            onRetry: () => ref.invalidate(provider),
          ),
          data: (tracks) => tracks.isEmpty
              ? const EditorialEmpty('平台暂未返回推荐')
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final width = (constraints.maxWidth - 40).clamp(
                      280.0,
                      440.0,
                    );
                    final extra =
                        (MediaQuery.textScalerOf(context).scale(34) - 34).clamp(
                          0.0,
                          80.0,
                        );
                    return EditorialShelf(
                      height: 234 + extra * 3,
                      children: [
                        for (
                          var index = 0;
                          index < tracks.length.clamp(0, 12);
                          index += 3
                        )
                          SizedBox(
                            width: width,
                            child: Column(
                              children: [
                                for (final track in tracks.skip(index).take(3))
                                  EditorialTrackRow(
                                    track: track,
                                    contextTracks: tracks,
                                  ),
                              ],
                            ),
                          ),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class KugouDiscoveryPlaylists extends ConsumerWidget {
  const KugouDiscoveryPlaylists({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Column(
    children: [
      EditorialSection(
        '推荐歌单',
        onTap: () =>
            openMusicHomeCatalogue(context, PlatformExploreKind.playlist),
      ),
      RetainedPlatformSnapshot(
        value: ref.watch(platformFeaturedProvider),
        artwork: (rows) => rows.map(
          (r) => '${r['sizable_cover'] ?? r['imgurl'] ?? r['pic'] ?? ''}'
              .replaceAll('{size}', '400'),
        ),
        loading: () => const PlatformFeedbackState(loading: true),
        error: (_, _) => EditorialEmpty(
          '歌单暂时无法加载',
          onRetry: () => ref.invalidate(platformFeaturedProvider),
        ),
        data: (rows) {
          final items = [
            for (final row in rows)
              if ('${row['global_collection_id'] ?? row['gid'] ?? ''}'
                  .isNotEmpty)
                PlatformExploreItem(
                  id: '${row['global_collection_id'] ?? row['gid']}',
                  title: '${row['name'] ?? row['specialname'] ?? '精选歌单'}',
                  cover:
                      '${row['sizable_cover'] ?? row['imgurl'] ?? row['pic'] ?? ''}'
                          .replaceAll('{size}', '400'),
                  kind: PlatformExploreKind.playlist,
                ),
          ];
          if (items.isEmpty) return const EditorialEmpty('平台暂未返回歌单');
          return EditorialShelf(
            height:
                250 +
                (MediaQuery.textScalerOf(context).scale(32) - 32).clamp(
                  0.0,
                  80.0,
                ),
            children: [
              for (final item in items.take(12))
                EditorialCover(
                  cover: item.cover,
                  title: item.title,
                  width: 174,
                  coverAction: PlatformCollectionPlayButton(item: item),
                  onTap: () => Navigator.of(context).push(
                    MestingPageRoute<void>(
                      builder: (_) => PlatformExploreSongsPage(item: item),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    ],
  );
}
