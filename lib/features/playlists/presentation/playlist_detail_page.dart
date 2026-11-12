import '../../../shared/widgets/beta_page_motion.dart';
import 'playlist_audit_page.dart';
import '../../music_platform/presentation/song_actions_sheet.dart';
import '../../../shared/widgets/song_list_tools.dart';
import '../../themes/beta_appearance.dart';
import '../../../shared/widgets/artwork_scroll_frontier.dart';
import '../../../shared/widgets/beta_content_insets.dart';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/audio/playback_providers.dart';
import '../../../core/platform/distribution_channel.dart';
import '../../music_platform/presentation/platform_library_page.dart';
import '../../../core/database/app_database.dart';
import '../../../shared/models/track.dart';
import '../../../shared/utils/duration_format.dart';
import '../../../shared/widgets/artwork_image.dart';
import '../../../shared/widgets/liquid_glass_sheet.dart';
import '../../../shared/widgets/mesting_loading_indicator.dart';
import '../../../shared/widgets/music_notice.dart';
import '../../library/library_providers.dart';
import '../../library/presentation/favorite_toggle_button.dart';
import '../../themes/mesting_palette.dart';
import '../../themes/music_theme_tokens.dart';
import 'playlist_editor_dialog.dart';
import '../../player/presentation/beta_playback_actions.dart';
import '../../themes/music_typography.dart';

bool _canPopPlaylistRoute(BuildContext context) =>
    Navigator.maybeOf(context)?.canPop() ?? false;

void _returnToMyPlaylists(BuildContext context) {
  if (_canPopPlaylistRoute(context)) {
    Navigator.of(context).pop();
    return;
  }
  context.go('/music?view=playlists');
}

class PlaylistDetailPage extends ConsumerWidget {
  const PlaylistDetailPage({required this.playlistId, super.key});

  final String playlistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (DistributionChannel.isBeta &&
        (playlistId.startsWith('kg:') || playlistId.startsWith('ne:'))) {
      return PlatformCloudPlaylistPage(id: playlistId);
    }
    final playlist = ref.watch(playlistProvider(playlistId));
    final tracks = ref.watch(playlistTracksProvider(playlistId));
    final favoriteTracks =
        ref.watch(favoriteTracksProvider).value ?? const <Track>[];

