import '../../../shared/widgets/artwork_scroll_frontier.dart';
import 'package:flutter/material.dart';
import '../../../shared/widgets/beta_content_insets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/layout/adaptive_layout.dart';
import '../../../shared/widgets/artwork_image.dart';
import '../../../shared/widgets/glass_card.dart';
import '../data/curated_playlists.dart';
import '../domain/curated_playlist.dart';
import '../../themes/music_theme_preset.dart';
import '../../themes/theme_controller.dart';
import '../../themes/music_theme_tokens.dart';
import '../../themes/music_typography.dart';

const double discoverPageBottomClearance = 168;

class DiscoverPage extends StatelessWidget {
  const DiscoverPage({super.key});

  @override
  Widget build(BuildContext context) {
    final pageWidth = MediaQuery.sizeOf(context).width;
    final availableWidth = pageWidth - 36;
    final columns = availableWidth >= 760 ? 3 : 2;
    final bottomClearance = mestingUsesNavigationRailForWidth(pageWidth)
        ? 112.0
        : discoverPageBottomClearance;
    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        physics: const ArtworkFrontierPhysics(parent: BouncingScrollPhysics()),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
            sliver: SliverToBoxAdapter(
              child: Row(
                children: [
                  IconButton(
                    tooltip: '返回上一页',
                    onPressed: () {
                      if (context.canPop()) {
                        context.pop();
                      } else {
                        context.go('/music');
                      }
                    },
                    icon: const Icon(Icons.arrow_back_ios_new_rounded),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'DISCOVER ONLINE',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontSize: MusicTypography.smallCaptionSize,
                            fontWeight: MusicTypography.bodyWeight,
                            letterSpacing: 1.8,
                          ),
                        ),
                        Text(
                          '发现歌单',
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                      ],
                    ),
                  ),
                  const _SourceBadge(),
                ],
              ),
            ),
          ),
          ..._playlistSectionSlivers(
            title: '精选歌单',
            subtitle: '延续原项目的首页策划推荐',
            playlists: curatedPlaylistsFor(CuratedPlaylistCategory.featured),
            columns: columns,
          ),
          ..._playlistSectionSlivers(
            title: '宝藏歌单',
            subtitle: '跨语种与独立音乐收藏',
            playlists: curatedPlaylistsFor(CuratedPlaylistCategory.treasure),
            columns: columns,
          ),
          ..._playlistSectionSlivers(
            title: '编辑推荐',
            subtitle: '适合不同场景的音乐电台',
            playlists: curatedPlaylistsFor(CuratedPlaylistCategory.editor),
            columns: columns,
          ),
          ..._playlistSectionSlivers(
            title: '全部发现',
            subtitle: '更多在线音乐主题',
            playlists: curatedPlaylistsFor(CuratedPlaylistCategory.explore),
            columns: columns,
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              key: ValueKey('discover-bottom-clearance'),
              height: BetaContentInsets.bottomOf(context, bottomClearance),
            ),
          ),
        ],
      ),
    );
  }
}

List<Widget> _playlistSectionSlivers({
  required String title,
  required String subtitle,
  required List<CuratedPlaylist> playlists,
  required int columns,
}) {
  return [
    SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      sliver: SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Builder(
              builder: (context) =>
                  Text(title, style: Theme.of(context).textTheme.titleLarge),
            ),
            const SizedBox(height: 3),
            Builder(
              builder: (context) => Text(
                subtitle,
                style: TextStyle(color: context.musicThemeTokens.textSecondary),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    ),
    SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.83,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) => _PlaylistCard(playlist: playlists[index]),
          childCount: playlists.length,
          addRepaintBoundaries: true,
        ),
      ),
    ),
    const SliverToBoxAdapter(child: SizedBox(height: 26)),
  ];
}

class _PlaylistCard extends ConsumerWidget {
  const _PlaylistCard({required this.playlist});

  final CuratedPlaylist playlist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.musicThemeTokens;
    final themePreset = ref.watch(effectiveMusicThemeProvider);
    final cover = themedPlaylistCover(
      preset: themePreset,
      index: curatedPlaylists.indexOf(playlist),
      fallback: playlist.coverAsset,
    );
    return GlassCard(
      padding: const EdgeInsets.all(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => context.push('/music/discover/${playlist.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: LayoutBuilder(
                  builder: (context, constraints) => ArtworkImage(
                    uri: cover,
                    width: constraints.maxWidth,
                    height: constraints.maxHeight,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 10, 6, 2),
              child: Text(
                playlist.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: MusicTypography.titleWeight),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                '在线电台',
                style: TextStyle(
                  color: tokens.textSecondary,
                  fontSize: MusicTypography.captionSize,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SourceBadge extends StatelessWidget {
  const _SourceBadge();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF5F75DE).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          'Audius',
          style: TextStyle(
            color: Color(0xFF4B63D0),
            fontSize: MusicTypography.smallCaptionSize,
            fontWeight: MusicTypography.bodyWeight,
          ),
        ),
      ),
    );
  }
}
