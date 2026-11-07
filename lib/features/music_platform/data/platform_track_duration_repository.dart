import 'dart:async';
import 'dart:collection';

import '../../../shared/models/track.dart';
import '../domain/platform_session.dart';
import 'music_platform_api.dart';
import 'platform_song_identity.dart';
import 'platform_track_duration.dart';

/// Read-only, bounded metadata hydration for visible queue rows. Never resolves
/// a stream URL or loads a song into the audio player just to learn its length.
class PlatformTrackDurationRepository {
  PlatformTrackDurationRepository(this.api) : _identity = api.session;
  final MusicPlatformApi api;
  final PlatformSession? _identity;
  final _cache = <String, Duration>{};
  final _pending = <String, _DurationJob>{};
  final _waiting = Queue<_DurationJob>();
  final _failedAt = <String, DateTime>{};
  bool _disposed = false;
  int _active = 0;

  bool get _current =>
      !_disposed &&
      api.session?.userId == _identity?.userId &&
      api.session?.token == _identity?.token &&
      api.session?.vipToken == _identity?.vipToken;

  Future<Duration?> resolve(Track track) {
    if (track.duration > Duration.zero) return Future.value(track.duration);
    if (!_current ||
        track.source != TrackSource.kugou ||
        !track.id.startsWith('kugou_')) {
      return Future.value(null);
    }
    final key = '${track.id}|${track.platformSongId}';
    final cached = _cache[key];
    if (cached != null) return Future.value(cached);
    final failed = _failedAt[key];
    if (failed != null &&
        DateTime.now().difference(failed) < const Duration(seconds: 30)) {
      return Future.value(null);
    }
    final job = _pending.putIfAbsent(key, () {
      final job = _DurationJob(key, track);
      _waiting.add(job);
      return job;
    });
    _drain();
    return job.result.future;
  }

  void _drain() {
    while (_current && _active < 2 && _waiting.isNotEmpty) {
      final job = _waiting.removeFirst();
      _active++;
      unawaited(_run(job));
    }
  }

  Future<void> _run(_DurationJob job) async {
    Duration? duration;
    try {
      final payload = await api
          .get(
            '/audio',
            query: {
              'hash': job.track.id.substring('kugou_'.length).toLowerCase(),
            },
            expectedSession: _identity,
            abortTrigger: job.abort.future,
          )
          .timeout(
            const Duration(seconds: 8),
            onTimeout: () {
              if (!job.abort.isCompleted) job.abort.complete();
              throw TimeoutException('queue metadata');
            },
          );
      if (_current) duration = _matchingDuration(payload, job.track);
      if (_current && duration != null) {
        _cache[job.key] = duration;
        if (_cache.length > 512) _cache.remove(_cache.keys.first);
      }
    } on Object {
      // Optional metadata failure leaves the row usable and honestly unknown.
    } finally {
      if (_current && duration == null) {
        _failedAt[job.key] = DateTime.now();
        if (_failedAt.length > 512) _failedAt.remove(_failedAt.keys.first);
      }
      if (!job.result.isCompleted) {
        job.result.complete(_current ? duration : null);
      }
      _pending.remove(job.key);
      _active--;
      if (_current) {
        _drain();
      } else if (!_disposed) {
        dispose();
      }
    }
  }

  static Duration? _matchingDuration(
    Object? payload,
    Track track, [
    int depth = 0,
  ]) {
    if (depth > 6) return null;
    if (payload is List) {
      for (final row in payload) {
        final duration = _matchingDuration(row, track, depth + 1);
        if (duration != null) return duration;
      }
    } else if (payload is Map) {
      final hash =
          '${payload['hash'] ?? payload['FileHash'] ?? payload['audio_hash'] ?? ''}'
              .toLowerCase();
      if (hash.isNotEmpty &&
          hash != track.id.substring('kugou_'.length).toLowerCase()) {
        return null;
      }
      final recording = PlatformSongIdentity.fromPayload({
        for (final key in [
          'album_audio_id',
          'albumAudioId',
          'AlbumAudioID',
          'MixSongID',
          'mixsongid',
          'mix_song_id',
        ])
          if (payload.containsKey(key)) key: payload[key],
      });
      if (recording.isNotEmpty &&
          track.platformSongId.isNotEmpty &&
          recording != track.platformSongId) {
        return null;
      }
      final duration = PlatformTrackDuration.fromFields(payload);
      if (duration != null) return duration;
      for (final key in [
        'data',
        'info',
        'base',
        'audio_info',
        'song_info',
        'audio',
        'list',
      ]) {
        final nested = _matchingDuration(payload[key], track, depth + 1);
        if (nested != null) return nested;
      }
    }
    return null;
  }

  void dispose() {
    _disposed = true;
    for (final job in _pending.values) {
      if (!job.abort.isCompleted) job.abort.complete();
      if (!job.result.isCompleted) job.result.complete(null);
    }
    _waiting.clear();
    _pending.clear();
    _cache.clear();
    _failedAt.clear();
  }
}

class _DurationJob {
  _DurationJob(this.key, this.track);
  final String key;
  final Track track;
  final result = Completer<Duration?>();
  final abort = Completer<void>();
}
