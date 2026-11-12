import 'package:flutter/material.dart';
import '../../../shared/widgets/automatic_song_paging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/models/track.dart';
import '../../../shared/widgets/artwork_image.dart';
import '../../../shared/widgets/liquid_glass_sheet.dart';
import '../../../shared/widgets/mesting_loading_indicator.dart';
import '../../../shared/widgets/music_notice.dart';
import '../../library/presentation/library_access.dart';
import '../../library/data/library_repository.dart';
import '../../library/library_providers.dart';
import '../../themes/music_theme_tokens.dart';
import '../../music_platform/data/platform_library_repository.dart';
import '../../music_platform/presentation/platform_feedback.dart';
import '../../themes/music_typography.dart';

const _openProfileAction = '__open_profile__';

Future<void> showAddToPlaylistSheet(
  BuildContext context,
  WidgetRef ref,
  Track track,
) async {
  final allowed = await ensureLibraryAccess(
    context,
    ref,
    reason: '登录后才能创建和保存个人歌单，歌单内容会跟随账号同步。',
    redirect: '/music?view=playlists',
  );
  if (!allowed || !context.mounted) return;
  final repository = ref.read(libraryRepositoryProvider);
  bool isFavorite;
  try {
    isFavorite =
        repository is PlatformLibraryRepository ||
        await repository.isFavorite(track.id);
  } catch (error) {
    if (context.mounted) showPlatformFailure(context, error);
    return;
  }
  if (!context.mounted) return;
  if (!isFavorite) {
    showMusicNotice(
      context,
      icon: Icons.favorite_border_rounded,
      title: '请先收藏这首歌',
      message: '个人歌单只收录“我的喜欢”中的歌曲',
    );
    return;
  }
  final selectedName = await showLiquidGlassBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => _AddToPlaylistSheet(track: track),
  );
  if (selectedName == _openProfileAction && context.mounted) {
    context.go('/profile');
  } else if (selectedName != null && context.mounted) {
    showMusicNotice(
      context,
      icon: Icons.check_rounded,
      title: '已加入「$selectedName」',
      message: track.title,
    );
  }
}

class _AddToPlaylistSheet extends ConsumerWidget {
  const _AddToPlaylistSheet({required this.track});

  final Track track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.musicThemeTokens;
    final playlists = ref.watch(playlistsProvider);
    final repository = ref.watch(libraryRepositoryProvider);
    final cloud = repository is PlatformLibraryRepository;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          132 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('加入歌单', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 6),
            Text(
              '${track.title} · ${track.artist}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 16),
            playlists.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: MestingLoadingIndicator(
                    key: ValueKey('add-to-playlist-loading-animation'),
                    size: 52,
                    semanticLabel: '正在加载个人歌单',
                  ),
                ),
              ),
              error: (error, stack) => const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('歌单读取失败')),
              ),
              data: (allItems) {
                final items = cloud
                    ? allItems
                          .where((item) => repository.canManage(item.id))
                          .toList()
                    : allItems;
                if (items.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    child: Center(
                      child: Column(
                        children: [
                          const Text('还没有个人歌单'),
                          const SizedBox(height: 7),
                          Text(
                            '请在“我的”页右上角 + 中创建',
                            style: TextStyle(
                              color: tokens.textSecondary,
                              fontSize: MusicTypography.smallCaptionSize,
                            ),
                          ),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            onPressed: () {
                              Navigator.pop(context, _openProfileAction);
                            },
                            icon: const Icon(Icons.person_rounded),
                            label: const Text('返回“我的”'),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 390),
                  child: AutomaticSongPaging(
                    enabled:
                        ref.exists(playlistDirectoryWindowProvider) &&
                        ref.watch(playlistDirectoryWindowProvider).hasMore &&
                        !ref.watch(playlistDirectoryWindowProvider).loading &&
                        ref.watch(playlistDirectoryWindowProvider).error ==
                            null,
                    onLoadMore: () =>
                        ref.read(playlistDirectoryWindowProvider).loadMore(),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: items.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 6),
                      itemBuilder: (context, index) {
                        final playlist = items[index];
                        final tracks = cloud
                            ? const <Track>[]
                            : ref
                                      .watch(
                                        playlistTracksProvider(playlist.id),
                                      )
                                      .value ??
                                  const <Track>[];
                        final cover =
                            playlist.coverAsset ??
                            (tracks.isEmpty ? '' : tracks.first.coverAsset);
                        return ListTile(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          tileColor: tokens.glassSubtle,
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: ArtworkImage(
                              uri: cover,
                              width: 48,
                              height: 48,
                            ),
                          ),
                          title: Text(
                            playlist.name,
                            style: const TextStyle(
                              fontWeight: MusicTypography.titleWeight,
                            ),
                          ),
                          subtitle: Text(
                            cloud ? '酷狗云端歌单' : '${tracks.length} 首歌曲',
                          ),
                          trailing: const Icon(Icons.add_rounded),
                          onTap: () async {
                            try {
                              await ref
                                  .read(libraryRepositoryProvider)
                                  .addTrackToPlaylist(playlist.id, track);
                              if (context.mounted) {
                                Navigator.pop(context, playlist.name);
                              }
                            } on FavoriteTrackRequiredException {
                              if (!context.mounted) return;
                              showMusicNotice(
                                context,
                                icon: Icons.favorite_border_rounded,
                                title: '请先收藏这首歌',
                                message: '收藏状态已变化，请返回后重试',
                              );
                            } on Object catch (error) {
                              if (context.mounted) {
                                showPlatformFailure(context, error);
                              }
                            }
                          },
                        );
                      },
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
