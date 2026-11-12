import '../../music_platform/presentation/song_actions_sheet.dart';
import '../../../shared/widgets/song_list_tools.dart';
import '../../../shared/widgets/beta_content_insets.dart';
import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/utils/duration_format.dart';
import '../../../shared/widgets/artwork_image.dart';
import '../../../shared/widgets/beta_glass_controls.dart';
import '../../../shared/widgets/beta_bottom_search.dart';
import '../../../shared/widgets/beta_page_search_layout.dart';
import '../../../shared/widgets/beta_swipe_pages.dart';
import '../../../shared/widgets/music_notice.dart';
import '../../music_platform/presentation/platform_design.dart';
import '../../player/presentation/beta_playback_actions.dart';
import '../../themes/music_theme_tokens.dart';
import '../data/local_music_repository.dart';
import '../domain/local_music.dart';
import '../local_music_providers.dart';
import '../../themes/music_typography.dart';

/// One device library, outside the account/cloud library. Opening the page only
/// loads its index; storage permission and scans require an explicit action.
class LocalMusicPage extends ConsumerStatefulWidget {
  const LocalMusicPage({super.key});
  @override
  ConsumerState<LocalMusicPage> createState() => _LocalMusicPageState();
}

class _LocalMusicPageState extends ConsumerState<LocalMusicPage> {
  late final _bottomSearch = BetaPageSearchController(
    hintText: '搜索歌曲、歌手或专辑',
    onSubmitted: _filter,
    onCleared: () => _filter(''),
    onChanged: _filter,
  );
  void _filter(String value) {
    if (mounted) setState(() => _query = value);
  }

  @override
  void dispose() {
    _bottomSearch.dispose();
    super.dispose();
  }

  String _view = 'songs';
  String _query = '';
  String? _folderId;
  bool _preparingPlayback = false;
  final _views = LocalMusicViewCache();

  Future<void> _play(
    LocalMusicEntry entry, {
    List<LocalMusicEntry>? all,
  }) async {
    if (_preparingPlayback) return;
    setState(() => _preparingPlayback = true);
    try {
      final prepared = await ref
          .read(localMusicRepositoryProvider)
          .prepare(entry);
      if (!mounted) return;
      await playBetaSelection(
        context,
        ref,
        prepared.track,
        playAll: all == null
            ? null
            : [
                for (final item in all)
                  item.id == prepared.id ? prepared.track : item.track,
              ],
      );
    } on Object catch (error) {
      if (!mounted) return;
      if (error is LocalMusicException && error.code == 'unavailable') {
        ref
            .read(localMusicControllerProvider.notifier)
            .markUnavailable(entry.id);
      }
      showMusicNotice(
        context,
        icon: CupertinoIcons.exclamationmark_circle,
        title: '文件暂时无法播放',
        message: error is LocalMusicException
            ? error.message
            : '请检查文件是否已移动，或重新导入音乐',
      );
    } finally {
      if (mounted) setState(() => _preparingPlayback = false);
    }
  }

  Future<void> _actions(LocalMusicEntry entry) => showSongActions(
    context,
    ref,
    entry.track,
    playable: entry.available,
    prepareForQueue: () async =>
        (await ref.read(localMusicRepositoryProvider).prepare(entry)).track,
    extras: [
      SongMenuExtraAction(
        '从本地音乐移除',
        CupertinoIcons.delete,
        () => _removeLocal(entry),
        destructive: true,
      ),
    ],
  );

