import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesting_music/core/network/music_network_diagnostics.dart';
import 'package:mesting_music/features/music_platform/netease/netease_api.dart';
import 'package:mesting_music/features/music_platform/netease/netease_request_exception.dart';
import 'package:mesting_music/features/music_platform/netease/netease_reward_requests.dart';
import 'package:mesting_music/features/music_platform/netease/netease_session.dart';

import 'netease_v114_workflows_test.dart' show eapiBody;

const _privateId = '8816001234';
const _privateCookie = 'synthetic-stage-private-cookie';
const _privateUrl = 'https://private.invalid/account/$_privateId';
const _privateMessage =
    'Cookie=MUSIC_U=$_privateCookie;userId=$_privateId;url=$_privateUrl';
const _session = NeteaseSession(
  userId: _privateId,
  deviceId: 'synthetic-stage-device',
  cookies: {'MUSIC_U': _privateCookie},
);

/// The production API and encryption run unchanged. Only the final HTTP client
/// is synthetic, so these cases cannot reach an account or award real rights.
class _Wire {
  _Wire(Future<http.Response> Function(http.Request) reply) {
    api = NeteaseApi(
      MockClient((request) async {
        calls++;
        requests.add(request);
        bodies.add(eapiBody(request));
        return reply(request);
      }),
    )..configure(_session);
  }

  late final NeteaseApi api;
  int calls = 0;
  final requests = <http.Request>[];
  final bodies = <Map<String, dynamic>>[];
}

const _paths = {
  NeteaseRewardStage.qualification: '/api/ad/listening/rights/qualification',
  NeteaseRewardStage.claim: '/api/ad/listening/rights/gain',
};

http.Response _response(Object value, {int status = 200}) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Future<Map<String, dynamic>> _send(_Wire wire, NeteaseRewardStage stage) =>
    NeteaseRewardRequests.send(
      api: wire.api,
      credential: _session.credentialId,
      path: _paths[stage]!,
      // This is a pass-through transport fixture, not an official entitlement
      // schema or an assertion that the platform accepts these parameters.
      data: {
        'reqParam': jsonEncode({
          'userId': int.parse(_privateId),
          'source': 300,
        }),
      },
    );

Map<String, Object> _stageRow(NeteaseRewardStage stage) =>
    MusicNetworkDiagnostics.shared.rows
        .where((row) => row['operation'] == stage.operation.name)
        .single;

void _expectPrivateFactsAbsent(String value) {
  for (final private in [
    _privateId,
    _privateCookie,
    _privateUrl,
    'MUSIC_U',
    'Cookie=',
    'reqParam',
  ]) {
    expect(value, isNot(contains(private)));
  }
}

void _expectOneEncryptedRequest(_Wire wire, NeteaseRewardStage stage) {
  expect(wire.calls, 1);
  final request = wire.requests.single;
  expect(request.method, 'POST');
  expect(request.url.scheme, 'https');
  expect(request.url.host, 'interface.music.163.com');
  expect(request.url.path, _paths[stage]!.replaceFirst('/api/', '/eapi/'));
  expect(request.bodyFields.keys, ['params']);
  expect(request.headers['cookie'], contains('MUSIC_U=$_privateCookie'));
  final body = wire.bodies.single;
  expect(jsonDecode(body['reqParam'] as String), {
    'userId': int.parse(_privateId),
    'source': 300,
  });
  expect(body['header'], isA<Map>());
  expect(body['e_r'], isFalse);
}

