import '../../themes/beta_appearance.dart';
import '../../../shared/widgets/artwork_scroll_frontier.dart';
import '../../../shared/widgets/beta_content_insets.dart';
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/media/artwork_network_image.dart';

import '../../../core/audio/playback_providers.dart';
import '../../../core/database/app_database.dart';
import '../../../shared/layout/adaptive_layout.dart';
import '../../../shared/models/track.dart';
import '../../../shared/utils/duration_format.dart';
import '../../../shared/widgets/artwork_image.dart';
import '../../../shared/widgets/track_artwork.dart';
import '../../../shared/widgets/liquid_glass_sheet.dart';
import '../../../shared/widgets/mesting_loading_indicator.dart';
import '../../../shared/widgets/music_notice.dart';
import '../../../shared/widgets/playing_equalizer.dart';
import '../../discover/data/curated_playlists.dart';
import '../../discover/domain/curated_playlist.dart';
import '../../../core/platform/distribution_channel.dart';
import '../../music_platform/presentation/platform_discovery_page.dart';
import '../../music_platform/presentation/platform_library_page.dart';
import '../../experience/presentation/music_functions_page.dart';
import '../../experience/presentation/music_library_page.dart';
import '../../music_platform/music_platform_providers.dart';
import '../../player/presentation/music_hub_top_bar.dart';
import '../../player/presentation/music_page_transition.dart';
import '../../player/presentation/persistent_mini_player.dart'
    show MiniPlayerOverflowMarquee;
import '../../recommendation/domain/personalized_recommendation.dart';
import '../../recommendation/recommendation_providers.dart';
import '../../search/search_providers.dart';
import '../../themes/mesting_palette.dart';
import '../../themes/music_theme_preset.dart';
import '../../themes/theme_controller.dart';
import '../../themes/music_theme_tokens.dart';
import '../library_providers.dart';
import '../../themes/music_typography.dart';

const double favoriteArtworkDecodeWidth = 84;
const double favoriteArtworkSwipeDistanceThreshold = 28;
const double favoriteArtworkSwipeVelocityThreshold = 420;
const Duration favoriteArtworkSwitchDuration = Duration(milliseconds: 320);
const double _songAddButtonTapTargetSize = 48;
const double _dailySongAddButtonVisualSize = 44;
const double _favoriteSongAddButtonVisualSize = 36;

Color favoriteCollectionAccentFor(Brightness brightness) =>
    brightness == Brightness.dark
    ? MestingPalette.heartBright
    : MestingPalette.heart;

class MusicHomePage extends ConsumerStatefulWidget {
  const MusicHomePage({super.key});

  @override
  ConsumerState<MusicHomePage> createState() => _MusicHomePageState();
}

class _MusicHomePageState extends ConsumerState<MusicHomePage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entrance;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 720),
    )..forward();
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final betaView = GoRouterState.of(context).uri.queryParameters['view'];
    if (DistributionChannel.isBeta &&
        (betaView == 'favorites' || betaView == 'playlists')) {
      return MusicLibraryPage(view: betaView);
    }
    if (DistributionChannel.isBeta &&
        ref.watch(platformAccountProvider).value != null &&
        (betaView == 'favorites' || betaView == 'playlists')) {
      return PlatformLibraryPage(favorites: betaView == 'favorites');
    }
    if (DistributionChannel.isBeta &&
        betaView != 'favorites' &&
        betaView != 'playlists') {
      return betaView == 'daily'
          ? const PlatformDiscoveryPage(dailyOnly: true)
          : const MusicFunctionsPage();
    }
    final selectedTheme = ref.watch(effectiveMusicThemeProvider);
    final favorites =
        ref.watch(favoriteTracksProvider).value ?? const <Track>[];
    final hotMusic = ref.watch(hotMusicControllerProvider);
    final hotSnapshot = hotMusic.value;
    final popularTracks = hotSnapshot?.tracks ?? const <Track>[];
    final onlineRecommendationTracks =
        hotSnapshot?.recommendationTracks.isNotEmpty == true
        ? hotSnapshot!.recommendationTracks
        : <Track>[
            ...?hotSnapshot?.tracks,
            ...?hotSnapshot?.popularTracks,
            ...?hotSnapshot?.risingTracks,
          ];
    final view = GoRouterState.of(context).uri.queryParameters['view'];
    final topInset = MediaQuery.paddingOf(context).top;
    final bottomClearance = mestingMusicPageBottomClearanceForWidth(
      MediaQuery.sizeOf(context).width,
    );

    return Stack(
      children: [
        CustomScrollView(
          physics: const ArtworkFrontierPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                12,
                topInset + 12,
                12,
                BetaContentInsets.bottomOf(context, bottomClearance),
              ),
              sliver: SliverList.list(
                children: [
                  _Entrance(
                    animation: _entrance,
                    interval: const Interval(
                      0,
                      .55,
                      curve: Curves.easeOutCubic,
                    ),
                    child: MusicHubTopBar(
                      showBack: view == 'daily' || view == 'playlists',
                      onBack: view == 'daily'
                          ? () => context.canPop()
                                ? context.pop()
                                : context.go('/music/recommend')
                          : view == 'playlists'
                          ? () => context.canPop()
                                ? context.pop()
                                : context.go('/profile')
                          : null,
                      title: switch (view) {
                        'daily' => '每日推荐',
                        'favorites' => '我的喜欢',
                        'playlists' => '我的歌单',
                        _ => '发现音乐',
                      },
                      subtitle: switch (view) {
                        'daily' => '每天更新的专属音乐队列',
                        'favorites' => '收藏会跟随账号安全保存',
                        'playlists' => '整理属于自己的音乐空间',
                        _ => '探索歌单、新歌与在线音乐',
                      },
                    ),
                  ),
                  const SizedBox(height: 19),
                  if (view == 'daily')
                    _DailySection(
                      localTracks: const <Track>[],
                      onlineTracks: onlineRecommendationTracks,
                    )
                  else if (view == 'favorites')
                    _FavoriteSection(tracks: favorites)
                  else if (view == 'playlists')
                    const _MyPlaylistsSection()
                  else ...[
                    _PlaylistSection(
                      title: '精选歌单',
                      playlists: curatedPlaylistsFor(
                        CuratedPlaylistCategory.featured,
                      ),
                      preset: selectedTheme,
                      entrance: _entrance,
                    ),
                    const SizedBox(height: 26),
                    _PopularMusicSection(
                      tracks: popularTracks,
                      entrance: _entrance,
                    ),
                    const SizedBox(height: 26),
                    _PlaylistSection(
                      title: '宝藏歌单',
                      playlists: curatedPlaylistsFor(
                        CuratedPlaylistCategory.treasure,
                      ),
                      preset: selectedTheme,
                      entrance: _entrance,
                    ),
                    const SizedBox(height: 26),
                    _PlaylistSection(
                      title: '今日编辑推荐',
                      playlists: curatedPlaylistsFor(
                        CuratedPlaylistCategory.editor,
                      ),
                      preset: selectedTheme,
                      entrance: _entrance,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Entrance extends StatelessWidget {
  const _Entrance({
    required this.animation,
    required this.interval,
    required this.child,
  });

  final Animation<double> animation;
  final Interval interval;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(parent: animation, curve: interval);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, .055),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.onMore});

  final String title;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final tokens = context.musicThemeTokens;
    return Padding(
      padding: const EdgeInsets.only(left: 3, right: 2, bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: tokens.textPrimary,
                fontSize: MusicTypography.headingSize,
                height: 1.2,
                fontWeight: MusicTypography.titleWeight,
                letterSpacing: -.5,
              ),
            ),
          ),
          TextButton(
            onPressed: onMore,
            style: TextButton.styleFrom(
              foregroundColor: tokens.textSecondary,
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: const TextStyle(
                fontSize: MusicTypography.captionSize,
                fontWeight: MusicTypography.bodyWeight,
              ),
            ),
            child: const Text('更多 >'),
          ),
        ],
      ),
    );
  }
}

