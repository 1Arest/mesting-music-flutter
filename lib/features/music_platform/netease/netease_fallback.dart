import '../../../core/network/system_music_io_client.dart';
import 'netease_track_sources.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../../../core/persistence/app_preferences.dart';
import '../../../core/diagnostics/app_exit_diagnostics.dart';
import '../../../shared/models/track.dart';
import '../data/embedded_kugou_music_source.dart';
import '../data/music_platform_api.dart';
import '../domain/platform_audio_quality.dart';
import '../music_platform_providers.dart';
import '../platform_backend_providers.dart';
import '../retained_kugou_scope.dart';
import 'fallback/netease_kugou_account_source.dart';
import 'netease_music_repository.dart';
import 'netease_playback_options.dart';
import 'fallback/netease_fallback_source.dart';
import 'fallback/netease_public_sources.dart';
import 'fallback/netease_kuwo_source.dart';
import 'fallback/netease_audio_probe.dart';
import 'fallback/netease_source_transport.dart';
export 'fallback/netease_fallback_source.dart';
export 'fallback/netease_audio_probe.dart';
export 'fallback/netease_source_transport.dart';

final neteaseFallbackEnabledProvider =
    NotifierProvider<NeteaseFallbackSetting, bool>(NeteaseFallbackSetting.new);

class NeteaseFallbackSetting extends Notifier<bool> {
  static const key = 'netease_same_recording_fallback_v1';
  @override
  bool build() => ref.watch(sharedPreferencesProvider).getBool(key) ?? true;
  Future<void> setEnabled(bool value) async {
    if (!await ref.read(sharedPreferencesProvider).setBool(key, value)) {
      throw const MusicPlatformException('补源设置未保存，请重试');
    }
    state = value;
  }
}

/// Exact NetEase IDs avoid cross-platform title matching. This public service
/// is anonymous: only a song ID and requested quality leave the device.
/// Calls are serialized at >=1s intervals per the provider's published limit.
class BugpkRequestGate {
  Future<void> _tail = Future.value();
  DateTime _lastRequest = DateTime.fromMillisecondsSinceEpoch(0);
  Future<Track?> run(
    Future<Track?> Function() request,
    bool Function() current,
  ) {
    final result = _tail.then((_) async {
      if (!current()) return null;
      final delay =
          const Duration(milliseconds: 1100) -
          DateTime.now().difference(_lastRequest);
      if (delay > Duration.zero) await Future<void>.delayed(delay);
      if (!current()) return null;
      _lastRequest = DateTime.now();
      return request();
    });
    _tail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }
}

class BugpkNeteaseFallback implements NeteaseExactIdSource {
  BugpkNeteaseFallback(this.client, {BugpkRequestGate? gate})
    : gate = gate ?? BugpkRequestGate();
  final http.Client client;
  final BugpkRequestGate gate;
  @override
  String get label => 'BugPk · 网易云同曲';
  @override
  Future<List<Track>> search(Track original) async => [original];
  @override
  Future<Track?> resolve(Track candidate) {
    return gate.run(
      () async {
        final id = candidate.platformSongId.isNotEmpty
            ? candidate.platformSongId
            : candidate.id.replaceFirst('netease_', '');
        final response = await client
            .get(
              Uri.https('api.bugpk.com', '/api/163_music', {
                'type': 'url',
                'id': id,
                'level': switch (candidate.playbackQuality) {
                  'flac' => 'lossless',
                  'high' => 'hires',
                  '320' => 'exhigh',
                  _ => 'standard',
                },
              }),
            )
            .timeout(const Duration(seconds: 12));
        if (response.statusCode != 200) {
          throw NeteaseSourceFailure(
            'resolve_http_error',
            httpStatus: response.statusCode,
          );
        }
        final payload = MusicPlatformApi.objectMap(
          jsonDecode(utf8.decode(response.bodyBytes)),
        );
        if (payload['code'] != 200) {
          throw const NeteaseSourceFailure('provider_unavailable');
        }
        final rows = payload['data'];
        final row = MusicPlatformApi.objectMap(
          rows is List && rows.isNotEmpty ? rows.first : rows,
        );
        if ('${row['id']}' != id) {
          throw const NeteaseSourceFailure('wrong_song_id');
        }
        if (row['freeTrialInfo'] is Map) {
          throw const NeteaseSourceFailure('preview_rejected');
        }
        final supplied = Uri.tryParse('${row['url'] ?? ''}');
        if (supplied == null) return null;
        final url = await _audioUrl(supplied, id);
        if (url == null) return null;
        final duration = int.tryParse('${row['time']}') ?? 0;
        if (duration > 0 &&
            duration <= 90000 &&
            candidate.duration.inMilliseconds > duration + 2000) {
          throw const NeteaseSourceFailure('preview_rejected');
        }
        final delivered = switch ('${row['level']}') {
          'standard' => '128',
          'higher' || 'exhigh' => '320',
          'lossless' => 'flac',
          'hires' => 'high',
          _ => '',
        };
        // Some provider responses silently downgrade. Keep the delivered tier.
        return candidate.copyWith(
          audioAsset: url.toString(),
          audioHeaders: const {},
          audioBitrate:
              int.tryParse('${row['br']}') ??
              switch ('${row['level']}') {
                'standard' => 128000,
                'higher' => 192000,
                'exhigh' => 320000,
                _ => 0,
              },
          isPreview: false,
          playbackQuality: delivered,
        );
      },
      () =>
          client is! NeteaseSourceClient ||
          !(client as NeteaseSourceClient).isClosed,
    );
  }

