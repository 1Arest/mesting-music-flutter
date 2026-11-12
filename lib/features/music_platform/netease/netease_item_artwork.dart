import 'dart:async';
import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/cache/browse_response_cache.dart';
import '../../../shared/utils/media_uri.dart';
import '../../../shared/widgets/artwork_image.dart';
import '../../../shared/widgets/artwork_reveal_boundary.dart';
import '../../../shared/widgets/music_activity_indicator.dart';
import '../platform_backend_providers.dart';
import 'netease_features_repository.dart';
import 'netease_music_repository.dart';
import 'netease_song_metadata.dart';

final neteaseArtworkRepositoryProvider = Provider(
  (ref) => NeteaseArtworkRepository(ref.watch(neteaseMusicRepositoryProvider)),
);

/// Account-local metadata cache. Visible categories are resolved lazily and at
/// most three requests run at once, including a failed playlist's recovery.
class NeteaseArtworkRepository {
  NeteaseArtworkRepository(this.music);
  final NeteaseMusicRepository music;
  final _categories = <String, Future<String>>{};
  final _rejectedCategories = <String, Set<String>>{};
  final _waiting = Queue<Completer<void>>();
  int _active = 0;
  Future<T> _limited<T>(Future<T> Function() load, {bool live = false}) async {
    if (_active >= 3) {
      final turn = Completer<void>();
      _waiting.add(turn);
      await turn.future;
    } else {
      _active++;
    }
    try {
      return await (live ? BrowseResponseCache.live(load) : load());
    } finally {
      if (_waiting.isNotEmpty) {
        _waiting.removeFirst().complete();
      } else {
        _active--;
      }
    }
  }

  Future<String> category(
    String name, {
    bool refresh = false,
    String rejected = '',
  }) {
    if (refresh) _categories.remove(name);
    // Failed lookups also leave rejection history, so bound that history even
    // when a network error has already evicted its pending cover future.
    if (!_rejectedCategories.containsKey(name) &&
        _rejectedCategories.length >= 96) {
      final oldest = _rejectedCategories.keys.first;
      _rejectedCategories.remove(oldest);
      _categories.remove(oldest);
    }
    final rejectedImages = _rejectedCategories.putIfAbsent(name, () => {});
    if (rejected.isNotEmpty) {
      rejectedImages.add(artworkContentIdentity(rejected));
    }
    if (_categories.length >= 96) {
      final oldest = _categories.keys.first;
      _categories.remove(oldest);
      _rejectedCategories.remove(oldest);
    }
    return _categories.putIfAbsent(
      name,
      () =>
          _limited(() async {
            final payload = await music.call('/top/playlist', {
              'cat': name,
              'offset': 0,
              'limit': rejectedImages.isEmpty ? 1 : 6,
            });
            final rows = NeteaseMusicRepository.rows(payload['playlists']);
            for (final row in rows) {
              final cover = neteaseArtwork(row);
              if (cover.isNotEmpty &&
                  !rejectedImages.contains(artworkContentIdentity(cover))) {
                return cover;
              }
              if (row['id'] != null) {
                // Reuse this request slot: nested acquisition could deadlock
                // three simultaneous category-cover recoveries.
                final alternatives = await _playlist('${row['id']}');
                for (final value in alternatives) {
                  if (!rejectedImages.contains(artworkContentIdentity(value))) {
                    return value;
                  }
                }
              }
            }
            throw StateError('该分类暂未返回歌单封面');
          }, live: refresh).catchError((Object error) {
            _categories.remove(name);
            throw error;
          }),
    );
  }

  Future<List<String>> playlist(String id) =>
      _limited(() => BrowseResponseCache.live(() => _playlist(id)));
  Future<List<String>> _playlist(String id) async {
    final payload = await music.call('/playlist/detail', {'id': id, 'n': 1});
    final row = NeteaseMusicRepository.object(payload['playlist']);
    final covers = <String>{neteaseArtwork(row)};
    for (final song in NeteaseMusicRepository.rows(row['tracks']).take(3)) {
      covers.add(neteaseArtwork(neteaseSongMetadata(song)));
    }
    return covers.where((value) => value.isNotEmpty).toList();
  }
}

