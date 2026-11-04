import '../../../shared/widgets/beta_content_insets.dart';
import '../../../shared/widgets/music_refresh_indicator.dart';
import '../../../shared/widgets/automatic_song_paging.dart';
import '../../../shared/widgets/music_list_footer.dart';
import 'package:flutter/cupertino.dart';
import '../../../shared/widgets/beta_popup_menu_button.dart';
import '../music_platform_providers.dart';
import '../../player/presentation/beta_playback_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/app_database.dart';
import '../../../core/audio/playback_providers.dart';
import '../../library/presentation/music_home_page.dart';
import '../../library/library_providers.dart';
import '../../player/presentation/music_hub_top_bar.dart';
import '../data/cloud_library_repository.dart';
import 'platform_discovery_page.dart';
import 'platform_feedback.dart';
import 'platform_comments_page.dart';
import 'platform_design.dart';
import '../../experience/presentation/music_library_page.dart';
import '../../playlists/presentation/playlist_editor_dialog.dart';
import '../../experience/presentation/editorial_widgets.dart';

Future<void> createPlatformPlaylist(BuildContext context, WidgetRef ref) async {
  await createEditorialPlaylist(context, ref);
}

class PlatformLibraryPage extends ConsumerWidget {
  const PlatformLibraryPage({required this.favorites, super.key});
  final bool favorites;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repository = ref.watch(libraryRepositoryProvider);
    return PlatformStyle(
      child: MusicRefreshIndicator(
        onRefresh: () async {
          await repository.synchronize(forcePull: true);
        },
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
              title: favorites ? '我的喜欢' : '我的歌单',
              subtitle:
                  '${ref.watch(platformAccountProvider).value?.platformLabel ?? '音乐'}云端曲库',
              showBack: true,
              onBack: () =>
                  context.canPop() ? context.pop() : context.go('/profile'),
            ),
            const SizedBox(height: 20),
            if (favorites)
              ref
                  .watch(favoriteTracksProvider)
                  .when(
                    loading: () => const PlatformFeedbackState(loading: true),
                    error: (error, stack) => PlatformFeedbackState(
                      message: '云端收藏暂时无法加载',
                      retry: () => repository.synchronize(forcePull: true),
                    ),
                    data: (tracks) => FavoriteCollectionView(
                      tracks: tracks,
                      currentTrackId: ref
                          .watch(currentMediaItemProvider)
                          .value
                          ?.id,
                      playing:
                          ref.watch(playbackStateProvider).value?.playing ??
                          false,
                      onPlayAll: tracks.isEmpty
                          ? null
                          : () => playBetaSelection(
                              context,
                              ref,
                              tracks.first,
                              playAll: tracks,
                            ),
                      onPlayTrack: (track) =>
                          playBetaSelection(context, ref, track),
                      onAddTrack: (track) => ref
                          .read(audioHandlerProvider)
                          .appendToUpcomingQueue(track),
                      onExplore: () => context.push('/music/search'),
                    ),
                  )
            else ...[
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: () => createPlatformPlaylist(context, ref),
                  icon: const Icon(Icons.add),
                  label: const Text('新建歌单'),
                ),
              ),
              ref
                  .watch(playlistsProvider)
                  .when(
                    loading: () => const PlatformFeedbackState(loading: true),
                    error: (error, stack) => TextButton.icon(
                      onPressed: () => repository.synchronize(forcePull: true),
                      icon: const Icon(Icons.refresh),
                      label: const Text('云端歌单加载失败，点击重试'),
                    ),
                    data: (items) => items.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.all(24),
                            child: Text('当前平台账号中还没有歌单'),
                          )
                        : MyPlaylistsCollectionView(playlists: items),
                  ),
            ],
          ],
        ),
      ),
    );
  }
}

