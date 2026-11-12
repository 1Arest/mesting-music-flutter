import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_api.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_diagnostics.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_listening_repository.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_request_signer.dart';

import 'qishui_signed_api167_test.dart' show account, reply;
import 'qishui_signer168_test.dart' show config168, signature168, token168;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(QishuiDiagnostics.shared.clear);
  tearDown(QishuiDiagnostics.shared.clear);

  for (final missing in [false, true]) {
    test(
      'official capability bytes are signed; missing duration=$missing',
      () async {
        final envelopes = <Map<String, dynamic>>[];
        var officialCalls = 0;
        final client = MockClient((request) async {
          if (request.url.host == 'nas.example.test') {
            if (request.url.path == '/config') return config168();
            envelopes.add(
              Map<String, dynamic>.from(jsonDecode(request.body) as Map),
            );
            return signature168();
          }
          officialCalls++;
          expect(request.method, 'POST');
          expect(request.url.host, 'api.qishui.com');
          expect(request.url.path, '/luna/me/music_wall');
          expect(request.body, envelopes.single['body']);
          final body = jsonDecode(request.body) as Map;
          expect(body.keys.toSet(), {'feed_music_wall_extra', 'ab_param'});
          expect(body['feed_music_wall_extra'], isEmpty);
          expect(body['ab_param'], isA<String>());
          // Expected values were recovered independently from official call
          // sites, rather than derived from the product constant under test.
          expect(jsonDecode(body['ab_param'] as String), {
            'enable_new_music_wall': 1,
            'enable_fav_artists': false,
            'enable_fav_playables': false,
          });
          return reply({
            'status_code': 0,
            'listen_duration': missing
                ? null
                : {'total_duration': 123456, 'week_duration': 789},
          });
        });
        final api = QishuiApi(
          client,
          signer: SodaMRequestSigner(
            client,
            custom: true,
            endpoint: Uri.parse('https://nas.example.test/sign'),
            accessToken: token168,
          ),
        )..configure(account());
        addTearDown(api.dispose);
        final repository = QishuiListeningRepository(
          api: api,
          current: () => true,
        );
        if (missing) {
          await expectLater(
            repository.fetch(),
            throwsA(isA<QishuiException>()),
          );
          expect(
            QishuiDiagnostics.shared.events.last['reason'],
            'missingFields',
          );
        } else {
          final snapshot = await repository.fetch();
          expect(snapshot.totalSeconds, 123456);
          expect(snapshot.weekSeconds, 789);
        }
        expect(officialCalls, 1);
        expect(envelopes, hasLength(1));
        final encoded = jsonEncode(envelopes);
        expect(encoded, isNot(contains('music-secret167')));
        expect(encoded, isNot(contains(token168)));
        if (!missing && const bool.fromEnvironment('EXPORT_179_CONTRACT')) {
          // A pure fixture of the real transport bytes for the independent
          // helper owner to validate offline. No real NAS or account is used.
          File(
            '.codex-artifacts/2026-11-08-release179/helper-app-envelopes179.json',
          ).writeAsStringSync(
            const JsonEncoder.withIndent('  ').convert(envelopes),
          );
        }
      },
    );
  }
}
