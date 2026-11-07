import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_api.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_request_signer.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_session.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_signer_settings.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_providers.dart';

const token168 = 'fixture168_private_helper_access_token_1234567890';
const identity168 = {
  'device_id': '12345678901234',
  'iid': '12345678901235',
  'fp': 'fixture-pc-168',
  'user_agent': 'LunaPC/3.7.0(452316191)',
};
http.Response json168(Object value) => http.Response(
  jsonEncode(value),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
http.Response config168() => json168({'ok': true, 'identity': identity168});
http.Response signature168() => json168({
  'ok': true,
  'headers': {
    'X-Helios': 'fixture-helios-168',
    'X-Medusa': 'fixture-medusa-168',
  },
  'device_id': identity168['device_id'],
});

class MemorySignerStore168 implements QishuiSignerSettingsStore {
  QishuiSignerConfig? value;
  bool fail = false;
  int reads = 0;
  @override
  Future<QishuiSignerConfig?> read() async {
    reads++;
    return value;
  }

  @override
  Future<void> write(QishuiSignerConfig config) async {
    if (fail) throw StateError('fixture refusal');
    value = config;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'creating the API does not open settings; saved changes retain its account',
    () async {
      final store = MemorySignerStore168();
      final container = ProviderContainer(
        overrides: [qishuiSignerSettingsStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      final api = container.read(qishuiApiProvider);
      await Future<void>.delayed(Duration.zero);
      expect(store.reads, 0);
      final session = QishuiSession(
        userId: 'fixture168',
        protocol: QishuiSessionProtocol.web,
        cookies: [
          {
            'name': 'sessionid',
            'value': 'fixture-only',
            'domain': 'api.qishui.com',
            'path': '/',
          },
        ],
      );
      api.configure(session);
      await container.read(qishuiSignerSettingsProvider.future);
      await container
          .read(qishuiSignerSettingsProvider.notifier)
          .save(
            QishuiSignerConfig.parse('https://nas.example.test/', token168),
          );
      expect(api.credential, session.credentialId);
      expect(api.session?.cookies, session.cookies);
    },
  );
  for (final address in [
    'http://192.168.1.8:18899',
    'https://nas.example.test/qishui-signer/',
    'https://nas.example.test/qishui-signer/sign',
  ]) {
    test('normalize service address $address', () {
      final config = QishuiSignerConfig.parse(address, token168);
      expect(config.signUri.path.endsWith('/sign'), isTrue);
      expect(config.configUri.path.endsWith('/config'), isTrue);
      expect(config.signUri.path, isNot(contains('/sign/sign')));
      expect(config.toString(), isNot(contains(token168)));
      expect(QishuiSignerConfig.fromJson(config.toJson()), config);
    });
  }
  for (final address in [
    'file:///nas',
    'https://user:secret@nas.test/',
    'https://nas.test/?token=secret',
    'https://nas.test/#secret',
    'http://nas.test:0/',
    'http://nas.test:65536/',
    'http://nas.test/a%2Fb/',
  ]) {
    test(
      'reject non-service address $address',
      () => expect(
        () => QishuiSignerConfig.parse(address, token168),
        throwsFormatException,
      ),
    );
  }
  test(
    'durable settings failure keeps the previously committed service',
    () async {
      final store = MemorySignerStore168();
      final container = ProviderContainer(
        overrides: [qishuiSignerSettingsStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      await container.read(qishuiSignerSettingsProvider.future);
      final one = QishuiSignerConfig.parse(
        'https://one.example.test/',
        token168,
      );
      await container.read(qishuiSignerSettingsProvider.notifier).save(one);
      store.fail = true;
      await expectLater(
        container
            .read(qishuiSignerSettingsProvider.notifier)
            .save(QishuiSignerConfig.parse('http://192.168.1.3/', token168)),
        throwsStateError,
      );
      expect(container.read(qishuiSignerSettingsProvider).value, one);
    },
  );
  test(
    'private helper and official requests keep credentials separate and exact bytes',
    () async {
      final envelopes = <Object>[];
      final client = MockClient((request) async {
        if (request.url.host == 'nas.example.test') {
          expect(request.headers['authorization'], 'Bearer $token168');
          expect(request.headers.containsKey('cookie'), isFalse);
          if (request.url.path.endsWith('/config')) return config168();
          expect(Zone.current[#flutter.io.allow_http], isNull);
          final envelope = jsonDecode(request.body) as Map<String, dynamic>;
          expect(request.followRedirects, isFalse);
          expect(request.body, isNot(contains('account-secret168')));
          envelopes.add(envelope);
          return signature168();
        }
        expect(request.url.host, 'api.qishui.com');
        final signed = envelopes.single as Map;
        expect(request.url.toString(), signed['url']);
        expect(request.body, signed['body']);
        expect(request.headers['user-agent'], identity168['user_agent']);
        expect(request.url.queryParameters['version_name'], '3.7.0');
        expect(request.url.queryParameters['version_code'], '3007000');
        expect(request.url.queryParameters.keys, isNot(contains('cdid')));
        expect(request.url.queryParameters.keys, isNot(contains('user_agent')));
        expect(request.headers['cookie'], 'sessionid=account-secret168');
        expect(request.headers['authorization'], isNull);
        expect(request.headers.values.join(), isNot(contains(token168)));
        return json168({
          'status_info': {'code': 0},
          'track_player': {},
        });
      });
      final signer = ConfiguredQishuiRequestSigner(
        client,
        () async => QishuiSignerConfig.parse(
          'https://nas.example.test/qishui-signer/',
          token168,
        ),
      );
      final api = QishuiApi(client, signer: signer)
        ..configure(
          QishuiSession(
            userId: 'owner168',
            protocol: QishuiSessionProtocol.web,
            cookies: [
              {
                'name': 'sessionid',
                'value': 'account-secret168',
                'domain': 'api.qishui.com',
                'path': '/',
                'secure': 'true',
              },
            ],
          ),
        );
      addTearDown(api.dispose);
      await api.request(
        '/luna/media_v2',
        body: {
          'media': [
            {'id': '123456789', 'type': 'track'},
          ],
        },
      );
      // Optional capture is checked against the *actual* helper policy offline.
      if (const bool.fromEnvironment('CAPTURE_SIGNER168')) {
        File(
          '.codex-artifacts/2026-11-06-release168/helper-envelopes.json',
        ).writeAsStringSync(jsonEncode(envelopes));
      }
    },
  );
  for (final status in [401, 404, 429, 500, 503]) {
    test(
      'HTTP $status remains a helper error without public fallback or raw body',
      () async {
        var calls = 0;
        final signer = ConfiguredQishuiRequestSigner(
          MockClient((r) async {
            calls++;
            expect(r.url.host, '192.168.1.8');
            expect(Zone.current[#flutter.io.allow_http], isTrue);
            return http.Response('private-response-$token168', status);
          }),
          () async =>
              QishuiSignerConfig.parse('http://192.168.1.8:18899/', token168),
        );
        await expectLater(
          signer.identity(Completer<void>().future),
          throwsA(
            isA<QishuiException>()
                .having((e) => e.message, 'HTTP status', contains('$status'))
                .having(
                  (e) => e.message,
                  'redacted',
                  isNot(contains(token168)),
                ),
          ),
        );
        expect(calls, 1);
        expect(Zone.current[#flutter.io.allow_http], isNull);
      },
    );
  }
  test(
    'connection check requests real signatures but dispatches no official request',
    () async {
      final requests = <String>[];
      await testQishuiSignerConnection(
        MockClient((r) async {
          expect(r.url.host, 'nas.example.test');
          requests.add(r.url.path);
          return r.method == 'GET' ? config168() : signature168();
        }),
        QishuiSignerConfig.parse('https://nas.example.test/prefix/', token168),
        Completer<void>().future,
      );
      expect(requests, ['/prefix/config', '/prefix/sign']);
    },
  );
  test(
    'unreadable private settings never contact a reference service',
    () async {
      final signer = ConfiguredQishuiRequestSigner(
        MockClient((_) async => fail('No network expected')),
        () async => throw StateError('fixture vault failure'),
      );
      await expectLater(
        signer.identity(Completer<void>().future),
        throwsA(isA<QishuiException>()),
      );
    },
  );
}