  /// The provider also returns official outer links. Resolve those anonymously
  /// with redirects disabled, validate every hop, and upgrade only known music
  /// CDN HTTP redirects to HTTPS. An arbitrary third-party location is rejected.
  Future<Uri?> _audioUrl(Uri uri, String songId) async {
    for (var hop = 0; hop < 3; hop++) {
      if (uri.userInfo.isNotEmpty || !{'http', 'https'}.contains(uri.scheme)) {
        throw const NeteaseSourceFailure('redirect_not_audio');
      }
      if (uri.host.endsWith('.music.126.net')) {
        return uri.replace(scheme: 'https');
      }
      if (uri.host != 'music.163.com' ||
          uri.path != '/song/media/outer/url' ||
          (uri.queryParameters['id'] ?? '').replaceFirst(
                RegExp(r'\.mp3$'),
                '',
              ) !=
              songId) {
        throw const NeteaseSourceFailure('redirect_not_audio');
      }
      final request = http.Request('GET', uri.replace(scheme: 'https'))
        ..followRedirects = false
        ..headers['Range'] = 'bytes=0-1023';
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 8));
      final location = response.headers['location'];
      await response.stream.take(1).drain<void>();
      if (![301, 302, 303, 307, 308].contains(response.statusCode) ||
          location == null) {
        throw NeteaseSourceFailure(
          'media_redirect_failed',
          httpStatus: response.statusCode,
        );
      }
      uri = uri.resolve(location);
    }
    return null;
  }
}

/// This anonymous API is owned exclusively by the fallback module. It never
/// observes either saved platform session, including a retained Kugou login.
class AnonymousKugouFallback implements NeteaseFallbackSource {
  AnonymousKugouFallback(this.source);
  final EmbeddedKugouMusicSource source;
  @override
  String get label => '酷狗公开音源';
  @override
  Future<List<Track>> search(Track original) =>
      source.search('${original.title} ${original.artist}', limit: 12);
  @override
  Future<Track?> resolve(Track candidate) async {
    final result = await source.resolveTrack(
      candidate,
      quality:
          PlatformAudioQuality.fromCode(candidate.playbackQuality) ??
          PlatformAudioQuality.high,
    );
    return result.isPreview ? null : result;
  }
}

/// Preserve the existing exported adapter name; its transport now follows the
/// anonymous mobile API instead of the failing desktop HTML search page.
class AnonymousKuwoFallback extends KuwoPublicSource {
  AnonymousKuwoFallback(super.client);
}

class NeteaseFallbackDiagnostics extends ChangeNotifier {
  final List<Map<String, Object?>> _rows = [];
  bool _disposed = false;
  bool _exitHistoryRead = false;
  List<Map<String, Object?>> get rows => List.unmodifiable(_rows);
  String get json => const JsonEncoder.withIndent('  ').convert(_rows);