    return PopScope<void>(
      canPop: _canPopPlaylistRoute(context),
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _returnToMyPlaylists(context);
      },
      child: playlist.when(
        loading: () => const Center(
          child: MestingLoadingIndicator(
            key: ValueKey('playlist-detail-loading-animation'),
            semanticLabel: '正在加载歌单',
          ),
        ),
        error: (error, stack) => const Center(child: Text('歌单读取失败')),
        data: (item) {
          if (item == null) {
            return Center(
              child: FilledButton(
                onPressed: () => _returnToMyPlaylists(context),
                child: const Text('歌单不存在，返回列表'),
              ),
            );
          }
          final trackList = tracks.value ?? const <Track>[];
          final cover =
              item.coverAsset ??
              (trackList.isEmpty ? null : trackList.first.coverAsset);
          return _PlaylistDetailContent(
            playlist: item,
            cover: cover,
            tracks: tracks,
            onBack: () => _returnToMyPlaylists(context),
            onManage: () => _showPlaylistActions(context, ref, item),
            onPlayAll: trackList.isEmpty
                ? null
                : () => DistributionChannel.isBeta
                      ? playBetaSelection(
                          context,
                          ref,
                          trackList.first,
                          playAll: trackList,
                        )
                      : ref.read(audioHandlerProvider).replaceQueue(trackList),
            onAddTracks: () async {
              try {
                final all = ref.exists(favoriteTrackWindowProvider)
                    ? await ref.read(favoriteTrackWindowProvider).complete()
                    : favoriteTracks;
                if (context.mounted) {
                  _showTrackPicker(context, ref, trackList, all);
                }
              } catch (failure) {
                if (context.mounted) {
                  _showPlaylistNotice(context, '收藏读取未完成，请重试', added: false);
                }
              }
            },
            onReorder: (items, oldIndex, newIndex) {
              final reordered = List<Track>.of(items);
              if (newIndex > oldIndex) newIndex -= 1;
              final moved = reordered.removeAt(oldIndex);
              reordered.insert(newIndex, moved);
              ref
                  .read(libraryRepositoryProvider)
                  .reorderPlaylistTracks(
                    playlistId,
                    reordered.map((track) => track.id).toList(),
                  );
            },
            onPlayTrack: (track) => DistributionChannel.isBeta
                ? playBetaSelection(context, ref, track)
                : ref
                      .read(audioHandlerProvider)
                      .playSingleTrack(track, playbackContext: trackList),
            onAddTrack: (track) => _appendTrack(context, ref, track),
            onRemoveTrack: (track) async {
              await ref
                  .read(libraryRepositoryProvider)
                  .removeTrackFromPlaylist(playlistId, track.id);
              if (context.mounted) {
                _showPlaylistNotice(
                  context,
                  '已移除「${track.title}」',
                  added: false,
                );
              }
            },
          );
        },
      ),
    );
  }

  Future<void> _appendTrack(
    BuildContext context,
    WidgetRef ref,
    Track track,
  ) async {
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
  }

  Future<void> _showPlaylistActions(
    BuildContext context,
    WidgetRef ref,
    UserPlaylist playlist,
  ) async {
    final action = await showLiquidGlassBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      barrierColor: const Color(0x730E0C14),
      builder: (sheetContext) =>
          _PlaylistActionSheet(playlistName: playlist.name),
    );
    if (!context.mounted) return;
    if (action == 'audit') {
      await Navigator.of(context).push(
        betaContentRoute<void>(PlaylistAuditPage(playlistId: playlist.id)),
      );
    } else if (action == 'edit') {
      await _editPlaylist(context, ref, playlist);
    } else if (action == 'delete') {
      await _deletePlaylist(context, ref, playlist.name);
    }
  }

  Future<void> _editPlaylist(
    BuildContext context,
    WidgetRef ref,
    UserPlaylist playlist,
  ) async {
    final repository = ref.read(libraryRepositoryProvider);
    await showPlaylistEditorDialog(
      context,
      initialName: playlist.name,
      initialDescription: playlist.description,
      initialCoverAsset: playlist.coverAsset,
      onSave: (draft) async {
        if (!identical(repository, ref.read(libraryRepositoryProvider))) {
          throw StateError('账号已变化，请重新打开歌单');
        }
        await repository.updatePlaylist(
          id: playlistId,
          name: draft.name,
          description: draft.description,
          coverAsset: draft.coverAsset,
          coverCloudId: draft.coverAsset == playlist.coverAsset
              ? playlist.coverCloudId
              : null,
        );
      },
    );
    ref.invalidate(playlistProvider(playlistId));
  }

  Future<void> _deletePlaylist(
    BuildContext context,
    WidgetRef ref,
    String name,
  ) async {
    final confirmed = await showLiquidGlassBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      barrierColor: const Color(0x730E0C14),
      builder: (dialogContext) => _DeletePlaylistSheet(name: name),
    );
    if (confirmed != true) return;
    await ref.read(libraryRepositoryProvider).deletePlaylist(playlistId);
    if (context.mounted) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (context.mounted) context.go('/music?view=playlists');
    }
  }

  Future<void> _showTrackPicker(
    BuildContext context,
    WidgetRef ref,
    List<Track> currentTracks,
    List<Track> availableTracks,
  ) async {
    final selected = currentTracks.map((track) => track.id).toSet();
    await showLiquidGlassBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      barrierColor: const Color(0x730E0C14),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetBodyContext, setSheetState) => ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetBodyContext).height * .88,
          ),
          child: _TrackPickerSheet(
            tracks: availableTracks,
            selectedIds: selected,
            onClose: () => Navigator.pop(sheetContext),
            onOpenFavorites: () {
              Navigator.pop(sheetContext);
              context.go('/music?view=favorites');
            },
            onToggle: (track) async {
              final included = selected.contains(track.id);
              if (included) {
                await ref
                    .read(libraryRepositoryProvider)
                    .removeTrackFromPlaylist(playlistId, track.id);
                selected.remove(track.id);
              } else {
                await ref
                    .read(libraryRepositoryProvider)
                    .addTrackToPlaylist(playlistId, track);
                selected.add(track.id);
              }
              if (sheetBodyContext.mounted) setSheetState(() {});
              if (context.mounted) {
                _showPlaylistNotice(
                  context,
                  included ? '已移除「${track.title}」' : '✅ 已添加「${track.title}」',
                  added: !included,
                );
              }
            },
          ),
        ),
      ),
    );
  }
}

