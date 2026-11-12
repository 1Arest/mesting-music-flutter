import 'platform_search_landing.dart' show PlatformExploreSongsPage;
import '../data/platform_explore.dart';
import 'song_actions_sheet.dart';
import '../../../shared/widgets/beta_page_motion.dart';
import '../../downloads/downloaded_track_subtitle.dart';
import '../../../shared/widgets/beta_content_insets.dart';
import '../../../shared/widgets/music_refresh_indicator.dart';
import '../../player/presentation/beta_playback_actions.dart';
import 'package:flutter/material.dart';
import '../../../shared/widgets/song_list_tools.dart';
import '../platform_browse_cache.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/models/track.dart';
import '../../../shared/widgets/artwork_image.dart';
import '../../../shared/widgets/track_artwork.dart';
import '../../library/presentation/favorite_toggle_button.dart';
import '../../player/presentation/music_hub_top_bar.dart';
import '../../search/search_providers.dart';
import '../../library/library_providers.dart';
import 'platform_feedback.dart';
import 'platform_recommendations_page.dart';
import '../music_platform_providers.dart';
import '../platform_catalog_providers.dart';
import 'platform_design.dart';
import 'retained_platform_snapshot.dart';
import '../../themes/music_theme_tokens.dart';
import '../../themes/music_typography.dart';

/// The incumbent Mesting shell with live upstream content. Each section owns
/// its loading/error state; a failed playlist request cannot hide valid songs.
class PlatformDiscoveryPage extends ConsumerWidget {
  const PlatformDiscoveryPage({this.dailyOnly = false, super.key});
  final bool dailyOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (dailyOnly) return const PlatformRecommendationDetail(title: '每日推荐');
    final signedIn = ref.watch(platformAccountProvider).value != null;
    final daily = ref.watch(platformDailyProvider);
    return PlatformStyle(
      child: MusicRefreshIndicator(
        onRefresh: () => refreshBrowse(ref, [
          () => ref.refresh(platformDailyProvider.future),
          if (!dailyOnly) ...[
            () => ref.refresh(platformDiscoveryProvider.future),
            () => ref.refresh(platformFeaturedProvider.future),
            () => ref.refresh(hotMusicControllerProvider.future),
          ],
        ]),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            16,
            MediaQuery.paddingOf(context).top + 12,
            16,
            BetaContentInsets.musicBottomOf(context, 140),
          ),
          children: [
            MusicHubTopBar(
              title: dailyOnly ? '每日推荐' : '发现音乐',
              subtitle: signedIn ? '酷狗概念版 · 为你推荐' : '酷狗概念版 · 公共推荐',
              showBack: dailyOnly,
              onBack: dailyOnly
                  ? () => context.canPop()
                        ? context.pop()
                        : context.go('/music/recommend')
                  : null,
            ),
            const SizedBox(height: 24),
            _SectionTitle(signedIn ? '你的每日推荐' : '新歌推荐'),
            PlatformSongs(
              value: daily,
              retry: () => ref.invalidate(platformDailyProvider),
            ),
            if (!dailyOnly) ...[
              const SizedBox(height: 24),
              const _SectionTitle('精选歌单'),
              _FeaturedPlaylists(),
              const SizedBox(height: 24),
              const _SectionTitle('发现更多音乐'),
              PlatformSongs(
                value: ref.watch(platformDiscoveryProvider),
                retry: () => ref.invalidate(platformDiscoveryProvider),
              ),
              const SizedBox(height: 24),
              const _SectionTitle('实时榜单'),
              RetainedPlatformSnapshot(
                value: ref.watch(hotMusicControllerProvider),
                artwork: (snapshot) =>
                    snapshot.tracks.map((track) => track.coverAsset),
                loading: () => const PlatformFeedbackState(loading: true),
                error: (error, stack) => _Retry(
                  retry: () => ref.invalidate(hotMusicControllerProvider),
                ),
                data: (snapshot) => snapshot.tracks.isEmpty
                    ? _Retry(
                        retry: () => ref.invalidate(hotMusicControllerProvider),
                      )
                    : _TrackList(tracks: snapshot.tracks),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => PlatformSectionTitle(text);
}

class _Retry extends StatelessWidget {
  const _Retry({required this.retry, this.empty = false});
  final VoidCallback retry;
  final bool empty;
  @override
  Widget build(BuildContext context) => PlatformFeedbackState(
    message: empty ? '平台暂未返回内容' : '内容暂时未能加载，请重试',
    retry: retry,
  );
}

class PlatformSongs extends StatelessWidget {
  const PlatformSongs({
    required this.value,
    required this.retry,
    this.playlistId,
    this.sliver = false,
    super.key,
  });
  final AsyncValue<List<Track>> value;
  final VoidCallback retry;
  final String? playlistId;
  final bool sliver;
  Widget wrap(Widget child) =>
      sliver ? SliverToBoxAdapter(child: child) : child;
  @override
  Widget build(BuildContext context) => RetainedPlatformSnapshot(
    value: value,
    artwork: (tracks) => tracks.map((track) => track.coverAsset),
    loading: () => wrap(const PlatformFeedbackState(loading: true)),
    error: (error, stack) => wrap(_Retry(retry: retry)),
    data: (tracks) => tracks.isEmpty
        ? wrap(_Retry(retry: retry, empty: true))
        : _TrackList(tracks: tracks, playlistId: playlistId, sliver: sliver),
  );
}

/// A sliver variant keeps complete cloud/public collections lazy while reusing
/// the exact same row actions, ownership and comments as compact preview lists.
class _TrackList extends ConsumerWidget {
  const _TrackList({
    required this.tracks,
    this.playlistId,
    this.sliver = false,
  });
  final List<Track> tracks;
  final String? playlistId;
  final bool sliver;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Widget row(Track track) => SongListEntry(
      track: track,
      tracks: tracks,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(vertical: 6),
        titleTextStyle: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: context.musicThemeTokens.textPrimary,
          fontSize: MusicTypography.subheadlineSize,
          fontWeight: MusicTypography.bodyWeight,
        ),
        subtitleTextStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: context.musicThemeTokens.textSecondary,
          fontSize: MusicTypography.captionSize,
          height: 1.6,
        ),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: TrackArtwork(track: track, width: 48, height: 48),
        ),
        title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: DownloadedTrackSubtitle(track: track),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FavoriteToggleButton(track: track, compact: true),
            SongActionsButton(
              track: track,
              extras: [
                if (playlistId != null)
                  SongMenuExtraAction(
                    '从云端歌单移除',
                    Icons.remove_circle_outline,
                    () => ref
                        .read(libraryRepositoryProvider)
                        .removeTrackFromPlaylist(playlistId!, track.id),
                    destructive: true,
                  ),
              ],
            ),
          ],
        ),
        onTap: () async {
          try {
            SongListTools.remember(context, track);
            await playBetaSelection(context, ref, track);
          } catch (error) {
            if (context.mounted) {
              showPlatformFailure(context, error);
            }
          }
        },
      ),
    );
    const padding = EdgeInsets.symmetric(horizontal: 22, vertical: 4);
    return sliver
        ? SliverPadding(
            padding: padding,
            sliver: SliverList.builder(
              itemCount: tracks.length,
              itemBuilder: (_, index) => row(tracks[index]),
            ),
          )
        : Padding(
            padding: padding,
            child: Column(children: tracks.map(row).toList()),
          );
  }
}

