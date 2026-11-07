import 'dart:convert';
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/features/music_platform/data/embedded_music_server.dart';
import 'package:mesting_music/features/music_platform/data/embedded_kugou_music_source.dart';
import 'package:mesting_music/features/music_platform/data/music_platform_api.dart';
import 'package:mesting_music/features/music_platform/data/platform_session_store.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';

class _Server implements MusicServer {
  _Server([this.host = '127.0.0.1']);
  final String host;
  @override
  Future<Uri> start() async => Uri(scheme: 'http', host: host, port: 12345);
}

class _Store implements PlatformSessionStore {
  PlatformSession? value;
  bool failClear = false;
  Completer<void>? writeGate;
  @override
  Future<PlatformSession?> read() async => value;
  @override
  Future<void> write(PlatformSession session) async {
    await writeGate?.future;
    value = session;
  }

  @override
  Future<void> clear() async {
    if (failClear) throw StateError('storage unavailable');
    value = null;
  }
}

void main() {
  late SharedPreferences preferences;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
  });
  test(
    'playback refresh uses the current account and rejects non-HTTP audio',
    () async {
      var url = 'https://audio.example/guest.mp3';
      final identities = <String?>[];
      final client = MockClient((request) async {
        identities.add(request.headers['Authorization']);
        expect(request.url.queryParameters['hash'], 'hash-one');
        return http.Response(
          jsonEncode({
            'data': {
              'url': [url],
            },
          }),
          200,
        );
      });
      final api = MusicPlatformApi(server: _Server(), client: client);
      final source = EmbeddedKugouMusicSource(client, api);
      final stored = EmbeddedKugouMusicSource.platformTrack({
        'hash': 'hash-one',
        'songname': '<em>Test</em>',
        'singername': 'Singer',
      })!.copyWith(audioAsset: 'https://expired.example/old.mp3');
      expect((await source.resolveTrack(stored)).audioAsset, url);
      expect(stored.title, 'Test');
      api.session = const PlatformSession(userId: 'two', token: 'new-token');
      url = 'https://audio.example/current-user.mp3';
      expect((await source.resolveTrack(stored)).audioAsset, url);
      expect(identities, [null, 'token=new-token;userid=two']);
      url = 'file:///private/should-not-play';
      expect((await source.resolveTrack(stored)).isPlayable, false);
    },
  );
  test(
    'logout waits for a slow credential write and leaves storage empty',
    () async {
      final store = _Store()..writeGate = Completer<void>();
      final api = MusicPlatformApi(
        server: _Server(),
        client: MockClient((_) async => http.Response('{}', 200)),
      );
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          platformSessionStoreProvider.overrideWithValue(store),
          musicPlatformApiProvider.overrideWithValue(api),
        ],
      );
      addTearDown(container.dispose);
      await container.read(platformAccountProvider.future);
      final account = container.read(platformAccountProvider.notifier);
      final login = account.accept({'userid': 'one', 'token': 'secret'});
      final logout = account.signOut();
      store.writeGate!.complete();
      await Future.wait([login, logout]);
      expect(store.value, null);
      expect(api.session, null);
      expect(container.read(platformAccountProvider).value, null);
    },
  );

  test(
    'QQ terminal string statuses stop scanning; pending statuses do not log in',
    () async {
      var status = 'wait';
      final api = MusicPlatformApi(
        server: _Server(),
        client: MockClient(
          (_) async => http.Response(jsonEncode({'status': status}), 200),
        ),
      );
      final service = PlatformLoginService(api);
      const challenge = PlatformQrChallenge(
        method: PlatformLoginMethod.qqQr,
        parameters: {},
        imageBase64: 'AA==',
      );
      expect(await service.poll(challenge), null);
      status = 'scanned';
      expect(await service.poll(challenge), null);
      for (final terminal in ['expired', 'blocked']) {
        status = terminal;
        await expectLater(
          service.poll(challenge),
          throwsA(isA<MusicPlatformException>()),
        );
      }
    },
  );
  test(
    'authenticated requests bypass cache and never carry a previous user after logout',
    () async {
      final requests = <http.Request>[];
      final api = MusicPlatformApi(
        server: _Server(),
        client: MockClient((request) async {
          requests.add(request);
          return http.Response('{"status":1,"data":{}}', 200);
        }),
      );
      api.session = const PlatformSession(userId: 'one', token: 'secret-one');
      await api.get('/user/detail');
      api.session = const PlatformSession(userId: 'two', token: 'secret-two');
      await api.get('/user/detail');
      api.session = null;
      await api.get('/search');
      expect(
        requests[0].headers['Authorization'],
        'token=secret-one;userid=one',
      );
      expect(
        requests[1].headers['Authorization'],
        'token=secret-two;userid=two',
      );
      expect(requests[2].headers.containsKey('Authorization'), false);
      for (final request in requests) {
        expect(request.headers['x-apicache-bypass'], '1');
        expect(request.url.toString().contains('secret-'), false);
      }
    },
  );

  test(
    'transport rejects remote server and URL-like endpoint before sending credentials',
    () async {
      var sent = false;
      final api = MusicPlatformApi(
        server: _Server('example.com'),
        client: MockClient((_) async {
          sent = true;
          return http.Response('{}', 200);
        }),
      );
      await expectLater(api.get('/user/detail'), throwsStateError);
      await expectLater(api.get('//attacker.invalid'), throwsArgumentError);
      await expectLater(
        api.get('https://attacker.invalid'),
        throwsArgumentError,
      );
      expect(sent, false);
    },
  );

  test(
    'business error during multi-account phone login preserves account choices',
    () async {
      final api = MusicPlatformApi(
        server: _Server(),
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'status': 0,
              'error_code': 34175,
              'data': {
                'info_list': [
                  {'userid': 'one', 'nickname': 'First'},
                  {'userid': 'two', 'nickname': 'Second'},
                ],
              },
            }),
            502,
          ),
        ),
      );
      final result = await PlatformLoginService(
        api,
      ).phoneLogin('13800000000', '000000');
      expect(result['error_code'], 34175);
      expect((result['data'] as Map)['info_list'], hasLength(2));
    },
  );

  test(
    'QR pending, success and expiry do not confuse credentials with a scan',
    () async {
      var status = 2;
      final api = MusicPlatformApi(
        server: _Server(),
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'data': {'status': status, 'userid': 'one', 'token': 'secret'},
            }),
            200,
          ),
        ),
      );
      final login = PlatformLoginService(api);
      const challenge = PlatformQrChallenge(
        method: PlatformLoginMethod.kugouQr,
        parameters: {'key': 'test'},
        imageBase64: 'AA==',
      );
      expect(await login.poll(challenge), null);
      status = 4;
      expect((await login.poll(challenge))?['userid'], 'one');
      status = 800;
      await expectLater(
        login.poll(challenge),
        throwsA(isA<MusicPlatformException>()),
      );
    },
  );

  test(
    'account initialization, login and logout use only the platform store',
    () async {
      final store = _Store();
      final api = MusicPlatformApi(
        server: _Server(),
        client: MockClient((_) async => http.Response('{}', 200)),
      );
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          platformSessionStoreProvider.overrideWithValue(store),
          musicPlatformApiProvider.overrideWithValue(api),
        ],
      );
      addTearDown(container.dispose);
      expect(await container.read(platformAccountProvider.future), null);
      final controller = container.read(platformAccountProvider.notifier);
      await controller.accept({'userid': 'one', 'token': 'secret'});
      expect(api.session?.userId, 'one');
      expect(store.value?.userId, 'one');
      store.failClear = true;
      await expectLater(controller.signOut(), throwsStateError);
      expect(container.read(platformAccountProvider).value?.userId, 'one');
      store.failClear = false;
      await controller.signOut();
      expect(api.session, null);
      expect(store.value, null);
      expect(container.read(platformAccountProvider).value, null);
    },
  );

  test(
    'API failure never exposes an upstream response containing credentials',
    () async {
      final api = MusicPlatformApi(
        server: _Server(),
        client: MockClient(
          (_) async => http.Response(
            '{"status":0,"token":"do-not-display","error_msg":"private"}',
            502,
          ),
        ),
      );
      try {
        await api.get('/login/cellphone');
        fail('Expected a safe error');
      } catch (error) {
        expect('$error', isNot(contains('do-not-display')));
        expect('$error', isNot(contains('private')));
      }
    },
  );
}
