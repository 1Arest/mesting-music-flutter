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
  bool _busy = false, _more = true;
  int _page = 0;
  String? _error;
  Future<List<Track>>? _neteaseTracks;
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
      if (identity?.platform == MusicPlatform.netease) {
        final repository = ref.read(neteaseMusicRepositoryProvider);
        final all = await (_neteaseTracks ??= _browse.load(
          key: 'netease-tracks',
          request: () => repository.categoryTracks(hit),
          onUpdate: (previous, current) {
            if (!mounted ||
                ref.read(platformAccountProvider).value?.ownerId != _owner ||
                ref.read(platformAccountProvider).value?.token != _token) {
              return;
            }
            setState(() {
              _neteaseTracks = Future.value(current);
              _tracks
                ..clear()
                ..addAll(current.take(_page * 30));
              _more = current.length > _tracks.length;
            });
          },
        ));
        fresh = all.skip(_page * 30).take(30).toList();
        rowCount = fresh.length;
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
        _more = rowCount >= 30 && added.isNotEmpty;
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
        enabled: _more && !_busy && _error == null,
        onLoadMore: _load,
        child: ListView.builder(
          key: PageStorageKey(
            'catalog-${widget.hit.kind.name}-${widget.hit.id}',
          ),
          padding: const EdgeInsets.only(bottom: 190),
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
                            width: 100,
                            height: 100,
                          ),
                        ),
                        const SizedBox(width: 18),
                        Expanded(child: Text(widget.hit.subtitle)),
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
                : const SizedBox(height: 20);
          },
        ),
      ),
    );
  }
}
