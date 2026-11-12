import '../../../shared/widgets/song_list_tools.dart';
import '../../../shared/widgets/beta_content_insets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/audio/playback_providers.dart';
import '../../../core/platform/distribution_channel.dart';
import '../../themes/beta_appearance.dart';
import '../../../shared/models/track.dart';
import '../../../shared/utils/duration_format.dart';
import '../../../shared/widgets/artwork_image.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/mesting_loading_indicator.dart';
import '../../../shared/widgets/music_notice.dart';
import '../../../shared/widgets/playing_equalizer.dart';
import '../../library/presentation/favorite_toggle_button.dart';
import '../../themes/mesting_palette.dart';
import '../../themes/music_theme_preset.dart';
import '../../themes/theme_controller.dart';
import '../../themes/music_theme_tokens.dart';
import '../data/curated_playlists.dart';
import '../discover_providers.dart';
import '../domain/curated_playlist.dart';
import '../../themes/music_typography.dart';

class CuratedPlaylistPage extends ConsumerWidget {
  const CuratedPlaylistPage({required this.playlistId, super.key});

  final String playlistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.musicThemeTokens;
    final playlist = curatedPlaylistForId(playlistId);
    if (playlist == null) {
      return _withBackFallback(
        context,
        Center(
          child: FilledButton(
            onPressed: () => _returnFromPlaylist(context),
            child: const Text('歌单不存在，返回发现页'),
          ),
        ),
      );
    }
    final tracks = ref.watch(curatedPlaylistTracksProvider(playlistId));
    final loaded = tracks.value;

    return _withBackFallback(
      context,
      SafeArea(
        bottom: false,
        child: ListView(
          padding: BetaContentInsets.musicPaddingOf(
            context,
            EdgeInsets.fromLTRB(18, 10, 18, 112),
          ),
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: '返回发现歌单',
                  onPressed: () => _returnFromPlaylist(context),
                  icon: const Icon(Icons.arrow_back_ios_new_rounded),
                ),
                const Spacer(),
                Text(
                  loaded?.isUnavailable == true
                      ? '在线曲库暂不可用'
                      : loaded?.isLocal == true
                      ? '本地音乐 · 离线模式'
                      : '策划歌单 · Audius',
                  style: TextStyle(
                    color: tokens.textSecondary,
                    fontWeight: MusicTypography.titleWeight,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _PlaylistHero(
              playlist: playlist,
              tracks: loaded?.tracks,
              isLocal: loaded?.isLocal ?? false,
              unavailable: loaded?.isUnavailable ?? false,
            ),
            const SizedBox(height: 22),
            tracks.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 64),
                child: Center(
                  child: MestingLoadingIndicator(
                    key: ValueKey('curated-playlist-loading-animation'),
                    semanticLabel: '正在加载在线歌单',
                  ),
                ),
              ),
              error: (error, stack) => _LoadError(
                onRetry: () =>
                    ref.invalidate(curatedPlaylistTracksProvider(playlistId)),
              ),
              data: (result) {
                if (result.tracks.isEmpty) {
                  return _LoadError(
                    message: '这张歌单暂时没有可播放歌曲',
                    onRetry: () => ref.invalidate(
                      curatedPlaylistTracksProvider(playlistId),
                    ),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (result.isLocal || result.isUnavailable)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: _OfflineNotice(
                          message:
                              result.warnings.firstOrNull ??
                              '当前处于离线模式，仅显示本地已有音乐',
                          onRetry: () => ref.invalidate(
                            curatedPlaylistTracksProvider(playlistId),
                          ),
                        ),
                      ),
                    for (final warning
                        in result.isLocal || result.isUnavailable
                            ? const <String>[]
                            : result.warnings)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(
                          warning,
                          style: const TextStyle(color: Color(0xFF4B63D0)),
                        ),
                      ),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            result.isUnavailable
                                ? '暂无歌曲'
                                : result.isLocal
                                ? '本地歌曲'
                                : '在线歌曲',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        Text('${result.tracks.length} 首'),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _CuratedTrackList(tracks: result.tracks),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _withBackFallback(BuildContext context, Widget child) {
    return PopScope<void>(
      canPop: _canPopPlaylistRoute(context),
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _returnFromPlaylist(context);
      },
      child: child,
    );
  }

  bool _canPopPlaylistRoute(BuildContext context) =>
      Navigator.maybeOf(context)?.canPop() ?? false;

  void _returnFromPlaylist(BuildContext context) {
    if (_canPopPlaylistRoute(context)) {
      Navigator.of(context).pop();
    } else {
      context.go('/music/discover');
    }
  }
}

class _PlaylistHero extends ConsumerWidget {
  const _PlaylistHero({
    required this.playlist,
    required this.tracks,
    required this.isLocal,
    required this.unavailable,
  });

  final CuratedPlaylist playlist;
  final List<Track>? tracks;
  final bool isLocal;
  final bool unavailable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.musicThemeTokens;
    final themePreset = ref.watch(effectiveMusicThemeProvider);
    final playlistIndex = curatedPlaylists.indexOf(playlist);
    final themedCover = themedPlaylistCover(
      preset: themePreset,
      index: playlistIndex,
      fallback: playlist.coverAsset,
    );
    return GlassCard(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 560;
          final coverSize = compact ? constraints.maxWidth : 170.0;
          final coverImage = ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: ArtworkImage(
              uri: themedCover,
              width: double.infinity,
              height: double.infinity,
              decodeWidth: coverSize,
              decodeHeight: coverSize,
              fit: BoxFit.cover,
            ),
          );
          final cover = compact
              ? AspectRatio(
                  key: const ValueKey('curated-playlist-cover-ratio'),
                  aspectRatio: 1,
                  child: coverImage,
                )
              : SizedBox.square(
                  key: const ValueKey('curated-playlist-cover-ratio'),
                  dimension: 170,
                  child: coverImage,
                );
          final details = Padding(
            padding: EdgeInsets.only(
              left: compact ? 0 : 20,
              top: compact ? 16 : 0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  playlist.name,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 7),
                Text(
                  unavailable
                      ? '连接在线曲库后即可查看完整歌单'
                      : isLocal
                      ? '网络不可用，当前显示 App 内置音乐'
                      : '${playlist.languageLabel} · 在线完整音乐 · 实时加载',
                  style: TextStyle(color: tokens.textSecondary),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  key: const ValueKey('curated-playlist-play-all'),
                  onPressed: tracks == null || tracks!.isEmpty
                      ? null
                      : () => ref
                            .read(audioHandlerProvider)
                            .replaceQueue(tracks!),
                  style: FilledButton.styleFrom(
                    backgroundColor: DistributionChannel.isBeta
                        ? BetaAppearance.playbackAction(
                            Theme.of(context).brightness,
                          )
                        : MestingPalette.heart,
                    foregroundColor: DistributionChannel.isBeta
                        ? Theme.of(context).colorScheme.onPrimary
                        : Colors.white,
                    disabledBackgroundColor:
                        (DistributionChannel.isBeta
                                ? BetaAppearance.playbackAction(
                                    Theme.of(context).brightness,
                                  )
                                : MestingPalette.heart)
                            .withValues(alpha: .42),
                    disabledForegroundColor: Colors.white.withValues(
                      alpha: .72,
                    ),
                  ),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('播放全部'),
                ),
              ],
            ),
          );
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [cover, details],
            );
          }
          return Row(
            children: [
              cover,
              Expanded(child: details),
            ],
          );
        },
      ),
    );
  }
}