  Future<void> includeExitHistory() async {
    if (_exitHistoryRead || _disposed) return;
    _exitHistoryRead = true;
    for (final exit in await AppExitDiagnostics.recent()) {
      if (_disposed) return;
      _rows.add({
        'time': DateTime.fromMillisecondsSinceEpoch(
          exit.timestampMs,
          isUtc: true,
        ).toIso8601String(),
        'source': 'Android历史退出',
        'result': exit.reason,
        'exitStatus': exit.status,
        'pssKiB': exit.pssKiB,
        'rssKiB': exit.rssKiB,
        'versionUnknown': true,
        'nativeTrace': ?exit.nativeTrace?.toJson(),
      });
      if (_rows.length > 80) _rows.removeAt(0);
    }
    if (!_disposed) notifyListeners();
  }

  // Deliberately excludes URLs, song names, account IDs and exception strings.
  void record(
    String source,
    String outcome,
    int elapsedMs, {
    int bitrate = 0,
    int? candidates,
    int? matches,
    int? httpStatus,
    int? mediaBytes,
    int? mediaDurationMs,
  }) {
    if (_disposed) return;
    _rows.add({
      'time': DateTime.now().toUtc().toIso8601String(),
      'source': source,
      'result': outcome,
      'elapsedMs': elapsedMs,
      if (bitrate > 0) 'bitrate': bitrate,
      'candidates': ?candidates,
      'matches': ?matches,
      'httpStatus': ?httpStatus,
      'mediaBytes': ?mediaBytes,
      'mediaDurationMs': ?mediaDurationMs,
    });
    if (_rows.length > 80) _rows.removeAt(0);
    notifyListeners();
  }

