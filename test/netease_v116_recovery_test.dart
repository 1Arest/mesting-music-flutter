import 'dart:async';
import 'dart:convert';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mesting_music/core/audio/mesting_audio_handler.dart';
import 'package:mesting_music/core/diagnostics/app_exit_diagnostics.dart';
import 'package:mesting_music/shared/models/track.dart';
import 'package:mesting_music/features/music_platform/netease/netease_fallback.dart';
import 'package:mesting_music/features/music_platform/netease/netease_playback_options.dart';
import 'package:mesting_music/features/music_platform/netease/fallback/netease_public_sources.dart';
import 'netease_v112_fallback_download_test.dart' show recording, until;
import 'support/deterministic_audio_player.dart';

http.Response jsonBody(Object value, {int status = 200}) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json'},
);

/// Realistic MPEG1/L3 Info-frame counts. Both full streams and 11s spoken
/// restriction messages are valid MP3; the latter must fail the duration gate.
List<int> mp3Prefix(int seconds) {
  final bytes = List<int>.filled(1024, 0);
  bytes.setRange(0, 4, [255, 251, 144, 0]);
  bytes.setRange(36, 40, ascii.encode('Info'));
  bytes[43] = 1;
  final frames = (seconds * 44100 / 1152).round();
  for (var i = 0; i < 4; i++) {
    bytes[44 + i] = frames >> (24 - 8 * i) & 255;
  }
  return bytes;
}

http.Response mp3Response(int seconds) => http.Response.bytes(
  mp3Prefix(seconds),
  206,
  headers: {
    'content-type': 'audio/mpeg',
    'content-range': 'bytes 0-1023/${seconds * 16000}',
  },
);

class FixtureSource implements NeteaseFallbackSource {
  FixtureSource({this.items, this.resolveValue, this.client});
  final List<Track>? items;
  final Track? resolveValue;
  final http.Client? client;
  @override
  String get label => 'fixture';
  @override
  Future<List<Track>> search(Track original) async {
    await client?.get(Uri.https('example.test', '/search'));
    return items ?? [original];
  }

  @override
  Future<Track?> resolve(Track candidate) async => resolveValue;
}

class WaitingClient extends http.BaseClient {
  final started = Completer<void>();
  bool aborted = false, closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = Completer<http.StreamedResponse>();
    if (!started.isCompleted) started.complete();
    if (request is http.AbortableRequest) {
      unawaited(
        request.abortTrigger!.then((_) {
          aborted = true;
          if (!response.isCompleted) {
            response.completeError(http.RequestAbortedException());
          }
        }),
      );
    }
    return response.future;
  }

  @override
  void close() {
    closed = true;
    super.close();
  }
}

class CompletionPlayer extends DeterministicAudioPlayer {
  final completions = StreamController<ProcessingState>.broadcast();
  @override
  Stream<ProcessingState> get processingStateStream => completions.stream;
}

class AlternativeFixture extends FixtureSource
    implements NeteaseAlternativeSearchSource {
  AlternativeFixture({required this.emptyFirst});
  final bool emptyFirst;
  final resolutions = <String>[];
  int queries = 0;
  @override
  Future<List<Track>> search(Track original) async {
    queries++;
    return emptyFirst ? [] : [recording(id: 'stale')];
  }

  @override
  Future<List<Track>> searchAlternative(Track original) async {
    queries++;
    return [recording(id: 'fresh')];
  }

  @override
  Future<Track?> resolve(Track candidate) async {
    resolutions.add(candidate.id);
    if (candidate.id == 'stale') {
      throw const NeteaseSourceFailure('video_unavailable');
    }
    return candidate.copyWith(audioAsset: 'https://example.test/full');
  }
}

