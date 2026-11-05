import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesting_music/core/network/music_http_client.dart';
import 'package:mesting_music/core/network/music_network_diagnostics.dart';
import 'package:mesting_music/features/music_platform/netease/netease_api.dart';
import 'package:mesting_music/features/music_platform/netease/netease_login.dart';
import 'package:mesting_music/features/music_platform/data/music_platform_api.dart';

class _StalledClient extends http.BaseClient {
  final aborted = Completer<void>();
  int calls = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    calls++;
    (request as http.Abortable).abortTrigger!.then((_) {
      if (!aborted.isCompleted) aborted.complete();
    });
    return Completer<http.StreamedResponse>().future;
  }
}

class _BodyStall extends _StalledClient {
  final controller = StreamController<List<int>>();
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    calls++;
    (request as http.Abortable).abortTrigger!.then((_) {
      if (!aborted.isCompleted) aborted.complete();
      controller.close();
    });
    return Future.value(http.StreamedResponse(controller.stream, 200));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.mesting.music/network');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() => MusicNetworkDiagnostics.shared.clear());
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  for (final body in [false, true]) {
    test(
      'deadline cancels a stalled ${body ? 'body' : 'header'} without replaying SMS',
      () async {
        final client = body ? _BodyStall() : _StalledClient();
        await expectLater(
          sendMusicRequest(
            client: client,
            build: (abort) => http.AbortableRequest(
              'POST',
              Uri.https('music.163.com', '/sms'),
              abortTrigger: abort,
            ),
            platform: 'netease',
            operation: MusicNetworkOperation.sms,
            timeout: const Duration(milliseconds: 25),
          ),
          throwsA(
            isA<MusicTransportException>().having(
              (e) => e.outcome,
              'outcome',
              MusicNetworkOutcome.timeout,
            ),
          ),
        );
        await client.aborted.future;
        expect(client.calls, 1);
      },
    );
  }
  test(
    'read retries once, but a write never replays after an uncertain failure',
    () async {
      for (final read in [true, false]) {
        var calls = 0;
        final client = MockClient((_) async {
          if (++calls == 1) throw const SocketException('connection reset');
          return http.Response('{}', 200);
        });
        final request = sendMusicRequest(
          client: client,
          build: (abort) => http.AbortableRequest(
            'POST',
            Uri.https('music.163.com', '/api'),
            abortTrigger: abort,
          ),
          platform: 'netease',
          operation: read
              ? MusicNetworkOperation.read
              : MusicNetworkOperation.login,
          retryRead: read,
        );
        if (read) {
          expect((await request).statusCode, 200);
        } else {
          await expectLater(request, throwsA(isA<MusicTransportException>()));
        }
        expect(calls, read ? 2 : 1);
      }
    },
  );
  test('platform business rejection is not retried', () async {
    var calls = 0;
    final response = await sendMusicRequest(
      client: MockClient((_) async {
        calls++;
        return http.Response('{"code":460}', 200);
      }),
      build: (abort) => http.AbortableRequest(
        'POST',
        Uri.https('music.163.com', '/api'),
        abortTrigger: abort,
      ),
      platform: 'netease',
      operation: MusicNetworkOperation.read,
      retryRead: true,
    );
    expect(response.statusCode, 200);
    expect(calls, 1);
  });
  test('already cancelled reads never dispatch', () async {
    final abort = Completer<void>()..complete();
    var calls = 0;
    await expectLater(
      sendMusicRequest(
        client: MockClient((_) async {
          calls++;
          return http.Response('{}', 200);
        }),
        build: (trigger) => http.AbortableRequest(
          'GET',
          Uri.https('music.163.com', '/api'),
          abortTrigger: trigger,
        ),
        platform: 'netease',
        operation: MusicNetworkOperation.read,
        abortTrigger: abort.future,
      ),
      throwsA(isA<http.RequestAbortedException>()),
    );
    expect(calls, 0);
  });
  test(
    'Android sends exact encrypted body and cookies through system transport',
    () async {
      var fallbacks = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'send');
        final args = call.arguments as Map;
        expect(args['method'], 'POST');
        expect((args['headers'] as Map)['Cookie'], 'MUSIC_U=fixture-only');
        expect(
          utf8.decode(args['body'] as List<int>),
          'params=encrypted-fixture',
        );
        return {
          'status': 200,
          'headers': {'set-cookie': 'MUSIC_U=fixture-new; Path=/'},
          'body': Uint8List.fromList(utf8.encode('{"code":200}')),
        };
      });
      final client = MusicHttpClient(
        android: true,
        fallback: MockClient((_) async {
          fallbacks++;
          return http.Response('{}', 200);
        }),
      );
      addTearDown(client.close);
      final response = await client.post(
        Uri.https('interface.music.163.com', '/eapi/login'),
        headers: {'Cookie': 'MUSIC_U=fixture-only'},
        body: 'params=encrypted-fixture',
      );
      expect(response.statusCode, 200);
      expect(response.headers['set-cookie'], contains('fixture-new'));
      expect(fallbacks, 0);
    },
  );
  test('native timeout never falls back and resends a login', () async {
    var fallback = 0;
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => throw PlatformException(
        code: 'timeout',
        message: 'secret-url-never-exported',
      ),
    );
    final client = MusicHttpClient(
      android: true,
      fallback: MockClient((_) async {
        fallback++;
        return http.Response('{}', 200);
      }),
    );
    addTearDown(client.close);
    await expectLater(
      client.post(Uri.https('music.163.com', '/login'), body: 'secret'),
      throwsA(isA<MusicTransportException>()),
    );
    expect(fallback, 0);
  });
  test(
    'missing native method falls back once without losing request bytes',
    () async {
      var calls = 0;
      final client = MusicHttpClient(
        android: true,
        fallback: MockClient((request) async {
          calls++;
          expect(request.body, 'fixture');
          return http.Response('{}', 200);
        }),
      );
      addTearDown(client.close);
      await client.post(Uri.https('music.163.com', '/login'), body: 'fixture');
      expect(calls, 1);
    },
  );
  test(
    'a bridge attached after cold bootstrap is used by the next request',
    () async {
      var fallback = 0, native = 0;
      final client = MusicHttpClient(
        android: true,
        fallback: MockClient((_) async {
          fallback++;
          return http.Response('{}', 200);
        }),
      );
      addTearDown(client.close);
      await client.post(
        Uri.https('music.163.com', '/login'),
        body: 'first-fixture',
      );
      messenger.setMockMethodCallHandler(channel, (_) async {
        native++;
        return {
          'status': 200,
          'headers': <String, String>{},
          'body': Uint8List.fromList(utf8.encode('{}')),
        };
      });
      await client.post(
        Uri.https('music.163.com', '/login'),
        body: 'second-fixture',
      );
      expect(fallback, 1);
      expect(native, 1);
    },
  );
  test(
    'loopback and unapproved HTTPS hosts never go through platform bridge',
    () {
      for (final url in [
        'http://127.0.0.1:9012/login',
        'https://music.163.com.evil.test/api',
        'https://user:secret@music.163.com/api',
        'https://music.163.com:444/api',
      ]) {
        expect(MusicHttpClient.systemHost(Uri.parse(url)), false);
      }
    },
  );
  test(
    'NetEase transport failure is readable and SMS is dispatched only once',
    () async {
      var calls = 0;
      final login = NeteaseLoginService(
        NeteaseApi(
          MockClient((_) async {
            calls++;
            throw const SocketException('Failed host lookup: secret.example');
          }),
        ),
      );
      await expectLater(
        login.sendCode('13800138000', '86'),
        throwsA(
          isA<MusicPlatformException>().having(
            (e) => e.message,
            'message',
            contains('地址解析失败'),
          ),
        ),
      );
      expect(calls, 1);
    },
  );
  test(
    'SMS requires an explicit successful receipt, not an empty JSON body',
    () async {
      final login = NeteaseLoginService(
        NeteaseApi(MockClient((_) async => http.Response('{}', 200))),
      );
      await expectLater(
        login.sendCode('13800138000', '86'),
        throwsA(isA<MusicPlatformException>()),
      );
    },
  );
  test(
    'diagnostics are bounded and never contain request/error credentials',
    () async {
      for (var i = 0; i < 100; i++) {
        MusicNetworkDiagnostics.shared.record(
          platform: 'secret-user',
          operation: MusicNetworkOperation.login,
          outcome: classifyMusicNetworkError(
            const SocketException('Failed host lookup: token=secret-user'),
          ),
          transport: 'secret-user',
        );
      }
      final report = MusicNetworkDiagnostics.shared.export();
      expect(MusicNetworkDiagnostics.shared.rows.length, 80);
      expect(report, isNot(contains('secret-user')));
      expect(report, isNot(contains('token=')));
    },
  );
}