/// Resolve real representative covers and repair stale playlist metadata. A
/// retry reads metadata again rather than repeatedly downloading a broken URL.
class NeteaseItemArtwork extends ConsumerStatefulWidget {
  const NeteaseItemArtwork({required this.item, super.key});
  final NeteaseItem item;
  @override
  ConsumerState<NeteaseItemArtwork> createState() => _ItemArtworkState();
}

class _ItemArtworkState extends ConsumerState<NeteaseItemArtwork> {
  NeteaseArtworkRepository? _repository;
  String _uri = '';
  bool _loading = false, _recovered = false;
  bool _retainingRow = false;
  int _imageRecoveries = 0;
  final _rejected = <String>{};
  final _alternatives = <String>[];
  int _epoch = 0;

  // Only these entities have a metadata recovery endpoint in this repository.
  // Other empty covers use ArtworkImage's settled empty state and retain its
  // normal image retry instead of waiting for a request that cannot run.
  bool get _canRecoverMetadata =>
      widget.item.kind == NeteaseEntity.category ||
      widget.item.kind == NeteaseEntity.playlist;
  @override
  void didUpdateWidget(covariant NeteaseItemArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id ||
        oldWidget.item.cover != widget.item.cover) {
      _epoch++;
      _uri = widget.item.cover;
      _recovered = false;
      _retainingRow = false;
      _imageRecoveries = 0;
      _rejected.clear();
      _alternatives.clear();
      _loading = false;
    }
  }

  Future<void> _load({bool explicit = false}) async {
    if (_loading || (!explicit && _recovered)) return;
    if (!_canRecoverMetadata) return;
    final repository = _repository!;
    final epoch = ++_epoch;
    setState(() {
      _loading = true;
      _recovered = true;
      _retainingRow = _retainingRow || explicit;
    });
    try {
      final candidates = widget.item.kind == NeteaseEntity.category
          ? [
              await repository.category(
                widget.item.name,
                refresh: explicit,
                rejected: explicit ? _uri : '',
              ),
            ]
          : await repository.playlist(widget.item.id);
      if (!mounted || epoch != _epoch || !identical(repository, _repository)) {
        return;
      }
      final fresh = candidates.where(
        (uri) =>
            uri != _uri && !_rejected.contains(artworkContentIdentity(uri)),
      );
      if (fresh.isNotEmpty) {
        setState(() {
          _alternatives
            ..clear()
            ..addAll(fresh);
          _uri = _alternatives.removeAt(0);
        });
      }
    } catch (_) {
      // The row and its navigation remain usable; the explicit retry persists.
    } finally {
      if (mounted && epoch == _epoch) setState(() => _loading = false);
    }
  }

  void _imageFailed() {
    if (_loading) return;
    _rejected.add(artworkContentIdentity(_uri));
    if (_alternatives.isNotEmpty) {
      setState(() => _uri = _alternatives.removeAt(0));
      return;
    }
    // Try distinct real covers, never the same rejected CDN resource in a
    // different thumbnail size. Automatic metadata recovery is still bounded.
    if (_imageRecoveries >= 3) return;
    _imageRecoveries++;
    unawaited(_load(explicit: true));
  }

  @override
  Widget build(BuildContext context) {
    final repository = ref.watch(neteaseArtworkRepositoryProvider);
    if (!identical(repository, _repository)) {
      _repository = repository;
      _uri = widget.item.cover;
      _loading = false;
      _recovered = false;
      _retainingRow = false;
      _imageRecoveries = 0;
      _rejected.clear();
      _alternatives.clear();
      _epoch++;
    }
    if (_canRecoverMetadata && _uri.isEmpty && !_recovered && !_loading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_load());
      });
    }
    final content = SizedBox(
      width: 60,
      height: 60,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(
          widget.item.kind == NeteaseEntity.artist ? 30 : 12,
        ),
        child: _uri.isNotEmpty || !_canRecoverMetadata
            ? ArtworkImage(
                uri: _uri,
                width: 60,
                height: 60,
                onLoadFailure: _canRecoverMetadata ? _imageFailed : null,
                onRetry: _canRecoverMetadata
                    ? () => unawaited(_load(explicit: true))
                    : null,
              )
            : _loading || !_recovered
            ? const ArtworkPendingContent(
                child: Center(child: MusicActivityIndicator(independent: true)),
              )
            : TextButton(
                onPressed: () => _load(explicit: true),
                child: const Text('重试'),
              ),
      ),
    );
    return _retainingRow ? ArtworkRevealExclusion(child: content) : content;
  }
}
