import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_api.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_request_signer.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_repository.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_session.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_models.dart';

http.Response reply(Object value) => http.Response(
  jsonEncode(value),
  200,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);
QishuiSession account() => QishuiSession(
  userId: 'owner167',
  protocol: QishuiSessionProtocol.web,
  cookies: const [
    {
      'name': 'sessionid',
      'value': 'music-secret167',
      'domain': 'api.qishui.com',
      'path': '/',
      'secure': 'true',
      'hostOnly': 'true',
    },
  ],
);

class FixtureSigner implements QishuiRequestSigner {
  String? signedBody;
  Map<String, String>? signedHeaders;
  @override
  Future<Map<String, String>> identity(Future<void> abort) async => {
    'device_id': '12345678901234',
    'iid': '12345678901235',
    'fp': 'fixture-fp',
  };
  @override
  Future<QishuiSignedRequest> sign(
    Uri uri,
    String method,
    String body,
    Map<String, String> headers,
    Future<void> abort,
  ) async {
    signedBody = body;
    signedHeaders = Map.of(headers);
    return QishuiSignedRequest(uri, const {
      'x-helios': 'fixture-helios',
      'x-medusa': 'fixture-medusa',
    });
  }

  @override
  void invalidateIdentity() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'desktop media signs final POST body before attaching account credentials',
    () async {
      final signer = FixtureSigner();
      final api = QishuiApi(
        MockClient((r) async {
          expect(r.method, 'POST');
          expect(r.url.path, '/luna/pc/track_v2');
          expect(r.headers['cookie'], 'sessionid=music-secret167');
          expect(r.headers['x-helios'], 'fixture-helios');
          expect(r.url.queryParameters['device_platform'], 'windows');
          expect(r.body, signer.signedBody);
          expect(
            r.headers['x-ss-stub'],
            md5.convert(utf8.encode(r.body)).toString().toUpperCase(),
          );
          expect(jsonDecode(r.body), {
            'track_id': 'track167',
            'media_type': 'track',
            'queue_type': 'favorite_track_playlist',
            'scene_name': 'library',
          });
          return reply({
            'track_player': {},
            'status_info': {'code': 0},
          });
        }),
        signer: signer,
      )..configure(account());
      await QishuiRepository(api).media('track167');
      expect(signer.signedHeaders!.keys, isNot(contains('cookie')));
      expect(
        jsonEncode(signer.signedHeaders),
        isNot(contains('music-secret167')),
      );
    },
  );
  test(
    'public signer receives no credentials and cannot overwrite official authorization',
    () async {
      var calls = 0;
      final signer = SodaMRequestSigner(
        MockClient((r) async {
          calls++;
          expect(r.headers['cookie'], isNull);
          final j = jsonDecode(r.body) as Map;
          final sent = j['headers'] as Map;
          expect(sent.keys, isNot(contains('Cookie')));
          expect(jsonEncode(j), isNot(contains('music-secret167')));
          expect(jsonEncode(j), isNot(contains('csrf-secret167')));
          return reply({
            'ok': true,
            'headers': {
              'X-Helios': 'h',
              'X-Medusa': 'm',
              'Cookie': 'injected',
              'authorization': 'injected',
            },
            'url': 'https://evil.test',
          });
        }),
        endpoint: Uri.parse('https://signer.example.test/sign'),
        accessToken: 'fixture-service-access',
      );
      final result = await signer.sign(
        Uri.parse('https://api.qishui.com/luna/pc/track_v2?a=1'),
        'POST',
        '{}',
        {
          'Cookie': 'music-secret167',
          'x-tt-passport-csrf-token': 'csrf-secret167',
          'Content-Type': 'application/json',
        },
        Completer<void>().future,
      );
      expect(result.uri.host, 'api.qishui.com');
      expect(result.headers, {'x-helios': 'h', 'x-medusa': 'm'});
      expect(calls, 1);
    },
  );
  test(
    'signer identity bootstraps without /config and does not use music credentials',
    () async {
      var calls = 0;
      final signer = SodaMRequestSigner(
        MockClient((r) async {
          calls++;
          if (r.url.path == '/config') return http.Response('', 404);
          final j = jsonDecode(r.body) as Map;
          expect(j['method'], 'GET');
          expect(j['body'], '');
          expect(j['url'], 'https://api.qishui.com/luna/pc/me');
          return reply({
            'ok': true,
            'device_id': '12345678901234',
            'headers': {'X-Helios': 'h', 'X-Medusa': 'm'},
          });
        }),
        endpoint: Uri.parse('https://signer.example.test/sign'),
        accessToken: 'fixture',
      );
      expect(
        (await signer.identity(Completer<void>().future))['device_id'],
        '12345678901234',
      );
      await signer.identity(Completer<void>().future);
      expect(calls, 2);
    },
  );
  test(
    'HTTP200 empty official reply is signature refusal, not a network claim',
    () async {
      final api = QishuiApi(
        MockClient((r) async => http.Response('', 200)),
        signer: FixtureSigner(),
      )..configure(account());
      await expectLater(
        QishuiRepository(api).media('track167'),
        throwsA(
          isA<QishuiException>()
              .having((e) => e.kind, 'kind', QishuiFailureKind.refused)
              .having((e) => e.message, 'message', isNot(contains('检查网络'))),
        ),
      );
    },
  );
  test('business code in status_info is not a successful read', () async {
    final api = QishuiApi(
      MockClient(
        (r) async => reply({
          'status_info': {'code': 1000004},
        }),
      ),
    )..configure(account());
    await expectLater(
      api.request('/luna/me', get: true),
      throwsA(isA<QishuiException>().having((e) => e.code, 'code', '1000004')),
    );
  });
  test(
    'malformed media JSON is classified without raw payload disclosure',
    () async {
      final api = QishuiApi(
        MockClient(
          (r) async => http.Response('not-json sessionid=secret', 200),
        ),
        signer: FixtureSigner(),
      )..configure(account());
      await expectLater(
        QishuiRepository(api).media('track167'),
        throwsA(
          isA<QishuiException>()
              .having((e) => e.kind, 'kind', QishuiFailureKind.format)
              .having((e) => e.message, 'message', isNot(contains('secret'))),
        ),
      );
    },
  );
  test(
    'playlist ordering uses exact non-PC endpoint and official readback',
    () async {
      var ids = ['one167', 'two167'];
      var writes = 0;
      final api = QishuiApi(
        MockClient((r) async {
          if (r.method == 'POST') {
            expect(r.url.path, '/luna/me/playlist/media/sort');
            writes++;
            ids = (jsonDecode(r.body)['media'] as List)
                .map((v) => v['id'] as String)
                .toList();
            return reply({
              'status_info': {'code': 0},
            });
          }
          if (r.url.path.endsWith('/me/playlist')) {
            return reply({
              'playlists': [
                {
                  'id': 'list167',
                  'title': 'Test',
                  'count_tracks': 2,
                  'owner': {'id': 'owner167'},
                },
              ],
            });
          }
          return reply({
            'playlist': {'id': 'list167'},
            'tracks': [
              for (final id in ids)
                {'id': id, 'name': id, 'duration': 200000, 'artists': []},
            ],
          });
        }),
        signer: FixtureSigner(),
      )..configure(account());
      final repo = QishuiRepository(api);
      final tracks = await repo.playlist('list167');
      await repo.reorderPlaylist('list167', tracks.reversed.toList());
      expect(ids, ['two167', 'one167']);
      expect(writes, 1);
    },
  );
  test(
    'unknown mutation is journaled and another tap reads without replaying',
    () async {
      var writes = 0;
      final api = QishuiApi(
        MockClient((r) async {
          if (r.method == 'POST') {
            writes++;
            throw http.ClientException('lost reply sessionid=secret');
          }
          if (r.url.path.endsWith('/me/playlist')) {
            return reply({
              'playlists': [
                {
                  'id': 'pending167',
                  'title': 'Test',
                  'count_tracks': 0,
                  'owner': {'id': 'owner167'},
                },
              ],
            });
          }
          return reply({
            'playlist': {'id': 'pending167'},
            'tracks': [],
          });
        }),
        signer: FixtureSigner(),
      )..configure(account());
      final track = sodaTrack({
        'id': 'test167',
        'name': 'Test',
        'duration': 200000,
        'artists': [],
      })!;
      final repo = QishuiRepository(api);
      for (var i = 0; i < 2; i++) {
        await expectLater(
          repo.addPlaylistTracks('pending167', [track]),
          throwsA(
            isA<QishuiException>().having(
              (e) => e.unknownWrite,
              'unknown',
              true,
            ),
          ),
        );
      }
      expect(writes, 1);
    },
  );
  test(
    'only own playlists can be modified and only Soda tracks can be submitted',
    () async {
      var writes = 0;
      final api = QishuiApi(
        MockClient((r) async {
          if (r.method == 'POST') writes++;
          return reply({
            'playlists': [
              {
                'id': 'foreign167',
                'title': 'Foreign',
                'count_tracks': 0,
                'owner': {'id': 'another-owner'},
              },
            ],
          });
        }),
        signer: FixtureSigner(),
      )..configure(account());
      final track = sodaTrack({
        'id': 'test167',
        'name': 'Test',
        'duration': 200000,
        'artists': [],
      })!;
      await expectLater(
        QishuiRepository(api).addPlaylistTracks('foreign167', [track]),
        throwsA(isA<QishuiException>()),
      );
      expect(writes, 0);
    },
  );
  test(
    'account cancellation after dispatch preserves an unknown write',
    () async {
      late QishuiApi api;
      api = QishuiApi(
        MockClient((request) async {
          api.configure(null);
          return reply({});
        }),
        signer: FixtureSigner(),
      )..configure(account());
      addTearDown(api.dispose);
      await expectLater(
        api.request(
          '/luna/me/playlist/update',
          body: {'playlist_id': 'test167', 'name': 'Test'},
          write: true,
        ),
        throwsA(
          isA<QishuiException>().having(
            (e) => e.unknownWrite,
            'unknown after dispatch',
            true,
          ),
        ),
      );
    },
  );
}