  void clear() {
    if (_disposed) return;
    _rows.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

final neteaseFallbackDiagnosticsProvider = Provider<NeteaseFallbackDiagnostics>(
  (ref) {
    final value = NeteaseFallbackDiagnostics();
    ref.listen(neteasePlaybackOptionsProvider.select((o) => o.diagnostics), (
      _,
      enabled,
    ) {
      if (enabled) unawaited(value.includeExitHistory());
    });
    if (ref.read(neteasePlaybackOptionsProvider).diagnostics) {
      unawaited(value.includeExitHistory());
    }
    ref.onDispose(value.dispose);
    return value;
  },
);

class NeteaseFallbackResolver {
  NeteaseFallbackResolver(
    this.sources,
    this.client, {
    this.options = const NeteasePlaybackOptions(),
    this.diagnostics,
    this.sourceTimeout = const Duration(seconds: 10),
    this.groupTimeout = const Duration(seconds: 20),
    this.sourceFactories = const [],
    this.sessionCurrent,
  });
  final List<NeteaseFallbackSource> sources;
  final http.Client client;
  final NeteasePlaybackOptions options;
  final NeteaseFallbackDiagnostics? diagnostics;
  final Duration sourceTimeout, groupTimeout;
  final List<NeteaseSourceFactory> sourceFactories;
  final bool Function()? sessionCurrent;
  final Map<String, ({Track track, DateTime until})> _cache = {};
  bool _disposed = false;
  void clearCache() => _cache.clear();
  void invalidate() {
    _disposed = true;
    clearCache();
  }

  Future<Track?> resolve(
    Track original, {
    required bool Function() current,
    String? requiredQuality,
    String? onlySource,
    String? requiredRecordingId,
    Future<void>? abortTrigger,
  }) async {
    final clients = <NeteaseFallbackSource, NeteaseSourceClient>{};
    final cacheProbe = NeteaseSourceClient(client);
    var cancelled = false;
    for (final factory in sourceFactories) {
      final scoped = NeteaseSourceClient(client, timeout: sourceTimeout);
      clients[factory.create(scoped)] = scoped;
    }
    void cancel() {
      cancelled = true;
      cacheProbe.close();
      for (final scoped in clients.values) {
        scoped.close();
      }
    }

    if (abortTrigger != null) unawaited(abortTrigger.then((_) => cancel()));
    try {
      return await _resolve(
        original,
        current: () =>
            !_disposed &&
            !cancelled &&
            (sessionCurrent?.call() ?? true) &&
            current(),
        requiredQuality: requiredQuality,
        requiredRecordingId: requiredRecordingId,
        activeSources: [...sources, ...clients.keys]
            .where((source) => onlySource == null || source.label == onlySource)
            .toList(),
        clients: clients,
        cacheProbeClient: cacheProbe,
      );
    } finally {
      cancel();
    }
  }

  Future<Track?> _resolve(
    Track original, {
    required bool Function() current,
    required List<NeteaseFallbackSource> activeSources,
    required Map<NeteaseFallbackSource, NeteaseSourceClient> clients,
    required http.Client cacheProbeClient,
    String? requiredQuality,
    String? requiredRecordingId,
  }) async {
    final key =
        '${original.id}|${original.title}|${original.artist}|${original.album}|${original.duration.inMilliseconds}|${original.playbackQuality}|$requiredQuality|$requiredRecordingId|${activeSources.map((s) => s.label).join(',')}';
    final cached = options.cache ? _cache[key] : null;
    if (cached != null && cached.until.isAfter(DateTime.now()) && current()) {
      try {
        if ((await inspectNeteaseAudio(
              cacheProbeClient,
              cached.track.audioAsset,
              headers: cached.track.audioHeaders,
              expectedDuration: original.duration,
              requireLossless: {
                'flac',
                'high',
              }.contains(cached.track.playbackQuality),
            )).playable &&
            current()) {
          return cached.track;
        }
      } catch (_) {
        /* Expired CDN URLs are resolved again, never replayed. */
      }
      _cache.remove(key);
    }
    if (!current()) return null;
    final groupWatch = Stopwatch()..start();
    Future<Track?> attempt(
      NeteaseFallbackSource source, {
      bool terminal = false,
    }) async {
      if (!current() || (!terminal && groupWatch.elapsed >= groupTimeout)) {
        return null;
      }
      final watch = Stopwatch()..start();
      var alive = true;
      var outcome = 'no_complete_stream';
      int? candidateCount, matchCount;
      NeteaseAudioProbe? media;
      bool valid() =>
          alive && current() && (terminal || groupWatch.elapsed < groupTimeout);
      Future<Track?> work() async {
        final seen = <String>{};
        Stream<Track> matchingCandidates() async* {
          for (var pass = 0; pass < 2; pass++) {
            if (!valid()) return;
            if (pass == 1 && source is! NeteaseAlternativeSearchSource) return;
            final candidates = pass == 0
                ? await source.search(original)
                : await (source as NeteaseAlternativeSearchSource)
                      .searchAlternative(original);
            if (!valid()) return;
            candidateCount = (candidateCount ?? 0) + candidates.length;
            final matched = candidates
                .where(
                  (c) =>
                      source is NeteaseExactIdSource ||
                      isSameNeteaseRecording(
                        original,
                        c,
                        allowMissingAlbum:
                            source is NeteasePublicMetadataSource,
                        durationTolerance: recordingDurationTolerance(
                          source,
                          original,
                        ),
                      ),
                )
                .where(
                  (candidate) =>
                      (requiredRecordingId == null ||
                          candidate.id == requiredRecordingId) &&
                      seen.add(candidate.id),
                )
                .toList();
            matchCount = (matchCount ?? 0) + matched.length;
            if (matchCount == 0) {
              outcome = candidateCount == 0
                  ? 'no_search_results'
                  : 'recording_mismatch';
            }
            for (final candidate in matched) {
              yield candidate;
            }
          }
        }

        await for (final candidate in matchingCandidates().take(2)) {
          if (!valid()) return null;
          final wanted =
              requiredQuality ??
              (!terminal &&
                      options.strategy ==
                          NeteaseSourceStrategy.highestQuality &&
                      options.lossless
                  ? 'flac'
                  : original.playbackQuality);
          Track? resolved;
          try {
            resolved = await source.resolve(
              candidate.copyWith(
                // A new provider must establish its own media requirements;
                // history may still carry a previous provider's header/bitrate.
                audioHeaders: const {},
                audioBitrate: 0,
                playbackQuality: options.lossless
                    ? wanted
                    : ({'flac', 'high'}.contains(wanted) ? '320' : wanted),
              ),
            );
          } on NeteaseSourceFailure catch (error) {
            outcome = error.reason;
            // One removed/preview candidate must not suppress another matched
            // recording. All candidates still share the same time/I/O budget.
            continue;
          }
          if (!valid()) return null;
          if (resolved == null) {
            outcome = 'no_complete_stream';
            continue;
          }
          if (resolved.isPreview) {
            outcome = 'preview_rejected';
            continue;
          }
          if (source is! AccountKugouFallback &&
              requiredQuality != null &&
              resolved.playbackQuality.isNotEmpty &&
              resolved.playbackQuality != requiredQuality) {
            outcome = 'requested_quality_unavailable';
            continue;
          }
          var bitrate = resolved.audioBitrate > 0
              ? resolved.audioBitrate
              : (int.tryParse(resolved.playbackQuality) ?? 0) * 1000;
          media = await inspectNeteaseAudio(
            clients[source] ?? client,
            resolved.audioAsset,
            headers: resolved.audioHeaders,
            requireLossless: {
              'flac',
              'high',
            }.contains(resolved.playbackQuality),
            minimumBytes: original.duration.inSeconds > 60 && bitrate > 0
                ? (original.duration.inSeconds * bitrate / 8 * .4).round()
                : 0,
            expectedDuration: original.duration,
          );
          if (!media!.playable) {
            outcome = media!.reason;
            continue;
          }
          if (source is AccountKugouFallback) {
            // Account adapters may echo the requested tier. Measured MP3
            // frames and FLAC STREAMINFO, rather than that label, own the badge.
            bitrate = media!.bitrate > 0
                ? media!.bitrate
                : resolved.audioBitrate;
          } else if (bitrate == 0) {
            bitrate = media!.bitrate;
          }
          final delivered =
              source is AccountKugouFallback && media!.format == 'flac'
              ? (media!.hiRes ? 'high' : 'flac')
              : source is AccountKugouFallback
              ? (media!.bitrate > 0
                    ? (media!.bitrate > 220000 ? '320' : '128')
                    : '')
              : resolved.playbackQuality.isNotEmpty
              ? resolved.playbackQuality
              : media!.format == 'mp3' && bitrate > 0 && bitrate <= 400000
              ? (bitrate > 220000 ? '320' : '128')
              : '';
          if (requiredQuality != null && delivered != requiredQuality) {
            outcome = 'requested_quality_unavailable';
            continue;
          }
          if (options.minimumBitrate > 0 &&
              !{'flac', 'high'}.contains(delivered) &&
              bitrate < options.minimumBitrate) {
            outcome = bitrate == 0
                ? 'bitrate_unknown'
                : 'below_minimum_bitrate';
            continue;
          }
          if (media!.totalBytes != null &&
              original.duration.inSeconds > 90 &&
              bitrate > 0 &&
              !{'flac', 'high'}.contains(delivered) &&
              media!.totalBytes! <
                  original.duration.inSeconds * bitrate / 8 * .4) {
            outcome = 'media_too_short';
            continue;
          }
          if (!valid()) return null;
          return original.copyWith(
            audioAsset: resolved.audioAsset,
            audioOrigin: AudioOrigin(source.label, candidate.id),
            audioHeaders: publicAudioHeaders(resolved.audioHeaders),
            audioBitrate: bitrate,
            isPreview: false,
            playbackQuality: delivered,
            availabilityMessage: '备用音源 · ${source.label}',
          );
        }
        return null;
      }

      try {
        final result = await work().timeout(sourceTimeout);
        if (options.diagnostics && current()) {
          diagnostics?.record(
            source.label,
            result == null ? outcome : 'ready',
            watch.elapsedMilliseconds,
            bitrate: result?.audioBitrate ?? 0,
            candidates: candidateCount,
            matches: matchCount,
            mediaBytes: media?.totalBytes,
            mediaDurationMs: media?.duration?.inMilliseconds,
          );
        }
        return result;
      } catch (error) {
        if (options.diagnostics && current()) {
          diagnostics?.record(
            source.label,
            error is NeteaseSourceFailure
                ? error.reason
                : error is TimeoutException
                ? 'request_timed_out'
                : error is http.RequestAbortedException
                ? 'request_cancelled_or_timed_out'
                : error is FormatException
                ? 'response_invalid'
                : 'request_failed',
            watch.elapsedMilliseconds,
            candidates: candidateCount,
            matches: matchCount,
            httpStatus: error is NeteaseSourceFailure ? error.httpStatus : null,
          );
        }
        return null;
      } finally {
        alive = false;
        clients[source]?.close();
      }
    }

    Track? accountResult;
    for (final source in activeSources.whereType<AccountKugouFallback>()) {
      accountResult = await attempt(source);
      if (accountResult != null || !current()) break;
    }
    if (!current()) return null;
    final newer = activeSources
        .where((s) => s is! BugpkNeteaseFallback && s is! AccountKugouFallback)
        .toList();
    Track? result = accountResult;
    if (result == null && options.strategy == NeteaseSourceStrategy.ordered) {
      for (final source in newer) {
        result = await attempt(source);
        if (result != null || !current()) break;
      }
    } else if (result == null) {
      // At most two metadata/media probes at once. BugPk is a separate final
      // stage, so a high bitrate there cannot override a working new source.
      var cursor = 0;
      final ready = <Track>[];
      Future<void> worker() async {
        while (cursor < newer.length &&
            current() &&
            groupWatch.elapsed < groupTimeout) {
          final source = newer[cursor++];
          final found = await attempt(source);
          if (found != null) ready.add(found);
        }
      }

      await Future.wait([worker(), worker()]);
      int rank(Track track) => switch (track.playbackQuality) {
        'high' => 20000000,
        'flac' => 10000000,
        _ => track.audioBitrate,
      };
      ready.sort((a, b) => rank(b).compareTo(rank(a)));
      result = ready.firstOrNull;
    }
    if (!current()) return null;
    if (result == null) {
      for (final source in activeSources.whereType<BugpkNeteaseFallback>()) {
        result = await attempt(source, terminal: true);
        if (result != null || !current()) break;
      }
    }
    if (!current()) return null;
    if (result != null && options.cache) {
      if (_cache.length >= 32) _cache.remove(_cache.keys.first);
      _cache[key] = (
        track: result,
        until: DateTime.now().add(const Duration(seconds: 45)),
      );
    }
    return result;
  }
}

final neteaseFallbackResolverProvider = Provider<NeteaseFallbackResolver>((
  ref,
) {
  final client = SystemMusicIoClient();
  // A session epoch owns its own anonymous caches, even though no credential
  // is sent to these adapters. Account switches dispose all pending I/O.
  ref.watch(
    platformAccountProvider.select((a) => (a.value?.ownerId, a.value?.token)),
  );
  final options = ref.watch(neteasePlaybackOptionsProvider);
  ref.onDispose(client.close);
  final server = ref.watch(musicServerProvider);
  final bugpkGate = BugpkRequestGate();
  final account = ref.watch(retainedKugouScopeProvider);
  final resolver = NeteaseFallbackResolver(
    const [],
    client,
    sessionCurrent: () =>
        ref.mounted && identical(ref.read(retainedKugouScopeProvider), account),
    sourceFactories: [
      if (account != null)
        NeteaseSourceFactory(
          (scoped) => AccountKugouFallback(
            EmbeddedKugouMusicSource(
              scoped,
              MusicPlatformApi(
                server: server,
                client: scoped,
                sessionCurrent: () =>
                    account.current &&
                    ref.mounted &&
                    identical(ref.read(retainedKugouScopeProvider), account),
              )..session = account.owner,
            ),
            current: () =>
                account.current &&
                ref.mounted &&
                identical(ref.read(retainedKugouScopeProvider), account),
          ),
        ),
      if (options.enabledSources.contains(NeteasePublicSource.kugou))
        NeteaseSourceFactory(
          (scoped) => AnonymousKugouFallback(
            EmbeddedKugouMusicSource(
              scoped,
              MusicPlatformApi(server: server, client: scoped),
            ),
          ),
        ),
      if (options.enabledSources.contains(NeteasePublicSource.kuwo))
        NeteaseSourceFactory(AnonymousKuwoFallback.new),
      if (options.enabledSources.contains(NeteasePublicSource.bilibili))
        NeteaseSourceFactory(BilibiliAudioSource.new),
      if (options.enabledSources.contains(NeteasePublicSource.bilivideo))
        NeteaseSourceFactory(BilibiliVideoSource.new),
      NeteaseSourceFactory(
        (scoped) => BugpkNeteaseFallback(scoped, gate: bugpkGate),
      ),
    ],
    options: options,
    diagnostics: ref.watch(neteaseFallbackDiagnosticsProvider),
  );
  ref.onDispose(resolver.invalidate);
  return resolver;
});

/// A newer explicit selection cancels the previous playback lookup, including
/// its HTTP requests. Downloads call the resolver independently and keep their
/// own scope, so playback cancellation cannot abort a user's download queue.
class NeteasePlaybackRequests {
  int _epoch = 0;
  Completer<void>? _pending;
  ({int epoch, Future<void> abort}) begin() {
    cancel();
    _pending = Completer<void>();
    return (epoch: _epoch, abort: _pending!.future);
  }

  bool current(int epoch) => epoch == _epoch && _pending != null;
  void finish(int epoch) {
    if (current(epoch)) cancel();
  }

  void cancel() {
    ++_epoch;
    if (_pending?.isCompleted == false) _pending!.complete();
    _pending = null;
  }
}

final neteasePlaybackRequestsProvider = Provider<NeteasePlaybackRequests>((
  ref,
) {
  final requests = NeteasePlaybackRequests();
  ref.onDispose(requests.cancel);
  return requests;
});

Future<Track> resolveNeteasePlayback(
  WidgetRef ref,
  Track track,
  PlatformAudioQuality quality, {
  bool requireQuality = false,
}) async {
  final music = ref.read(neteaseMusicRepositoryProvider);
  final credential = music.credential;
  final requests = ref.read(neteasePlaybackRequestsProvider);
  final request = requests.begin();
  bool current() =>
      ref.context.mounted &&
      requests.current(request.epoch) &&
      ref.read(usesNeteaseProvider) &&
      ref.read(neteaseMusicRepositoryProvider).credential == credential;
  try {
    return await resolveNeteaseTrack(
      music: music,
      fallback: ref.read(neteaseFallbackResolverProvider),
      allowFallback: ref.read(neteaseFallbackEnabledProvider),
      current: current,
      track: track,
      quality: quality,
      requireQuality: requireQuality,
      selectedSource:
          ref.read(neteaseTrackSourcesProvider)[track.id] ??
          NeteaseTrackSource.automatic,
      abortTrigger: request.abort,
    );
  } finally {
    requests.finish(request.epoch);
  }
}

/// Playback and quality changes share the same source decision. Keeping the
/// decision independent of WidgetRef makes queue/autoplay failure cases testable.
Future<Track> resolveNeteaseTrack({
  required NeteaseMusicRepository music,
  required NeteaseFallbackResolver fallback,
  required bool allowFallback,
  required bool Function() current,
  required Track track,
  required PlatformAudioQuality quality,
  bool requireQuality = false,
  NeteaseTrackSource selectedSource = NeteaseTrackSource.automatic,
  Future<void>? abortTrigger,
}) async {
  if (quality.neteaseOnly && requireQuality && selectedSource.adapter != null) {
    throw const MusicPlatformException('此档位仅由网易云官方音源提供，请选择自动或网易云官方');
  }
  if (selectedSource.adapter != null) {
    final selected = await fallback.resolve(
      track.copyWith(playbackQuality: quality.code),
      current: current,
      requiredQuality: requireQuality ? quality.code : null,
      onlySource: selectedSource.adapter,
      abortTrigger: abortTrigger,
    );
    if (!current()) throw const MusicPlatformException('播放请求已取消或账号已变化');
    if (selected == null) {
      throw MusicPlatformException(
        '${selectedSource.label}暂未提供这首歌的完整版本，请重新检测或选择自动',
      );
    }
    return selected;
  }
  Track? original;
  Object? failure;
  try {
    original = await music.resolve(
      track,
      quality,
      requireQuality: requireQuality,
      abortTrigger: abortTrigger,
    );
  } catch (error) {
    failure = error;
  }
  if (!current()) throw const MusicPlatformException('播放请求已取消或账号已变化');
  if (original != null && !original.isPreview) return original;
  if (quality.neteaseOnly && requireQuality) {
    throw failure ?? const MusicPlatformException('网易云未提供所选档位的完整音频，已保留原音源');
  }
  if (failure is MusicPlatformException &&
      {'301', '302', '415', '405', '460'}.contains(failure.code)) {
    throw failure;
  }
  if (selectedSource == NeteaseTrackSource.official) {
    if (original != null && !original.isPreview) return original;
    throw failure ?? const MusicPlatformException('网易云官方当前未提供完整音频');
  }
  if (allowFallback) {
    final resolved = await fallback.resolve(
      track.copyWith(playbackQuality: quality.code),
      current: current,
      requiredQuality: requireQuality ? quality.code : null,
      abortTrigger: abortTrigger,
    );
    if (resolved != null) return resolved;
  }
  if (!current()) throw const MusicPlatformException('账号已变化，请重新播放');
  if (original != null) {
    return original.copyWith(
      availabilityMessage: allowFallback
          ? '网易云试听片段 · 备用音源暂未提供完整版本'
          : '网易云试听片段 · 备用音源已关闭',
    );
  }
  throw failure ?? const MusicPlatformException('未找到同一录音版本的可播放音源');
}
