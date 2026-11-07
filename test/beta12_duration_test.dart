import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesting_music/core/platform/distribution_channel.dart';
import 'package:mesting_music/features/music_platform/data/embedded_kugou_music_source.dart';
import 'package:mesting_music/features/music_platform/data/embedded_music_server.dart';
import 'package:mesting_music/features/music_platform/data/music_platform_api.dart';
import 'package:mesting_music/features/music_platform/data/platform_track_duration.dart';
import 'package:mesting_music/features/music_platform/data/platform_track_duration_repository.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/queue/presentation/queue_track_duration.dart';
import 'package:mesting_music/shared/models/track.dart';

class _Server implements MusicServer {
  @override
  Future<Uri> start() async => Uri.parse('http://127.0.0.1:12345');
}

Track _track(String hash, {Duration duration = Duration.zero}) => Track(
  id: 'kugou_$hash',
  title: hash,
  artist: '歌手',
  album: '专辑',
  duration: duration,
  audioAsset: '',
  coverAsset: '',
  lyricsAsset: '',
  source: TrackSource.kugou,
);

http.Response _response(Object data) =>
    http.Response(jsonEncode({'status': 1, 'data': data}), 200);

void main() {
  test(
    'catalogue duration aliases preserve seconds, milliseconds, fractions and zero fallback',
    () {
      for (final key in [
        'TimeLen',
        'timeLen',
        'time_len',
        'TimeLength',
        'duration',
      ]) {
        expect(
          PlatformTrackDuration.fromFields({key: '241'}),
          const Duration(seconds: 241),
        );
      }
      expect(
        PlatformTrackDuration.fromFields({'duration': 0, 'TimeLen': 241}),
        const Duration(seconds: 241),
      );
      expect(
        PlatformTrackDuration.fromFields({'timelength': 241450}),
        const Duration(milliseconds: 241450),
      );
      expect(
        PlatformTrackDuration.fromFields({'timelength': '9800'}),
        const Duration(milliseconds: 9800),
      );
      expect(
        PlatformTrackDuration.fromFields({'Duration': 10800}),
        const Duration(hours: 3),
      );
      expect(
        PlatformTrackDuration.fromFields({'durationMs': 9000}),
        const Duration(seconds: 9),
      );
      expect(
        PlatformTrackDuration.fromFields({'duration': 241.45}),
        const Duration(milliseconds: 241450),
      );
      expect(
        PlatformTrackDuration.fromFields({'duration': '1:02:03'}),
        const Duration(hours: 1, minutes: 2, seconds: 3),
      );
      expect(PlatformTrackDuration.fromFields({'duration': -1}), isNull);
      final parsed = EmbeddedKugouMusicSource.platformTrack({
        'hash': 'H',
        'audio_info': {'TimeLen': 241450},
        'songname': '真实总时长',
      });
      expect(parsed!.duration, const Duration(milliseconds: 241450));
    },
  );

  test(
    'metadata requests coalesce and never resolve a playback stream',
    () async {
      final response = Completer<http.Response>();
      final requests = <Uri>[];
      final api = MusicPlatformApi(
        server: _Server(),
        client: MockClient((request) {
          requests.add(request.url);
          return response.future;
        }),
      );
      final repo = PlatformTrackDurationRepository(api);
      addTearDown(repo.dispose);
      final first = repo.resolve(_track('HASH'));
      final second = repo.resolve(_track('HASH'));
      await Future<void>.delayed(Duration.zero);
      expect(requests.single.path, '/audio');
      response.complete(
        _response([
          {'hash': 'hash', 'timelength': 259000},
        ]),
      );
      expect(await first, const Duration(seconds: 259));
      expect(await second, const Duration(seconds: 259));
      expect(await repo.resolve(_track('HASH')), const Duration(seconds: 259));
      expect(requests.length, 1);
    },
  );

  test(
    'hydration bounds concurrency and ignores another recording in a list',
    () async {
      final pending = <String, Completer<http.Response>>{};
      final api = MusicPlatformApi(
        server: _Server(),
        client: MockClient((request) {
          final key = request.url.queryParameters['hash']!;
          return (pending[key] = Completer<http.Response>()).future;
        }),
      );
      final repo = PlatformTrackDurationRepository(api);
      addTearDown(repo.dispose);
      final jobs = [
        for (final key in ['a', 'b', 'c']) repo.resolve(_track(key)),
      ];
      await Future<void>.delayed(Duration.zero);
      expect(pending.keys, ['a', 'b']);
      pending['a']!.complete(
        _response([
          {'hash': 'other', 'duration': 999},
          {'hash': 'a', 'duration': 201},
        ]),
      );
      expect(await jobs[0], const Duration(seconds: 201));
      await Future<void>.delayed(Duration.zero);
      expect(pending.keys, ['a', 'b', 'c']);
      pending['b']!.complete(
        _response([
          {'hash': 'wrong', 'duration': 999},
        ]),
      );
      pending['c']!.complete(
        _response([
          {'hash': 'c', 'duration': 203},
        ]),
      );
      expect(await jobs[1], isNull);
      expect(await jobs[2], const Duration(seconds: 203));
    },
  );

  test('account change discards active and queued results', () async {
    final response = Completer<http.Response>();
    final api = MusicPlatformApi(
      server: _Server(),
      client: MockClient((_) => response.future),
    );
    final repo = PlatformTrackDurationRepository(api);
    final jobs = [
      for (final key in ['a', 'b', 'c']) repo.resolve(_track(key)),
    ];
    await Future<void>.delayed(Duration.zero);
    api.session = const PlatformSession(
      userId: 'new',
      token: 'new',
      nickname: '新账号',
    );
    response.complete(
      _response([
        {'duration': 999},
      ]),
    );
    expect(await Future.wait(jobs), [null, null, null]);
    repo.dispose();
  });

  testWidgets(
    'unknown visible row updates to real total while other rows stay usable',
    (tester) async {
      final response = Completer<http.Response>();
      final api = MusicPlatformApi(
        server: _Server(),
        client: MockClient((_) => response.future),
      );
      final repo = PlatformTrackDurationRepository(api);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [queueDurationRepositoryProvider.overrideWithValue(repo)],
          child: MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  QueueTrackDuration(
                    track: _track('unknown'),
                    mediaDuration: Duration.zero,
                    style: const TextStyle(),
                  ),
                  QueueTrackDuration(
                    track: _track(
                      'known',
                      duration: const Duration(seconds: 250),
                    ).copyWith(isPreview: true),
                    mediaDuration: const Duration(seconds: 60),
                    style: const TextStyle(),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('--:--'), findsOneWidget);
      expect(find.text('4:10'), findsOneWidget);
      response.complete(
        _response([
          {'hash': 'unknown', 'duration': 241},
        ]),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('4:01'), findsOneWidget);
      expect(find.text('4:10'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      repo.dispose();
    },
    skip: !DistributionChannel.isBeta,
  );
}