class _FeaturedPlaylists extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) => RetainedPlatformSnapshot(
    value: ref.watch(platformFeaturedProvider),
    artwork: (rows) => rows.map(
      (row) => '${row['sizable_cover'] ?? row['imgurl'] ?? row['pic'] ?? ''}'
          .replaceAll('{size}', '400'),
    ),
    loading: () => const PlatformFeedbackState(loading: true),
    error: (error, stack) =>
        _Retry(retry: () => ref.invalidate(platformFeaturedProvider)),
    data: (rows) {
      final playlists = rows
          .where(
            (row) =>
                '${row['global_collection_id'] ?? row['gid'] ?? ''}'.isNotEmpty,
          )
          .toList();
      if (playlists.isEmpty) {
        return _Retry(
          retry: () => ref.invalidate(platformFeaturedProvider),
          empty: true,
        );
      }
      return Column(
        children: [
          for (final row in playlists)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: ArtworkImage(
                  uri:
                      '${row['sizable_cover'] ?? row['imgurl'] ?? row['pic'] ?? ''}'
                          .replaceAll('{size}', '400'),
                  width: 56,
                  height: 56,
                ),
              ),
              title: Text(
                '${row['name'] ?? row['specialname'] ?? '精选歌单'}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: const Text('酷狗概念版'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MestingPageRoute<void>(
                  builder: (_) => PlatformPublicPlaylistPage(
                    id: '${row['global_collection_id'] ?? row['gid']}',
                    name: '${row['name'] ?? row['specialname'] ?? '精选歌单'}',
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
}

class PlatformPublicPlaylistPage extends ConsumerWidget {
  const PlatformPublicPlaylistPage({
    required this.id,
    required this.name,
    this.cover = '',
    super.key,
  });
  final String id;
  final String name;
  final String cover;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PlatformExploreSongsPage(
      item: PlatformExploreItem(
        id: id,
        title: name,
        cover: cover,
        kind: PlatformExploreKind.playlist,
      ),
    );
  }
}
