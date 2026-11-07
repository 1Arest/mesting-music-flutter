import 'dart:async';
import '../../core/cache/cached_browse_provider.dart';
import '../../core/cache/browse_response_cache.dart';
import 'dart:collection';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'data/music_platform_api.dart';
import 'data/platform_artwork.dart';
import 'music_platform_providers.dart';

final _artistPortraitRepository = Provider(
  (ref) => _PortraitRepository(ref.watch(musicPlatformApiProvider)),
);
final artistPortraitProvider = FutureProvider.family<String, String>(
  (ref, id) =>
      cachedBrowse(ref, () => ref.watch(_artistPortraitRepository).load(id)),
);

/// Singer search returns names/IDs without portraits. Fetch visible identities
/// only, coalesce duplicates, and cap concurrent metadata requests at three.
class _PortraitRepository {
  _PortraitRepository(this.api);
  final MusicPlatformApi api;
  final _cache = <String, String>{};
  final _pending = <String, Future<String>>{};
  final _waiting = Queue<Completer<void>>();
  int _active = 0;
  Future<String> load(String id) {
    if (!BrowseResponseCache.observing && _cache.containsKey(id)) {
      return Future.value(_cache[id]);
    }
    return _pending.putIfAbsent(
      id,
      () => _load(id).whenComplete(() => _pending.remove(id)),
    );
  }

  Future<String> _load(String id) async {
    if (_active >= 3) {
      final wait = Completer<void>();
      _waiting.add(wait);
      await wait.future;
    } else {
      _active++;
    }
    try {
      final response = await api.get('/artist/detail', query: {'id': id});
      final data = MusicPlatformApi.objectMap(response['data']);
      final url = PlatformArtwork.normalize(data['sizable_avatar']);
      if (url.isNotEmpty) {
        if (_cache.length >= 160) _cache.remove(_cache.keys.first);
        _cache[id] = url;
      }
      return url;
    } catch (_) {
      return '';
    } finally {
      if (_waiting.isNotEmpty) {
        _waiting.removeFirst().complete();
      } else {
        _active--;
      }
    }
  }
}
