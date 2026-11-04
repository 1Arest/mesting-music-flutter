import '../../../shared/widgets/music_list_footer.dart';
import '../../../shared/widgets/beta_content_insets.dart';
import '../platform_backend_providers.dart';
import '../domain/platform_session.dart';
import 'package:flutter/material.dart';
import '../../../core/cache/cached_browse_loader.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/models/track.dart';
import '../../../shared/widgets/artwork_image.dart';
import '../../../shared/widgets/automatic_song_paging.dart';
import '../../experience/presentation/editorial_widgets.dart';
import '../music_platform_providers.dart';
import '../data/platform_catalog.dart';
import '../data/platform_category_search.dart';
import '../data/music_platform_api.dart';
import 'platform_design.dart';
import '../netease/netease_features_page.dart';
import '../netease/netease_features_repository.dart';
import 'platform_play_all_button.dart';
import '../../player/presentation/beta_playback_actions.dart';
import 'platform_feedback.dart';

/// Read-only real catalogue details; selected songs use the shared audio owner
/// and account-guarded library actions. No surrounding list is an implicit queue.
class PlatformCatalogDetailPage extends ConsumerStatefulWidget {
  const PlatformCatalogDetailPage({required this.hit, super.key});
  final PlatformSearchHit hit;
  @override
  ConsumerState<PlatformCatalogDetailPage> createState() =>
      _PlatformCatalogDetailPageState();
}