Track localSong(String id) => Track(
  id: id,
  title: id,
  artist: 'fixture',
  album: '',
  duration: const Duration(minutes: 4),
  audioAsset: 'assets/$id.mp3',
  coverAsset: '',
  lyricsAsset: '',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'a VBR first-frame bitrate cannot confirm a requested quality',
    () async {
      final data = mp3Prefix(274)..setRange(36, 40, ascii.encode('Xing'));
      final probe = await inspectNeteaseAudio(
        MockClient(
          (_) async => http.Response.bytes(
            data,
            206,
            headers: {'content-type': 'audio/mpeg'},
          ),
        ),
        'https://example.test/audio',
        expectedDuration: const Duration(seconds: 274),
      );
      expect(probe.playable, isTrue);
      expect(probe.bitrate, 0);
    },
  );
  test(
    'MP4 header duration rejects previews without downloading media',
    () async {
      List<int> box(String name, List<int> bytes) => [
        ...[24, 16, 8, 0].map((s) => (bytes.length + 8) >> s & 255),
        ...ascii.encode(name),
        ...bytes,
      ];
      for (final seconds in [30, 274]) {
        final mdhd = List<int>.filled(24, 0);
        for (var i = 0; i < 4; i++) {
          mdhd[12 + i] = 48000 >> (24 - 8 * i) & 255;
          mdhd[16 + i] = seconds * 48000 >> (24 - 8 * i) & 255;
        }
        final bytes = [
          ...box('ftyp', ascii.encode('M4A ')),
          ...box('moov', box('trak', box('mdia', box('mdhd', mdhd)))),
        ];
        final found = await inspectNeteaseAudio(
          MockClient(
            (_) async => http.Response.bytes(
              bytes,
              206,
              headers: {'content-type': 'audio/mp4'},
            ),
          ),
          'https://example.test/audio.m4s',
          expectedDuration: const Duration(seconds: 274),
        );
        expect(found.duration, Duration(seconds: seconds));
        expect(found.playable, seconds == 274);
      }
    },
  );
  test('lyric captions require evidence from the original LRC', () {
    final original = recording();
    const title = '【Hi-Res无损】薛之谦-陪你去流浪「也知道下场不怎么样 就快要夜深人静了」动态歌词';
    expect(bilibiliRecordingTitle(title, original), isNot(original.title));
    expect(
      bilibiliRecordingTitle(
        title,
        original,
        lyricEvidence: '[00:32.00]也知道下场不怎么样\n[00:35.00]就快要夜深人静了',
      ),
      original.title,
    );
    expect(
      bilibiliRecordingTitle(title, original, lyricEvidence: '[00:00.00]另一首歌'),
      isNot(original.title),
    );
    expect(
      bilibiliRecordingTitle(
        '【Hi-Res无损】薛之谦-陪你去流浪 (Live)「也知道下场不怎么样」动态歌词',
        original,
        lyricEvidence: '也知道下场不怎么样',
      ),
      isNot(original.title),
    );
  });
  for (final emptyFirst in [false, true]) {
    test(
      'a bounded alternative query recovers after stale/empty results, empty=$emptyFirst',
      () async {
        final source = AlternativeFixture(emptyFirst: emptyFirst);
        final found = await NeteaseFallbackResolver(
          [source],
          MockClient((_) async => mp3Response(274)),
        ).resolve(recording(), current: () => true);
        expect(found!.audioAsset, 'https://example.test/full');
        expect(source.queries, 2);
        expect(source.resolutions, emptyFirst ? ['fresh'] : ['stale', 'fresh']);
      },
    );
  }
  test(
    'anonymous Kuwo mobile sections preserve recording evidence without cookies',
    () async {
      final requests = <http.Request>[];
      final source = AnonymousKuwoFallback(
        MockClient((r) async {
          requests.add(r);
          expect(r.headers['cookie'], isNull);
          expect(r.headers['authorization'], isNull);
          if (r.url.host == 'search.kuwo.cn') {
            return jsonBody({
              'content': [
                {'interestpage': {}},
                {
                  'musicpage': {
                    'abslist': [
                      {
                        'MUSICRID': 'MUSIC_71401250',
                        'SONGNAME': '陪你去流浪',
                        'ARTIST': '薛之谦',
                        'ALBUM': '尘',
                        'DURATION': '274',
                      },
                      {
                        'MUSICRID': 'MUSIC_2',
                        'SONGNAME': '陪你去流浪 (Live)',
                        'ARTIST': '薛之谦',
                        'ALBUM': '现场',
                        'DURATION': '274',
                      },
                    ],
                  },
                },
              ],
            });
          }
          return http.Response('https://kw-bj.kuwo.cn/resource/audio.mp3', 200);
        }),
      );
      final rows = await source.search(recording());
      expect(rows.length, 2);
      expect(isSameNeteaseRecording(recording(), rows.first), isTrue);
      expect(isSameNeteaseRecording(recording(), rows.last), isFalse);
      final resolved = await source.resolve(
        rows.first.copyWith(playbackQuality: 'flac', audioBitrate: 999999),
      );
      expect(resolved!.playbackQuality, isEmpty);
      expect(resolved.audioBitrate, 0);
      expect(requests.map((r) => r.url.host), [
        'search.kuwo.cn',
        'antiserver.kuwo.cn',
      ]);
    },
  );

  test(
    'provider HTTP errors remain distinguishable from empty searches',
    () async {
      final source = AnonymousKuwoFallback(
        MockClient((_) async => http.Response('', 500)),
      );
      await expectLater(
        source.search(recording()),
        throwsA(
          isA<NeteaseSourceFailure>()
              .having((e) => e.reason, 'reason', 'search_http_error')
              .having((e) => e.httpStatus, 'status', 500),
        ),
      );
    },
  );

  test(
    'spoken restriction MP3 is rejected, complete recording passes frame count',
    () async {
      for (final seconds in [11, 30, 90, 274]) {
        final result = await inspectNeteaseAudio(
          MockClient((_) async => mp3Response(seconds)),
          'https://kw-bj.kuwo.cn/audio.mp3',
          expectedDuration: const Duration(seconds: 274),
        );
        expect(result.playable, seconds == 274);
        expect(result.duration!.inSeconds, closeTo(seconds, 1));
        if (seconds < 274) expect(result.reason, 'media_duration_too_short');
      }
    },
  );

  test(
    'probe distinguishes HTTP denial, non-audio and fake lossless',
    () async {
      final responses = [
        http.Response('', 403),
        http.Response('{"error":true}', 200),
        mp3Response(274),
      ];
      final expected = [
        'media_http_403',
        'media_not_audio',
        'lossless_not_confirmed',
      ];
      for (var i = 0; i < responses.length; i++) {
        final result = await inspectNeteaseAudio(
          MockClient((_) async => responses[i]),
          'https://example.test/audio',
          requireLossless: i == 2,
        );
        expect(result.reason, expected[i]);
      }
    },
  );

  test(
    'FLAC STREAMINFO duration detects a short valid lossless preview',
    () async {
      final bytes = List<int>.filled(42, 0)
        ..setRange(0, 4, ascii.encode('fLaC'));
      bytes[7] = 34;
      final packed = (44100 << 44) | (1 << 41) | (15 << 36) | (44100 * 30);
      for (var i = 0; i < 8; i++) {
        bytes[18 + i] = packed >> (56 - 8 * i) & 255;
      }
      final result = await inspectNeteaseAudio(
        MockClient(
          (_) async => http.Response.bytes(
            bytes,
            206,
            headers: {'content-type': 'audio/flac'},
          ),
        ),
        'https://example.test/audio',
        requireLossless: true,
        expectedDuration: const Duration(seconds: 274),
      );
      expect(result.reason, 'media_duration_too_short');
      expect(result.duration, const Duration(seconds: 30));
    },
  );

  test(
    'source scope closing aborts pending I/O without closing the parent',
    () async {
      final parent = WaitingClient();
      final scope = NeteaseSourceClient(parent);
      final pending = scope.get(Uri.https('example.test', '/search'));
      final assertion = expectLater(
        pending,
        throwsA(isA<http.RequestAbortedException>()),
      );
      await parent.started.future;
      scope.close();
      await assertion;
      expect(parent.aborted, isTrue);
      expect(parent.closed, isFalse);
      await expectLater(
        scope.get(Uri.https('example.test', '/later')),
        throwsA(isA<http.RequestAbortedException>()),
      );
    },
  );

  test(
    'source timeout terminates its HTTP request, not just the waiting Future',
    () async {
      final parent = WaitingClient();
      final result = await NeteaseFallbackResolver(
        [],
        parent,
        sourceFactories: [
          NeteaseSourceFactory((c) => FixtureSource(client: c)),
        ],
        sourceTimeout: const Duration(milliseconds: 20),
      ).resolve(recording(), current: () => true);
      await Future<void>.delayed(Duration.zero);
      expect(result, isNull);
      expect(parent.aborted, isTrue);
      expect(parent.closed, isFalse);
    },
  );

  test('source response size is bounded before JSON decoding', () async {
    final scope = NeteaseSourceClient(
      MockClient((_) async => http.Response('x' * 2048, 200)),
      maximumBytes: 1024,
    );
    addTearDown(scope.close);
    await expectLater(
      scope.get(Uri.https('example.test', '/huge')),
      throwsA(
        isA<NeteaseSourceFailure>().having(
          (e) => e.reason,
          'reason',
          'response_too_large',
        ),
      ),
    );
  });

  test(
    'latest playback aborts the old request and old completion cannot cancel the new one',
    () async {
      final owner = NeteasePlaybackRequests();
      final old = owner.begin();
      var cancelled = false;
      unawaited(old.abort.then((_) => cancelled = true));
      final fresh = owner.begin();
      await Future<void>.delayed(Duration.zero);
      expect(cancelled, isTrue);
      expect(owner.current(old.epoch), isFalse);
      owner.finish(old.epoch);
      expect(owner.current(fresh.epoch), isTrue);
      owner.finish(fresh.epoch);
      await fresh.abort;
    },
  );

  test('playback abort closes only its own provider scope', () async {
    final abort = Completer<void>();
    final parent = WaitingClient();
    final resolver = NeteaseFallbackResolver(
      [],
      parent,
      sourceFactories: [NeteaseSourceFactory((c) => FixtureSource(client: c))],
    );
    final pending = resolver.resolve(
      recording(),
      current: () => true,
      abortTrigger: abort.future,
    );
    await parent.started.future;
    abort.complete();
    expect(await pending, isNull);
    expect(parent.aborted, isTrue);
    expect(parent.closed, isFalse);
  });

  for (final scenario in [
    'empty',
    'mismatch',
    'missing_stream',
    'short_audio',
    'ready',
  ]) {
    test('diagnostics separate the $scenario failure stage', () async {
      final diagnostics = NeteaseFallbackDiagnostics();
      addTearDown(diagnostics.dispose);
      final source = FixtureSource(
        items: scenario == 'empty'
            ? []
            : scenario == 'mismatch'
            ? [recording(artist: 'another')]
            : null,
        resolveValue: scenario == 'missing_stream'
            ? null
            : recording().copyWith(audioAsset: 'https://example.test/audio'),
      );
      final found = await NeteaseFallbackResolver(
        [source],
        MockClient(
          (_) async => mp3Response(scenario == 'short_audio' ? 11 : 274),
        ),
        diagnostics: diagnostics,
        options: const NeteasePlaybackOptions(diagnostics: true),
      ).resolve(recording(), current: () => true);
      final expected = {
        'empty': 'no_search_results',
        'mismatch': 'recording_mismatch',
        'missing_stream': 'no_complete_stream',
        'short_audio': 'media_duration_too_short',
        'ready': 'ready',
      };
      expect(diagnostics.rows.single['result'], expected[scenario]);
      expect(found != null, scenario == 'ready');
      expect(diagnostics.json, isNot(contains('https:')));
      expect(diagnostics.json, isNot(contains('薛之谦')));
    });
  }

  test('late diagnostics after disposal are safe', () {
    final diagnostics = NeteaseFallbackDiagnostics()..dispose();
    diagnostics.record('source', 'ready', 1);
    diagnostics.clear();
    expect(diagnostics.rows, isEmpty);
  });

  test(
    'Bilibili quoted/lyric titles retain artist and reject altered recordings',
    () {
      final original = recording(title: '我好像在哪见过你');
      expect(
        bilibiliRecordingTitle('《我好像在哪见过你》- 薛之谦 Hi-Res 无损音质', original),
        '我好像在哪见过你',
      );
      expect(bilibiliRecordingTitle('薛之谦《我好像在哪见过你》MV', original), '我好像在哪见过你');
      for (final title in ['我好像在哪见过你 伴奏', '我好像在哪见过你 (Live)', '我好像在哪见过你 DJ版']) {
        final parsed = bilibiliRecordingTitle('薛之谦 - $title', original);
        expect(
          normalizeRecordingText(parsed!),
          isNot(normalizeRecordingText(original.title)),
        );
      }
      expect(bilibiliRecordingTitle('其它歌手《我好像在哪见过你》MV', original), isNull);
      expect(bilibiliRecordingTitle('薛之谦《我好像在哪见过你》翻唱', original), isNull);
      final video = BilibiliVideoSource(
        MockClient((_) async => http.Response('', 500)),
      );
      expect(
        recordingDurationTolerance(video, original),
        const Duration(seconds: 4),
      );
      expect(
        isSameNeteaseRecording(
          original,
          recording(title: original.title, seconds: 278),
          durationTolerance: recordingDurationTolerance(video, original),
        ),
        isTrue,
      );
      expect(
        isSameNeteaseRecording(
          original,
          recording(title: original.title, seconds: 295),
          durationTolerance: recordingDurationTolerance(video, original),
        ),
        isFalse,
      );
    },
  );

  test('Android exit report copies only known numeric fields', () {
    final exit = AppExitRecord.parse({
      'reason': 'native_crash',
      'timestampMs': 1793250000000,
      'status': 11,
      'pssKiB': -2,
      'rssKiB': 1000,
      'trace': 'https://private.example/token',
    });
    expect(exit!.reason, 'native_crash');
    expect(exit.pssKiB, 0);
    expect(
      AppExitRecord.parse({'reason': 'unexpected_url', 'timestampMs': 1}),
      isNull,
    );
    expect(AppExitRecord.parse({'reason': 'anr', 'timestampMs': 0}), isNull);
  });

  test(
    'diagnostic log includes own-process historical exit without claiming its build',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        AppExitDiagnostics.channel,
        (_) async => [
          {
            'reason': 'native_crash',
            'timestampMs': 1793250000000,
            'status': 11,
            'rssKiB': 1000,
            'trace': 'must-not-copy',
          },
        ],
      );
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          AppExitDiagnostics.channel,
          null,
        ),
      );
      final diagnostics = NeteaseFallbackDiagnostics();
      addTearDown(diagnostics.dispose);
      await diagnostics.includeExitHistory();
      await diagnostics.includeExitHistory();
      expect(diagnostics.rows.length, 1);
      expect(diagnostics.rows.single['versionUnknown'], isTrue);
      expect(diagnostics.json, isNot(contains('must-not-copy')));
    },
  );

  test(
    'automatic source failure becomes a player error instead of an unhandled Future',
    () async {
      final player = CompletionPlayer();
      final handler = MestingAudioHandler(tracks: [], player: player);
      addTearDown(() async {
        await handler.debugDispose();
        await player.completions.close();
      });
      await handler.replaceQueue([
        localSong('one'),
        localSong('two'),
      ], autoplay: false);
      handler.configureTrackPlaybackResolver(
        (track) async => throw StateError('source unavailable'),
      );
      player.at = const Duration(minutes: 4);
      player.completions.add(ProcessingState.completed);
      await until(
        () =>
            handler.playbackState.value.processingState ==
            AudioProcessingState.error,
      );
      expect(handler.mediaItem.value!.id, 'two');
      // The failed selection stays visible with its error. Explicit commands still let their UI surface the same source failure.
      await expectLater(handler.skipToNext(), throwsStateError);
    },
  );

  test(
    'cancelled stale queue lookup cannot replace or fail a later selection',
    () async {
      final player = DeterministicAudioPlayer();
      final handler = MestingAudioHandler(tracks: [], player: player);
      addTearDown(handler.debugDispose);
      await handler.replaceQueue([localSong('initial')], autoplay: false);
      final old = Completer<Track>();
      final started = Completer<void>();
      handler.configureTrackPlaybackResolver((track) async {
        if (track.id == 'old') {
          started.complete();
          return old.future;
        }
        return track;
      });
      final pending = handler.playSingleTrack(
        localSong('old'),
        autoplay: false,
      );
      await started.future;
      await handler.playSingleTrack(localSong('new'), autoplay: false);
      old.completeError(http.RequestAbortedException());
      await pending;
      expect(handler.mediaItem.value!.id, 'new');
    },
  );
}
