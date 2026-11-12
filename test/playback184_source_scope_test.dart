import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesting_music/features/music_platform/cross_platform_music_scope.dart';
import 'package:mesting_music/features/music_platform/data/embedded_music_server.dart';
import 'package:mesting_music/features/music_platform/data/music_platform_api.dart';
import 'package:mesting_music/features/music_platform/domain/platform_audio_quality.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/music_platform/platform_quality_providers.dart';
import 'package:mesting_music/shared/models/track.dart';

const _owner = PlatformSession(
  userId: 'n',
  token: 'synthetic-n',
  platform: MusicPlatform.netease,
);
const _source = PlatformSession(userId: 'k', token: 'synthetic-k');
const _track = Track(
  id: 'kugou_HASH',
  source: TrackSource.kugou,
  title: '晴天',
  artist: '周杰伦',
  album: '叶惠美',
  duration: Duration(minutes: 4),
  audioAsset: 'mesting-platform://kugou/kugou_HASH',
  coverAsset: '',
  lyricsAsset: '',
);

class _Account extends PlatformAccountController {
  @override
  Future<PlatformSession?> build() async => _owner;
  void replace() => state = const AsyncData(
    PlatformSession(
      userId: 'new',
      token: 'replacement',
      platform: MusicPlatform.netease,
    ),
  );
}

class _Server implements MusicServer {
  @override
  Future<Uri> start() async => Uri.parse('http://127.0.0.1:18400');
}

void main() {
  Future<(ProviderContainer, WidgetRef, List<Uri>)> mount(
    WidgetTester tester, {
    Completer<http.Response>? pending,
  }) async {
    final calls = <Uri>[];
    final api = MusicPlatformApi(
      server: _Server(),
      client: MockClient((request) {
        calls.add(request.url);
        if (pending != null) return pending.future;
        return Future.value(
          http.Response(
            jsonEncode({
              'status': 1,
              'data': request.url.path == '/audio'
                  ? {'hash_128': 'HASH'}
                  : {
                      'url': 'https://media.example.test/recording.mp3',
                      'quality': '128',
                      'bitRate': 128000,
                      'priv_status': 1,
                      'fileSize': 5000000,
                    },
            }),
            200,
            headers: {'content-type': 'application/json'},
          ),
        );
      }),
    )..session = _source;
    final scope = ProviderContainer(
      overrides: [
        platformAccountProvider.overrideWith(_Account.new),
        supplementaryKugouApiProvider.overrideWith((_) async => api),
        musicPlatformApiProvider.overrideWithValue(
          MusicPlatformApi(
            server: _Server(),
            client: MockClient(
              (_) async =>
                  throw StateError('selected transport must stay untouched'),
            ),
          ),
        ),
      ],
    );
    await scope.read(platformAccountProvider.future);
    late WidgetRef captured;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: scope,
        child: MaterialApp(
          home: Consumer(
            builder: (_, ref, _) {
              captured = ref;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    return (scope, captured, calls);
  }

  testWidgets('NetEase owner plays Kugou URL through source transport', (
    tester,
  ) async {
    final (scope, ref, calls) = await mount(tester);
    late Track result;
    await tester.runAsync(() async {
      result =
          await resolveSupplementaryMusic(
            ref,
            _track,
            PlatformAudioQuality.sky,
          ).timeout(
            const Duration(seconds: 5),
            onTimeout: () => throw StateError('source resolution timed out'),
          );
    });
    expect(result.audioAsset, 'https://media.example.test/recording.mp3');
    expect(result.source, TrackSource.kugou);
    expect(result.audioOrigin!.adapter, AudioOrigin.kugou);
    expect(result.isPreview, false);
    expect(calls.map((u) => u.path), contains('/song/url'));
    expect(calls.first.queryParameters['quality'], 'high');
    expect(scope.read(platformAccountProvider).value, same(_owner));
    expect(
      scope.read(supplementaryKugouApiProvider).value!.session,
      same(_source),
    );
    await tester.pumpWidget(const SizedBox());
    scope.dispose();
  });
  test('foreign Kugou quality reads only its retained transport', () async {
    final api = MusicPlatformApi(
      server: _Server(),
      client: MockClient((request) async {
        expect(request.url.path, '/audio');
        expect(request.headers['Authorization'], contains('synthetic-k'));
        return http.Response('{"status":1,"data":{"hash_128":"HASH"}}', 200);
      }),
    )..session = _source;
    final scope = ProviderContainer(
      overrides: [
        platformAccountProvider.overrideWith(_Account.new),
        supplementaryKugouApiProvider.overrideWith((_) async => api),
        musicPlatformApiProvider.overrideWithValue(
          MusicPlatformApi(
            server: _Server(),
            client: MockClient((_) async => throw StateError('wrong source')),
          ),
        ),
      ],
    );
    addTearDown(scope.dispose);
    await scope.read(platformAccountProvider.future);
    final subscription = scope.listen(
      platformSongQualitiesProvider(_track.id),
      (_, _) {},
    );
    addTearDown(subscription.close);
    expect(
      await scope.read(platformSongQualitiesProvider(_track.id).future),
      contains(PlatformAudioQuality.standard),
    );
    expect(scope.read(platformAccountProvider).value, same(_owner));
  });
  testWidgets('late source URL is rejected after owner replacement', (
    tester,
  ) async {
    // The transport completes in runAsync's real zone. Construct its completer
    // there too, so fake-widget microtasks cannot delay the supplied response.
    late final Completer<http.Response> pending;
    await tester.runAsync(() async {
      pending = Completer<http.Response>();
    });
    final (scope, ref, calls) = await mount(tester, pending: pending);
    await tester.runAsync(() async {
      final future = resolveSupplementaryMusic(
        ref,
        _track,
        PlatformAudioQuality.standard,
      ).timeout(const Duration(seconds: 5));
      final rejected = expectLater(
        future,
        throwsA(isA<MusicPlatformException>()),
      );
      for (var i = 0; calls.isEmpty && i < 30; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(calls, isNotEmpty);
      (scope.read(platformAccountProvider.notifier) as _Account).replace();
      pending.complete(
        http.Response(
          jsonEncode({
            'status': 1,
            'data': {
              'url': 'https://media.example.test/stale.mp3',
              'quality': '128',
              'priv_status': 1,
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );
      await rejected;
    });
    expect(scope.read(platformAccountProvider).value!.userId, 'new');
    await tester.pumpWidget(const SizedBox());
    scope.dispose();
  });
}
