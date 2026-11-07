import '../../music_platform/presentation/song_actions_sheet.dart';
import '../../downloads/downloaded_track_subtitle.dart';
import '../../themes/beta_appearance.dart';
import '../../../shared/widgets/music_list_footer.dart';
import '../../../shared/widgets/artwork_scroll_frontier.dart';
import '../../../shared/widgets/beta_content_insets.dart';
import '../../../shared/widgets/music_refresh_indicator.dart';
import 'package:flutter/material.dart';
import 'cold_start_greeting.dart';
import '../../../shared/widgets/beta_glass_controls.dart';
import '../../player/presentation/beta_playback_actions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/models/track.dart';
import '../../../shared/widgets/artwork_image.dart';
import '../../../shared/widgets/track_artwork.dart';
import '../../library/presentation/favorite_toggle_button.dart';
import '../../music_platform/music_platform_providers.dart';
import '../../music_platform/platform_profile_provider.dart';
import '../../music_platform/presentation/platform_avatar.dart';
import '../../music_platform/presentation/platform_feedback.dart';
import '../../themes/music_theme_tokens.dart';
import '../../../shared/widgets/song_list_tools.dart';
import '../../themes/music_typography.dart';

/// THESIS: Cover art leads a personal listening space with editorial pacing.
/// OWN-WORLD: Large Chinese system type, generous space, theme-aware neutrals,
/// photographic covers, and liquid glass confined to floating controls.
/// STORY: Discover a track, play it, and keep it in the active account's library.
/// FIRST VIEWPORT: Large title/avatar, a horizontal cover-led feature, then a
/// smaller recent shelf; persistent playback and four destinations float below.
/// FORM: User-pinned Apple Music references; seed=user-pinned-beta5.
/// FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, and DESIGN.md

const editorialBottomClearance = 210.0;

/// Shared page rhythm, not a second router or an alternate account model.
class EditorialScroll extends StatelessWidget {
  const EditorialScroll({
    required this.children,
    this.onRefresh,
    this.footer = const MusicListEnd(label: '已到底'),
    super.key,
  });
  final List<Widget> children;
  final Future<void> Function()? onRefresh;
  final Widget footer;

  /// Box sections must share a lazy delegate. One SliverToBoxAdapter per shelf
  /// still lays out every shelf to discover its extent, mounting offscreen
  /// provider subscriptions and image requests during the first frame. Keep
  /// genuine sliver sections in order, and lazily build each intervening run
  /// of ordinary boxes using the viewport's bounded cache extent.
  Iterable<Widget> _slivers() sync* {
    var boxes = <Widget>[];
    for (final child in [...children, footer]) {
      if (child is EditorialSliver) {
        if (boxes.isNotEmpty) {
          yield SliverList.list(children: boxes);
          boxes = <Widget>[];
        }
        yield child;
      } else {
        boxes.add(child);
      }
    }
    if (boxes.isNotEmpty) yield SliverList.list(children: boxes);
  }

  @override
  Widget build(BuildContext context) {
    final scroll = CustomScrollView(
      physics: const ArtworkFrontierPhysics(
        parent: AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      ),
      slivers: [
        SliverPadding(
          padding: EdgeInsets.only(
            top: MediaQuery.paddingOf(context).top + 14,
            bottom: BetaContentInsets.musicBottomOf(
              context,
              editorialBottomClearance,
            ),
          ),
          sliver: SliverMainAxisGroup(
            slivers: _slivers().toList(growable: false),
          ),
        ),
      ],
    );
    final content = onRefresh == null
        ? scroll
        : MusicRefreshIndicator(onRefresh: onRefresh!, child: scroll);
    return SongListTools.contains(context)
        ? content
        : SongListTools(child: content);
  }
}

/// A lazy section embedded in the common editorial scroll, without a nested
/// shrink-wrapped list that lays out the entire collection on first entry.
class EditorialSliver extends StatelessWidget {
  const EditorialSliver({required this.sliver, super.key});
  final Widget sliver;
  @override
  Widget build(BuildContext context) => sliver;
}

