import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_api.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_diagnostics.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_http_diagnostics.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_repository.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_request_signer.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_social_models.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_social_repository.dart';

import 'qishui_signed_api167_test.dart' show FixtureSigner, reply;
import 'qishui_signer168_test.dart' show config168, identity168, token168;
import 'qishui_social177_test.dart' show account177;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(QishuiDiagnostics.shared.clear);
  tearDown(QishuiDiagnostics.shared.clear);

  test(
    'a 200 follow reply and a rejected DTO have separate observations',
    () async {
      final api = QishuiApi(
        MockClient(
          (r) async => reply({
            'status_code': 0,
            'data': {
              'users': [
                {'id': '178001', 'nickname': 'private-fixture-name'},
              ],
              'private-fixture-key': 'private-fixture-value',
            },
          }),
        ),
        signer: FixtureSigner(),
      )..configure(account177());
      addTearDown(api.dispose);
      await expectLater(
        QishuiSocialRepository(
          QishuiRepository(api),
        ).list(QishuiFollowListKind.following),
        throwsA(isA<QishuiException>()),
      );
      final rows = QishuiDiagnostics.shared.events;
      expect(
        rows.any((r) => r['stage'] == 'response' && r['httpStatus'] == 200),
        isTrue,
      );
      final failure = rows.last;
      expect(failure['feature'], 'following');
      expect(failure['stage'], 'parse');
      expect(failure['outcome'], 'format');
      expect(failure['reason'], 'responseShape');
      final exported = QishuiDiagnostics.shared.export();
      expect(exported, contains('users'));
      for (final value in ['178001', '17701', 'private-fixture', 'sessionid']) {
        expect(exported, isNot(contains(value)));
      }
    },
  );

  test(
    'helper rejection is identified without exporting signing material',
    () async {
      final api = QishuiApi(
        MockClient((r) async {
          if (r.url.path == '/config') return config168();
          if (r.url.host == 'nas.example.test') {
            return http.Response(
              jsonEncode({
                'code': 'forbidden_query',
                'message': 'private-helper-fixture',
                'headers': {'X-Helios': 'private-helper-signature'},
              }),
              400,
            );
          }
          fail('The official request must not follow a helper rejection');
        }),
      );
      // Use the very same client for the helper and official API, as production
      // does, while every endpoint in this test remains an in-memory fake.
      final signed = QishuiApi(
        api.client,
        signer: SodaMRequestSigner(
          api.client,
          endpoint: Uri.parse('https://nas.example.test/sign'),
          accessToken: token168,
          custom: true,
        ),
      )..configure(account177());
      addTearDown(signed.dispose);
      await expectLater(
        signed.request('/luna/users/17701/following', get: true),
        throwsA(isA<QishuiException>()),
      );
      final failure = QishuiDiagnostics.shared.events.lastWhere(
        (r) => r['stage'] == 'helper',
      );
      expect(failure['feature'], 'following');
      expect(failure['httpStatus'], 400);
      expect(failure['serviceCode'], 'forbidden_query');
      final exported = QishuiDiagnostics.shared.export();
      expect(exported, isNot(contains('private-helper')));
      expect(exported, isNot(contains(token168)));
      expect(exported, isNot(contains('nas.example.test')));
    },
  );

  test('diagnostic routing excludes already working catalogue requests', () {
    expect(qishuiDiagnosticFeatureForRequest('/luna/search/track'), isNull);
    expect(qishuiDiagnosticFeatureForRequest('/luna/pc/search/artist'), isNull);
    expect(
      qishuiDiagnosticFeatureForRequest('/luna/me/playlist/update'),
      isNull,
    );
    expect(
      qishuiDiagnosticFeatureForRequest(
        '/luna/me/playlist/update',
        body: const {'cover_uri': 'private-image-key'},
      ),
      QishuiDiagnosticFeature.playlistCover,
    );
  });

  for (final failure in [
    'invalidJson',
    'rejected',
    'missingFields',
    'identityMismatch',
  ]) {
    test(
      'helper 200 followed by $failure ends with an explicit failure',
      () async {
        final client = MockClient((r) async {
          if (r.url.path == '/config') return config168();
          if (r.url.host != 'nas.example.test') {
            fail('No official dispatch is allowed');
          }
          if (failure == 'invalidJson') return http.Response('{', 200);
          return http.Response(
            jsonEncode({
              'ok': failure != 'rejected',
              if (failure != 'missingFields')
                'headers': {
                  'X-Helios': 'private-signature-a',
                  'X-Medusa': 'private-signature-b',
                },
              'device_id': failure == 'identityMismatch'
                  ? 'private-different-device'
                  : identity168['device_id'],
            }),
            200,
          );
        });
        final api = QishuiApi(
          client,
          signer: SodaMRequestSigner(
            client,
            endpoint: Uri.parse('https://nas.example.test/sign'),
            accessToken: token168,
            custom: true,
          ),
        )..configure(account177());
        addTearDown(api.dispose);
        await expectLater(
          api.request('/luna/users/17701/following', get: true),
          throwsA(isA<QishuiException>()),
        );
        final last = QishuiDiagnostics.shared.events.last;
        expect(last['stage'], 'helper');
        expect(last['outcome'], isNot('success'));
        expect(
          last['reason'],
          failure == 'rejected' ? 'receiptRejected' : failure,
        );
        final exported = QishuiDiagnostics.shared.export();
        expect(exported, isNot(contains('private-')));
        expect(exported, isNot(contains(token168)));
      },
    );
  }

  test(
    'an empty 200 business payload is recorded as a format failure',
    () async {
      final api = QishuiApi(
        MockClient((r) async => http.Response('{}', 200)),
        signer: FixtureSigner(),
      )..configure(account177());
      addTearDown(api.dispose);
      await expectLater(
        api.request('/luna/me/music_wall'),
        throwsA(isA<QishuiException>()),
      );
      final last = QishuiDiagnostics.shared.events.last;
      expect(last['feature'], 'officialListening');
      expect(last['outcome'], 'format');
      expect(last['reason'], 'responseShape');
    },
  );
}