Future<NeteaseRewardRequestFailure> _failure(
  Future<Map<String, dynamic>> pending,
) async {
  try {
    await pending;
    fail('Expected a stage-labelled request failure');
  } on NeteaseRewardRequestFailure catch (error) {
    return error;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(MusicNetworkDiagnostics.shared.clear);
  tearDown(MusicNetworkDiagnostics.shared.clear);

  for (final stage in _paths.keys) {
    test(
      'HTTP 200 business 500 retains ${stage.name} without HTTP identity',
      () async {
        final wire = _Wire(
          (_) async => _response({'code': 500, 'message': _privateMessage}),
        );
        final reply = await _send(wire, stage);
        final result = NeteaseRewardRequests.refused(stage, reply);
        _expectOneEncryptedRequest(wire, stage);
        expect(result.success, isFalse);
        expect(result.uncertain, stage.writes);
        expect(result.message, contains(stage.label));
        expect(result.message, contains('业务码 500'));
        expect(result.message, isNot(contains('HTTP')));
        expect(_stageRow(stage), containsPair('outcome', 'business'));
        expect(_stageRow(stage), containsPair('status', 500));
        expect(_stageRow(stage), containsPair('phase', 'responseValidate'));
        _expectPrivateFactsAbsent(result.message);
        _expectPrivateFactsAbsent(MusicNetworkDiagnostics.shared.export());
      },
    );

    test(
      'true HTTP 500 retains ${stage.name} and mutation uncertainty',
      () async {
        final wire = _Wire(
          (_) async => _response({'message': _privateMessage}, status: 500),
        );
        final error = await _failure(_send(wire, stage));
        _expectOneEncryptedRequest(wire, stage);
        expect(error.stage, stage);
        expect(error.outcome, MusicNetworkOutcome.http);
        expect(error.httpStatus, 500);
        expect(error.result.success, isFalse);
        expect(error.result.uncertain, stage.writes);
        expect(error.result.message, contains('HTTP 500'));
        expect(error.result.message, contains(stage.label));
        expect(_stageRow(stage), containsPair('outcome', 'http'));
        expect(_stageRow(stage), containsPair('status', 500));
        expect(_stageRow(stage), containsPair('phase', 'networkSend'));
        _expectPrivateFactsAbsent(error.result.message);
        _expectPrivateFactsAbsent(MusicNetworkDiagnostics.shared.export());
      },
    );

    for (final badCode in [null, 'not-a-code']) {
      test(
        '${stage.name} missing or invalid code $badCode is an incomplete receipt',
        () async {
          final wire = _Wire(
            (_) async =>
                _response({'code': ?badCode, 'message': _privateMessage}),
          );
          final reply = await _send(wire, stage);
          final result = NeteaseRewardRequests.refused(stage, reply);
          _expectOneEncryptedRequest(wire, stage);
          expect(_stageRow(stage), containsPair('outcome', 'format'));
          expect(_stageRow(stage), containsPair('phase', 'responseValidate'));
          expect(_stageRow(stage).containsKey('status'), isFalse);
          expect(result.success, isFalse);
          expect(result.uncertain, stage.writes);
          expect(result.message, contains(stage.label));
          expect(result.message, contains('回执不完整'));
          _expectPrivateFactsAbsent(result.message);
          _expectPrivateFactsAbsent(MusicNetworkDiagnostics.shared.export());
        },
      );
    }

    test(
      '${stage.name} malformed JSON retains decode failure and never retries',
      () async {
        final wire = _Wire(
          (_) async => http.Response('not-json:$_privateMessage', 200),
        );
        final error = await _failure(_send(wire, stage));
        _expectOneEncryptedRequest(wire, stage);
        expect(error.stage, stage);
        expect(error.outcome, MusicNetworkOutcome.format);
        expect(error.httpStatus, isNull);
        expect(error.result.success, isFalse);
        expect(error.result.uncertain, stage.writes);
        expect(error.result.message, contains('回执格式异常'));
        expect(_stageRow(stage), containsPair('outcome', 'format'));
        expect(_stageRow(stage), containsPair('phase', 'responseDecode'));
        _expectPrivateFactsAbsent(error.result.message);
        _expectPrivateFactsAbsent(MusicNetworkDiagnostics.shared.export());
      },
    );

    test('${stage.name} timeout retains its stage and never retries', () async {
      // A synthetic timeout completes immediately; no real 18-second wait or
      // orphaned network work is needed to exercise the production classifier.
      final wire = _Wire((_) async => throw TimeoutException(_privateMessage));
      final error = await _failure(_send(wire, stage));
      _expectOneEncryptedRequest(wire, stage);
      expect(error.stage, stage);
      expect(error.outcome, MusicNetworkOutcome.timeout);
      expect(error.httpStatus, isNull);
      expect(error.result.success, isFalse);
      expect(error.result.uncertain, stage.writes);
      expect(error.result.message, contains('连接超时'));
      expect(_stageRow(stage), containsPair('outcome', 'timeout'));
      expect(_stageRow(stage), containsPair('phase', 'networkSend'));
      _expectPrivateFactsAbsent(error.result.message);
      _expectPrivateFactsAbsent(MusicNetworkDiagnostics.shared.export());
    });

    test(
      '${stage.name} HTTP 503 cannot opt into generic read retries',
      () async {
        final wire = _Wire(
          (_) async => _response({'message': _privateMessage}, status: 503),
        );
        final error = await _failure(_send(wire, stage));
        _expectOneEncryptedRequest(wire, stage);
        expect(error.httpStatus, 503);
        expect(error.result.uncertain, stage.writes);
        expect(_stageRow(stage), containsPair('outcome', 'http'));
      },
    );
  }

  for (final gained in [false, 0, '0', 'false', null, 'unexpected']) {
    test(
      'claim code 200 with gainFlag=$gained never records a confirmed reward',
      () async {
        final wire = _Wire(
          (_) async => _response({
            'code': 200,
            'data': {'gainFlag': ?gained},
            'message': _privateMessage,
          }),
        );
        await _send(wire, NeteaseRewardStage.claim);
        _expectOneEncryptedRequest(wire, NeteaseRewardStage.claim);
        final expected = gained == null || gained == 'unexpected'
            ? 'format'
            : 'business';
        expect(
          _stageRow(NeteaseRewardStage.claim),
          containsPair('outcome', expected),
        );
        expect(
          _stageRow(NeteaseRewardStage.claim),
          containsPair('status', 200),
        );
        expect(
          _stageRow(NeteaseRewardStage.claim),
          containsPair('phase', 'responseValidate'),
        );
        _expectPrivateFactsAbsent(MusicNetworkDiagnostics.shared.export());
      },
    );
  }

  test('only an explicit gainFlag confirms the claim stage', () async {
    final wire = _Wire(
      (_) async => _response({
        'code': 200,
        'data': {'gainFlag': true},
      }),
    );
    await _send(wire, NeteaseRewardStage.claim);
    _expectOneEncryptedRequest(wire, NeteaseRewardStage.claim);
    expect(
      _stageRow(NeteaseRewardStage.claim),
      containsPair('outcome', 'success'),
    );
    expect(_stageRow(NeteaseRewardStage.claim), containsPair('status', 200));
  });

  test(
    'the underlying API exposes typed HTTP facts without its response body',
    () async {
      final wire = _Wire(
        (_) async => _response({'message': _privateMessage}, status: 500),
      );
      await expectLater(
        wire.api.request(_paths[NeteaseRewardStage.qualification]!, const {}),
        throwsA(
          isA<NeteaseRequestException>()
              .having((error) => error.httpStatus, 'HTTP status', 500)
              .having(
                (error) => error.outcome,
                'outcome',
                MusicNetworkOutcome.http,
              )
              .having(
                (error) => error.message,
                'message',
                isNot(contains(_privateCookie)),
              ),
        ),
      );
      expect(wire.calls, 1);
      _expectPrivateFactsAbsent(MusicNetworkDiagnostics.shared.export());
    },
  );

  test(
    'the underlying API exposes typed format failures without raw JSON',
    () async {
      final wire = _Wire((_) async => http.Response(_privateMessage, 200));
      await expectLater(
        wire.api.request(_paths[NeteaseRewardStage.claim]!, const {}),
        throwsA(
          isA<NeteaseRequestException>()
              .having((error) => error.httpStatus, 'HTTP status', isNull)
              .having(
                (error) => error.outcome,
                'outcome',
                MusicNetworkOutcome.format,
              )
              .having(
                (error) => error.message,
                'message',
                isNot(contains(_privateCookie)),
              ),
        ),
      );
      expect(wire.calls, 1);
      _expectPrivateFactsAbsent(MusicNetworkDiagnostics.shared.export());
    },
  );
}