class _PlaylistDetailContent extends StatelessWidget {
  const _PlaylistDetailContent({
    required this.playlist,
    required this.cover,
    required this.tracks,
    required this.onBack,
    required this.onManage,
    required this.onPlayAll,
    required this.onAddTracks,
    required this.onReorder,
    required this.onPlayTrack,
    required this.onAddTrack,
    required this.onRemoveTrack,
  });

  final UserPlaylist playlist;
  final String? cover;
  final AsyncValue<List<Track>> tracks;
  final VoidCallback onBack;
  final VoidCallback onManage;
  final VoidCallback? onPlayAll;
  final VoidCallback onAddTracks;
  final void Function(List<Track> tracks, int oldIndex, int newIndex) onReorder;
  final ValueChanged<Track> onPlayTrack;
  final Future<void> Function(Track track) onAddTrack;
  final Future<void> Function(Track track) onRemoveTrack;

  @override
  Widget build(BuildContext context) {
    final items = tracks.value ?? const <Track>[];
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: BetaContentInsets.musicPaddingOf(
          context,
          EdgeInsets.fromLTRB(16, 12, 16, 112),
        ),
        child: Column(
          children: [
            _PlaylistTopBar(onBack: onBack, onManage: onManage),
            const SizedBox(height: 13),
            _PlaylistHero(
              playlist: playlist,
              cover: cover,
              trackCount: items.length,
              onPlayAll: onPlayAll,
              onAddTracks: onAddTracks,
            ),
            const SizedBox(height: 20),
            _PlaylistSectionHeading(count: items.length),
            const SizedBox(height: 8),
            Expanded(
              child: tracks.when(
                loading: () => const _PlaylistLoadingState(),
                error: (error, stack) => const _PlaylistMessageState(
                  title: '歌曲暂时无法读取',
                  subtitle: '请稍后再试',
                ),
                data: (trackItems) => trackItems.isEmpty
                    ? _PlaylistEmptyState(onAddTracks: onAddTracks)
                    : ReorderableListView.builder(
                        padding: const EdgeInsets.only(top: 2, bottom: 12),
                        physics: const ArtworkFrontierPhysics(
                          parent: BouncingScrollPhysics(),
                        ),
                        buildDefaultDragHandles: false,
                        itemCount: trackItems.length,
                        onReorder: (oldIndex, newIndex) =>
                            onReorder(trackItems, oldIndex, newIndex),
                        itemBuilder: (context, index) {
                          final track = trackItems[index];
                          return _PlaylistTrackRow(
                            key: ValueKey(track.id),
                            track: track,
                            contextTracks: trackItems,
                            index: index,
                            onTap: () => onPlayTrack(track),
                            onAdd: () => onAddTrack(track),
                            onRemove: () => onRemoveTrack(track),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaylistTopBar extends StatelessWidget {
  const _PlaylistTopBar({required this.onBack, required this.onManage});

  final VoidCallback onBack;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final tokens = context.musicThemeTokens;
    return Row(
      children: [
        _CircleActionButton(
          tooltip: '返回我的歌单',
          icon: Icons.arrow_back_ios_new_rounded,
          onTap: onBack,
        ),
        Expanded(
          child: Column(
            children: [
              Text(
                'PERSONAL PLAYLIST',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontSize: MusicTypography.smallCaptionSize,
                  letterSpacing: 2.2,
                  fontWeight: MusicTypography.bodyWeight,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '歌单详情',
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: MusicTypography.bodySize,
                  fontWeight: MusicTypography.titleWeight,
                ),
              ),
            ],
          ),
        ),
        _CircleActionButton(
          tooltip: '管理歌单',
          icon: Icons.more_horiz_rounded,
          onTap: onManage,
        ),
      ],
    );
  }
}

class _PlaylistHero extends StatelessWidget {
  const _PlaylistHero({
    required this.playlist,
    required this.cover,
    required this.trackCount,
    required this.onPlayAll,
    required this.onAddTracks,
  });

  final UserPlaylist playlist;
  final String? cover;
  final int trackCount;
  final VoidCallback? onPlayAll;
  final VoidCallback onAddTracks;

  @override
  Widget build(BuildContext context) {
    final tokens = context.musicThemeTokens;
    final accent = Theme.of(context).colorScheme.primary;
    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: Stack(
        children: [
          Positioned.fill(child: ColoredBox(color: tokens.glassStrong)),
          if (cover != null)
            Positioned.fill(
              child: Opacity(
                opacity: .22,
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                  child: Transform.scale(
                    scale: 1.22,
                    child: ArtworkImage(uri: cover!, width: 560, height: 250),
                  ),
                ),
              ),
            ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    tokens.glassStrong.withValues(alpha: .82),
                    Color.alphaBlend(
                      accent.withValues(alpha: .14),
                      tokens.glassStrong.withValues(alpha: .93),
                    ),
                  ],
                ),
                border: Border.all(color: tokens.borderStrong),
                borderRadius: BorderRadius.circular(30),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _PlaylistCover(cover: cover, accent: accent),
                    const SizedBox(width: 16),
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
                              fontSize: MusicTypography.titleSize,
                              height: 1.05,
                              fontWeight: MusicTypography.titleWeight,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            playlist.description.isEmpty
                                ? '收藏此刻喜欢的声音'
                                : playlist.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: tokens.textSecondary,
                              fontSize: MusicTypography.captionSize,
                              height: 1.4,
                              fontWeight: MusicTypography.bodyWeight,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _PlaylistMetaPill(trackCount: trackCount),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 17),
                Row(
                  children: [
                    Expanded(
                      flex: 6,
                      child: _PlaylistHeroAction(
                        label: '播放全部',
                        red: true,
                        icon: Icons.play_arrow_rounded,
                        onTap: onPlayAll,
                        emphasized: true,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 5,
                      child: _PlaylistHeroAction(
                        label: '添加歌曲',
                        icon: Icons.add_rounded,
                        onTap: onAddTracks,
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

class _PlaylistCover extends StatelessWidget {
  const _PlaylistCover({required this.cover, required this.accent});

  final String? cover;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 112,
      height: 112,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: .9),
            accent.withValues(alpha: .5),
          ],
        ),
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .16),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(23),
        child: cover == null
            ? DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      accent.withValues(alpha: .36),
                      accent.withValues(alpha: .12),
                    ],
                  ),
                ),
                child: const Center(
                  child: Icon(Icons.music_note_rounded, size: 40),
                ),
              )
            : ArtworkImage(uri: cover!, width: 106, height: 106),
      ),
    );
  }
}

class _PlaylistMetaPill extends StatelessWidget {
  const _PlaylistMetaPill({required this.trackCount});

  final int trackCount;

  @override
  Widget build(BuildContext context) {
    final tokens = context.musicThemeTokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: tokens.glassSubtle,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tokens.border),
      ),
      child: Text(
        '$trackCount 首',
        key: const ValueKey('playlist-hero-track-count'),
        style: TextStyle(
          color: tokens.textSecondary,
          fontSize: MusicTypography.smallCaptionSize,
          fontWeight: MusicTypography.bodyWeight,
        ),
      ),
    );
  }
}