class _PlaylistSection extends StatelessWidget {
  const _PlaylistSection({
    required this.title,
    required this.playlists,
    required this.preset,
    required this.entrance,
  });

  final String title;
  final List<CuratedPlaylist> playlists;
  final MusicThemePreset preset;
  final Animation<double> entrance;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          title: title,
          onMore: () => context.push('/music/discover'),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final cardWidth = (constraints.maxWidth * .44)
                .clamp(142.0, 178.0)
                .toDouble();
            return SizedBox(
              height: cardWidth + 48,
              child: ListView.separated(
                key: ValueKey('playlist-rail-$title'),
                scrollDirection: Axis.horizontal,
                primary: false,
                clipBehavior: Clip.none,
                physics: const ArtworkFrontierPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                padding: const EdgeInsets.only(right: 18),
                itemCount: playlists.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final playlist = playlists[index];
                  return SizedBox(
                    key: ValueKey('playlist-rail-card-${playlist.id}'),
                    width: cardWidth,
                    child: _Entrance(
                      animation: entrance,
                      interval: Interval(
                        (.20 + index * .055).clamp(0, .66),
                        (.72 + index * .045).clamp(.73, 1),
                        curve: Curves.easeOutCubic,
                      ),
                      child: _PlaylistCard(
                        playlist: playlist,
                        cover: themedPlaylistCover(
                          preset: preset,
                          index: index,
                          fallback: playlist.coverAsset,
                        ),
                        cardWidth: cardWidth,
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ],
    );
  }
}

class _PlaylistCard extends StatelessWidget {
  const _PlaylistCard({
    required this.playlist,
    required this.cover,
    required this.cardWidth,
  });

  final CuratedPlaylist playlist;
  final String cover;
  final double cardWidth;

  @override
  Widget build(BuildContext context) {
    final tokens = context.musicThemeTokens;
    final coverDecodeWidth = cardWidth - 16;
    return _PressScale(
      onTap: () => context.go('/music/discover/${playlist.id}'),
      child: _GlassSurface(
        radius: 18,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                key: ValueKey('playlist-rail-cover-${playlist.id}'),
                aspectRatio: 1,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(13),
                  child: ArtworkImage(
                    uri: cover,
                    width: double.infinity,
                    height: double.infinity,
                    fit: BoxFit.cover,
                    decodeWidth: coverDecodeWidth,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 6, 0, 0),
                child: Text(
                  playlist.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontSize: MusicTypography.footnoteSize,
                    fontWeight: MusicTypography.bodyWeight,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '在线完整歌单',
                style: TextStyle(
                  color: tokens.textSecondary,
                  fontSize: MusicTypography.smallCaptionSize,
                  fontWeight: MusicTypography.bodyWeight,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PopularMusicSection extends ConsumerWidget {
  const _PopularMusicSection({required this.tracks, required this.entrance});

  final List<Track> tracks;
  final Animation<double> entrance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final handler = ref.watch(audioHandlerProvider);
    final current = ref.watch(currentMediaItemProvider).value?.id;
    final playing = ref.watch(playbackStateProvider).value?.playing ?? false;
    final columnCount = (tracks.length + 2) ~/ 3;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          title: '热门音乐',
          onMore: () => context.push(
            '/music/search',
            extra: const MusicPageTransitionIntent.forward(),
          ),
        ),
        if (tracks.isEmpty)
          const SizedBox(
            height: 72,
            child: Center(
              child: MestingLoadingIndicator(
                key: ValueKey('popular-music-loading-animation'),
                size: 48,
                semanticLabel: '正在加载热门音乐',
              ),
            ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final columnWidth = (constraints.maxWidth * .92)
                  .clamp(286.0, 520.0)
                  .toDouble();
              return SizedBox(
                height: 210,
                child: ListView.separated(
                  key: const ValueKey('popular-music-column-rail'),
                  scrollDirection: Axis.horizontal,
                  primary: false,
                  clipBehavior: Clip.none,
                  physics: const ArtworkFrontierPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  padding: const EdgeInsets.only(right: 18),
                  itemCount: columnCount,
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (context, columnIndex) {
                    final start = columnIndex * 3;
                    final end = (start + 3).clamp(0, tracks.length);
                    final columnTracks = tracks.sublist(start, end);
                    return SizedBox(
                      key: ValueKey('popular-music-column-$columnIndex'),
                      width: columnWidth,
                      child: Column(
                        children: [
                          for (
                            var rowIndex = 0;
                            rowIndex < columnTracks.length;
                            rowIndex++
                          ) ...[
                            if (rowIndex > 0) const SizedBox(height: 9),
                            _Entrance(
                              animation: entrance,
                              interval: Interval(
                                (.16 + (start + rowIndex) * .04).clamp(0, .66),
                                (.70 + (start + rowIndex) * .035).clamp(.71, 1),
                                curve: Curves.easeOutCubic,
                              ),
                              child: _SongRow(
                                track: columnTracks[rowIndex],
                                active: current == columnTracks[rowIndex].id,
                                playing: playing,
                                onTap: () => handler.playSingleTrack(
                                  columnTracks[rowIndex],
                                  playbackContext: tracks,
                                ),
                                onAdd: () => _appendTrack(
                                  context,
                                  ref,
                                  columnTracks[rowIndex],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
              );
            },
          ),
      ],
    );
  }

  Future<void> _appendTrack(
    BuildContext context,
    WidgetRef ref,
    Track track,
  ) async {
    try {
      final added = await ref
          .read(audioHandlerProvider)
          .appendToUpcomingQueue(track);
      if (!context.mounted) return;
      showMusicNotice(
        context,
        icon: added ? Icons.check_rounded : Icons.queue_music_rounded,
        title: added ? '已添加' : '已在播放列表',
        message: '',
      );
    } on Object {
      if (!context.mounted) return;
      showMusicNotice(
        context,
        icon: Icons.error_outline_rounded,
        title: '添加失败',
        message: '暂时无法加入《${track.title}》，请稍后重试',
      );
    }
  }
}

class _SongRow extends StatelessWidget {
  const _SongRow({
    required this.track,
    required this.active,
    required this.playing,
    required this.onTap,
    this.onAdd,
  });

  final Track track;
  final bool active;
  final bool playing;
  final VoidCallback onTap;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final tokens = context.musicThemeTokens;
    final favoriteAccent = favoriteCollectionAccentFor(
      Theme.of(context).brightness,
    );
    return _PressScale(
      onTap: onTap,
      scale: .965,
      child: _GlassSurface(
        radius: 18,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(18),
                ),
                child: TrackArtwork(track: track, width: 62, height: 64),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: active ? favoriteAccent : tokens.textPrimary,
                        fontSize: MusicTypography.subheadlineSize,
                        fontWeight: MusicTypography.bodyWeight,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      track.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: tokens.textSecondary,
                        fontSize: MusicTypography.smallCaptionSize,
                        fontWeight: MusicTypography.bodyWeight,
                      ),
                    ),
                  ],
                ),
              ),
              if (active && playing)
                PlayingEqualizer(animate: true, color: favoriteAccent, size: 22)
              else if (onAdd != null)
                Semantics(
                  button: true,
                  label: '将${track.title}添加至播放列表',
                  child: _PressScale(
                    onTap: onAdd!,
                    scale: .88,
                    child: SizedBox.square(
                      dimension: 34,
                      child: Icon(
                        Icons.add_rounded,
                        size: 22,
                        color: tokens.textMuted,
                      ),
                    ),
                  ),
                ),
              const SizedBox(width: 13),
            ],
          ),
        ),
      ),
    );
  }
}

class FavoriteTrackRow extends StatelessWidget {
  const FavoriteTrackRow({
    required this.track,
    required this.onPlay,
    required this.onAdd,
    this.index = 0,
    this.active = false,
    this.playing = false,
    super.key,
  });

  final Track track;
  final VoidCallback onPlay;
  final VoidCallback onAdd;
  final int index;
  final bool active;
  final bool playing;

  @override
  Widget build(BuildContext context) {
    final tokens = context.musicThemeTokens;
    final accent = favoriteCollectionAccentFor(Theme.of(context).brightness);
    return Semantics(
      container: true,
      explicitChildNodes: true,
      button: true,
      label: '播放${track.title}',
      child: Material(
        key: ValueKey('favorite-track-${track.id}'),
        color: Colors.transparent,
        child: InkWell(
          onTap: onPlay,
          excludeFromSemantics: true,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            height: 76,
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            color: active ? accent.withValues(alpha: .085) : Colors.transparent,
            child: Row(
              children: [
                SizedBox(
                  width: 28,
                  child: active
                      ? PlayingEqualizer(
                          animate: playing,
                          color: accent,
                          size: 20,
                        )
                      : Text(
                          '${index + 1}'.padLeft(2, '0'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: tokens.textMuted,
                            fontSize: MusicTypography.smallCaptionSize,
                            fontWeight: MusicTypography.bodyWeight,
                            letterSpacing: .5,
                          ),
                        ),
                ),
                const SizedBox(width: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: TrackArtwork(
                    track: track,
                    width: 52,
                    height: 52,
                    decodeWidth: favoriteArtworkDecodeWidth,
                    retryOnNetworkError: true,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      MiniPlayerOverflowMarquee(
                        text: track.title,
                        semanticLabel: '歌曲名称',
                        marqueeEnabled: active,
                        animate: active && playing,
                        keyPrefix: 'favorite-track-title-${track.id}',
                        style: TextStyle(
                          color: active ? accent : tokens.textPrimary,
                          fontSize: MusicTypography.subheadlineSize,
                          fontWeight: MusicTypography.bodyWeight,
                          letterSpacing: -.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      MiniPlayerOverflowMarquee(
                        text: track.artist,
                        semanticLabel: '歌手名称',
                        marqueeEnabled: active,
                        animate: active && playing,
                        keyPrefix: 'favorite-track-artist-${track.id}',
                        style: TextStyle(
                          color: tokens.textSecondary,
                          fontSize: MusicTypography.smallCaptionSize,
                          fontWeight: MusicTypography.bodyWeight,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  formatDuration(track.duration),
                  style: TextStyle(
                    color: tokens.textMuted,
                    fontSize: MusicTypography.smallCaptionSize,
                    fontWeight: MusicTypography.bodyWeight,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: 4),
                _QueueAddButton(
                  key: ValueKey('favorite-track-add-${track.id}'),
                  semanticLabel: '将${track.title}添加至播放列表',
                  onPressed: onAdd,
                  foregroundColor: tokens.textSecondary,
                  visualSize: _favoriteSongAddButtonVisualSize,
                  iconSize: 19,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QueueAddButton extends StatelessWidget {
  const _QueueAddButton({
    required this.semanticLabel,
    required this.onPressed,
    required this.foregroundColor,
    required this.visualSize,
    required this.iconSize,
    super.key,
  });

  final String semanticLabel;
  final VoidCallback onPressed;
  final Color foregroundColor;
  final double visualSize;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      label: semanticLabel,
      child: ExcludeSemantics(
        child: SizedBox.square(
          dimension: _songAddButtonTapTargetSize,
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onPressed,
              customBorder: const CircleBorder(),
              child: Align(
                alignment: Alignment.center,
                child: IgnorePointer(
                  child: IconButton(
                    onPressed: onPressed,
                    icon: Icon(Icons.add_rounded, size: iconSize),
                    color: foregroundColor,
                    padding: EdgeInsets.zero,
                    style: IconButton.styleFrom(
                      minimumSize: Size.square(visualSize),
                      maximumSize: Size.square(visualSize),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DailySection extends ConsumerStatefulWidget {
  const _DailySection({required this.localTracks, required this.onlineTracks});

  final List<Track> localTracks;
  final List<Track> onlineTracks;

  @override
  ConsumerState<_DailySection> createState() => _DailySectionState();
}

class _DailySectionState extends ConsumerState<_DailySection> {
  int _selectedDay = 0;

  Future<void> _appendTrack(Track track) async {
    try {
      final added = await ref
          .read(audioHandlerProvider)
          .appendToUpcomingQueue(track);
      if (!mounted) return;
      showMusicNotice(
        context,
        icon: added ? Icons.check_rounded : Icons.queue_music_rounded,
        title: added ? '已添加' : '已在播放列表',
        message: '',
      );
    } on Object {
      if (!mounted) return;
      showMusicNotice(
        context,
        icon: Icons.error_outline_rounded,
        title: '添加失败',
        message: '暂时无法加入《${track.title}》，请稍后重试',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final yesterday = today.subtract(const Duration(days: 1));
    final recommendationDate = _selectedDay == 0 ? today : yesterday;
    final legacyListeningSignals =
        ref.watch(listeningSignalsProvider).value ?? const <ListeningSignal>[];
    final todayPreferenceDate = recommendationPreferenceDate(today);
    final todayDailyListeningSignals =
        ref.watch(listeningSignalsForDayProvider(todayPreferenceDate)).value ??
        const <ListeningSignal>[];
    final todayPreferenceSignals = recommendationPreferenceSignalsForDate(
      today,
      dailySignals: todayDailyListeningSignals,
      legacySignals: legacyListeningSignals,
    );
    final yesterdayPreferenceDate = recommendationPreferenceDate(yesterday);
    final yesterdayDailyListeningSignals =
        ref
            .watch(listeningSignalsForDayProvider(yesterdayPreferenceDate))
            .value ??
        const <ListeningSignal>[];
    final yesterdayPreferenceSignals = recommendationPreferenceSignalsForDate(
      yesterday,
      dailySignals: yesterdayDailyListeningSignals,
      legacySignals: legacyListeningSignals,
    );
    final favoriteTracks =
        ref.watch(favoriteTracksProvider).value ?? const <Track>[];
    final recommendations = consecutiveDailyRecommendations(
      today: today,
      localTracks: widget.localTracks,
      onlineTracks: widget.onlineTracks,
      todayPreferenceSignals: todayPreferenceSignals,
      yesterdayPreferenceSignals: yesterdayPreferenceSignals,
      favoriteTracks: favoriteTracks,
    );
    final tracks = _selectedDay == 0
        ? recommendations.today
        : recommendations.yesterday;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 236,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF465CC7), Color(0xFF4A86D8), Color(0xFF2E9B82)],
            ),
            borderRadius: BorderRadius.circular(22),
            boxShadow: const [
              BoxShadow(
                color: Color(0x2B4F65D1),
                blurRadius: 28,
                offset: Offset(0, 14),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: AnimatedSwitcher(
                  key: const ValueKey('daily-hero-switcher'),
                  duration: const Duration(milliseconds: 420),
                  reverseDuration: const Duration(milliseconds: 420),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: _dailyDayTransition,
                  child: _DailyHeroContent(
                    key: ValueKey(('hero', _selectedDay)),
                    recommendationDate: recommendationDate,
                    title: _selectedDay == 0 ? '每日推荐' : '昨日推荐',
                    tracks: tracks,
                    onPlay: tracks.isEmpty
                        ? null
                        : () => ref
                              .read(audioHandlerProvider)
                              .replaceQueue(tracks),
                  ),
                ),
              ),
              Positioned(
                right: 16,
                top: 19,
                child: _DailyDaySelector(
                  selectedDay: _selectedDay,
                  onChanged: (next) {
                    if (next != _selectedDay) {
                      setState(() => _selectedDay = next);
                    }
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 26),
        AnimatedSwitcher(
          key: const ValueKey('daily-queue-switcher'),
          duration: const Duration(milliseconds: 420),
          reverseDuration: const Duration(milliseconds: 420),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: _dailyDayTransition,
          layoutBuilder: (currentChild, previousChildren) => Stack(
            alignment: Alignment.topCenter,
            children: [...previousChildren, ?currentChild],
          ),
          child: _DailyQueueContent(
            key: ValueKey(('queue', _selectedDay)),
            tracks: tracks,
            onPlayTrack: (track) => ref
                .read(audioHandlerProvider)
                .playSingleTrack(track, playbackContext: tracks),
            onAddTrack: _appendTrack,
          ),
        ),
      ],
    );
  }
}

Widget _dailyDayTransition(Widget child, Animation<double> animation) {
  final day = (child.key as ValueKey<(String, int)>).value.$2;
  final movement = CurvedAnimation(
    parent: animation,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );
  final opacity = CurvedAnimation(
    parent: animation,
    curve: const Interval(.12, 1, curve: Curves.easeOutCubic),
    reverseCurve: const Interval(0, .88, curve: Curves.easeInCubic),
  );
  return FadeTransition(
    opacity: opacity,
    child: SlideTransition(
      position: Tween<Offset>(
        begin: Offset(day == 0 ? -.045 : .045, 0),
        end: Offset.zero,
      ).animate(movement),
      child: child,
    ),
  );
}

class _DailyDaySelector extends StatelessWidget {
  const _DailyDaySelector({required this.selectedDay, required this.onChanged});

  final int selectedDay;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('daily-day-selector'),
      width: 132,
      height: 34,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .055),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: Colors.white.withValues(alpha: .1)),
      ),
      child: Stack(
        children: [
          AnimatedAlign(
            key: const ValueKey('daily-day-selector-indicator'),
            alignment: selectedDay == 0
                ? Alignment.centerLeft
                : Alignment.centerRight,
            duration: const Duration(milliseconds: 360),
            curve: Curves.easeOutCubic,
            child: Container(
              width: 65,
              height: 32,
              margin: const EdgeInsets.all(1),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: .1)),
              ),
            ),
          ),
          Row(
            children: [
              _DailyDayOption(
                label: '今日推荐',
                selected: selectedDay == 0,
                onTap: () => onChanged(0),
              ),
              _DailyDayOption(
                label: '昨日推荐',
                selected: selectedDay == 1,
                onTap: () => onChanged(1),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DailyDayOption extends StatelessWidget {
  const _DailyDayOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Center(
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              style: TextStyle(
                color: selected ? Colors.white : Colors.white70,
                fontSize: MusicTypography.smallCaptionSize,
                fontWeight: MusicTypography.bodyWeight,
              ),
              child: Text(label),
            ),
          ),
        ),
      ),
    );
  }
}

class _DailyHeroContent extends StatelessWidget {
  const _DailyHeroContent({
    required this.recommendationDate,
    required this.title,
    required this.tracks,
    required this.onPlay,
    super.key,
  });

  final DateTime recommendationDate;
  final String title;
  final List<Track> tracks;
  final VoidCallback? onPlay;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (tracks.isNotEmpty)
          Positioned(
            right: -21,
            bottom: -12,
            child: Transform.rotate(
              angle: .08,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: TrackArtwork(
                  track: tracks.first,
                  width: 126,
                  height: 150,
                ),
              ),
            ),
          ),
        if (tracks.length > 1)
          Positioned(
            right: 64,
            bottom: 32,
            child: Transform.rotate(
              angle: -.12,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: TrackArtwork(track: tracks[1], width: 85, height: 108),
              ),
            ),
          ),
        Positioned(
          left: 18,
          top: 18,
          child: Container(
            width: 62,
            height: 70,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .15),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: Colors.white.withValues(alpha: .38)),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${recommendationDate.day}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: MusicTypography.titleSize,
                    height: 1,
                    fontWeight: MusicTypography.titleWeight,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${recommendationDate.month}月',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: MusicTypography.smallCaptionSize,
                  ),
                ),
              ],
            ),
          ),
        ),
        const Positioned(
          left: 18,
          top: 96,
          child: Text(
            'DAILY MIX',
            style: TextStyle(
              color: Colors.white70,
              fontSize: MusicTypography.smallCaptionSize,
              fontWeight: MusicTypography.bodyWeight,
              letterSpacing: 1.6,
            ),
          ),
        ),
        Positioned(
          left: 18,
          top: 124,
          child: Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: MusicTypography.titleSize,
              fontWeight: MusicTypography.titleWeight,
            ),
          ),
        ),
        Positioned(
          left: 18,
          bottom: 18,
          child: FilledButton.icon(
            onPressed: onPlay,
            icon: const Icon(Icons.play_arrow_rounded, size: 18),
            label: const Text('播放全部'),
            style: FilledButton.styleFrom(
              backgroundColor: DistributionChannel.isBeta
                  ? BetaAppearance.playbackAction(Theme.of(context).brightness)
                  : const Color(0xFF465CC7),
              foregroundColor: Colors.white,
              minimumSize: const Size(116, 44),
              textStyle: const TextStyle(
                fontSize: MusicTypography.captionSize,
                fontWeight: MusicTypography.bodyWeight,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DailyQueueContent extends StatelessWidget {
  const _DailyQueueContent({
    required this.tracks,
    required this.onPlayTrack,
    required this.onAddTrack,
    super.key,
  });

  final List<Track> tracks;
  final ValueChanged<Track> onPlayTrack;
  final ValueChanged<Track> onAddTrack;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                '精选队列',
                style: TextStyle(
                  fontSize: MusicTypography.bodySize,
                  fontWeight: MusicTypography.titleWeight,
                ),
              ),
            ),
            Text(
              '${tracks.length} 首歌曲',
              style: const TextStyle(
                color: Color(0xFF77717B),
                fontSize: MusicTypography.smallCaptionSize,
              ),
            ),
          ],
        ),
        const SizedBox(height: 11),
        if (tracks.isEmpty)
          _GlassSurface(
            radius: 18,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 28),
              child: Center(
                child: Text('在线推荐暂时不可用，请检查网络后刷新', textAlign: TextAlign.center),
              ),
            ),
          ),
        for (var index = 0; index < tracks.length; index++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _DailyTrackRow(
              index: index,
              track: tracks[index],
              onPlay: () => onPlayTrack(tracks[index]),
              onAdd: () => onAddTrack(tracks[index]),
            ),
          ),
      ],
    );
  }
}

class _DailyTrackRow extends StatelessWidget {
  const _DailyTrackRow({
    required this.index,
    required this.track,
    required this.onPlay,
    required this.onAdd,
  });

  final int index;
  final Track track;
  final VoidCallback onPlay;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(18);
    final tokens = context.musicThemeTokens;
    return _GlassSurface(
      radius: 18,
      child: Material(
        key: ValueKey('daily-track-material-$index'),
        color: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: borderRadius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('daily-track-$index'),
          onTap: onPlay,
          borderRadius: borderRadius,
          child: SizedBox(
            height: 72,
            child: Row(
              children: [
                SizedBox(
                  width: 48,
                  child: Text(
                    '${index + 1}'.padLeft(2, '0'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF8A848D),
                      fontSize: MusicTypography.captionSize,
                    ),
                  ),
                ),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: TrackArtwork(track: track, width: 54, height: 54),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: MusicTypography.subheadlineSize,
                          fontWeight: MusicTypography.bodyWeight,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        track.isRemote
                            ? '${track.artist} · ${track.provider}'
                            : track.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF77717B),
                          fontSize: MusicTypography.smallCaptionSize,
                        ),
                      ),
                    ],
                  ),
                ),
                _QueueAddButton(
                  key: ValueKey('daily-track-add-$index'),
                  semanticLabel: '将${track.title}加入播放列表',
                  onPressed: onAdd,
                  foregroundColor: tokens.textSecondary,
                  visualSize: _dailySongAddButtonVisualSize,
                  iconSize: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MyPlaylistsSection extends ConsumerWidget {
  const _MyPlaylistsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlists = ref.watch(playlistsProvider);
    return playlists.when(
      loading: () => const _PlaylistLibraryLoading(),
      error: (error, stackTrace) => const _PlaylistLibraryError(),
      data: (items) => MyPlaylistsCollectionView(playlists: items),
    );
  }
}

class MyPlaylistsCollectionView extends StatelessWidget {
  const MyPlaylistsCollectionView({required this.playlists, super.key});

  final List<UserPlaylist> playlists;

  @override
  Widget build(BuildContext context) {
    final tokens = context.musicThemeTokens;
    return Column(
      key: const ValueKey('my-playlists-library'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PlaylistLibraryOverview(playlistCount: playlists.length),
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: Row(
            children: [
              Text(
                '全部歌单',
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: MusicTypography.bodySize,
                  fontWeight: MusicTypography.titleWeight,
                  letterSpacing: -.3,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                key: const ValueKey('my-playlists-count'),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: tokens.textPrimary.withValues(alpha: .07),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${playlists.length}',
                  style: TextStyle(
                    color: tokens.textSecondary,
                    fontSize: MusicTypography.smallCaptionSize,
                    fontWeight: MusicTypography.bodyWeight,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                '按最近编辑排序',
                style: TextStyle(
                  color: tokens.textMuted,
                  fontSize: MusicTypography.smallCaptionSize,
                  fontWeight: MusicTypography.bodyWeight,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (playlists.isEmpty)
          const _PlaylistLibraryEmpty()
        else
          for (final playlist in playlists)
            Padding(
              padding: const EdgeInsets.only(bottom: 11),
              child: _HomePlaylistTile(playlist: playlist),
            ),
      ],
    );
  }
}

class _PlaylistLibraryOverview extends StatelessWidget {
  const _PlaylistLibraryOverview({required this.playlistCount});

  final int playlistCount;

  @override
  Widget build(BuildContext context) {
    final tokens = context.musicThemeTokens;
    final accent = Theme.of(context).colorScheme.primary;
    return Container(
      key: const ValueKey('my-playlists-overview'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: accent.withValues(alpha: .22)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: .20),
            tokens.glassStrong,
            tokens.glassSubtle,
          ],
          stops: const [0, .58, 1],
        ),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: .10),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(21),
              color: accent.withValues(alpha: .15),
              border: Border.all(color: accent.withValues(alpha: .26)),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Transform.translate(
                  offset: const Offset(-7, -5),
                  child: Icon(
                    Icons.album_rounded,
                    size: 31,
                    color: accent.withValues(alpha: .42),
                  ),
                ),
                Transform.translate(
                  offset: const Offset(8, 7),
                  child: Icon(
                    Icons.queue_music_rounded,
                    size: 29,
                    color: accent,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '私人音乐资料库',
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontSize: MusicTypography.bodySize,
                    fontWeight: MusicTypography.titleWeight,
                    letterSpacing: -.35,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '收藏主题、心情和只属于你的声音',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tokens.textSecondary,
                    fontSize: MusicTypography.smallCaptionSize,
                    fontWeight: MusicTypography.bodyWeight,
                  ),
                ),
                const SizedBox(height: 11),
                Row(
                  children: [
                    Icon(
                      Icons.lock_outline_rounded,
                      size: 14,
                      color: tokens.textMuted,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '$playlistCount 个私人歌单',
                      style: TextStyle(
                        color: tokens.textSecondary,
                        fontSize: MusicTypography.smallCaptionSize,
                        fontWeight: MusicTypography.bodyWeight,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HomePlaylistTile extends ConsumerWidget {
  const _HomePlaylistTile({required this.playlist});

  final UserPlaylist playlist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracks =
        ref.watch(playlistTracksProvider(playlist.id)).value ?? const <Track>[];
    final cover =
        playlist.coverAsset ?? (tracks.isEmpty ? '' : tracks.first.coverAsset);
    final tokens = context.musicThemeTokens;
    final accent = Theme.of(context).colorScheme.primary;
    final borderRadius = BorderRadius.circular(23);
    final description = playlist.description.trim();
    return _GlassSurface(
      radius: 23,
      child: Material(
        key: ValueKey('playlist-tile-ink-${playlist.id}'),
        color: Colors.transparent,
        borderRadius: borderRadius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('my-playlist-${playlist.id}'),
          onTap: () => context.push('/music/playlists/${playlist.id}'),
          borderRadius: borderRadius,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                _PlaylistLibraryCover(uri: cover),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        playlist.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: tokens.textPrimary,
                          fontSize: MusicTypography.calloutSize,
                          fontWeight: MusicTypography.bodyWeight,
                          letterSpacing: -.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        description.isEmpty ? '还没有写歌单简介' : description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: tokens.textSecondary,
                          fontSize: MusicTypography.smallCaptionSize,
                          fontWeight: MusicTypography.bodyWeight,
                        ),
                      ),
                      const SizedBox(height: 9),
                      Row(
                        children: [
                          Icon(
                            Icons.music_note_rounded,
                            size: 14,
                            color: accent,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${tracks.length} 首歌曲',
                            style: TextStyle(
                              color: tokens.textSecondary,
                              fontSize: MusicTypography.smallCaptionSize,
                              fontWeight: MusicTypography.bodyWeight,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            width: 3,
                            height: 3,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: tokens.textMuted,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _playlistUpdatedLabel(playlist.updatedAt),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: tokens.textMuted,
                                fontSize: MusicTypography.smallCaptionSize,
                                fontWeight: MusicTypography.bodyWeight,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 9),
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: tokens.textPrimary.withValues(alpha: .055),
                  ),
                  child: Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 14,
                    color: tokens.textSecondary,
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

class _PlaylistLibraryCover extends StatelessWidget {
  const _PlaylistLibraryCover({required this.uri});

  final String uri;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Container(
      key: const ValueKey('my-playlist-cover'),
      width: 72,
      height: 72,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: .30),
            const Color(0xFF6650A4).withValues(alpha: .22),
          ],
        ),
        border: Border.all(color: accent.withValues(alpha: .16)),
      ),
      child: uri.trim().isEmpty
          ? Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  Icons.album_rounded,
                  color: Colors.white.withValues(alpha: .18),
                  size: 48,
                ),
                Icon(Icons.queue_music_rounded, color: accent, size: 27),
              ],
            )
          : ArtworkImage(uri: uri, width: 72, height: 72, fit: BoxFit.cover),
    );
  }
}

class _PlaylistLibraryEmpty extends StatelessWidget {
  const _PlaylistLibraryEmpty();

  @override
  Widget build(BuildContext context) {
    final tokens = context.musicThemeTokens;
    final accent = Theme.of(context).colorScheme.primary;
    return _GlassSurface(
      radius: 25,
      child: Padding(
        key: const ValueKey('my-playlists-empty'),
        padding: const EdgeInsets.fromLTRB(24, 34, 24, 32),
        child: Column(
          children: [
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accent.withValues(alpha: .10),
                border: Border.all(color: accent.withValues(alpha: .18)),
              ),
              child: Icon(
                Icons.library_music_outlined,
                color: accent,
                size: 31,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              '这里还没有歌单',
              style: TextStyle(
                color: tokens.textPrimary,
                fontSize: MusicTypography.bodySize,
                fontWeight: MusicTypography.titleWeight,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '请回到“我的”页，点击右上角 +\n从抽屉中创建你的第一个歌单',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: tokens.textSecondary,
                height: 1.55,
                fontSize: MusicTypography.smallCaptionSize,
                fontWeight: MusicTypography.bodyWeight,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaylistLibraryLoading extends StatelessWidget {
  const _PlaylistLibraryLoading();

  @override
  Widget build(BuildContext context) => const Center(
    child: MestingLoadingIndicator(
      key: ValueKey('my-playlists-loading'),
      semanticLabel: '正在加载我的歌单',
    ),
  );
}

class _PlaylistLibraryError extends StatelessWidget {
  const _PlaylistLibraryError();

  @override
  Widget build(BuildContext context) {
    final tokens = context.musicThemeTokens;
    return _GlassSurface(
      radius: 25,
      child: Padding(
        key: const ValueKey('my-playlists-error'),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 38),
        child: Column(
          children: [
            Icon(Icons.cloud_off_rounded, color: tokens.textMuted, size: 38),
            const SizedBox(height: 14),
            Text(
              '暂时无法读取歌单',
              style: TextStyle(
                color: tokens.textPrimary,
                fontSize: MusicTypography.calloutSize,
                fontWeight: MusicTypography.bodyWeight,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '请稍后返回此页面重试',
              style: TextStyle(
                color: tokens.textSecondary,
                fontSize: MusicTypography.smallCaptionSize,
                fontWeight: MusicTypography.bodyWeight,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _playlistUpdatedLabel(DateTime updatedAt) {
  final local = updatedAt.toLocal();
  final now = DateTime.now();
  if (local.year == now.year &&
      local.month == now.month &&
      local.day == now.day) {
    return '今天编辑';
  }
  if (local.year == now.year) return '${local.month}月${local.day}日编辑';
  return '${local.year}年${local.month}月${local.day}日编辑';
}

class _FavoriteSection extends ConsumerWidget {
  const _FavoriteSection({required this.tracks});

  final List<Track> tracks;

  Future<void> _appendTrack(
    BuildContext context,
    WidgetRef ref,
    Track track,
  ) async {
    try {
      final added = await ref
          .read(audioHandlerProvider)
          .appendToUpcomingQueue(track);
      if (!context.mounted) return;
      showMusicNotice(
        context,
        icon: added ? Icons.check_rounded : Icons.queue_music_rounded,
        title: added ? '已添加' : '已在播放列表',
        message: '',
      );
    } on Object {
      if (!context.mounted) return;
      showMusicNotice(
        context,
        icon: Icons.error_outline_rounded,
        title: '添加失败',
        message: '暂时无法加入《${track.title}》，请稍后重试',
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final handler = ref.watch(audioHandlerProvider);
    final currentTrackId = ref.watch(currentMediaItemProvider).value?.id;
    final playing = ref.watch(playbackStateProvider).value?.playing ?? false;
    return FavoriteCollectionView(
      tracks: tracks,
      currentTrackId: currentTrackId,
      playing: playing,
      onPlayAll: tracks.isEmpty ? null : () => handler.replaceQueue(tracks),
      onPlayTrack: handler.playSingleTrack,
      onAddTrack: (track) => _appendTrack(context, ref, track),
      onExplore: () => context.push(
        '/music/search',
        extra: const MusicPageTransitionIntent.forward(),
      ),
    );
  }
}

class FavoriteCollectionView extends StatelessWidget {
  const FavoriteCollectionView({
    required this.tracks,
    required this.onPlayAll,
    required this.onPlayTrack,
    required this.onAddTrack,
    required this.onExplore,
    this.currentTrackId,
    this.playing = false,
    super.key,
  });

  final List<Track> tracks;
  final VoidCallback? onPlayAll;
  final ValueChanged<Track> onPlayTrack;
  final ValueChanged<Track> onAddTrack;
  final VoidCallback onExplore;
  final String? currentTrackId;
  final bool playing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.musicThemeTokens;
    final accent = favoriteCollectionAccentFor(theme.brightness);
    return Theme(
      data: theme.copyWith(
        colorScheme: theme.colorScheme.copyWith(
          primary: accent,
          secondary: MestingPalette.heartSoft,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _FavoritesHero(tracks: tracks, onPlayAll: onPlayAll),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Row(
              children: [
                Text(
                  '收藏曲目',
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontSize: MusicTypography.headingSize,
                    fontWeight: MusicTypography.titleWeight,
                    letterSpacing: -.4,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  key: const ValueKey('favorite-track-count'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: .10),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${tracks.length}',
                    style: TextStyle(
                      color: accent,
                      fontSize: MusicTypography.smallCaptionSize,
                      fontWeight: MusicTypography.bodyWeight,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 11),
          if (tracks.isEmpty)
            _FavoriteEmptyState(onExplore: onExplore)
          else
            LiquidGlassSurface(
              key: const ValueKey('favorite-track-list-liquid-glass'),
              borderRadius: BorderRadius.circular(26),
              blurSigma: 24,
              child: Column(
                key: const ValueKey('favorite-track-list'),
                children: [
                  for (var index = 0; index < tracks.length; index++) ...[
                    FavoriteTrackRow(
                      track: tracks[index],
                      index: index,
                      active: currentTrackId == tracks[index].id,
                      playing: playing,
                      onPlay: () => onPlayTrack(tracks[index]),
                      onAdd: () => onAddTrack(tracks[index]),
                    ),
                    if (index != tracks.length - 1)
                      Divider(
                        height: 1,
                        indent: 48,
                        endIndent: 12,
                        color: accent.withValues(alpha: .09),
                      ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _FavoritesHero extends StatelessWidget {
  const _FavoritesHero({required this.tracks, required this.onPlayAll});

  final List<Track> tracks;
  final VoidCallback? onPlayAll;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final foreground = dark ? const Color(0xFFF5F6FA) : const Color(0xFF20242D);
    final secondary = dark ? const Color(0xFFC3CAD7) : const Color(0xFF656E7C);
    final accent = favoriteCollectionAccentFor(Theme.of(context).brightness);
    final subtitle = tracks.isEmpty ? '从第一首心动开始' : '${tracks.length} 首收藏';
    return LiquidGlassSurface(
      key: const ValueKey('favorites-collection-hero'),
      borderRadius: BorderRadius.circular(30),
      blurSigma: 24,
      child: SizedBox(
        height: 210,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                accent.withValues(alpha: dark ? .055 : .075),
                Colors.transparent,
                accent.withValues(alpha: dark ? .035 : .045),
              ],
              stops: const [0, .56, 1],
            ),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final artworkWidth = constraints.maxWidth < 330 ? 102.0 : 120.0;
              return Stack(
                children: [
                  Positioned(
                    left: 0,
                    top: 28,
                    bottom: 28,
                    child: Container(
                      width: 4,
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: const BorderRadius.horizontal(
                          right: Radius.circular(99),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: -34,
                    bottom: -48,
                    child: Icon(
                      Icons.favorite_border_rounded,
                      size: 142,
                      color: accent.withValues(alpha: dark ? .045 : .055),
                    ),
                  ),
                  Positioned(
                    right: -54,
                    top: -58,
                    child: Container(
                      width: 176,
                      height: 176,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: accent.withValues(alpha: dark ? .10 : .08),
                          width: 24,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 36,
                    right: 15,
                    bottom: 28,
                    width: artworkWidth,
                    child: _FavoriteArtworkStack(tracks: tracks),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(22, 20, artworkWidth + 21, 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          key: const ValueKey(
                            'favorites-private-archive-label',
                          ),
                          padding: const EdgeInsets.fromLTRB(8, 5, 9, 5),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: dark ? .14 : .09),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: accent.withValues(alpha: dark ? .25 : .16),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.favorite_rounded,
                                color: accent,
                                size: 11,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'PRIVATE ARCHIVE',
                                style: TextStyle(
                                  color: accent,
                                  fontSize: MusicTypography.smallCaptionSize,
                                  fontWeight: MusicTypography.bodyWeight,
                                  letterSpacing: 1.15,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 15),
                        Text(
                          '心动收藏',
                          style: TextStyle(
                            color: foreground,
                            fontSize: MusicTypography.titleSize,
                            height: 1,
                            fontWeight: MusicTypography.titleWeight,
                            letterSpacing: -1,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '把每一首喜欢，收进自己的声音档案',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: secondary,
                            fontSize: MusicTypography.smallCaptionSize,
                            height: 1.35,
                            fontWeight: MusicTypography.bodyWeight,
                          ),
                        ),
                        const Spacer(),
                        Row(
                          children: [
                            Container(
                              key: const ValueKey('favorites-hero-track-count'),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: foreground.withValues(alpha: .065),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                subtitle,
                                style: TextStyle(
                                  color: secondary,
                                  fontSize: MusicTypography.smallCaptionSize,
                                  fontWeight: MusicTypography.bodyWeight,
                                ),
                              ),
                            ),
                            const SizedBox(width: 7),
                            SizedBox(
                              height: 34,
                              child: FilledButton.icon(
                                key: const ValueKey('favorites-play-all'),
                                onPressed: onPlayAll,
                                style: FilledButton.styleFrom(
                                  backgroundColor: MestingPalette.heart,
                                  disabledBackgroundColor: MestingPalette.heart
                                      .withValues(alpha: .18),
                                  foregroundColor: Colors.white,
                                  disabledForegroundColor: secondary,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 11,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                ),
                                icon: const Icon(
                                  Icons.play_arrow_rounded,
                                  size: 16,
                                ),
                                label: const Text(
                                  '播放',
                                  style: TextStyle(
                                    fontSize: MusicTypography.smallCaptionSize,
                                    fontWeight: MusicTypography.bodyWeight,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

enum _FavoriteArtworkSwipeAction { previous, next }

_FavoriteArtworkSwipeAction? _resolveFavoriteArtworkSwipe({
  required double dragDistance,
  required double primaryVelocity,
}) {
  final direction = dragDistance.abs() >= favoriteArtworkSwipeDistanceThreshold
      ? dragDistance
      : primaryVelocity.abs() >= favoriteArtworkSwipeVelocityThreshold
      ? primaryVelocity
      : 0;
  if (direction == 0) return null;
  return direction < 0
      ? _FavoriteArtworkSwipeAction.next
      : _FavoriteArtworkSwipeAction.previous;
}

class _FavoriteArtworkStack extends StatefulWidget {
  const _FavoriteArtworkStack({required this.tracks});

  final List<Track> tracks;

  @override
  State<_FavoriteArtworkStack> createState() => _FavoriteArtworkStackState();
}

class _FavoriteArtworkStackState extends State<_FavoriteArtworkStack> {
  int _frontIndex = 0;
  double _horizontalDragDistance = 0;
  _FavoriteArtworkSwipeAction _lastAction = _FavoriteArtworkSwipeAction.next;
  final Set<String> _precacheScheduled = <String>{};

  List<Track> get _tracks => widget.tracks;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scheduleNearbyArtworkPrecache();
  }

  @override
  void didUpdateWidget(covariant _FavoriteArtworkStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previousFrontId = oldWidget.tracks.isEmpty
        ? null
        : oldWidget
              .tracks[_frontIndex.clamp(0, oldWidget.tracks.length - 1)]
              .id;
    if (_tracks.isEmpty) {
      _frontIndex = 0;
    } else {
      final preservedIndex = previousFrontId == null
          ? -1
          : _tracks.indexWhere((track) => track.id == previousFrontId);
      _frontIndex = preservedIndex >= 0
          ? preservedIndex
          : _frontIndex.clamp(0, _tracks.length - 1);
    }
    _scheduleNearbyArtworkPrecache();
  }

  void _scheduleNearbyArtworkPrecache() {
    if (_tracks.isEmpty) return;
    final targets = <Track>[
      for (var offset = 0; offset < _tracks.length && offset < 5; offset++)
        _tracks[(_frontIndex + offset) % _tracks.length],
    ];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_precacheArtworkInOrder(targets));
    });
  }

  Future<void> _precacheArtworkInOrder(List<Track> targets) async {
    for (final track in targets) {
      if (!mounted) return;
      final uri = track.coverAsset.trim();
      if (uri.isEmpty || !_precacheScheduled.add(uri)) continue;
      final provider = _favoriteArtworkProvider(context, uri);
      if (provider == null) continue;
      await precacheImage(
        provider,
        context,
        onError: (Object error, StackTrace? stackTrace) {
          _precacheScheduled.remove(uri);
        },
      );
    }
  }

  void _show(_FavoriteArtworkSwipeAction action) {
    if (_tracks.length < 2) return;
    setState(() {
      _lastAction = action;
      _frontIndex = switch (action) {
        _FavoriteArtworkSwipeAction.next => (_frontIndex + 1) % _tracks.length,
        _FavoriteArtworkSwipeAction.previous =>
          (_frontIndex - 1 + _tracks.length) % _tracks.length,
      };
    });
    _scheduleNearbyArtworkPrecache();
  }

  @override
  Widget build(BuildContext context) {
    if (_tracks.isEmpty) {
      return Center(
        key: const ValueKey('favorites-artwork-stack'),
        child: Container(
          width: 92,
          height: 112,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .10),
            borderRadius: BorderRadius.circular(25),
            border: Border.all(color: Colors.white.withValues(alpha: .20)),
          ),
          child: const Icon(
            Icons.favorite_border_rounded,
            color: Color(0xD9FFFFFF),
            size: 34,
          ),
        ),
      );
    }

    final visibleCount = _tracks.length < 3 ? _tracks.length : 3;
    final visibleTracks = <Track>[
      for (var offset = 0; offset < visibleCount; offset++)
        _tracks[(_frontIndex + offset) % _tracks.length],
    ];
    final frontTrack = visibleTracks.first;
    final deckKey = ValueKey<String>(
      'favorites-artwork-deck-${frontTrack.id}-$_frontIndex',
    );
    return Semantics(
      key: const ValueKey('favorites-artwork-stack'),
      container: true,
      label:
          '收藏封面：${frontTrack.title}，第 ${_frontIndex + 1} 首，共 ${_tracks.length} 首',
      hint: _tracks.length > 1 ? '左右滑动切换封面' : null,
      onIncrease: _tracks.length > 1
          ? () => _show(_FavoriteArtworkSwipeAction.next)
          : null,
      onDecrease: _tracks.length > 1
          ? () => _show(_FavoriteArtworkSwipeAction.previous)
          : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) => _horizontalDragDistance = 0,
        onHorizontalDragUpdate: (details) {
          _horizontalDragDistance += details.primaryDelta ?? 0;
        },
        onHorizontalDragCancel: () => _horizontalDragDistance = 0,
        onHorizontalDragEnd: (details) {
          final action = _resolveFavoriteArtworkSwipe(
            dragDistance: _horizontalDragDistance,
            primaryVelocity: details.primaryVelocity ?? 0,
          );
          _horizontalDragDistance = 0;
          if (action != null) _show(action);
        },
        child: AnimatedSwitcher(
          key: const ValueKey('favorites-artwork-switcher'),
          duration: favoriteArtworkSwitchDuration,
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          layoutBuilder: (currentChild, previousChildren) => Stack(
            alignment: Alignment.center,
            children: [...previousChildren, ?currentChild],
          ),
          transitionBuilder: (child, animation) {
            final incoming = child.key == deckKey;
            final entersFromRight =
                _lastAction == _FavoriteArtworkSwipeAction.next;
            final begin = Offset(
              entersFromRight
                  ? (incoming ? .18 : -.18)
                  : (incoming ? -.18 : .18),
              0,
            );
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: begin,
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            );
          },
          child: _FavoriteArtworkDeck(key: deckKey, tracks: visibleTracks),
        ),
      ),
    );
  }
}

class _FavoriteArtworkDeck extends StatelessWidget {
  const _FavoriteArtworkDeck({required this.tracks, super.key});

  final List<Track> tracks;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        for (var depth = tracks.length - 1; depth >= 0; depth--)
          Transform.translate(
            offset: Offset(depth * 7.0, -depth * 7.0),
            child: Transform.rotate(
              angle: (depth - 1) * .045,
              child: Container(
                key: depth == 0
                    ? ValueKey('favorites-artwork-front-${tracks[depth].id}')
                    : ValueKey(
                        'favorites-artwork-layer-$depth-${tracks[depth].id}',
                      ),
                width: 92,
                height: 112,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: const Color(
                    0xFFF0F3FC,
                  ).withValues(alpha: 1 - depth * .12),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x590F0710),
                      blurRadius: 18,
                      offset: Offset(0, 9),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: ArtworkImage(
                    key: ValueKey(
                      'favorites-artwork-image-${tracks[depth].id}',
                    ),
                    uri: tracks[depth].coverAsset,
                    width: 84,
                    height: 104,
                    decodeWidth: favoriteArtworkDecodeWidth,
                    retryOnNetworkError: true,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

ImageProvider<Object>? _favoriteArtworkProvider(
  BuildContext context,
  String uri,
) {
  ImageProvider<Object> provider;
  if (uri.startsWith('http://') || uri.startsWith('https://')) {
    provider = networkArtworkProvider(uri);
  } else {
    File? file;
    if (uri.startsWith('file://')) {
      file = File.fromUri(Uri.parse(uri));
    } else if (uri.startsWith('/') ||
        RegExp(r'^[A-Za-z]:[\\/]').hasMatch(uri)) {
      file = File(uri);
    }
    if (file != null) {
      if (!file.existsSync()) return null;
      provider = FileImage(file);
    } else {
      provider = AssetImage(uri);
    }
  }
  return ResizeImage.resizeIfNeeded(
    artworkCacheDimension(context, favoriteArtworkDecodeWidth),
    null,
    provider,
  );
}

class _FavoriteEmptyState extends StatelessWidget {
  const _FavoriteEmptyState({required this.onExplore});

  final VoidCallback onExplore;

  @override
  Widget build(BuildContext context) {
    final tokens = context.musicThemeTokens;
    final accent = favoriteCollectionAccentFor(Theme.of(context).brightness);
    return LiquidGlassSurface(
      key: const ValueKey('favorite-empty-liquid-glass'),
      borderRadius: BorderRadius.circular(26),
      blurSigma: 24,
      child: SizedBox(
        height: 184,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: .10),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.favorite_border_rounded,
                  color: accent,
                  size: 23,
                ),
              ),
              const SizedBox(height: 11),
              Text(
                '还没有喜欢的歌曲',
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: MusicTypography.subheadlineSize,
                  fontWeight: MusicTypography.bodyWeight,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '遇见心动旋律时，点亮爱心收藏',
                style: TextStyle(
                  color: tokens.textSecondary,
                  fontSize: MusicTypography.smallCaptionSize,
                  fontWeight: MusicTypography.bodyWeight,
                ),
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                key: const ValueKey('favorites-explore'),
                onPressed: onExplore,
                icon: const Icon(Icons.explore_outlined, size: 17),
                label: const Text('去发现音乐'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlassSurface extends StatelessWidget {
  const _GlassSurface({required this.radius, required this.child});

  final double radius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = context.musicThemeTokens;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderRadius = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: isDark
            ? const [
                BoxShadow(
                  color: Color(0x16252A39),
                  blurRadius: 18,
                  offset: Offset(0, 8),
                ),
              ]
            : const [
                BoxShadow(
                  color: Color(0x1F2E3D61),
                  blurRadius: 18,
                  offset: Offset(0, 7),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: isDark ? tokens.glass : const Color(0xFFF4F6FA),
            borderRadius: borderRadius,
            border: Border.all(
              color: isDark ? tokens.border : const Color(0x3D596784),
            ),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: borderRadius,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: isDark ? .04 : .20),
                  Colors.transparent,
                ],
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _PressScale extends StatefulWidget {
  const _PressScale({
    required this.child,
    required this.onTap,
    this.scale = .97,
  });

  final Widget child;
  final VoidCallback onTap;
  final double scale;

  @override
  State<_PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<_PressScale> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        scale: _pressed ? widget.scale : 1,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
          opacity: _pressed ? .82 : 1,
          child: widget.child,
        ),
      ),
    );
  }
}
