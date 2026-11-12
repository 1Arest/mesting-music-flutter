import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_api.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_diagnostics.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_listening_repository.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_request_signer.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_session.dart';

const _owner = '178900000001';
const _device = '1788123456789001';

class _Store implements QishuiListeningStore {
  final values = <String, QishuiListeningLedger>{};
  bool failRead = false;
  final failWrites = <int>{};
  int writes = 0;

  @override
  Future<QishuiListeningLedger> read(String owner) async {
    if (failRead) throw StateError('private-ledger-read178');
    return values[owner] ?? const QishuiListeningLedger();
  }

  @override
  Future<void> write(String owner, QishuiListeningLedger value) async {
    if (failWrites.contains(++writes)) {
      throw StateError('private-ledger-write178');
    }
    values[owner] = value;
  }
}

class _Signer implements QishuiRequestSigner {
  _Signer({this.did = _device, this.ua = 'LunaPC/3.7.0(452316191)', this.load});
  final String did, ua;
  final Future<Map<String, String>> Function()? load;

  @override
  Future<Map<String, String>> identity(Future<void> abort) async =>
      load != null ? await load!() : {'device_id': did, 'user_agent': ua};

  @override
  void invalidateIdentity() {}

  @override
  Future<QishuiSignedRequest> sign(
    Uri uri,
    String method,
    String body,
    Map<String, String> headers,
    Future<void> abort,
  ) async => QishuiSignedRequest(uri, const {
    'x-helios': 'private-signature178',
    'x-medusa': 'private-medusa178',
  });
}

QishuiSession _session(String owner) => QishuiSession(
  userId: owner,
  protocol: QishuiSessionProtocol.web,
  cookies: const [
    {
      'name': 'sessionid',
      'value': 'private-cookie178',
      'domain': 'api.qishui.com',
      'path': '/',
      'secure': 'true',
    },
  ],
  tokens: const {'x-tt-token': 'private-token178'},
);

http.Response _json(Object? body, {int status = 200}) => http.Response(
  jsonEncode(body),
  status,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);

class _Fixture {
  _Fixture({
    _Store? store,
    QishuiRequestSigner? signer,
    bool withSigner = true,
    bool reportEnabled = true,
    bool Function()? current,
    Future<http.Response> Function(http.Request)? respond,
  }) : store = store ?? _Store() {
    api = QishuiApi(
      MockClient((request) async {
        requests.add(request);
        return respond == null ? _json({'code': 0}) : await respond(request);
      }),
      signer: withSigner ? signer ?? _Signer() : null,
    )..configure(_session(_owner));
    repository = QishuiListeningRepository(
      api: api,
      store: this.store,
      current: current ?? () => true,
      reportEnabled: reportEnabled,
    );
    addTearDown(() {
      repository.dispose();
      api.dispose();
    });
  }

  final _Store store;
  final requests = <http.Request>[];
  late final QishuiApi api;
  late final QishuiListeningRepository repository;

  Future<QishuiListeningDelivery> submit([int heard = 1000]) =>
      repository.submit(
        [
          QishuiListeningEvent('audio_over', {
            'duration': heard,
            'track_id': 'private-track178',
          }, DateTime.utc(2026, 11, 8)),
        ],
        heardMilliseconds: heard,
        playing: false,
      );
}

Map<String, Object> _last(QishuiDiagnosticFeature feature) => QishuiDiagnostics
    .shared
    .events
    .where((event) => event['feature'] == feature.name)
    .last;