class EditorialHeader extends ConsumerWidget {
  const EditorialHeader(
    this.title, {
    this.back = false,
    this.trailing,
    super.key,
  });
  final String title;
  final bool back;
  final Widget? trailing;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final platform = ref.watch(platformAccountProvider).value;
    final profile = platform == null
        ? null
        : ref.watch(platformProfileProvider).value;
    final homeGreeting = !back && (title == '首页' || title == '发现');
    final titleLabel = Text(
      title,
      style: TextStyle(
        color: context.musicThemeTokens.textPrimary,
        fontSize: MusicTypography.largeTitleSize,
        fontWeight: MusicTypography.titleWeight,
        letterSpacing: -.9,
        height: 1.2,
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 8, 18, 24),
      child: Row(
        children: [
          if (back)
            BetaGlassBackButton(
              onPressed: () => context.canPop()
                  ? context.pop()
                  : context.go('/music/library'),
            ),
          if (back) const SizedBox(width: 16),
          Expanded(
            child: Row(
              children: [
                // Keep 首页 on one line at large text sizes; the ephemeral
                // greeting takes only the remaining width and truncates its name.
                if (homeGreeting) titleLabel else Flexible(child: titleLabel),
                if (homeGreeting) const Flexible(child: ColdStartGreeting()),
              ],
            ),
          ),
          trailing ??
              IconButton(
                tooltip: '我的账号',
                onPressed: () => context.go('/profile'),
                icon: PlatformAvatar(
                  url: profile?.avatarUrl ?? platform?.avatarUrl ?? '',
                  size: 42,
                ),
              ),
        ],
      ),
    );
  }
}

class EditorialSection extends StatelessWidget {
  const EditorialSection(
    this.title, {
    this.onTap,
    this.actionLabel = '查看全部',
    this.fontWeight = MusicTypography.titleWeight,
    super.key,
  });
  final String title;
  final VoidCallback? onTap;
  final String actionLabel;
  final FontWeight fontWeight;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(22, 28, 16, 14),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: context.musicThemeTokens.textPrimary,
              fontSize: MusicTypography.sectionTitleSize,
              fontWeight: fontWeight,
              letterSpacing: -.4,
            ),
          ),
        ),
        if (onTap != null)
          IconButton(
            tooltip: actionLabel,
            onPressed: onTap,
            icon: Icon(
              Icons.chevron_right_rounded,
              color: context.musicThemeTokens.textSecondary,
            ),
          ),
      ],
    ),
  );
}

class EditorialCover extends StatelessWidget {
  const EditorialCover({
    required this.cover,
    this.track,
    required this.title,
    this.subtitle = '',
    this.width = 158,
    this.feature = false,
    this.height,
    this.rank,
    this.coverAction,
    required this.onTap,
    super.key,
  });
  final String cover;
  final Track? track;
  final String title;
  final String subtitle;
  final double width;
  final bool feature;
  final double? height;
  final int? rank;

  /// A separate overlay target leaves the cover's navigation tap unchanged.
  final Widget? coverAction;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Semantics(
      button: true,
      label: '$title，$subtitle',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(feature ? 22 : 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(feature ? 22 : 12),
              child: Stack(
                children: [
                  if (track != null)
                    TrackArtwork(
                      track: track!,
                      width: width,
                      height: height ?? width * (feature ? 1.13 : 1),
                    )
                  else
                    ArtworkImage(
                      uri: cover,
                      retryOnNetworkError: true,
                      persistentNetworkCacheKey: 'editorial-cover:$cover',
                      width: width,
                      height: height ?? width * (feature ? 1.13 : 1),
                      fit: BoxFit.cover,
                    ),
                  if (feature)
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: .82),
                            ],
                            stops: const [.4, 1],
                          ),
                        ),
                      ),
                    ),
                  if (rank != null)
                    Positioned(
                      top: 14,
                      left: 18,
                      child: Text(
                        '$rank',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 56,
                          height: 1,
                          fontWeight: MusicTypography.titleWeight,
                          shadows: [
                            Shadow(color: Colors.black45, blurRadius: 12),
                          ],
                        ),
                      ),
                    ),
                  if (feature)
                    Positioned(
                      left: 18,
                      right: coverAction == null ? 18 : 66,
                      bottom: 18,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xE6FFFFFF),
                              fontSize: MusicTypography.footnoteSize,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: MusicTypography.titleWeight,
                              fontSize: MusicTypography.sectionTitleSize,
                              height: 1.2,
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
            if (!feature) ...[
              const SizedBox(height: 9),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: context.musicThemeTokens.textPrimary,
                  fontSize: MusicTypography.subheadlineSize,
                  fontWeight: MusicTypography.bodyWeight,
                ),
              ),
              if (subtitle.isNotEmpty)
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.musicThemeTokens.textSecondary,
                    fontSize: MusicTypography.captionSize,
                    height: 1.6,
                  ),
                ),
            ],
          ],
        ),
      ),
    ),
  );
}