  Future<void> _removeLocal(LocalMusicEntry entry) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('移除这首音乐？', style: MusicTypography.titleEmphasis),
        content: const Text('手机中的原文件会保留，之后可以重新扫描或导入。'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消', style: MusicTypography.regularText),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('移除', style: MusicTypography.regularText),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await ref.read(localMusicControllerProvider.notifier).remove(entry.id);
    }
  }

  void _selectView(int index) {
    final view = index == 0 ? 'songs' : 'folders';
    if (_view == view) return;
    setState(() {
      _view = view;
      _folderId = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(localMusicControllerProvider);
    final controller = ref.read(localMusicControllerProvider.notifier);
    final tokens = context.musicThemeTokens;
    final view = _views.select(
      state.library,
      query: _query,
      folderId: _folderId,
    );
    final visibleFolders = view.folders;
    final selectedFolder = view.selectedFolder;
    final entries = view.entries;
    // Share one membership snapshot across lazy rows; remapping a long device
    // library in every visible row would multiply work during scrolling.
    final currentTracks = entries
        .map((item) => item.track)
        .toList(growable: false);
    final available = view.available;
    final busy = state.busy || _preparingPlayback;

    return BetaPageSearchLayout(
      controller: _bottomSearch,
      child: PlatformPageFrame(
        title: '本地音乐',
        subtitle: '${state.library.entries.length} 首音乐 · 离线随时听',
        pageKey: const ValueKey('local-music-page'),
        actions: [
          if (busy)
            const Padding(
              padding: EdgeInsets.all(14),
              child: BetaActivityIndicator(label: '正在处理本地音乐'),
            )
          else
            Tooltip(
              message: '刷新本地音乐',
              child: BetaGlassButton(
                label: '刷新本地音乐',
                width: 48,
                height: 48,
                onPressed: controller.refresh,
                child: const Icon(CupertinoIcons.arrow_clockwise, size: 21),
              ),
            ),
        ],
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: CupertinoSlidingSegmentedControl<String>(
                groupValue: _view,
                onValueChanged: (value) {
                  if (value != null) {
                    _selectView(value == 'songs' ? 0 : 1);
                  }
                },
                children: const {
                  'songs': Padding(
                    padding: EdgeInsets.symmetric(vertical: 4, horizontal: 14),
                    child: Text('全部歌曲'),
                  ),
                  'folders': Padding(
                    padding: EdgeInsets.symmetric(vertical: 4, horizontal: 14),
                    child: Text('文件夹'),
                  ),
                },
              ),
            ),
            Expanded(
              child: BetaSwipePages(
                index: _view == 'songs' ? 0 : 1,
                length: 2,
                onChanged: _selectView,
                itemBuilder: (context, index) {
                  final showingFolders = index == 1 && _folderId == null;
                  return SongListTools(
                    listId: 'local-music:$index:${_folderId ?? 'all'}:$_query',
                    child: CustomScrollView(
                      key: PageStorageKey('local-music-scroll-$index'),
                      slivers: [
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
                          sliver: SliverToBoxAdapter(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // Keep related imports beside each other. Normal phone
                                // widths fit all three; narrow/large-text layouts can scroll
                                // this row without wrapping folder import onto a new line.
                                SingleChildScrollView(
                                  key: const ValueKey('local-import-actions'),
                                  scrollDirection: Axis.horizontal,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 6,
                                    ),
                                    child: Row(
                                      children: [
                                        _ImportButton(
                                          label: '扫描手机',
                                          icon: CupertinoIcons.search_circle,
                                          onPressed: busy
                                              ? null
                                              : controller.scan,
                                          blue: state.library.entries.isEmpty,
                                        ),
                                        const SizedBox(width: 8),
                                        _ImportButton(
                                          label: '导入文件',
                                          icon: CupertinoIcons.doc,
                                          onPressed: busy
                                              ? null
                                              : controller.importFiles,
                                        ),
                                        const SizedBox(width: 8),
                                        _ImportButton(
                                          label: '导入文件夹',
                                          icon: CupertinoIcons.folder,
                                          onPressed: busy
                                              ? null
                                              : controller.importDirectory,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                if (state.error.isNotEmpty) ...[
                                  const SizedBox(height: 18),
                                  Semantics(
                                    liveRegion: true,
                                    child: Text(
                                      state.error,
                                      style: TextStyle(
                                        color: tokens.textPrimary,
                                        height: 1.5,
                                      ),
                                    ),
                                  ),
                                  if (state.errorCode ==
                                      'permission_permanently_denied')
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: TextButton(
                                        onPressed: () async {
                                          try {
                                            await ref
                                                .read(
                                                  localMusicRepositoryProvider,
                                                )
                                                .openSettings();
                                          } on LocalMusicException catch (
                                            error
                                          ) {
                                            if (context.mounted) {
                                              showMusicNotice(
                                                context,
                                                icon: CupertinoIcons
                                                    .exclamationmark_circle,
                                                title: '设置未打开',
                                                message: error.message,
                                              );
                                            }
                                          }
                                        },
                                        child: const Text('前往系统设置授权'),
                                      ),
                                    ),
                                ],
                                if (state.library.notice.isNotEmpty) ...[
                                  const SizedBox(height: 16),
                                  Text(
                                    state.library.notice,
                                    style: TextStyle(
                                      color: tokens.textSecondary,
                                      height: 1.5,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 24),
                                const SizedBox(height: 22),
                                if (_folderId != null)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: Row(
                                      children: [
                                        CupertinoButton(
                                          padding: EdgeInsets.zero,
                                          minimumSize: const Size(44, 44),
                                          onPressed: () =>
                                              setState(() => _folderId = null),
                                          child: const Icon(
                                            CupertinoIcons.chevron_back,
                                            size: 21,
                                          ),
                                        ),
                                        Expanded(
                                          child: Text(
                                            selectedFolder?.name ?? '文件夹',
                                            style: const TextStyle(
                                              fontSize:
                                                  MusicTypography.headingSize,
                                              fontWeight:
                                                  MusicTypography.titleWeight,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                if (!showingFolders && available.isNotEmpty)
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: BetaGlassButton(
                                      label: '播放全部 ${available.length} 首歌曲',
                                      red: true,
                                      onPressed: busy
                                          ? null
                                          : () => _play(
                                              available.first,
                                              all: available,
                                            ),
                                      height: 46,
                                      accent: true,
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            CupertinoIcons.play_fill,
                                            size: 17,
                                          ),
                                          const SizedBox(width: 8),
                                          Text('播放全部 · ${available.length} 首'),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        if (state.loading)
                          const SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsets.all(32),
                              child: Center(child: BetaActivityIndicator()),
                            ),
                          )
                        else if (state.library.entries.isEmpty)
                          const SliverToBoxAdapter(
                            child: _EmptyLibrary(
                              icon: CupertinoIcons.music_albums,
                              title: '把喜欢的音乐留在身边',
                              message: '扫描手机中的音频，或选择文件与文件夹导入。音乐会保留在这台设备上。',
                            ),
                          )
                        else if (showingFolders && visibleFolders.isEmpty)
                          const SliverToBoxAdapter(
                            child: _EmptyLibrary(
                              icon: CupertinoIcons.search,
                              title: '没有找到文件夹',
                              message: '试试其他歌曲、歌手或文件夹名称。',
                            ),
                          )
                        else if (showingFolders)
                          SliverList.builder(
                            itemCount: visibleFolders.length,
                            itemBuilder: (context, index) {
                              final folder = visibleFolders[index];
                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 22,
                                  vertical: 8,
                                ),
                                leading: Icon(
                                  CupertinoIcons.folder_fill,
                                  color: Theme.of(context).colorScheme.primary,
                                  size: 36,
                                ),
                                title: Text(
                                  folder.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  '${folder.count} 首${folder.path.isEmpty ? '' : ' · ${folder.path}'}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: const Icon(
                                  CupertinoIcons.chevron_forward,
                                  size: 16,
                                ),
                                onTap: () =>
                                    setState(() => _folderId = folder.id),
                              );
                            },
                          )
                        else if (entries.isEmpty)
                          const SliverToBoxAdapter(
                            child: _EmptyLibrary(
                              icon: CupertinoIcons.search,
                              title: '没有找到音乐',
                              message: '试试其他歌曲、歌手或专辑名称。',
                            ),
                          )
                        else
                          SliverList.builder(
                            itemCount: entries.length,
                            itemBuilder: (context, index) {
                              final entry = entries[index];
                              return SongListEntry(
                                key: ValueKey(entry.id),
                                track: entry.track,
                                tracks: currentTracks,
                                child: ListTile(
                                  contentPadding: const EdgeInsets.fromLTRB(
                                    22,
                                    6,
                                    12,
                                    6,
                                  ),
                                  leading: _LocalArtwork(entry: entry),
                                  title: Text(
                                    entry.displayTitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: MusicTypography.subheadlineSize,
                                      fontWeight: MusicTypography.bodyWeight,
                                      color: entry.available
                                          ? tokens.textPrimary
                                          : tokens.textSecondary,
                                    ),
                                  ),
                                  subtitle: Text(
                                    entry.available
                                        ? '${entry.artist} · ${entry.duration > Duration.zero ? formatDuration(entry.duration) : '--:--'}'
                                        : '文件不可用 · 重新导入以恢复',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: MusicTypography.captionSize,
                                      color: tokens.textSecondary,
                                    ),
                                  ),
                                  trailing: CupertinoButton(
                                    padding: EdgeInsets.zero,
                                    minimumSize: const Size(44, 44),
                                    onPressed: busy
                                        ? null
                                        : () => _actions(entry),
                                    child: Semantics(
                                      label: '${entry.title}的更多操作',
                                      button: true,
                                      child: const Icon(
                                        Icons.more_vert_rounded,
                                        size: 23,
                                      ),
                                    ),
                                  ),
                                  onTap: busy || !entry.available
                                      ? null
                                      : () {
                                          SongListTools.remember(
                                            context,
                                            entry.track,
                                          );
                                          unawaited(_play(entry));
                                        },
                                ),
                              );
                            },
                          ),
                        SliverToBoxAdapter(
                          child: SizedBox(
                            height: BetaContentInsets.musicBottomOf(
                              context,
                              160,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImportButton extends StatelessWidget {
  const _ImportButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.blue = false,
  });
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool blue;
  @override
  Widget build(BuildContext context) => BetaGlassButton(
    label: label,
    height: 46,
    horizontalPadding: 11,
    fontSize: 13.5,
    blue: blue,
    onPressed: onPressed,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [Icon(icon, size: 18), const SizedBox(width: 6), Text(label)],
    ),
  );
}

class _LocalArtwork extends ConsumerWidget {
  const _LocalArtwork({required this.entry});
  final LocalMusicEntry entry;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The native cache may evict an old cover while retaining the audio index.
    // Check that cache lazily even when the stored row had a previous cover.
    final artwork =
        ref.watch(localMusicArtworkProvider(entry.id)).value ?? entry.artwork;
    return ClipRRect(
      borderRadius: BorderRadius.circular(11),
      child: artwork.isEmpty
          ? ColoredBox(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              child: SizedBox(
                width: 50,
                height: 50,
                child: Icon(
                  CupertinoIcons.music_note,
                  color: Theme.of(context).colorScheme.primary,
                  size: 25,
                ),
              ),
            )
          : ArtworkImage(uri: artwork, width: 50, height: 50),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({
    required this.icon,
    required this.title,
    required this.message,
  });
  final IconData icon;
  final String title, message;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(34, 42, 34, 24),
    child: Column(
      children: [
        Icon(icon, size: 46, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 20),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: MusicTypography.sectionTitleSize,
            fontWeight: MusicTypography.titleWeight,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: MusicTypography.subheadlineSize,
            height: 1.6,
            color: context.musicThemeTokens.textSecondary,
          ),
        ),
      ],
    ),
  );
}
