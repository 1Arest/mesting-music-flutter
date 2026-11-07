import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesting_music/core/network/music_network_diagnostics.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_api.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_entitlements.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_repository.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_request_signer.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_signer_defaults.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_signer_settings.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_session.dart';
import 'qishui_signed_api167_test.dart' show account;
import 'qishui_signer168_test.dart'
    show token168, config168, signature168, json168;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => MusicNetworkDiagnostics.shared.clear());
  test(
    'old encrypted settings stay anonymous; opt-in persists independently',
    () {
      final old = QishuiSignerConfig.parse(
        'https://nas.example.test/',
        token168,
      );
      final legacy = Map<String, dynamic>.of(old.toJson())
        ..remove('accountBoundSigning');
      expect(QishuiSignerConfig.fromJson(legacy).accountBoundSigning, false);
      final enabled = QishuiSignerConfig.parse(
        'https://nas.example.test/',
        token168,
        accountBoundSigning: true,
      );
      expect(QishuiSignerConfig.fromJson(Map.of(enabled.toJson())), enabled);
      expect(enabled, isNot(old));
      expect(enabled.toString(), isNot(contains(token168)));
      legacy['accountBoundSigning'] = 'true';
      expect(() => QishuiSignerConfig.fromJson(legacy), throwsFormatException);
    },
  );
  for (final address in [
    'http://nas.example.test/',
    qishuiReferenceSignerUrl,
  ]) {
    test('account signing cannot be enabled for $address', () {
      expect(
        () => QishuiSignerConfig.parse(
          address,
          token168,
          accountBoundSigning: true,
        ),
        throwsFormatException,
      );
    });
    test(
      'direct signer boundary rejects invalid account opt-in $address',
      () async {
        var sent = false;
        final signer = SodaMRequestSigner(
          MockClient((_) async {
            sent = true;
            return signature168();
          }),
          endpoint: Uri.parse(address),
          custom: true,
          accountBoundSigning: true,
        );
        await expectLater(
          signer.sign(
            Uri.https('api.qishui.com', '/luna/pc/track_v2'),
            'POST',
            '{}',
            {'cookie': 'fixture-private'},
            Completer<void>().future,
          ),
          throwsA(isA<QishuiException>()),
        );
        expect(sent, false);
      },
    );
  }
  for (final enabled in [false, true]) {
    test(
      'official media Cookie is ${enabled ? 'identical during signing' : 'absent from helper'}',
      () async {
        String? signedCookie, officialCookie;
        final client = MockClient((r) async {
          if (r.url.host == 'nas.example.test') {
            expect(r.headers['cookie'], isNull);
            if (r.method == 'GET') return config168();
            final headers = Map<String, dynamic>.from(
              (jsonDecode(r.body) as Map)['headers'] as Map,
            );
            signedCookie = headers['cookie'] as String?;
            expect(headers.containsKey('x-tt-passport-csrf-token'), false);
            expect(headers.containsKey('authorization'), false);
            return signature168();
          }
          officialCookie = r.headers['cookie'];
          return json168({'status_code': 0, 'track_player': {}});
        });
        final config = QishuiSignerConfig.parse(
          'https://nas.example.test/',
          token168,
          accountBoundSigning: enabled,
        );
        final api = QishuiApi(
          client,
          signer: ConfiguredQishuiRequestSigner(client, () async => config),
        )..configure(account());
        addTearDown(api.dispose);
        await QishuiRepository(api).media('fixture');
        expect(officialCookie, 'sessionid=music-secret167');
        expect(signedCookie, enabled ? officialCookie : null);
        final exported = MusicNetworkDiagnostics.shared.export();
        expect(exported, isNot(contains('music-secret167')));
        expect(exported, isNot(contains(token168)));
        expect(
          MusicNetworkDiagnostics.shared.rows
              .where((r) => r['phase'] == 'accountSigning')
              .single['accountCookieSigned'],
          enabled,
        );
      },
    );
  }
  test(
    'a concurrent Cookie rotation cannot change the signed request bytes',
    () async {
      final signing = Completer<void>(), release = Completer<void>();
      String? signed, dispatched;
      final client = MockClient((r) async {
        if (r.url.host == 'nas.example.test') {
          if (r.method == 'GET') return config168();
          signed =
              ((jsonDecode(r.body) as Map)['headers'] as Map)['cookie']
                  as String?;
          signing.complete();
          await release.future;
          return signature168();
        }
        if (r.url.path == '/luna/pc/me') {
          return http.Response(
            '{"status_code":0}',
            200,
            headers: {
              'set-cookie': 'sessionid=fixture-rotated; Path=/; Secure',
            },
          );
        }
        dispatched = r.headers['cookie'];
        return json168({'status_code': 0});
      });
      final config = QishuiSignerConfig.parse(
        'https://nas.example.test/',
        token168,
        accountBoundSigning: true,
      );
      final api = QishuiApi(
        client,
        signer: ConfiguredQishuiRequestSigner(client, () async => config),
      )..configure(account());
      addTearDown(api.dispose);
      final media = QishuiRepository(api).media('fixture');
      await signing.future;
      await api.request('/luna/me');
      release.complete();
      await media;
      expect(dispatched, signed);
      expect(dispatched, 'sessionid=music-secret167');
    },
  );
  test(
    'Cookie, CSRF and token use one snapshot during concurrent renewal',
    () async {
      final signing = Completer<void>(), release = Completer<void>();
      String? signedCookie;
      final session = QishuiSession(
        userId: 'fixture172',
        protocol: QishuiSessionProtocol.web,
        cookies: [
          ...account().cookies,
          {
            'name': 'passport_csrf_token',
            'value': 'fixture-old-csrf',
            'domain': 'api.qishui.com',
            'path': '/',
          },
        ],
        tokens: {'x-tt-token': 'fixture-old-token'},
      );
      final client = MockClient((r) async {
        if (r.url.host == 'nas.example.test') {
          if (r.method == 'GET') return config168();
          final headers = (jsonDecode(r.body) as Map)['headers'] as Map;
          signedCookie = headers['cookie'] as String?;
          expect(headers.containsKey('x-tt-token'), false);
          expect(headers.containsKey('x-tt-passport-csrf-token'), false);
          signing.complete();
          await release.future;
          return signature168();
        }
        if (r.url.path == '/luna/pc/me') {
          return http.Response(
            '{"status_code":0}',
            200,
            headers: {
              'set-cookie':
                  'passport_csrf_token=fixture-new-csrf; Path=/; Secure',
              'x-tt-token': 'fixture-new-token',
            },
          );
        }
        expect(r.headers['cookie'], signedCookie);
        expect(r.headers['x-tt-passport-csrf-token'], 'fixture-old-csrf');
        expect(r.headers['x-tt-token'], 'fixture-old-token');
        return json168({'status_code': 0});
      });
      final config = QishuiSignerConfig.parse(
        'https://nas.example.test/',
        token168,
        accountBoundSigning: true,
      );
      final api = QishuiApi(
        client,
        signer: ConfiguredQishuiRequestSigner(client, () async => config),
      )..configure(session);
      addTearDown(api.dispose);
      final media = QishuiRepository(api).media('fixture');
      await signing.future;
      await api.request('/luna/me');
      release.complete();
      await media;
      expect(
        MusicNetworkDiagnostics.shared.export(),
        isNot(contains('fixture-old-csrf')),
      );
    },
  );
  test('non-media signatures remain anonymous even with opt-in', () async {
    final signer = SodaMRequestSigner(
      MockClient((r) async {
        expect(
          (jsonDecode(r.body) as Map)['headers'],
          isNot(contains('cookie')),
        );
        return signature168();
      }),
      endpoint: Uri.parse('https://nas.example.test/sign'),
      custom: true,
      accountBoundSigning: true,
    );
    await signer.sign(
      Uri.https('api.qishui.com', '/luna/pc/me/playlist', {
        'device_id': '12345678901234',
      }),
      'POST',
      '{}',
      {'cookie': 'fixture-private'},
      Completer<void>().future,
    );
  });

  final now = DateTime.utc(2026, 11, 7);
  final later = now.add(const Duration(days: 29));
  for (final millis in [false, true]) {
    for (final field in ['play_entitlements', 'incentive']) {
      test(
        '$field ${millis ? 'milliseconds' : 'seconds'} reads existing 29 day benefit',
        () {
          final rights = QishuiEntitlements({
            field: {
              field == 'incentive' ? 'expire_time' : 'expire_at':
                  later.millisecondsSinceEpoch ~/ (millis ? 1 : 1000),
            },
          }, now: now);
          expect(rights.freeListeningUntil, later);
          expect(rights.membershipActive, false);
          expect(rights.listeningSummary, contains('2026-12-06'));
        },
      );
    }
  }
  for (final expiry in [
    0,
    null,
    -1,
    'invalid',
    1794000000.5,
    double.infinity,
  ]) {
    test('invalid or expired benefit $expiry does not create membership', () {
      final rights = QishuiEntitlements({
        'play_entitlements': {'expire_at': expiry},
        'incentive': {'max_release_days': 29},
        'activity_free_vip': {
          'end_time_sec': later.millisecondsSinceEpoch ~/ 1000,
        },
      }, now: now);
      expect(rights.freeListeningActive, false);
      expect(rights.membershipActive, false);
    });
  }
  test('unavailable incentive and expired membership stay inactive', () {
    final rights = QishuiEntitlements({
      'incentive': {
        'available': false,
        'expire_time': later.millisecondsSinceEpoch,
      },
      'membership': {
        'is_membership': true,
        'expire_time': now.millisecondsSinceEpoch ~/ 1000,
      },
    }, now: now);
    expect(rights.freeListeningActive, false);
    expect(rights.membershipActive, false);
  });
  test(
    'QR account can read commerce, without signing or enabling benefit writes',
    () async {
      var reads = 0;
      final api = QishuiApi(
        MockClient((r) async {
          reads++;
          expect(r.url.host, 'api.qishui.com');
          expect(r.url.path, '/luna/commerce/v2/commerce_info');
          expect(r.url.queryParameters['device_platform'], 'windows');
          expect(r.headers['cookie'], 'sessionid=music-secret167');
          expect(
            (jsonDecode(r.body) as Map)['includes'],
            contains('incentive'),
          );
          return json168({
            'play_entitlements': {'expire_at': later.millisecondsSinceEpoch},
            'status_info': {'code': 0, 'now_ts_ms': now.millisecondsSinceEpoch},
          });
        }),
      )..configure(account());
      addTearDown(api.dispose);
      final music = QishuiRepository(api);
      expect(
        QishuiEntitlements(await music.commerce()).freeListeningActive,
        true,
      );
      await expectLater(
        music.call('/luna/commerce/v2/apply_free_vip', write: true),
        throwsA(isA<QishuiException>()),
      );
      expect(reads, 1);
    },
  );
}
