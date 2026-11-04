import 'dart:collection';
import '../../../core/cache/browse_response_cache.dart';
import 'dart:async';

import '../../../shared/models/track.dart';
import 'music_platform_api.dart';

/// The upstream endpoints use different cover keys and sometimes return a bare
/// filename in `img` before a usable URL in `sizable_cover`. Pick a valid URL,
/// never the first nonempty value. Preserve HTTP: some Kugou CDNs lack TLS.
class PlatformArtwork {
  static String normalize(Object? value) {
    if (value is! String) return '';
    var text = value.trim().replaceAll('{size}', '400');
    if (text.startsWith('//')) text = 'https:$text';
    final uri = Uri.tryParse(text);
    return uri != null &&
            const {'http', 'https'}.contains(uri.scheme) &&
            uri.host.isNotEmpty
        ? uri.toString()
        : '';
  }

  static String fromPayload(Object? value, [int depth = 0]) {
    if (depth > 7) return '';
    if (value is List) {
      for (final row in value) {
        final result = fromPayload(row, depth + 1);
        if (result.isNotEmpty) return result;
      }
    } else if (value is Map) {
      for (final key in const [
        'sizable_cover',
        'album_sizable_cover',
        'Image',
        'ImgUrl',
        'imgurl',
        'img',
        'pic',
        'cover',
        'image',
        'image_320',
        'cover_pic',
        'union_cover',
        'album_img',
        'album_cover',
        'theme_cover',
        'theme_image',
        'scene_cover',
      ]) {
        final result = normalize(value[key]);
        if (result.isNotEmpty) return result;
      }
      for (final key in const [
        'album_info',
        'albuminfo',
        'audio_info',
        'song_info',
        'base',
        'audio',
        'rec_song_info',
        'trans_param',
        'data',
        'info',
        'list',
        'songs',
      ]) {
        final result = fromPayload(value[key], depth + 1);
        if (result.isNotEmpty) return result;
      }
    }
    return '';
  }
}

/// Read-only, bounded metadata repair for visible songs, including old saved
/// rows. Coalesce requests and cache successful covers, not temporary failures.
/// This repository is independent of widgets, playback and cloud mutations.
class PlatformArtworkRepository {
  PlatformArtworkRepository(this.api);
  final MusicPlatformApi api;
  final _cache = <String, String>{};
  final _pending = <String, Future<String>>{};
  final _waiting = Queue<Completer<void>>();
  int _active = 0;

  Future<void> _acquire() async {
    if (_active < 3) {
      _active++;
      return;
    }
    final waiter = Completer<void>();
    _waiting.add(waiter);
    await waiter.future;
  }

  void _release() {
    if (_waiting.isNotEmpty) {
      _waiting.removeFirst().complete();
    } else {
      _active--;
    }
  }

  Future<String> resolve(Track track) {
    if (track.source != TrackSource.kugou || !track.id.startsWith('kugou_')) {
      return Future.value(track.coverAsset);
    }
    final hash = track.id.substring(6).toLowerCase();
    final cached = _cache.remove(hash);
    if (cached != null && !BrowseResponseCache.observing) {
      _cache[hash] = cached;
      return Future.value(cached);
    }
    return _pending.putIfAbsent(
      hash,
      () => _load(hash).whenComplete(() {
        _pending.remove(hash);
      }),
    );
  }

  Future<String> _load(String hash) async {
    await _acquire();
    try {
      final cover = PlatformArtwork.fromPayload(
        await api.get('/audio', query: {'hash': hash}),
      );
      if (cover.isNotEmpty) {
        _cache[hash] = cover;
        if (_cache.length > 256) _cache.remove(_cache.keys.first);
      }
      return cover;
    } on Object {
      // Artwork failure must never turn a playable song into an audio error.
      return '';
    } finally {
      _release();
    }
  }
}
