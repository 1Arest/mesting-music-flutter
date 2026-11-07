import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesting_music/features/music_platform/data/embedded_kugou_music_source.dart';
import 'package:mesting_music/features/music_platform/data/embedded_music_server.dart';
import 'package:mesting_music/features/music_platform/data/music_platform_api.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';

class _Server implements MusicServer {
  @override
  Future<Uri> start() async => Uri.parse('http://127.0.0.1:12345');
}

http.Response _response(Object data, [int status = 200]) => http.Response(
  jsonEncode(data),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  final track = EmbeddedKugouMusicSource.platformTrack({
    'hash': 'HASH',
    'songname': '测试歌曲',
  })!;

  test(
    'guest uses permitted preview after ordinary URL is unavailable, even with HTTP 502 business response',
    () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        if (request.url.queryParameters['free_part'] == '1') {
          return _response({
            'status': 1,
            'data': {
              'url': ['http://fs.test.kugou.com/trial.mp3'],
            },
          });
        }
        return _response({
          'status': 0,
          'data': {'error_code': 31863},
        }, 502);
      });
      final source = EmbeddedKugouMusicSource(
        client,
        MusicPlatformApi(server: _Server(), client: client),
      );
      final result = await source.resolveTrack(track);
      expect(result.audioAsset, 'http://fs.test.kugou.com/trial.mp3');
      expect(result.isPreview, true);
      expect(requests.length, 2);
      expect(
        requests.first.url.queryParameters.containsKey('free_part'),
        false,
      );
      expect(
        requests.every(
          (request) => !request.headers.containsKey('Authorization'),
        ),
        true,
      );
    },
  );

  test(
    'device error 20028 triggers one registration and retries with dfid',
    () async {
      final paths = <String>[];
      var registered = false;
      final client = MockClient((request) async {
        paths.add(request.url.path);
        if (request.url.path == '/register/dev') {
          registered = true;
          return _response({
            'status': 1,
            'data': {'dfid': 'registered-device'},
          });
        }
        if (!registered) return _response({'status': 0, 'errcode': 20028}, 502);
        expect(request.url.queryParameters['dfid'], 'registered-device');
        return _response({
          'status': 1,
          'data': {'url': 'https://media.example/full.mp3'},
        });
      });
      final result = await EmbeddedKugouMusicSource(
        client,
        MusicPlatformApi(server: _Server(), client: client),
      ).resolveTrack(track);
      expect(result.isPlayable, true);
      expect(result.isPreview, false);
      expect(paths, ['/song/url', '/register/dev', '/song/url']);
    },
  );

  test(
    'repeated device errors cannot create an infinite registration loop',
    () async {
      var registrations = 0;
      final client = MockClient((request) async {
        if (request.url.path == '/register/dev') {
          registrations++;
          return _response({
            'status': 1,
            'data': {'dfid': 'registered'},
          });
        }
        return _response({'status': 0, 'errcode': 20028});
      });
      final result = await EmbeddedKugouMusicSource(
        client,
        MusicPlatformApi(server: _Server(), client: client),
      ).resolveTrack(track);
      expect(result.isPlayable, false);
      expect(registrations, 1);
      expect(result.availabilityMessage, contains('登录酷狗'));
    },
  );

  test(
    'VIP resolves complete media and never switches to anonymous preview',
    () async {
      final paths = <Uri>[];
      final client = MockClient((request) async {
        paths.add(request.url);
        expect(request.headers['Authorization'], contains('vip_token=vip'));
        return _response({
          'status': 1,
          'data': {'url': 'https://media.example/full.mp3', 'priv_status': 1},
        });
      });
      final api = MusicPlatformApi(server: _Server(), client: client)
        ..session = const PlatformSession(
          userId: '7',
          token: 'token',
          vipToken: 'vip',
        );
      final result = await EmbeddedKugouMusicSource(
        client,
        api,
      ).resolveTrack(track);
      expect(result.isPreview, false);
      expect(paths.single.path, '/song/url/new');
      expect(paths.single.queryParameters.containsKey('free_part'), false);
    },
  );

  test(
    'VIP rejected endpoint falls back to ordinary endpoint without free-part request',
    () async {
      final paths = <Uri>[];
      final client = MockClient((request) async {
        paths.add(request.url);
        return request.url.path == '/song/url/new'
            ? _response({
                'status': 1,
                'data': {
                  'url': 'https://media.example/preview.mp3',
                  'priv_status': 0,
                },
              })
            : _response({
                'status': 1,
                'data': {'url': 'https://media.example/full.mp3'},
              });
      });
      final api = MusicPlatformApi(server: _Server(), client: client)
        ..session = const PlatformSession(
          userId: '7',
          token: 'token',
          vipToken: 'vip',
        );
      final result = await EmbeddedKugouMusicSource(
        client,
        api,
      ).resolveTrack(track);
      expect(result.audioAsset, endsWith('/full.mp3'));
      expect(paths.map((uri) => uri.path), ['/song/url/new', '/song/url']);
      expect(
        paths.every((uri) => !uri.queryParameters.containsKey('free_part')),
        true,
      );
    },
  );

  test(
    'URL parser skips empty and unsafe entries and keeps the first valid media URL',
    () async {
      final client = MockClient(
        (request) async => _response({
          'data': [
            {
              'url': ['', 'file:///private', 'https://media.example/full.mp3'],
            },
          ],
        }),
      );
      final result = await EmbeddedKugouMusicSource(
        client,
        MusicPlatformApi(server: _Server(), client: client),
      ).resolveTrack(track);
      expect(result.audioAsset, 'https://media.example/full.mp3');
    },
  );

  test(
    'search defers URL resolution rather than locking all rows on a transient failure',
    () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/search');
        return _response({
          'data': {
            'lists': [
              {'FileHash': 'HASH', 'SongName': '测试歌曲'},
            ],
          },
        });
      });
      final result = await EmbeddedKugouMusicSource(
        client,
        MusicPlatformApi(server: _Server(), client: client),
      ).search('测试');
      expect(result.single.audioAsset, startsWith('mesting-platform:'));
      expect(result.single.availabilityMessage, '点击获取播放地址');
    },
  );

  test(
    'guest resolution cannot attach a new account after awaiting the first response',
    () async {
      final gate = Completer<http.Response>();
      var count = 0;
      final client = MockClient((request) {
        count++;
        return gate.future;
      });
      final api = MusicPlatformApi(server: _Server(), client: client);
      final pending = EmbeddedKugouMusicSource(client, api).resolveTrack(track);
      await Future<void>.delayed(Duration.zero);
      api.session = const PlatformSession(userId: 'new', token: 'token');
      gate.complete(_response({'status': 0}));
      await expectLater(pending, throwsA(isA<MusicPlatformException>()));
      expect(count, 1);
    },
  );
}
