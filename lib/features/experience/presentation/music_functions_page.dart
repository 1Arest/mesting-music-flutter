import '../../../shared/widgets/beta_page_motion.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../music_platform/platform_backend_providers.dart';
import '../../music_platform/netease/netease_features_page.dart';
import '../../music_platform/netease/netease_features_repository.dart';
import '../../music_platform/netease/full/netease_full_page.dart';
import '../../downloads/audio_downloads_page.dart';
import '../../../shared/widgets/beta_bottom_search.dart';

import '../../music_platform/data/platform_explore.dart';
import '../../music_platform/data/platform_recommendations.dart';
import '../../music_platform/presentation/platform_recommendations_page.dart';
import '../../music_platform/presentation/platform_design.dart';
import '../../music_platform/presentation/music_effects_page.dart';
import '../../themes/music_theme_tokens.dart';
import '../../themes/music_application_theme.dart';
import '../../themes/beta_appearance.dart';
import 'editorial_widgets.dart';
import 'music_home_catalogues.dart';
import '../../themes/music_typography.dart';

/// Fixed launchpad: only destinations with a working local/platform owner are
/// shown. Tiles inherit the quiet Apple library surface; expensive live glass
/// belongs to the persistent floating navigation, not every grid cell.
class MusicFunctionsPage extends ConsumerWidget {
  const MusicFunctionsPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final netease = ref.watch(usesNeteaseProvider);
    void page(Widget child) => Navigator.of(
      context,
    ).push(MestingPageRoute<void>(builder: (_) => child));
    final entries = <_FunctionEntry>[
      _FunctionEntry(
        '私人 FM',
        CupertinoIcons.antenna_radiowaves_left_right,
        () => page(
          const PlatformRecommendationDetail(
            title: '私人 FM',
            kind: PlatformRecommendationKind.fm,
          ),
        ),
      ),
      _FunctionEntry(
        '每日推荐',
        CupertinoIcons.calendar,
        () => context.push('/music?view=daily'),
      ),
      _FunctionEntry('搜索', CupertinoIcons.search, () {
        final search = BetaBottomSearchScope.maybeOf(context);
        if (search != null) {
          search.openMusicSearch();
        } else {
          context.push('/music/search');
        }
      }),
      _FunctionEntry(
        '排行榜',
        CupertinoIcons.chart_bar,
        () => openMusicHomeCatalogue(context, PlatformExploreKind.rank),
        tone: BetaFeatureTone.insights,
      ),
      _FunctionEntry(
        '精选歌单',
        CupertinoIcons.music_note_list,
        () => openMusicHomeCatalogue(context, PlatformExploreKind.playlist),
      ),
      if (!netease)
        _FunctionEntry(
          '听歌识曲',
          CupertinoIcons.mic,
          () => context.push('/music/recognize'),
        ),
      if (!netease)
        _FunctionEntry(
          '听书',
          CupertinoIcons.book,
          () => context.push('/music/audiobooks'),
        ),
      if (!netease)
        _FunctionEntry(
          '场景音乐',
          CupertinoIcons.sun_haze,
          () => openMusicHomeCatalogue(context, PlatformExploreKind.scene),
        ),
      if (!netease)
        _FunctionEntry(
          '一起听',
          CupertinoIcons.person_2,
          () => context.push('/music/together'),
          tone: BetaFeatureTone.together,
        ),
      _FunctionEntry(
        '听歌回顾',
        CupertinoIcons.clock,
        () => context.push('/music/replay'),
        tone: BetaFeatureTone.insights,
      ),
      _FunctionEntry(
        '新碟上架',
        CupertinoIcons.music_note_2,
        () => openMusicHomeCatalogue(context, PlatformExploreKind.album),
      ),
      _FunctionEntry(
        '音效',
        CupertinoIcons.slider_horizontal_3,
        () => page(const MusicEffectsPage()),
        tone: BetaFeatureTone.together,
      ),
      if (netease) ...[
        for (final entry in <(NeteaseFeed, IconData)>[
          (NeteaseFeed.categories, CupertinoIcons.square_grid_2x2),
          (NeteaseFeed.premium, CupertinoIcons.sparkles),
          (NeteaseFeed.artists, CupertinoIcons.person),
          (NeteaseFeed.mvs, CupertinoIcons.play_rectangle),
          (NeteaseFeed.cloud, CupertinoIcons.cloud),
          (NeteaseFeed.intelligence, CupertinoIcons.heart_circle),
          (NeteaseFeed.week, CupertinoIcons.chart_bar),
          (NeteaseFeed.podcasts, CupertinoIcons.mic),
          (NeteaseFeed.historyDates, CupertinoIcons.calendar),
          (NeteaseFeed.artistNewSongs, CupertinoIcons.music_note),
          (NeteaseFeed.recommendedMvs, CupertinoIcons.play_rectangle),
          (NeteaseFeed.privateContent, CupertinoIcons.star),
          (NeteaseFeed.newestAlbums, CupertinoIcons.music_albums),
          (NeteaseFeed.topAlbums, CupertinoIcons.chart_bar),
          (NeteaseFeed.recommendedSongs, CupertinoIcons.music_note_2),
        ])
          _FunctionEntry(
            NeteaseFeaturesRepository.titles[entry.$1]!,
            entry.$2,
            () => openNeteaseFeed(context, entry.$1),
            tone: switch (entry.$1) {
              NeteaseFeed.week ||
              NeteaseFeed.topAlbums ||
              NeteaseFeed.historyDates => BetaFeatureTone.insights,
              NeteaseFeed.intelligence => BetaFeatureTone.music,
              _ => BetaFeatureTone.action,
            },
          ),
      ],
    ];
    final common = <_FunctionEntry>[
      _FunctionEntry(
        '下载管理',
        CupertinoIcons.arrow_down_circle,
        () => openAudioDownloads(context),
        tone: BetaFeatureTone.downloads,
      ),
      _FunctionEntry(
        '发现',
        CupertinoIcons.compass,
        () => context.go('/music/recommend'),
      ),
      _FunctionEntry(
        '收藏',
        CupertinoIcons.heart,
        () => context.push('/music/library?view=favorites'),
        tone: BetaFeatureTone.music,
      ),
      _FunctionEntry(
        '本地音乐',
        CupertinoIcons.music_albums,
        () => context.push('/music/local'),
      ),
    ];
    // The launchpad is an application destination. A retained route must not
    // inherit a player/menu-local dark palette after the app switches to light.
    return Theme(
      data: MusicApplicationTheme.of(context),
      child: PlatformStyle(
        child: EditorialScroll(
          children: [
            const EditorialHeader('功能'),
            _FunctionGrid(entries),
            const EditorialSection('常用'),
            _FunctionGrid(common),
            if (netease) const NeteaseFullNavigation(tab: '功能'),
          ],
        ),
      ),
    );
  }
}

class _FunctionEntry {
  const _FunctionEntry(
    this.title,
    this.icon,
    this.open, {
    this.tone = BetaFeatureTone.action,
  });
  final String title;
  final IconData icon;
  final VoidCallback open;
  final BetaFeatureTone tone;
}

class _FunctionGrid extends StatelessWidget {
  const _FunctionGrid(this.entries);
  final List<_FunctionEntry> entries;
  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        itemCount: entries.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          mainAxisExtent: 116 + (scale - 1).clamp(0, 2) * 48,
        ),
        itemBuilder: (context, i) {
          final item = entries[i];
          return CupertinoButton(
            key: ValueKey('function-${item.title}'),
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(22),
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 14),
            onPressed: item.open,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  item.icon,
                  size: 32,
                  color: BetaAppearance.feature(context, item.tone),
                ),
                const SizedBox(height: 13),
                Text(
                  item.title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: TextStyle(
                    fontSize: MusicTypography.subheadlineSize,
                    fontWeight: MusicTypography.bodyWeight,
                    color: context.musicThemeTokens.textPrimary,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