/// Height is owned by the shelf so covers never lay out unbounded in a list.
class EditorialShelf extends StatelessWidget {
  const EditorialShelf({required this.children, this.height = 224, super.key});
  final List<Widget> children;
  final double height;
  @override
  Widget build(BuildContext context) => SizedBox(
    height:
        height +
        (MediaQuery.textScalerOf(context).scale(36) - 36).clamp(0.0, 100.0),
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      itemCount: children.length,
      separatorBuilder: (_, _) => const SizedBox(width: 14),
      itemBuilder: (_, index) => children[index],
    ),
  );
}

class EditorialTrackRow extends ConsumerWidget {
  const EditorialTrackRow({
    required this.track,
    required this.contextTracks,
    this.rank,
    this.favorites = false,
    this.onPlay,
    super.key,
  });
  final VoidCallback? onPlay;
  final Track track;
  final List<Track> contextTracks;
  final int? rank;
  final bool favorites;
  @override
  Widget build(BuildContext context, WidgetRef ref) => SongListEntry(
    track: track,
    tracks: contextTracks,
    child: InkWell(
      onLongPress: () =>
          showSongActions(context, ref, track, favorites: favorites),
      onTap: () {
        SongListTools.remember(context, track);
        if (onPlay != null) {
          onPlay!();
        } else {
          playEditorialTrack(context, ref, track, contextTracks);
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 9),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: TrackArtwork(track: track, width: 52, height: 52),
            ),
            if (rank != null)
              SizedBox(
                width: 28,
                child: Text(
                  '$rank',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: context.musicThemeTokens.textSecondary,
                    fontWeight: MusicTypography.titleWeight,
                  ),
                ),
              ),
            if (rank == null) const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.musicThemeTokens.textPrimary,
                      fontSize: MusicTypography.calloutSize,
                      fontWeight: MusicTypography.bodyWeight,
                    ),
                  ),
                  const SizedBox(height: 4),
                  DownloadedTrackSubtitle(
                    track: track,
                    style: TextStyle(
                      color: context.musicThemeTokens.textSecondary,
                      fontSize: MusicTypography.footnoteSize,
                    ),
                  ),
                ],
              ),
            ),
            FavoriteToggleButton(track: track, compact: true),
            SongActionsButton(track: track, favorites: favorites),
          ],
        ),
      ),
    ),
  );
}

Future<void> playEditorialTrack(
  BuildContext context,
  WidgetRef ref,
  Track track,
  List<Track> tracks,
) async {
  try {
    await playBetaSelection(context, ref, track);
  } catch (error) {
    if (context.mounted) showPlatformFailure(context, error);
  }
}

class EditorialEmpty extends StatelessWidget {
  const EditorialEmpty(this.message, {this.onRetry, super.key});
  final String message;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      children: [
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: context.musicThemeTokens.textSecondary,
            height: 1.6,
          ),
        ),
        if (onRetry != null)
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('重新加载'),
          ),
      ],
    ),
  );
}

/// A common collection introduction keeps cloud, public and local playlists
/// visually related without moving their ownership or mutation rules into UI.
class EditorialCollectionHero extends ConsumerWidget {
  const EditorialCollectionHero({
    required this.cover,
    required this.tracks,
    this.description = '',
    this.total,
    this.loadComplete,
    super.key,
  });
  final String cover;
  final String description;
  final List<Track> tracks;
  final int? total;
  final Future<List<Track>> Function()? loadComplete;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
    padding: const EdgeInsets.fromLTRB(22, 16, 22, 26),
    child: Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: cover.isEmpty && tracks.isNotEmpty
              ? TrackArtwork(track: tracks.first, width: 210, height: 210)
              : ArtworkImage(uri: cover, width: 210, height: 210),
        ),
        const SizedBox(height: 18),
        if (description.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              description,
              textAlign: TextAlign.center,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: context.musicThemeTokens.textSecondary,
                height: 1.6,
              ),
            ),
          ),
        Text(
          '${total ?? tracks.length} 首歌曲',
          style: TextStyle(color: context.musicThemeTokens.textSecondary),
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: tracks.isEmpty
              ? null
              : () async {
                  try {
                    final all = loadComplete == null
                        ? tracks
                        : await loadComplete!();
                    if (context.mounted && all.isNotEmpty) {
                      await playBetaSelection(
                        context,
                        ref,
                        all.first,
                        playAll: all,
                      );
                    }
                  } catch (failure) {
                    if (context.mounted) showPlatformFailure(context, failure);
                  }
                },
          icon: const Icon(Icons.play_arrow_rounded),
          style: FilledButton.styleFrom(
            backgroundColor: BetaAppearance.playbackAction(
              Theme.of(context).brightness,
            ),
            foregroundColor: Colors.white,
          ),
          label: const Text('播放全部'),
        ),
      ],
    ),
  );
}
