import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/track.dart';
import '../../music_platform/cross_platform_music_scope.dart';
import '../../music_platform/domain/platform_session.dart';
import '../../music_platform/music_platform_providers.dart';
import '../../music_platform/platform_backend_providers.dart';

typedef SongCountIdentity = (TrackSource, String);

SongCountIdentity? songCountIdentity(Track track) {
  if (track.source != TrackSource.netease &&
      track.source != TrackSource.kugou) {
    return null;
  }
  final id = track.platformSongId.isNotEmpty
      ? track.platformSongId
      : track.source == TrackSource.netease && track.id.startsWith('netease_')
      ? track.id.substring(8)
      : '';
  return RegExp(r'^[1-9]\d{0,19}$').hasMatch(id) ? (track.source, id) : null;
}

int? _count(Object? value) {
  if (value is int && value >= 0) return value;
  if (value is String && RegExp(r'^\d+$').hasMatch(value)) {
    return int.tryParse(value);
  }
  return null;
}

/// Parse only the requested song's aggregate, never a comment's likes or the
/// current user's library size. Missing and failed responses stay unknown.
int? songFavoriteCount(Map<String, dynamic> payload, SongCountIdentity song) {
  final data = payload['data'];
  if (data is! Map) return null;
  if (song.$1 == TrackSource.netease) {
    return payload['code'] == 200 ? _count(data['count']) : null;
  }
  if (song.$1 != TrackSource.kugou ||
      payload['status'] != 1 ||
      data['list'] is! List) {
    return null;
  }
  for (final row in data['list'] as List) {
    if (row is Map && '${row['mixsongid']}' == song.$2) {
      return _count(row['count']);
    }
  }
  return null;
}

String formatSongFavoriteCount(int count) {
  if (count >= 9990000) return '999w+';
  if (count < 10000) return '$count';
  final value = ((count ~/ 1000) / 10)
      .toStringAsFixed(1)
      .replaceFirst(RegExp(r'\.0$'), '');
  return '${value}w';
}

/// A bounded session cache coalesces list/player reads for the same recording.
class SongFavoriteCountCache {
  final _values = <SongCountIdentity, ({DateTime time, int? count})>{};
  final _pending = <SongCountIdentity, Future<int?>>{};
  final _waiting = <Completer<void>>[];
  int _active = 0;

  void invalidate(SongCountIdentity song) => _values.remove(song);

  Future<int?> load(
    SongCountIdentity song,
    Future<Map<String, dynamic>> Function() request,
    bool Function() current,
  ) {
    final cached = _values[song];
    if (cached != null &&
        DateTime.now().difference(cached.time) < const Duration(minutes: 5)) {
      return Future.value(cached.count);
    }
    return _pending.putIfAbsent(song, () async {
      if (_active >= 4) {
        final ready = Completer<void>();
        _waiting.add(ready);
        await ready.future;
      } else {
        _active++;
      }
      try {
        if (!current()) return null;
        final result = songFavoriteCount(
          await request().timeout(const Duration(seconds: 8)),
          song,
        );
        if (current()) {
          _values.remove(song);
          _values[song] = (time: DateTime.now(), count: result);
          if (_values.length > 256) _values.remove(_values.keys.first);
        }
        return result;
      } on Object {
        if (current()) {
          _values[song] = (time: DateTime.now(), count: null);
          if (_values.length > 256) _values.remove(_values.keys.first);
        }
        return null;
      } finally {
        _pending.remove(song);
        if (_waiting.isEmpty) {
          _active--;
        } else {
          _waiting.removeAt(0).complete();
        }
      }
    });
  }
}

final songFavoriteCountCacheProvider = Provider((ref) {
  ref.watch(
    platformAccountProvider.select(
      (account) => (account.value?.ownerId, account.value?.token),
    ),
  );
  return SongFavoriteCountCache();
});

final songFavoriteCountProvider = FutureProvider.autoDispose
    .family<int?, SongCountIdentity>((ref, song) {
      final cache = ref.watch(songFavoriteCountCacheProvider);
      return cache.load(song, () async {
        final account = ref.read(platformAccountProvider).value;
        if (song.$1 == TrackSource.netease) {
          final music = account?.platform == MusicPlatform.netease
              ? ref.read(neteaseMusicRepositoryProvider)
              : await ref.read(supplementaryNeteaseMusicProvider.future);
          if (!ref.mounted) return const {};
          return music.call('/song/red/count', {'id': song.$2});
        }
        final api = account?.platform == MusicPlatform.kugou
            ? ref.read(musicPlatformApiProvider)
            : await ref.read(supplementaryKugouApiProvider.future);
        if (!ref.mounted) return const {};
        return api.get('/favorite/count', query: {'mixsongids': song.$2});
      }, () => ref.mounted);
    }, retry: (_, _) => null);