void _expectPrivateValuesAbsent() {
  final exported = QishuiDiagnostics.shared.export(
    group: QishuiDiagnosticGroup.listening,
  );
  for (final value in [
    _owner,
    _device,
    'private-cookie178',
    'private-token178',
    'private-signature178',
    'private-medusa178',
    'private-track178',
    'private-response178',
    'private-ledger-read178',
    'private-ledger-write178',
  ]) {
    expect(exported, isNot(contains(value)));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(QishuiDiagnostics.shared.clear);
  tearDown(_expectPrivateValuesAbsent);

  test(
    'missing official duration is distinguishable from transport success',
    () async {
      final fixture = _Fixture(
        respond: (_) async => _json({
          'status_code': 0,
          'data': {
            'user': {'id': _owner, 'nickname': 'private-response178'},
          },
        }),
      );
      await expectLater(
        fixture.repository.fetch(),
        throwsA(isA<QishuiException>()),
      );
      final event = _last(QishuiDiagnosticFeature.officialListening);
      expect(event['stage'], 'parse');
      expect(event['outcome'], 'format');
      expect(event['reason'], 'missingFields');
      expect(event['shape'], isNotNull);
    },
  );

  test('malformed official seconds have a separate DTO failure', () async {
    final fixture = _Fixture(
      respond: (_) async => _json({
        'listen_duration': {'total_duration': 'private-response178'},
      }),
    );
    await expectLater(
      fixture.repository.fetch(),
      throwsA(isA<QishuiException>()),
    );
    expect(
      _last(QishuiDiagnosticFeature.officialListening)['reason'],
      'invalidFields',
    );
  });

  test(
    'restoring old unknown hearing never dispatches or changes official totals',
    () async {
      final store = _Store()
        ..values[_owner] = const QishuiListeningLedger(
          heardMilliseconds: 591000,
          unconfirmedMilliseconds: 591000,
        );
      final fixture = _Fixture(store: store);
      final restored = await fixture.repository.ledger();
      expect(restored.heardMilliseconds, 591000);
      expect(restored.unconfirmedMilliseconds, 591000);
      expect(fixture.requests, isEmpty);

      // Only this fresh interval may be submitted; retained unknown time is not
      // converted into an event when the repository is restored or later used.
      expect(await fixture.submit(), QishuiListeningDelivery.accepted);
      expect(fixture.requests, hasLength(1));
      expect(fixture.requests.single.body, isNot(contains('591000')));
      final updated = await fixture.repository.ledger();
      expect(updated.heardMilliseconds, 592000);
      expect(updated.transportAcceptedMilliseconds, 1000);
      expect(updated.unconfirmedMilliseconds, 591000);
    },
  );

  test(
    'failed ledger read stops a report before any remote dispatch',
    () async {
      final fixture = _Fixture(store: _Store()..failRead = true);
      await expectLater(fixture.submit(), throwsStateError);
      expect(fixture.requests, isEmpty);
      final event = _last(QishuiDiagnosticFeature.listeningReport);
      expect(event['stage'], 'ledger');
      expect(event['reason'], 'storeReadFailed');
      expect(event['willSubmit'], false);
      expect(event['receiptAccepted'], false);
    },
  );

  test('failed initial ledger write cannot issue or replay a report', () async {
    final store = _Store()..failWrites.add(1);
    final fixture = _Fixture(store: store);
    await expectLater(fixture.submit(), throwsStateError);
    expect(fixture.requests, isEmpty);
    expect(store.values, isEmpty);
    final event = _last(QishuiDiagnosticFeature.listeningReport);
    expect(event['reason'], 'storeWriteFailed');
    expect(event['receiptAccepted'], false);
  });

  test('an outgoing account is settled locally without dispatch', () async {
    final fixture = _Fixture(current: () => false);
    expect(await fixture.submit(), QishuiListeningDelivery.unconfirmed);
    expect(fixture.requests, isEmpty);
    expect(fixture.store.values[_owner]!.heardMilliseconds, 1000);
    final event = _last(QishuiDiagnosticFeature.listeningReport);
    expect(event['reason'], 'accountChanged');
    expect(event['willSubmit'], false);
  });

  test(
    'explicit local-only mode remains separate from network failure',
    () async {
      final fixture = _Fixture(reportEnabled: false);
      expect(await fixture.submit(), QishuiListeningDelivery.localOnly);
      expect(fixture.requests, isEmpty);
      expect(
        _last(QishuiDiagnosticFeature.listeningReport)['reason'],
        'reportDisabled',
      );
    },
  );

  test(
    'missing signer preserves hearing and explains why no report was submitted',
    () async {
      final fixture = _Fixture(withSigner: false);
      expect(await fixture.submit(), QishuiListeningDelivery.unconfirmed);
      expect(fixture.requests, isEmpty);
      expect(fixture.store.values[_owner]!.unconfirmedMilliseconds, 1000);
      final event = _last(QishuiDiagnosticFeature.listeningReport);
      expect(event['reason'], 'missingSigner');
      expect(event['identityReady'], false);
      expect(event['willSubmit'], false);
    },
  );

  for (final identity in [
    (signer: _Signer(did: ''), reason: 'identityMissing'),
    (signer: _Signer(ua: 'private-response178'), reason: 'invalidFields'),
  ]) {
    test(
      'invalid report identity is explained as ${identity.reason}',
      () async {
        final fixture = _Fixture(signer: identity.signer);
        expect(await fixture.submit(), QishuiListeningDelivery.unconfirmed);
        expect(fixture.requests, isEmpty);
        final event = _last(QishuiDiagnosticFeature.listeningReport);
        expect(event['stage'], 'identity');
        expect(event['reason'], identity.reason);
        expect(event['identityReady'], false);
        expect(event['ownerReady'], true);
      },
    );
  }

  for (final refusal in [
    (
      response: _json({
        'code': 4009,
        'message': 'private-response178',
      }, status: 400),
      reason: 'httpRejected',
    ),
    (response: http.Response('', 200), reason: 'emptyResponse'),
    (
      response: http.Response('{private-response178', 200),
      reason: 'invalidJson',
    ),
    (response: _json({}), reason: 'receiptMissing'),
    (
      response: _json({'code': 4009, 'message': 'private-response178'}),
      reason: 'receiptRejected',
    ),
    (response: _json(['private-response178']), reason: 'responseShape'),
  ]) {
    test(
      'unconfirmed service receipt retains hearing once: ${refusal.reason}',
      () async {
        final fixture = _Fixture(respond: (_) async => refusal.response);
        expect(await fixture.submit(), QishuiListeningDelivery.unconfirmed);
        expect(fixture.requests, hasLength(1));
        final saved = await fixture.repository.ledger();
        expect(saved.heardMilliseconds, 1000);
        expect(saved.transportAcceptedMilliseconds, 0);
        expect(saved.unconfirmedMilliseconds, 1000);
        final event = _last(QishuiDiagnosticFeature.listeningReport);
        expect(event['reason'], refusal.reason);
        expect(event['receiptAccepted'], false);
        if (refusal.reason == 'httpRejected') {
          expect(event['httpStatus'], 400);
          expect(event['businessCode'], 4009);
        }
      },
    );
  }

  test(
    'transport exceptions are classified without exporting their text',
    () async {
      final fixture = _Fixture(
        respond: (_) async => throw http.ClientException('private-response178'),
      );
      expect(await fixture.submit(), QishuiListeningDelivery.unconfirmed);
      final event = _last(QishuiDiagnosticFeature.listeningReport);
      expect(event['outcome'], 'network');
      expect(event['reason'], 'networkFailure');
      expect(fixture.requests, hasLength(1));
    },
  );

  test(
    'a positive transport receipt followed by disk failure stays explicit',
    () async {
      final store = _Store()..failWrites.add(2);
      final fixture = _Fixture(store: store);
      expect(await fixture.submit(), QishuiListeningDelivery.unconfirmed);
      expect(fixture.requests, hasLength(1));
      expect(store.values[_owner]!.unconfirmedMilliseconds, 1000);
      final event = _last(QishuiDiagnosticFeature.listeningReport);
      expect(event['stage'], 'ledger');
      expect(event['reason'], 'storeWriteFailed');
      expect(event['receiptAccepted'], true);

      final restored = QishuiListeningRepository(
        api: fixture.api,
        current: () => true,
        store: store,
      );
      addTearDown(restored.dispose);
      expect((await restored.ledger()).unconfirmedMilliseconds, 1000);
      expect(fixture.requests, hasLength(1));
    },
  );

  test(
    'account change while identity loads cannot report as the next owner',
    () async {
      final entered = Completer<void>();
      final identity = Completer<Map<String, String>>();
      final fixture = _Fixture(
        signer: _Signer(
          load: () {
            entered.complete();
            return identity.future;
          },
        ),
      );
      final pending = fixture.submit();
      await entered.future;
      fixture.api.configure(_session('178900000002'));
      identity.complete({
        'device_id': _device,
        'user_agent': 'LunaPC/3.7.0(452316191)',
      });
      expect(await pending, QishuiListeningDelivery.unconfirmed);
      expect(fixture.requests, isEmpty);
      expect(fixture.store.values.keys, [_owner]);
      expect(
        _last(QishuiDiagnosticFeature.listeningReport)['reason'],
        'accountChanged',
      );
    },
  );
}
