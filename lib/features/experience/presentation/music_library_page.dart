import '../../../shared/widgets/artwork_scroll_frontier.dart';
import '../../../shared/widgets/beta_content_insets.dart';
import '../../../shared/widgets/music_refresh_indicator.dart';
import '../../music_platform/music_platform_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../history/listening_history_providers.dart';
import '../../library/library_providers.dart';
import '../../music_platform/data/cloud_library_repository.dart';
import '../../music_platform/platform_backend_providers.dart';
import '../../music_platform/netease/netease_features_page.dart';
import '../../music_platform/netease/netease_library_sections.dart';
import '../../downloads/audio_downloads_page.dart';
import '../../music_platform/presentation/platform_design.dart';
import '../../playlists/presentation/playlist_editor_dialog.dart';
import '../../../shared/models/track.dart';
import '../../../shared/widgets/track_artwork.dart';
import '../../themes/music_theme_tokens.dart';
import '../../themes/beta_appearance.dart';
import 'editorial_widgets.dart';
import '../../player/presentation/beta_playback_actions.dart';
import '../../library/presentation/library_access.dart';

/// One collection shell for Kugou, Mesting and guest. Ownership is supplied by
/// libraryRepositoryProvider, and no UI branch copies data between accounts.
class MusicLibraryPage extends ConsumerWidget {
  const MusicLibraryPage({this.view, super.key});
  final String? view;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repository = ref.watch(libraryRepositoryProvider);
    final cloud = repository is CloudLibraryRepository;
    final favorites = ref.watch(favoriteTracksProvider);
    final playlists = ref.watch(playlistsProvider);
    final recent = ref.watch(recentPlaybackProvider);
    if (view == 'favorites' || view == 'recent') {
      final value = view == 'favorites'
          ? favorites
          : recent.whenData(
              (items) => items.map((item) => item.track).toList(),
            );
      return PlatformStyle(
        child: value.when(
          loading: () => const PlatformFeedbackState(loading: true),
          error: (_, _) => EditorialEmpty(
            '歌曲暂时无法读取',
            onRetry: () => repository.synchronize(forcePull: true),
          ),
          data: (tracks) => MusicRefreshIndicator(
            onRefresh: () => repository.synchronize(forcePull: true),
            child: ListView.builder(
              padding: EdgeInsets.only(
                top: MediaQuery.paddingOf(context).top + 14,
                bottom: BetaContentInsets.musicBottomOf(
                  context,
                  editorialBottomClearance,
                ),
              ),
              physics: const ArtworkFrontierPhysics(
                parent: AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
              ),
              itemCount: tracks.length + 2,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return EditorialHeader(
                    view == 'favorites' ? '我的喜欢' : '最近播放',
                    back: true,
                    trailing: IconButton(
                      tooltip: '新建歌单',
                      onPressed: () => createEditorialPlaylist(context, ref),
                      icon: const Icon(Icons.add_circle_outline_rounded),
                    ),
                  );
                }
                if (index == 1) {
                  return _CollectionTracks(
                    tracks: tracks,
                    headerOnly: true,
                    empty: view == 'favorites'
                        ? '还没有收藏，点亮爱心留住喜欢的歌。'
                        : '播放一首歌后，在这里继续聆听。',
                  );
                }
                return EditorialTrackRow(
                  track: tracks[index - 2],
                  contextTracks: tracks,
                );
              },
            ),
          ),
        ),
      );
    }
    return PlatformStyle(
      child: EditorialScroll(
        onRefresh: () async {
          await repository.synchronize(forcePull: true);
        },
        children: [
          EditorialHeader(
            switch (view) {
              'favorites' => '我的喜欢',
              'playlists' => '我的歌单',
              'recent' => '最近播放',
              _ => '音乐库',
            },
            back: view != null,
            trailing: IconButton(
              tooltip: '新建歌单',
              onPressed: () => createEditorialPlaylist(context, ref),
              icon: Icon(
                Icons.add_circle_outline_rounded,
                color: Theme.of(context).colorScheme.primary,
                size: 29,
              ),
            ),
          ),
          if (view == null) ...[
            const EditorialSection('常用音乐'),
            _LibraryLink(
              icon: Icons.favorite_rounded,
              tone: BetaFeatureTone.music,
              title: '我的喜欢',
              subtitle: cloud
                  ? '${ref.watch(platformAccountProvider).value?.platformLabel ?? '音乐'}云端收藏'
                  : '${favorites.value?.length ?? 0} 首歌曲',
              onTap: () => context.push('/music?view=favorites'),
            ),
            _LibraryLink(
              icon: Icons.download_rounded,
              tone: BetaFeatureTone.downloads,
              title: '已下载',
              subtitle: '离线播放、导出与下载任务',
              onTap: () => openAudioDownloads(context, downloadedOnly: true),
            ),
            if (ref.watch(usesNeteaseProvider)) ...[
              const NeteaseLibraryLinks(section: NeteaseLibrarySection.common),
              const EditorialSection('收藏与订阅'),
              const NeteaseLibraryLinks(
                section: NeteaseLibrarySection.collections,
              ),
            ],
            const EditorialSection('播放足迹'),
            _LibraryLink(
              icon: Icons.history_rounded,
              tone: BetaFeatureTone.insights,
              title: '最近播放',
              subtitle: '接着上一次的旋律',
              onTap: () => context.push('/music/library?view=recent'),
            ),
            _LibraryLink(
              icon: Icons.insights_rounded,
              tone: BetaFeatureTone.insights,
              title: '听歌回顾',
              subtitle: '你的每月与年度音乐足迹',
              onTap: () => context.push('/music/replay'),
            ),
            if (ref.watch(usesNeteaseProvider))
              const NeteaseLibraryLinks(section: NeteaseLibrarySection.history),
            EditorialSection(
              '我的歌单',
              onTap: () => context.push('/music?view=playlists'),
            ),
          ],
          playlists.when(
            loading: () => const PlatformFeedbackState(loading: true),
            error: (_, _) => EditorialEmpty(
              '歌单暂时无法加载',
              onRetry: () => ref.invalidate(playlistsProvider),
            ),
            data: (items) => items.isEmpty
                ? const EditorialEmpty('还没有歌单。\n点右上角的加号，为一段心情取个名字。')
                : Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 22),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final columns = constraints.maxWidth >= 650 ? 4 : 2;
                        final width =
                            (constraints.maxWidth - (columns - 1) * 16) /
                            columns;
                        return Wrap(
                          spacing: 16,
                          runSpacing: 24,
                          children: [
                            for (final list in items)
                              EditorialCover(
                                cover: list.coverAsset ?? '',
                                title: list.name,
                                subtitle: cloud
                                    ? '${ref.watch(platformAccountProvider).value?.platformLabel ?? '音乐'}云端歌单'
                                    : '我的歌单',
                                width: width,
                                onTap: () => context.push(
                                  '/music/playlists/${Uri.encodeComponent(list.id)}',
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
          ),
          if (view == null && ref.watch(usesNeteaseProvider)) ...[
            const NeteaseLibraryLinks(section: NeteaseLibrarySection.playlists),
            const NeteaseLibraryLinks(section: NeteaseLibrarySection.other),
          ],
        ],
      ),
    );
  }
}

class _LibraryLink extends StatelessWidget {
  const _LibraryLink({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.tone = BetaFeatureTone.action,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final BetaFeatureTone tone;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        children: [
          Icon(icon, color: BetaAppearance.feature(context, tone), size: 26),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: context.musicThemeTokens.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: context.musicThemeTokens.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right_rounded,
            color: context.musicThemeTokens.textMuted,
          ),
        ],
      ),
    ),
  );
}