class _PlaylistHeroAction extends StatelessWidget {
  const _PlaylistHeroAction({
    required this.label,
    required this.icon,
    required this.onTap,
    this.emphasized = false,
    this.red = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool emphasized, red;

  @override
  Widget build(BuildContext context) {
    final tokens = context.musicThemeTokens;
    final enabled = onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: Opacity(
        opacity: enabled ? 1 : .42,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(17),
            child: Ink(
              key: ValueKey(
                'playlist-hero-action-${emphasized ? 'primary' : 'secondary'}',
              ),
              height: 48,
              decoration: BoxDecoration(
                color: emphasized
                    ? (DistributionChannel.isBeta
                          ? red
                                ? BetaAppearance.playbackAction(
                                    Theme.of(context).brightness,
                                  )
                                : Theme.of(context).colorScheme.primary
                          : MestingPalette.heart)
                    : tokens.glassSubtle,
                borderRadius: BorderRadius.circular(17),
                border: Border.all(
                  color: emphasized
                      ? Colors.white.withValues(alpha: .22)
                      : tokens.borderStrong,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: 19,
                    color: emphasized
                        ? (DistributionChannel.isBeta
                              ? Theme.of(context).colorScheme.onPrimary
                              : Colors.white)
                        : tokens.textPrimary,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    label,
                    style: TextStyle(
                      color: emphasized
                          ? (DistributionChannel.isBeta
                                ? Theme.of(context).colorScheme.onPrimary
                                : Colors.white)
                          : tokens.textPrimary,
                      fontSize: MusicTypography.footnoteSize,
                      fontWeight: MusicTypography.bodyWeight,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlaylistSectionHeading extends StatelessWidget {
  const _PlaylistSectionHeading({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final tokens = context.musicThemeTokens;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '歌曲列表',
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: MusicTypography.headingSize,
                  fontWeight: MusicTypography.titleWeight,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                count > 1 ? '长按歌曲可调整播放顺序' : '把喜欢的音乐收进这里',
                style: TextStyle(
                  color: tokens.textMuted,
                  fontSize: MusicTypography.smallCaptionSize,
                ),
              ),
            ],
          ),
        ),
        Text(
          '$count 首',
          key: const ValueKey('playlist-section-track-count'),
          style: TextStyle(
            color: tokens.textSecondary,
            fontSize: MusicTypography.smallCaptionSize,
            fontWeight: MusicTypography.bodyWeight,
          ),
        ),
      ],
    );
  }
}

class _PlaylistEmptyState extends StatelessWidget {
  const _PlaylistEmptyState({required this.onAddTracks});

  final VoidCallback onAddTracks;

  @override
  Widget build(BuildContext context) {
    final tokens = context.musicThemeTokens;
    final accent = Theme.of(context).colorScheme.primary;
    return Center(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        decoration: BoxDecoration(
          color: tokens.glassSubtle,
          borderRadius: BorderRadius.circular(25),
          border: Border.all(color: tokens.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 54,
              height: 54,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accent.withValues(alpha: .12),
              ),
              child: Icon(Icons.music_note_rounded, color: accent, size: 28),
            ),
            const SizedBox(height: 13),
            Text(
              '这张歌单还没有声音',
              style: TextStyle(
                color: tokens.textPrimary,
                fontSize: MusicTypography.calloutSize,
                fontWeight: MusicTypography.bodyWeight,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              '添加几首喜欢的歌曲，慢慢整理成自己的音乐空间',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: tokens.textSecondary,
                fontSize: MusicTypography.smallCaptionSize,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: 150,
              child: _PlaylistHeroAction(
                label: '添加第一首歌',
                icon: Icons.add_rounded,
                onTap: onAddTracks,
                emphasized: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaylistLoadingState extends StatelessWidget {
  const _PlaylistLoadingState();

  @override
  Widget build(BuildContext context) => const Center(
    child: MestingLoadingIndicator(
      key: ValueKey('playlist-tracks-loading-animation'),
      size: 64,
      semanticLabel: '正在加载歌单歌曲',
    ),
  );
}

class _PlaylistMessageState extends StatelessWidget {
  const _PlaylistMessageState({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final tokens = context.musicThemeTokens;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: TextStyle(
              color: tokens.textPrimary,
              fontSize: MusicTypography.subheadlineSize,
              fontWeight: MusicTypography.bodyWeight,
            ),
          ),
          const SizedBox(height: 5),
          Text(subtitle, style: TextStyle(color: tokens.textSecondary)),
        ],
      ),
    );
  }
}

void _showPlaylistNotice(
  BuildContext context,
  String message, {
  required bool added,
}) {
  showMusicNotice(
    context,
    icon: added ? Icons.check_rounded : Icons.remove_circle_outline,
    title: message,
    message: '',
  );
}

class _CircleActionButton extends StatelessWidget {
  const _CircleActionButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.musicThemeTokens;
    return Tooltip(
      message: tooltip,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: tokens.glassStrong,
          border: Border.all(color: tokens.borderStrong),
        ),
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: 46,
              height: 46,
              child: Icon(icon, color: tokens.textPrimary, size: 24),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlaylistTrackRow extends StatelessWidget {
  const _PlaylistTrackRow({
    required this.track,
    required this.contextTracks,
    required this.index,
    required this.onTap,
    required this.onAdd,
    required this.onRemove,
    super.key,
  });

  final Track track;
  final List<Track> contextTracks;
  final int index;
  final VoidCallback onTap;
  final Future<void> Function() onAdd;
  final Future<void> Function() onRemove;

  @override
  Widget build(BuildContext context) {
    final tokens = context.musicThemeTokens;
    final radius = BorderRadius.circular(22);
    return SongListEntry(
      track: track,
      tracks: contextTracks,
      child: ReorderableDelayedDragStartListener(
        index: index,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: radius,
              boxShadow: [
                BoxShadow(
                  color: tokens.shadow.withValues(alpha: .42),
                  blurRadius: 16,
                  offset: const Offset(0, 7),
                ),
              ],
            ),
            child: Material(
              key: ValueKey('playlist-track-surface-${track.id}'),
              color: tokens.glassStrong.withValues(alpha: .86),
              shape: RoundedRectangleBorder(
                borderRadius: radius,
                side: BorderSide(color: tokens.borderStrong),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () {
                  SongListTools.remember(context, track);
                  onTap();
                },
                borderRadius: radius,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 10, 9, 10),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 54,
                        height: 54,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(15),
                              child: ArtworkImage(
                                uri: track.coverAsset,
                                width: 54,
                                height: 54,
                              ),
                            ),
                            Positioned(
                              left: -3,
                              bottom: -3,
                              child: Container(
                                width: 21,
                                height: 21,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: tokens.glassStrong,
                                  border: Border.all(
                                    color: tokens.borderStrong,
                                  ),
                                ),
                                child: Text(
                                  '${index + 1}'.padLeft(2, '0'),
                                  style: TextStyle(
                                    color: tokens.textSecondary,
                                    fontSize: MusicTypography.smallCaptionSize,
                                    fontWeight: MusicTypography.bodyWeight,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              track.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: tokens.textPrimary,
                                fontSize: MusicTypography.subheadlineSize,
                                fontWeight: MusicTypography.bodyWeight,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${track.artist}  ·  ${formatDuration(track.duration)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: tokens.textSecondary,
                                fontSize: MusicTypography.captionSize,
                                fontWeight: MusicTypography.bodyWeight,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 38,
                        height: 38,
                        child: FavoriteToggleButton(
                          track: track,
                          compact: true,
                        ),
                      ),
                      if (DistributionChannel.isBeta)
                        SongActionsButton(
                          track: track,
                          extras: [
                            SongMenuExtraAction(
                              '从歌单移除',
                              Icons.remove_circle_outline,
                              onRemove,
                              destructive: true,
                            ),
                          ],
                        ),
                      const SizedBox(width: 5),
                      if (!DistributionChannel.isBeta)
                        _TrackActionButton(
                          tooltip: '从歌单移除',
                          icon: Icons.remove_rounded,
                          onTap: onRemove,
                        ),
                      const SizedBox(width: 5),
                      if (!DistributionChannel.isBeta)
                        _TrackActionButton(
                          tooltip: '添加至播放列表',
                          icon: Icons.add_rounded,
                          onTap: onAdd,
                          positive: true,
                        ),
                    ],
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

class _TrackActionButton extends StatelessWidget {
  const _TrackActionButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
    this.positive = false,
  });

  final String tooltip;
  final IconData icon;
  final Future<void> Function() onTap;
  final bool positive;

  @override
  Widget build(BuildContext context) {
    final tokens = context.musicThemeTokens;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Ink(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: positive
                ? Color.alphaBlend(const Color(0x142FAD72), tokens.glassStrong)
                : const Color(0x12C24A34),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: positive
                  ? const Color(0x4A36B678)
                  : const Color(0x2EC24A34),
            ),
          ),
          child: Icon(
            icon,
            color: positive ? const Color(0xFF38B879) : const Color(0xFFC24A34),
            size: 20,
          ),
        ),
      ),
    );
  }
}

class _PlaylistActionSheet extends StatelessWidget {
  const _PlaylistActionSheet({required this.playlistName});

  final String playlistName;

  @override
  Widget build(BuildContext context) {
    final tokens = context.musicThemeTokens;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Material(
              color: tokens.glassStrong,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '管理歌单',
                      style: TextStyle(
                        color: tokens.textPrimary,
                        fontSize: MusicTypography.sectionTitleSize,
                        fontWeight: MusicTypography.titleWeight,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      playlistName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: tokens.textSecondary),
                    ),
                    const SizedBox(height: 16),
                    _ActionSheetTile(
                      icon: Icons.fact_check_outlined,
                      title: '歌单体检',
                      caption: '核对重复歌曲与本地文件',
                      onTap: () => Navigator.pop(context, 'audit'),
                    ),
                    const SizedBox(height: 9),
                    _ActionSheetTile(
                      icon: Icons.edit_rounded,
                      title: '编辑歌单',
                      caption: '修改名称、简介与封面',
                      onTap: () => Navigator.pop(context, 'edit'),
                    ),
                    const SizedBox(height: 9),
                    _ActionSheetTile(
                      icon: Icons.delete_outline_rounded,
                      title: '删除歌单',
                      caption: '歌曲文件与收藏不会被删除',
                      destructive: true,
                      onTap: () => Navigator.pop(context, 'delete'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionSheetTile extends StatelessWidget {
  const _ActionSheetTile({
    required this.icon,
    required this.title,
    required this.caption,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final String caption;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final tokens = context.musicThemeTokens;
    final accent = destructive
        ? const Color(0xFFC24A34)
        : Theme.of(context).colorScheme.primary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Color.alphaBlend(
              accent.withValues(alpha: .08),
              tokens.glassSubtle,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: accent.withValues(alpha: .16)),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: .13),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(icon, color: accent),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: destructive ? accent : tokens.textPrimary,
                        fontSize: MusicTypography.subheadlineSize,
                        fontWeight: MusicTypography.bodyWeight,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      caption,
                      style: TextStyle(
                        color: tokens.textSecondary,
                        fontSize: MusicTypography.captionSize,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: tokens.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeletePlaylistSheet extends StatelessWidget {
  const _DeletePlaylistSheet({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final tokens = context.musicThemeTokens;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        child: Container(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
          decoration: BoxDecoration(
            color: tokens.glassStrong,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: tokens.borderStrong),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.delete_sweep_rounded,
                color: Color(0xFFC24A34),
                size: 38,
              ),
              const SizedBox(height: 12),
              Text(
                '删除「$name」？',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: MusicTypography.headingSize,
                  fontWeight: MusicTypography.titleWeight,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                '只删除歌单，歌曲文件和收藏不会受到影响。',
                textAlign: TextAlign.center,
                style: TextStyle(color: tokens.textSecondary),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: _SheetButton(
                      label: '先保留',
                      onTap: () => Navigator.pop(context, false),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _SheetButton(
                      label: '确认删除',
                      destructive: true,
                      onTap: () => Navigator.pop(context, true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrackPickerSheet extends StatelessWidget {
  const _TrackPickerSheet({
    required this.tracks,
    required this.selectedIds,
    required this.onToggle,
    required this.onClose,
    required this.onOpenFavorites,
  });

  final List<Track> tracks;
  final Set<String> selectedIds;
  final Future<void> Function(Track track) onToggle;
  final VoidCallback onClose;
  final VoidCallback onOpenFavorites;

  @override
  Widget build(BuildContext context) {
    final tokens = context.musicThemeTokens;
    final includedTracks = <Track>[];
    final availableTracks = <Track>[];
    for (final track in tracks) {
      (selectedIds.contains(track.id) ? includedTracks : availableTracks).add(
        track,
      );
    }
    final orderedTracks = [...includedTracks, ...availableTracks];

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
        child: Material(
          key: const ValueKey('favorite-track-picker'),
          color: tokens.glassStrong,
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 14, 10),
                  child: Row(
                    children: [
                      Container(
                        width: 45,
                        height: 45,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: const Color(0x18745CC7),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(
                          Icons.playlist_add_rounded,
                          color: Color(0xFF745CC7),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '从我的喜欢添加',
                              style: TextStyle(
                                color: tokens.textPrimary,
                                fontSize: MusicTypography.sectionTitleSize,
                                fontWeight: MusicTypography.titleWeight,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '仅显示已收藏歌曲 · 歌单内 ${selectedIds.length} 首',
                              style: TextStyle(
                                color: tokens.textSecondary,
                                fontSize: MusicTypography.captionSize,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _CircleActionButton(
                        tooltip: '关闭',
                        icon: Icons.close_rounded,
                        onTap: onClose,
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: tokens.border),
                Flexible(
                  fit: FlexFit.loose,
                  child: tracks.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(28),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 70,
                                height: 70,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: const Color(0x18745CC7),
                                  borderRadius: BorderRadius.circular(24),
                                ),
                                child: const Icon(
                                  Icons.favorite_border_rounded,
                                  color: Color(0xFF745CC7),
                                  size: 32,
                                ),
                              ),
                              const SizedBox(height: 18),
                              Text(
                                '还没有收藏歌曲',
                                style: TextStyle(
                                  color: tokens.textPrimary,
                                  fontSize: MusicTypography.bodySize,
                                  fontWeight: MusicTypography.titleWeight,
                                ),
                              ),
                              const SizedBox(height: 7),
                              Text(
                                '先把喜欢的歌曲加入“我的喜欢”\n再回来整理自己的歌单',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: tokens.textSecondary,
                                  height: 1.6,
                                  fontWeight: MusicTypography.titleWeight,
                                ),
                              ),
                              const SizedBox(height: 18),
                              _SheetButton(
                                label: '去我的喜欢',
                                emphasized: true,
                                onTap: onOpenFavorites,
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                          itemCount: orderedTracks.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final track = orderedTracks[index];
                            final included = selectedIds.contains(track.id);
                            return _TrackPickerRow(
                              track: track,
                              included: included,
                              onTap: () => onToggle(track),
                            );
                          },
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 34),
                  child: _SheetButton(
                    label: '完成 · 已选 ${selectedIds.length} 首',
                    emphasized: true,
                    onTap: onClose,
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

class _TrackPickerRow extends StatelessWidget {
  const _TrackPickerRow({
    required this.track,
    required this.included,
    required this.onTap,
  });

  final Track track;
  final bool included;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.musicThemeTokens;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: included
            ? Color.alphaBlend(const Color(0x15745CC7), tokens.glassSubtle)
            : tokens.glassSubtle,
        borderRadius: BorderRadius.circular(19),
        border: Border.all(
          color: included ? const Color(0x55745CC7) : tokens.border,
        ),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(13),
            child: ArtworkImage(uri: track.coverAsset, width: 54, height: 54),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontSize: MusicTypography.subheadlineSize,
                    fontWeight: MusicTypography.bodyWeight,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${track.artist}  ·  ${formatDuration(track.duration)}',
                  style: TextStyle(
                    color: tokens.textSecondary,
                    fontSize: MusicTypography.captionSize,
                    fontWeight: MusicTypography.bodyWeight,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              customBorder: const CircleBorder(),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 43,
                height: 43,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: included
                      ? const Color(0xFF745CC7)
                      : tokens.glassStrong,
                  border: Border.all(
                    color: included
                        ? const Color(0xFF745CC7)
                        : tokens.borderStrong,
                  ),
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 160),
                  transitionBuilder: (child, animation) =>
                      ScaleTransition(scale: animation, child: child),
                  child: Icon(
                    included ? Icons.check_rounded : Icons.add_rounded,
                    key: ValueKey(included),
                    color: included ? Colors.white : tokens.textPrimary,
                    size: 24,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetButton extends StatelessWidget {
  const _SheetButton({
    required this.label,
    required this.onTap,
    this.emphasized = false,
    this.destructive = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool emphasized;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final tokens = context.musicThemeTokens;
    final accent = destructive
        ? const Color(0xFFC24A34)
        : Theme.of(context).colorScheme.primary;
    final filled = emphasized || destructive;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(17),
        child: Ink(
          height: 52,
          decoration: BoxDecoration(
            color: filled ? accent : tokens.glassSubtle,
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: filled ? accent : tokens.borderStrong),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: filled ? Colors.white : tokens.textPrimary,
                fontSize: MusicTypography.subheadlineSize,
                fontWeight: MusicTypography.bodyWeight,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
