import '../../../shared/widgets/music_refresh_indicator.dart';
import '../../music_platform/netease/fallback/netease_source_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../../downloads/audio_downloads_page.dart';
import 'cold_start_greeting.dart';
import '../../../shared/widgets/beta_glass_controls.dart';
import '../../music_platform/netease/full/netease_full_page.dart';
import '../../player/presentation/beta_playback_actions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/models/track.dart';
import '../../../shared/widgets/artwork_image.dart';
import '../../../shared/widgets/track_artwork.dart';
import '../../auth/auth_providers.dart';
import '../../library/presentation/favorite_toggle_button.dart';
import '../../music_platform/music_platform_providers.dart';
import '../../music_platform/platform_profile_provider.dart';
import '../../music_platform/presentation/platform_avatar.dart';
import '../../music_platform/presentation/platform_feedback.dart';
import '../../playlists/presentation/add_to_playlist_sheet.dart';
import '../../themes/music_theme_tokens.dart';

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
  const EditorialScroll({required this.children, this.onRefresh, super.key});
  final List<Widget> children;
  final Future<void> Function()? onRefresh;
  @override
  Widget build(BuildContext context) {
    final scroll = ListView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: EdgeInsets.only(
        top: MediaQuery.paddingOf(context).top + 14,
        bottom: editorialBottomClearance,
      ),
      children: children,
    );
    return onRefresh == null
        ? scroll
        : MusicRefreshIndicator(onRefresh: onRefresh!, child: scroll);
  }
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
    final user = ref.watch(currentUserProvider);
    final homeGreeting = !back && (title == '首页' || title == '发现');
    final titleLabel = Text(
      title,
      style: TextStyle(
        color: context.musicThemeTokens.textPrimary,
        fontSize: 34,
        fontWeight: FontWeight.w800,
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
                  url:
                      profile?.avatarUrl ??
                      platform?.avatarUrl ??
                      user?.avatarUrl ??
                      '',
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
    this.fontWeight = FontWeight.w800,
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
              fontSize: 23,
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
                          fontWeight: FontWeight.w800,
                          shadows: [
                            Shadow(color: Colors.black45, blurRadius: 12),
                          ],
                        ),
                      ),
                    ),
                  if (feature)
                    Positioned(
                      left: 18,
                      right: 18,
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
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 23,
                              height: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
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
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (subtitle.isNotEmpty)
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.musicThemeTokens.textSecondary,
                    fontSize: 12,
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
    this.onPlay,
    super.key,
  });
  final VoidCallback? onPlay;
  final Track track;
  final List<Track> contextTracks;
  final int? rank;
  @override
  Widget build(BuildContext context, WidgetRef ref) => InkWell(
    onLongPress: track.isRemote
        ? () => showCupertinoModalPopup<void>(
            context: context,
            builder: (c) => CupertinoActionSheet(
              title: Text(track.title),
              actions: [
                if (track.source == TrackSource.netease)
                  CupertinoActionSheetAction(
                    onPressed: () {
                      Navigator.pop(c);
                      showNeteaseTrackSources(context, ref, track);
                    },
                    child: const Text('选择音乐来源'),
                  ),
                CupertinoActionSheetAction(
                  onPressed: () {
                    Navigator.pop(c);
                    enqueueAudioDownload(context, ref, track);
                  },
                  child: const Text('下载音乐'),
                ),
                if (track.source == TrackSource.netease)
                  CupertinoActionSheetAction(
                    onPressed: () {
                      Navigator.pop(c);
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => NeteaseFullHubPage(
                            entityKind: 'song',
                            seed: {
                              'id': track.platformSongId,
                              'ids': track.platformSongId,
                            },
                          ),
                        ),
                      );
                    },
                    child: const Text('网易云相关功能'),
                  ),
              ],
              cancelButton: CupertinoActionSheetAction(
                onPressed: () => Navigator.pop(c),
                child: const Text('取消'),
              ),
            ),
          )
        : null,
    onTap:
        onPlay ?? () => playEditorialTrack(context, ref, track, contextTracks),
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
                  fontWeight: FontWeight.w700,
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
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  track.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.musicThemeTokens.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          FavoriteToggleButton(track: track, compact: true),
          IconButton(
            tooltip: '加入歌单',
            onPressed: () => showAddToPlaylistSheet(context, ref, track),
            icon: const Icon(Icons.playlist_add_rounded, size: 22),
          ),
        ],
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
    super.key,
  });
  final String cover;
  final String description;
  final List<Track> tracks;
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
          '${tracks.length} 首歌曲',
          style: TextStyle(color: context.musicThemeTokens.textSecondary),
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: tracks.isEmpty
              ? null
              : () => playBetaSelection(
                  context,
                  ref,
                  tracks.first,
                  playAll: tracks,
                ),
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Text('播放全部'),
        ),
      ],
    ),
  );
}