class _PlatformCatalogDetailPageState
    extends ConsumerState<PlatformCatalogDetailPage> {
  final _browse = CachedBrowseLoader();
  final _tracks = <Track>[];
  bool _busy = false, _more = true, _playingAll = false;
  int _page = 0;
  String? _error;
  int _sourceOffset = 0;
  late final String? _owner, _token;
  @override
  void initState() {
    super.initState();
    final account = ref.read(platformAccountProvider).value;
    _owner = account?.ownerId;
    _token = account?.token;
    Future<void>.microtask(_load);
  }

  Future<void> _load() async {
    if (_busy || !_more) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final api = ref.read(musicPlatformApiProvider);
    final identity = ref.read(platformAccountProvider).value;
    try {
      final hit = widget.hit;
      if (hit.kind == PlatformSearchKind.playlists && hit.globalId.isEmpty) {
        throw const MusicPlatformException('平台未返回可打开的歌单标识，请返回后重试');
      }
      final List<Track> fresh;
      final int rowCount;
      bool? sourceMore;
      if (identity?.platform == MusicPlatform.netease) {
        final repository = ref.read(neteaseMusicRepositoryProvider);
        final start = _sourceOffset;
        final page = await _browse.load(
          key: 'netease-tracks:$start',
          request: () => repository.categoryTrackPage(hit, offset: start),
          onUpdate: (previous, current) {
            if (!mounted ||
                ref.read(platformAccountProvider).value?.ownerId != _owner ||
                ref.read(platformAccountProvider).value?.token != _token) {
              return;
            }
            setState(() {
              replaceBrowsePage(
                _tracks,
                previous.items,
                current.items,
                (track) => track.id,
                fallbackIndex: start,
              );
              if (_sourceOffset == previous.nextOffset) {
                _sourceOffset = current.nextOffset;
                _more = current.hasMore;
              }
            });
          },
        );
        fresh = page.items;
        rowCount = page.nextOffset - start;
        _sourceOffset = page.nextOffset;
        sourceMore = page.hasMore;
      } else {
        final page = _page + 1;
        final path = switch (hit.kind) {
          PlatformSearchKind.artists => '/artist/audios',
          PlatformSearchKind.albums => '/album/songs',
          _ => '/playlist/track/all',
        };
        final query = <String, String>{
          if (hit.kind == PlatformSearchKind.artists) 'id': hit.id,
          if (hit.kind == PlatformSearchKind.albums) 'album_id': hit.id,
          if (hit.kind == PlatformSearchKind.playlists)
            'global_collection_id': hit.globalId,
          'page': '$page',
          'pagesize': '30',
        };
        final payload = await _browse.load(
          key: page,
          request: () => api.get(path, query: query, expectedSession: identity),
          onUpdate: (previous, current) {
            if (!mounted ||
                ref.read(platformAccountProvider).value?.ownerId != _owner ||
                ref.read(platformAccountProvider).value?.token != _token) {
              return;
            }
            setState(() {
              replaceBrowsePage(
                _tracks,
                PlatformCatalog.tracks(PlatformCatalog.rows(previous)),
                PlatformCatalog.tracks(PlatformCatalog.rows(current)),
                (track) => track.id,
                fallbackIndex: (page - 1) * 30,
              );
              if (page == _page) {
                _more = PlatformCatalog.rows(current).length >= 30;
              }
            });
          },
        );
        final rows = PlatformCatalog.rows(payload);
        fresh = PlatformCatalog.tracks(rows);
        rowCount = rows.length;
      }
      if (!mounted ||
          ref.read(platformAccountProvider).value?.ownerId !=
              identity?.ownerId ||
          ref.read(platformAccountProvider).value?.token != identity?.token) {
        return;
      }
      setState(() {
        final ids = _tracks.map((t) => t.id).toSet();
        final added = fresh.where((t) => ids.add(t.id)).toList();
        _tracks.addAll(added);
        _page++;
        _more = sourceMore ?? (rowCount >= 30 && added.isNotEmpty);
      });
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is MusicPlatformException
              ? error.message
              : '加载未完成，请重试',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _browse.dispose();
    super.dispose();
  }

  Future<void> _playAll() async {
    if (_busy || _playingAll) return;
    setState(() => _playingAll = true);
    bool current() =>
        mounted &&
        ref.read(platformAccountProvider).value?.ownerId == _owner &&
        ref.read(platformAccountProvider).value?.token == _token;
    try {
      while (_more && current()) {
        final before = _page;
        final itemCount = _tracks.length;
        await _load();
        if (_error != null) throw StateError(_error!);
        if (_more && _page == before) throw StateError('完整歌曲列表尚未加载，请重试');
        if (_more && _tracks.length == itemCount) {
          throw StateError('来源重复返回相同内容，未更改播放队列，请重试');
        }
      }
      if (mounted && current() && _tracks.isNotEmpty) {
        await playBetaSelection(
          context,
          ref,
          _tracks.first,
          playAll: List.of(_tracks),
        );
      }
    } catch (error) {
      if (mounted) showPlatformFailure(context, error);
    } finally {
      if (mounted) setState(() => _playingAll = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(platformAccountProvider).value;
    if (account?.ownerId != _owner || account?.token != _token) {
      return PlatformPageFrame(
        title: widget.hit.title,
        child: const EditorialEmpty('账号已变化，请返回后重新打开'),
      );
    }
    return PlatformPageFrame(
      title: widget.hit.title,
      child: AutomaticSongPaging(
        enabled: _more && !_busy && !_playingAll && _error == null,
        onLoadMore: _load,
        child: ListView.builder(
          cacheExtent: MediaQuery.sizeOf(context).height,
          key: PageStorageKey(
            'catalog-${widget.hit.kind.name}-${widget.hit.id}',
          ),
          padding: BetaContentInsets.musicPaddingOf(
            context,
            EdgeInsets.only(bottom: 190),
          ),
          itemCount: _tracks.length + 2,
          itemBuilder: (context, index) {
            if (index == 0) {
              return Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  children: [
                    Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(
                            widget.hit.kind == PlatformSearchKind.artists
                                ? 50
                                : 14,
                          ),
                          child: ArtworkImage(
                            uri: widget.hit.cover,
                            width: 80,
                            height: 80,
                          ),
                        ),
                        const SizedBox(width: 18),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (widget.hit.subtitle.isNotEmpty) ...[
                                Text(
                                  widget.hit.subtitle,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 8),
                              ],
                              PlatformPlayAllButton(
                                loading: _playingAll,
                                onPressed: _busy || _tracks.isEmpty
                                    ? null
                                    : _playAll,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (ref.watch(usesNeteaseProvider) &&
                        widget.hit.kind != PlatformSearchKind.playlists)
                      NeteaseResourceActions(
                        item: NeteaseItem(
                          id: widget.hit.id,
                          name: widget.hit.title,
                          kind: widget.hit.kind == PlatformSearchKind.artists
                              ? NeteaseEntity.artist
                              : NeteaseEntity.album,
                        ),
                      ),
                  ],
                ),
              );
            }
            if (index <= _tracks.length) {
              return EditorialTrackRow(
                track: _tracks[index - 1],
                contextTracks: _tracks,
              );
            }
            if (_busy) return const PlatformFeedbackState(loading: true);
            if (_error != null) {
              return TextButton(onPressed: _load, child: Text(_error!));
            }
            return _tracks.isEmpty
                ? const EditorialEmpty('平台暂未返回歌曲')
                : _more
                ? const SizedBox(height: 12)
                : const MusicListEnd();
          },
        ),
      ),
    );
  }
}
