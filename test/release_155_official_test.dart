import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesting_music/core/network/music_network_diagnostics.dart';
import 'package:mesting_music/features/music_platform/data/kugou_official_api.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';

const _owner155 = PlatformSession(
  userId: '15599',
  token: 'synthetic-lite-private',
  kugouStandardToken: 'synthetic-standard-private',
);
const _device155 = {
  'mid': 'synthetic-mid-private',
  'uuid': 'synthetic-uuid-private',
  'dfid': 'synthetic-dfid-private',
};

KugouOfficialApi _api155(http.Client client) => KugouOfficialApi(
  client: client,
  currentIdentity: () => _owner155,
  device: () async => _device155,
);

void _privateValuesAbsent() {
  final text = MusicNetworkDiagnostics.shared.export();
  for (final value in [
    _owner155.userId,
    _owner155.token,
    _owner155.kugouStandardToken,
    ..._device155.values,
    'signature',
    'https://',
    'sensitive-fixture-error',
  ]) {
    expect(text, isNot(contains(value)));
  }
}

class _TrickleClient155 extends http.BaseClient {
  final abortSeen = Completer<void>();
  final body = StreamController<List<int>>();
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    (request as http.Abortable).abortTrigger!.then((_) {
      if (!abortSeen.isCompleted) abortSeen.complete();
    });
    return http.StreamedResponse(body.stream, 200);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => MusicNetworkDiagnostics.shared.clear());

  for (final scenario in <(Object, MusicNetworkOutcome)>[
    (
      const HandshakeException('sensitive-fixture-error'),
      MusicNetworkOutcome.tls,
    ),
    (
      const SocketException('Failed host lookup: sensitive-fixture-error'),
      MusicNetworkOutcome.dns,
    ),
    (TimeoutException('sensitive-fixture-error'), MusicNetworkOutcome.timeout),
    (
      const SocketException('sensitive-fixture-error'),
      MusicNetworkOutcome.connection,
    ),
  ]) {
    test(
      '155 official ${scenario.$2.name} failure is classified and never replays a write',
      () async {
        var calls = 0;
        final api = _api155(
          MockClient((request) async {
            calls++;
            expect(request.method, 'POST');
            throw scenario.$1;
          }),
        );
        await expectLater(
          api.request(
            KugouOfficialRoute.medalReceive,
            _owner155,
            body: {'medal_id': 1},
          ),
          throwsA(
            isA<KugouOfficialException>().having(
              (e) => e.outcome,
              'network outcome',
              scenario.$2,
            ),
          ),
        );
        expect(calls, 1);
        expect(
          MusicNetworkDiagnostics.shared.rows.last['outcome'],
          scenario.$2.name,
        );
        _privateValuesAbsent();
      },
    );
  }

  test(
    '155 successful official GET keeps standard app/token/signature and has no invented request body',
    () async {
      final api = _api155(
        MockClient((request) async {
          expect(request.url.host, 'songplay.kugou.com');
          expect(request.url.queryParameters['appid'], '1005');
          expect(
            request.url.queryParameters['token'],
            _owner155.kugouStandardToken,
          );
          expect(request.body, isEmpty);
          expect(request.headers.containsKey('content-type'), isFalse);
          final parameters = Map.of(request.url.queryParameters)
            ..remove('signature');
          expect(
            request.url.queryParameters['signature'],
            KugouOfficialApi.signature(parameters, ''),
          );
          return http.Response(
            jsonEncode({
              'status': 1,
              'data': {
                'grade': {'level': 9},
              },
            }),
            200,
          );
        }),
      );
      final result = await api.request(KugouOfficialRoute.levelInfo, _owner155);
      expect((result['data'] as Map)['grade'], {'level': 9});
      _privateValuesAbsent();
    },
  );

  for (final body in ['not-json-sensitive-fixture-error', '[]']) {
    test(
      '155 malformed official response is format failure: ${body.startsWith('[')}',
      () async {
        final api = _api155(MockClient((_) async => http.Response(body, 200)));
        await expectLater(
          api.request(KugouOfficialRoute.statistics, _owner155),
          throwsA(
            isA<KugouOfficialException>().having(
              (e) => e.outcome,
              'outcome',
              MusicNetworkOutcome.format,
            ),
          ),
        );
        expect(
          MusicNetworkDiagnostics.shared.rows.last['phase'],
          'responseDecode',
        );
        _privateValuesAbsent();
      },
    );
  }

  test(
    '155 official HTTP rejection differs from authentication rejection',
    () async {
      await expectLater(
        _api155(
          MockClient((_) async => http.Response('private', 503)),
        ).request(KugouOfficialRoute.medals, _owner155),
        throwsA(
          isA<KugouOfficialException>().having(
            (e) => e.outcome,
            'outcome',
            MusicNetworkOutcome.http,
          ),
        ),
      );
      final api = _api155(
        MockClient(
          (_) async =>
              http.Response(jsonEncode({'status': 0, 'errcode': 20018}), 200),
        ),
      );
      await expectLater(
        api.request(KugouOfficialRoute.levelInfo, _owner155),
        throwsA(
          isA<KugouOfficialException>().having(
            (e) => e.loginRequired,
            'requires authorization',
            true,
          ),
        ),
      );
      expect(MusicNetworkDiagnostics.shared.rows.last['outcome'], 'business');
      expect(MusicNetworkDiagnostics.shared.rows.last['status'], 20018);
      _privateValuesAbsent();
    },
  );

  test(
    '155 only small official JSON is bounded; oversized response aborts once',
    () async {
      var calls = 0;
      final api = _api155(
        MockClient((_) async {
          calls++;
          return http.Response('x' * (4 * 1024 * 1024 + 1), 200);
        }),
      );
      await expectLater(
        api.request(KugouOfficialRoute.medals, _owner155),
        throwsA(
          isA<KugouOfficialException>().having(
            (e) => e.outcome,
            'outcome',
            MusicNetworkOutcome.format,
          ),
        ),
      );
      expect(calls, 1);
    },
  );

  testWidgets(
    '155 complete official deadline cancels a trickling response body',
    (tester) async {
      final client = _TrickleClient155();
      final request = expectLater(
        _api155(client).request(KugouOfficialRoute.levelInfo, _owner155),
        throwsA(
          isA<KugouOfficialException>().having(
            (e) => e.outcome,
            'outcome',
            MusicNetworkOutcome.timeout,
          ),
        ),
      );
      await tester.pump();
      for (var i = 0; i < 4; i++) {
        client.body.add([32]);
        await tester.pump(const Duration(seconds: 4));
      }
      await request;
      expect(client.abortSeen.isCompleted, isTrue);
      await client.body.close();
      _privateValuesAbsent();
    },
  );
}