class _CuratedTrackList extends ConsumerWidget {
  const _CuratedTrackList({required this.tracks});

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
    final currentId = ref.watch(currentMediaItemProvider).value?.id;
    final playing = ref.watch(playbackStateProvider).value?.playing ?? false;
    final tokens = context.musicThemeTokens;
    final favoriteAccent = DistributionChannel.isBeta
        ? BetaAppearance.favorite(Theme.of(context).brightness)
        : Theme.of(context).brightness == Brightness.dark
        ? MestingPalette.heartBright
        : MestingPalette.heart;
    return GlassCard(
      padding: const EdgeInsets.all(8),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: tracks.length,
        separatorBuilder: (context, index) =>
            Divider(height: 8, indent: 70, color: tokens.border),
        itemBuilder: (context, index) {
          final track = tracks[index];
          final active = currentId == track.id;
          return SongListEntry(
            track: track,
            tracks: tracks,
            child: ListTile(
              onTap: () {
                SongListTools.remember(context, track);
                handler.playSingleTrack(track, playbackContext: tracks);
              },
              tileColor: active
                  ? favoriteAccent.withValues(alpha: 0.085)
                  : null,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(13),
                child: ArtworkImage(
                  uri: track.coverAsset,
                  width: 52,
                  height: 52,
                ),
              ),
              title: Text(
                track.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: MusicTypography.titleWeight,
                  color: active ? favoriteAccent : null,
                ),
              ),
              subtitle: Text(
                '${track.artist} · ${formatDuration(track.duration)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FavoriteToggleButton(track: track, compact: true),
                  if (active)
                    PlayingEqualizer(
                      key: ValueKey(
                        'curated-playlist-playing-equalizer-${track.id}',
                      ),
                      animate: playing,
                      color: favoriteAccent,
                      size: 22,
                    )
                  else
                    Semantics(
                      button: true,
                      label: '将${track.title}添加至播放列表',
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _appendTrack(context, ref, track),
                        child: SizedBox(
                          key: ValueKey(
                            'curated-playlist-queue-add-${track.id}',
                          ),
                          width: 40,
                          height: 40,
                          child: Center(
                            child: Icon(
                              Icons.add_rounded,
                              size: 25,
                              color: tokens.textMuted,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _OfflineNotice extends StatelessWidget {
  const _OfflineNotice({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final tokens = context.musicThemeTokens;
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: .11),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.cloud_off_rounded,
              color: Theme.of(context).colorScheme.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '离线音乐模式',
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontWeight: MusicTypography.bodyWeight,
                    fontSize: MusicTypography.footnoteSize,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  message,
                  style: TextStyle(
                    color: tokens.textSecondary,
                    fontSize: MusicTypography.smallCaptionSize,
                  ),
                ),
              ],
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('重试联网')),
        ],
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.onRetry, this.message = '在线歌单加载失败，请检查网络后重试'});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 36),
        child: Column(
          children: [
            const Icon(Icons.cloud_off_rounded, size: 42),
            const SizedBox(height: 10),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 14),
            FilledButton.tonal(onPressed: onRetry, child: const Text('重新加载')),
          ],
        ),
      ),
    );
  }
}
