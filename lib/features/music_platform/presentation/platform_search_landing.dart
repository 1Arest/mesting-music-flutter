import 'dart:convert';
import '../../../shared/widgets/music_notice.dart';
import '../../../shared/widgets/automatic_song_paging.dart';
import 'package:flutter/material.dart';
import '../../../core/cache/cached_browse_loader.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/models/track.dart';
import '../../../shared/widgets/artwork_image.dart';
import '../../experience/presentation/editorial_widgets.dart';
import '../../search/search_providers.dart';
import '../data/platform_explore.dart';
import '../music_platform_providers.dart';
import '../platform_recommendation_providers.dart';
import 'platform_design.dart';
import 'apple_hot_search.dart';
import '../data/music_platform_api.dart';
import '../data/platform_recommendations.dart';
import '../platform_explore_providers.dart';
import '../platform_backend_providers.dart';
import '../netease/netease_features_page.dart';
import '../netease/netease_features_repository.dart';
import '../../downloads/audio_downloads_page.dart';
export '../platform_explore_providers.dart';

/// Search history, real keyword boards, then upstream music exploration. A
/// keyword opens search; it is never presented as a directly playable song.
class PlatformSearchLanding extends ConsumerStatefulWidget {
  const PlatformSearchLanding({required this.onSearch, super.key});
  final ValueChanged<String> onSearch;
  @override
  ConsumerState<PlatformSearchLanding> createState() =>
      _PlatformSearchLandingState();
}

class _PlatformSearchLandingState extends ConsumerState<PlatformSearchLanding> {
  bool _refreshing = false;
  String? _refreshStatus;