class PlatformCloudPlaylistPage extends ConsumerWidget {
  const PlatformCloudPlaylistPage({required this.id, super.key});
  final String id;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repository = ref.watch(libraryRepositoryProvider);
    if (repository is! CloudLibraryRepository) {
      return Center(
        child: TextButton(
          onPressed: () => context.go('/profile'),
          child: const Text('当前账号已退出，返回我的'),
        ),
      );
    }
    final playlist = ref.watch(playlistProvider(id));
    final value = ref.watch(playlistTracksProvider(id));
    final window = ref.exists(playlistTrackWindowProvider(id))
        ? ref.watch(playlistTrackWindowProvider(id))
        : null;
    return PlatformPageFrame(
      title: playlist.value?.name ?? '云端歌单',
      subtitle:
          '${ref.watch(platformAccountProvider).value?.platformLabel ?? ''}云端歌单',
      actions: [
        IconButton(
          tooltip: '歌单评论',
          icon: const Icon(Icons.comment_outlined),
          onPressed: () async {
            try {
              final commentId = await repository.commentId(id);
              if (context.mounted) {
                openPlatformPlaylistComments(
                  context,
                  ref,
                  id: commentId,
                  name: playlist.value?.name ?? '歌单',
                );
              }
            } catch (error) {
              if (context.mounted) showPlatformFailure(context, error);
            }
          },
        ),
        if (playlist.value != null && repository.canManage(id))
          BetaPopupMenuButton<String>(
            onSelected: (action) =>
                _manage(context, ref, repository, playlist.value!, action),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'rename', child: Text('编辑名称与封面')),
              PopupMenuItem(value: 'delete', child: Text('删除歌单')),
            ],
          ),
      ],
      child: MusicRefreshIndicator(
        onRefresh: () async {
          await repository.synchronize(forcePull: true);
          ref.invalidate(playlistProvider(id));
        },
        child: ListenableBuilder(
          listenable: window ?? const AlwaysStoppedAnimation(0),
          builder: (context, _) => AutomaticSongPaging(
            songListId: 'cloud-playlist:$id',
            enabled:
                window != null &&
                window.hasMore &&
                !window.loading &&
                window.error == null,
            onLoadMore: () => window?.loadMore() ?? Future.value(),
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                if (playlist.hasValue)
                  SliverToBoxAdapter(
                    child: EditorialCollectionHero(
                      cover: playlist.value?.coverAsset ?? '',
                      description: playlist.value?.description ?? '',
                      tracks: value.value ?? const [],
                      total: window?.total,
                      loadComplete: window?.complete,
                    ),
                  ),
                PlatformSongs(
                  sliver: true,
                  value: value,
                  retry: () => repository.synchronize(forcePull: true),
                  playlistId: repository.canManage(id) ? id : null,
                ),
                SliverToBoxAdapter(
                  child: window?.loading == true
                      ? const PlatformFeedbackState(loading: true)
                      : window?.error != null
                      ? TextButton(
                          onPressed: window!.loadMore,
                          child: const Text('加载未完成，点击重试'),
                        )
                      : window?.hasMore == true
                      ? const SizedBox(height: 12)
                      : const MusicListEnd(),
                ),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: BetaContentInsets.musicBottomOf(
                      context,
                      editorialBottomClearance,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _manage(
    BuildContext context,
    WidgetRef ref,
    CloudLibraryRepository repository,
    UserPlaylist playlist,
    String action,
  ) async {
    try {
      if (action == 'rename') {
        await showPlaylistEditorDialog(
          context,
          initialName: playlist.name,
          initialDescription: playlist.description,
          initialCoverAsset: playlist.coverAsset,
          onSave: (draft) async {
            if (!identical(ref.read(libraryRepositoryProvider), repository)) {
              throw StateError('账号已变化，请重新打开歌单');
            }
            await repository.updatePlaylist(
              id: id,
              name: draft.name,
              description: draft.description,
              coverAsset: draft.coverAsset,
            );
          },
        );
        ref.invalidate(playlistProvider(id));
      } else {
        final confirmed = await showCupertinoDialog<bool>(
          context: context,
          builder: (dialogContext) => CupertinoAlertDialog(
            title: const Text('删除云端歌单？'),
            content: Text('将从当前平台账号中删除「${playlist.name}」。此操作会同步到云端。'),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('取消'),
              ),
              CupertinoDialogAction(
                isDestructiveAction: true,
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('删除'),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
        await repository.deletePlaylist(id);
        if (context.mounted) context.go('/music?view=playlists');
      }
    } catch (error) {
      if (context.mounted) showPlatformFailure(context, error);
    }
  }
}