class _CollectionTracks extends ConsumerWidget {
  const _CollectionTracks({
    required this.tracks,
    required this.empty,
    this.headerOnly = false,
  });
  final List<Track> tracks;
  final String empty;
  final bool headerOnly;
  @override
  Widget build(BuildContext context, WidgetRef ref) => tracks.isEmpty
      ? EditorialEmpty(empty)
      : Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 24),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: TrackArtwork(
                      track: tracks.first,
                      width: 112,
                      height: 112,
                    ),
                  ),
                  const SizedBox(width: 22),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${tracks.length} 首歌曲',
                          style: TextStyle(
                            color: context.musicThemeTokens.textSecondary,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: () => playBetaSelection(
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
                  ),
                ],
              ),
            ),
            if (!headerOnly)
              for (final track in tracks)
                EditorialTrackRow(track: track, contextTracks: tracks),
          ],
        );
}

/// The repository is captured before opening the editor. If the active owner
/// changes while a user edits, saving stops rather than writing to either user.
Future<void> createEditorialPlaylist(
  BuildContext context,
  WidgetRef ref,
) async {
  if (!await ensureLibraryAccess(
        context,
        ref,
        reason: '登录后才能创建自己的歌单',
        redirect: '/music/library',
      ) ||
      !context.mounted) {
    return;
  }
  final repository = ref.read(libraryRepositoryProvider);
  final draftId = 'playlist_${DateTime.now().microsecondsSinceEpoch}';
  await showPlaylistEditorDialog(
    context,
    onSave: (draft) async {
      if (!identical(ref.read(libraryRepositoryProvider), repository)) {
        throw StateError('账号已变化，请返回后重新创建');
      }
      await repository.createPlaylist(
        id: draftId,
        name: draft.name,
        description: draft.description,
        coverAsset: draft.coverAsset,
      );
    },
  );
}