  Future<void> _refreshHotSearch() async {
    if (_refreshing) return;
    final previous = ref.read(platformHotSearchProvider).value;
    final owner = ref.read(platformAccountProvider).value?.ownerId;
    setState(() {
      _refreshing = true;
      _refreshStatus = null;
    });
    try {
      final fresh = await ref.refresh(platformHotSearchProvider.future);
      if (!mounted ||
          ref.read(platformAccountProvider).value?.ownerId != owner) {
        return;
      }
      // Server ranks stay authoritative: identical results are a successful
      // refresh, not a reason to shuffle songs merely to produce movement.
      String signature(List<PlatformHotSearchBoard> items) => jsonEncode([
        for (final board in items) [board.name, board.keywords],
      ]);
      setState(
        () => _refreshStatus =
            previous != null && signature(previous) == signature(fresh)
            ? '已是最新热搜'
            : '热搜已更新',
      );
      showMusicNotice(
        context,
        icon: Icons.check_rounded,
        title: _refreshStatus!,
        message: '',
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => _refreshStatus = previous?.isNotEmpty == true
              ? '刷新失败，已保留原榜单，请重试'
              : '刷新失败，请重试',
        );
        showMusicNotice(
          context,
          icon: Icons.error_outline_rounded,
          title: _refreshStatus!,
          message: '',
        );
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(musicSearchControllerProvider).recentSearches;
    final boards = ref.watch(platformHotSearchProvider);
    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 190),
      children: [
        if (history.isNotEmpty) ...[
          Row(
            children: [
              Text('搜索历史', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              TextButton(
                onPressed: () => ref
                    .read(musicSearchControllerProvider.notifier)
                    .clearRecentSearches(),
                child: const Text('清空'),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            children: [
              for (final word in history)
                ActionChip(
                  label: Text(word),
                  onPressed: () => widget.onSearch(word),
                ),
            ],
          ),
          const SizedBox(height: 22),
        ],
        Row(
          children: [
            Text('热门搜索', style: Theme.of(context).textTheme.titleLarge),
            const Spacer(),
            IconButton(
              tooltip: '刷新热门搜索',
              onPressed: _refreshing ? null : _refreshHotSearch,
              icon: _refreshing
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
            ),
          ],
        ),
        boards.when(
          skipError: true,
          loading: () => const PlatformFeedbackState(loading: true),
          error: (_, _) => EditorialEmpty(
            '热搜暂时无法加载',
            onRetry: () => ref.invalidate(platformHotSearchProvider),
          ),
          data: (items) => items.isEmpty
              ? EditorialEmpty(
                  '平台暂未返回热搜',
                  onRetry: () => ref.invalidate(platformHotSearchProvider),
                )
              : AppleHotSearchBoards(boards: items, onSearch: widget.onSearch),
        ),
        const SizedBox(height: 28),
        for (final kind in PlatformExploreKind.values.where(
          (k) =>
              !ref.watch(usesNeteaseProvider) ||
              (k != PlatformExploreKind.scene &&
                  k != PlatformExploreKind.theme),
        ))
          _ExploreSection(kind: kind),
      ],
    );
  }
}

class _ExploreSection extends ConsumerWidget {
  const _ExploreSection({required this.kind});
  final PlatformExploreKind kind;
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(platformExploreProvider(kind))
      .when(
        loading: () => const SizedBox.shrink(),
        error: (error, _) => Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${kind.label}暂时未能加载${error is MusicPlatformException ? '\n${error.message}' : ''}',
                ),
              ),
              TextButton(
                onPressed: () => ref.invalidate(platformExploreProvider(kind)),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
        data: (items) => items.isEmpty
            ? const SizedBox.shrink()
            : Padding(
                padding: const EdgeInsets.only(bottom: 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      kind.label,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    if (kind == PlatformExploreKind.scene)
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final item in items)
                            Chip(label: Text(item.title)),
                        ],
                      )
                    else
                      SizedBox(
                        height: 182,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: items.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 14),
                          itemBuilder: (context, index) {
                            final item = items[index];
                            return SizedBox(
                              width: 132,
                              child: InkWell(
                                onTap:
                                    kind == PlatformExploreKind.theme ||
                                        item.id.isEmpty
                                    ? null
                                    : () => Navigator.of(context).push(
                                        MaterialPageRoute<void>(
                                          builder: (_) =>
                                              PlatformExploreSongsPage(
                                                item: item,
                                              ),
                                        ),
                                      ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(14),
                                      child: ArtworkImage(
                                        uri: item.cover,
                                        width: 132,
                                        height: 132,
                                      ),
                                    ),
                                    const SizedBox(height: 9),
                                    Text(
                                      item.title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.labelLarge,
                                    ),
                                  ],
                                ),
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

class PlatformExploreSongsPage extends ConsumerStatefulWidget {
  const PlatformExploreSongsPage({required this.item, super.key});
  final PlatformExploreItem item;
  @override
  ConsumerState<PlatformExploreSongsPage> createState() =>
      _ExploreSongsPageState();
}

class _ExploreSongsPageState extends ConsumerState<PlatformExploreSongsPage> {
  final _browse = CachedBrowseLoader();
  final _tracks = <Track>[];
  final _collections = <PlatformExploreItem>[];
  int _page = 0;
  bool _busy = false, _more = true;
  String? _error;
  String? _owner;
  String? _token;
  bool _loaded = false;
  PlatformExploreItem? _resolvedItem;
  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_load);
  }

  Future<void> _load() async {
    if (_busy || !_more) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final account = await ref.read(platformAccountProvider.future);
      if (!mounted) return;
      final owner = account?.ownerId, token = account?.token;
      final repository = ref.read(platformExploreRepositoryProvider);
      final page = _page + 1;
      final batch = await _browse.load(
        key: page,
        request: () async {
          final resolved = await repository.resolveScene(widget.item);
          final collectionScene =
              resolved.kind == PlatformExploreKind.scene &&
              resolved.sceneContent == PlatformSceneContent.collections;
          return (
            resolved: resolved,
            tracks: collectionScene
                ? <Track>[]
                : await repository.tracks(resolved, page: page),
            collections: collectionScene
                ? await repository.sceneCollections(resolved, page: page)
                : <PlatformExploreItem>[],
          );
        },
        onUpdate: (previous, current) {
          if (!mounted ||
              ref.read(platformAccountProvider).value?.ownerId != owner ||
              ref.read(platformAccountProvider).value?.token != token) {
            return;
          }
          setState(() {
            replaceBrowsePage(
              _tracks,
              previous.tracks,
              current.tracks,
              (track) => track.id,
              fallbackIndex: (page - 1) * 30,
            );
            replaceBrowsePage(
              _collections,
              previous.collections,
              current.collections,
              (item) => item.id,
              fallbackIndex: (page - 1) * 30,
            );
            _resolvedItem = current.resolved;
            if (page == _page) {
              _more =
                  current.resolved.sceneContent ==
                      PlatformSceneContent.collections
                  ? current.collections.length >= 30
                  : widget.item.kind != PlatformExploreKind.theme &&
                        current.tracks.length >= 30;
            }
          });
        },
      );
      final resolved = batch.resolved;
      final isCollectionScene =
          resolved.kind == PlatformExploreKind.scene &&
          resolved.sceneContent == PlatformSceneContent.collections;
      final fresh = batch.tracks;
      final collections = batch.collections;
      if (!mounted ||
          ref.read(platformAccountProvider).value?.ownerId != owner ||
          ref.read(platformAccountProvider).value?.token != token) {
        return;
      }
      setState(() {
        final ids = _tracks.map((e) => e.id).toSet();
        final additions = fresh.where((e) => ids.add(e.id)).toList();
        _tracks.addAll(additions);
        final collectionIds = _collections.map((item) => item.id).toSet();
        final newCollections = collections
            .where((item) => collectionIds.add(item.id))
            .toList();
        _collections.addAll(newCollections);
        _page++;
        _more = isCollectionScene
            ? collections.length >= 30 && newCollections.isNotEmpty
            : widget.item.kind != PlatformExploreKind.theme &&
                  fresh.length >= 30 &&
                  additions.isNotEmpty;
        _owner = owner;
        _token = token;
        _loaded = true;
        _resolvedItem = resolved;
      });
    } catch (_) {
      if (mounted) setState(() => _error = '歌曲加载失败，请重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _browse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(platformAccountProvider).value;
    if (_loaded && (account?.ownerId != _owner || account?.token != _token)) {
      return PlatformPageFrame(
        title: widget.item.title,
        child: const EditorialEmpty('账号已变化，请返回后重新打开'),
      );
    }
    final collectionScene =
        _resolvedItem?.sceneContent == PlatformSceneContent.collections;
    return PlatformPageFrame(
      title: widget.item.title,
      child: AutomaticSongPaging(
        enabled: _more && !_busy && _error == null,
        onLoadMore: _load,
        child: ListView.builder(
          padding: const EdgeInsets.only(bottom: 190),
          itemCount:
              (collectionScene ? _collections.length : _tracks.length) + 2,
          itemBuilder: (context, index) {
            if (index == 0) {
              if (!ref.watch(usesNeteaseProvider)) {
                return const SizedBox.shrink();
              }
              return Column(
                children: [
                  NeteaseResourceActions(
                    item: NeteaseItem(
                      id: widget.item.id,
                      name: widget.item.title,
                      kind: widget.item.kind == PlatformExploreKind.album
                          ? NeteaseEntity.album
                          : NeteaseEntity.playlist,
                    ),
                  ),
                  if (_tracks.isNotEmpty)
                    TextButton.icon(
                      icon: const Icon(Icons.download_rounded),
                      label: const Text('下载已加载歌曲'),
                      onPressed: () {
                        final current = ref.read(platformAccountProvider).value;
                        if (!_loaded ||
                            current?.ownerId != _owner ||
                            current?.token != _token) {
                          return;
                        }
                        enqueueAudioDownloads(context, ref, _tracks);
                      },
                    ),
                ],
              );
            }
            index--;
            if (collectionScene && index < _collections.length) {
              final collection = _collections[index];
              return ListTile(
                key: ValueKey('scene-collection-${collection.id}'),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 10,
                ),
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: ArtworkImage(
                    uri: collection.cover,
                    width: 58,
                    height: 58,
                  ),
                ),
                title: Text(
                  collection.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: collection.subtitle.isEmpty
                    ? null
                    : Text(
                        collection.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => PlatformExploreSongsPage(item: collection),
                  ),
                ),
              );
            }
            if (!collectionScene && index < _tracks.length) {
              return EditorialTrackRow(
                track: _tracks[index],
                contextTracks: _tracks,
              );
            }
            if (_busy) return const PlatformFeedbackState(loading: true);
            if (_error != null) {
              return TextButton(onPressed: _load, child: Text(_error!));
            }
            if ((collectionScene ? _collections.isEmpty : _tracks.isEmpty) &&
                !_more) {
              return EditorialEmpty(collectionScene ? '平台暂未返回歌单' : '平台暂未返回歌曲');
            }
            return const SizedBox(height: 24);
          },
        ),
      ),
    );
  }
}
