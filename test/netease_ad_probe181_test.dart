import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesting_music/core/network/music_reward_diagnostic.dart';
import 'package:mesting_music/features/music_platform/netease/ad_probe/netease_ad_probe_export.dart';
import 'package:mesting_music/features/music_platform/netease/ad_probe/netease_ad_probe_report.dart';
import 'package:mesting_music/features/music_platform/netease/ad_probe/netease_ad_probe_repository.dart';
import 'package:mesting_music/features/music_platform/netease/netease_api.dart';
import 'package:mesting_music/features/music_platform/netease/netease_music_repository.dart';
import 'package:mesting_music/features/music_platform/netease/netease_session.dart';

import 'netease_v114_workflows_test.dart' show eapiBody;

// All accounts/URLs/ad contexts are invented. MockClient decrypts the actual
// existing eapi wire request; none of these tests contacts a platform or media.
const _owner = NeteaseSession(
  userId: '181001',
  deviceId: 'private-device181',
  cookies: {'MUSIC_U': 'private-cookie181'},
);
const _slot = '987654_private-resource181';

String adProbe181Entry({String qualification = 'false'}) => Uri(
  scheme: 'orpheus',
  host: 'nm',
  path: '/motivationAd/show',
  queryParameters: {
    'adPosition': '987654',
    'resourceId': 'private-resource181',
    'source': '987653',
    'isNeedGetRights': qualification,
  },
).toString();

Map<String, Object?> adProbe181Response() => {
  'code': 200,
  'ads': {
    _slot: {
      'creativeType': 36,
      'videoUrl': 'https://private-video181.invalid/video.mp4?token=secret181',
      'actionUrl': 'jd-private181://private-landing181',
      'webviewUrl': 'https://private-page181.invalid/ad',
      'extJson': jsonEncode({
        'contextInfo': {'req_id': 'private-req181', 'userId': '181001'},
      }),
      'generalRightsInfo': jsonEncode({
        'rightsGainMethod': 4,
        'rightsGainDuration': 8000,
        'qualified': true,
        'rightsExtJson': 'private-rights181',
        'source': 987653,
      }),
      'private-field181': {'cookie': 'private-cookie181'},
    },
  },
  'message': 'private-message181',
};

NeteaseAdProbeReport adProbe181Report() => NeteaseAdProbeReport.observe(
  response: Map<String, dynamic>.from(adProbe181Response()),
  requestedSlot: _slot,
  identity: MusicRewardIdentity.defaultPc,
  entry: const MusicRewardDiagnostic(
    step: MusicRewardStep.entry,
    reason: MusicRewardReason.accepted,
    route: MusicRewardEntryRoute.officialNm,
  ),
);

typedef _Reply = Future<http.Response> Function(http.Request request);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  http.Response json(Object response, [int status = 200]) =>
      http.Response(jsonEncode(response), status);

  ({NeteaseAdProbeRepository repository, NeteaseApi api, List<String> calls})
  harness({
    Object? entry,
    _Reply? reply,
    DateTime Function()? clock,
    bool Function()? current,
  }) {
    final calls = <String>[];
    final client = MockClient((request) async {
      expect(request.url.host, 'interface.music.163.com');
      calls.add(request.url.path);
      final body = eapiBody(request);
      expect((body['header'] as Map)['os'], 'pc');
      expect(request.headers['user-agent'], contains('NeteaseMusic/9.0.65'));
      if (reply != null) return reply(request);
      if (request.url.path.endsWith('/continuous_rights')) {
        expect(body['entranceType'], 'FREE_LISTEN');
        return json({
          'code': 200,
          'data': {'actionUrl': entry ?? adProbe181Entry()},
        });
      }
      expect(request.url.path, '/eapi/ad/get');
      expect(jsonDecode(body['type_ids'] as String), [_slot]);
      expect(body.containsKey('reqParam'), isFalse);
      return json(adProbe181Response());
    });
    addTearDown(client.close);
    final api = NeteaseApi(client)..configure(_owner);
    return (
      repository: NeteaseAdProbeRepository(
        NeteaseMusicRepository(api),
        stillCurrent: current,
        clock: clock,
      ),
      api: api,
      calls: calls,
    );
  }

  for (final qualification in ['false', 'true']) {
    test(
      'issued entry $qualification reads config, never qualification/gain',
      () async {
        final h = harness(entry: adProbe181Entry(qualification: qualification));
        expect(h.calls, isEmpty);
        final report = await h.repository.inspect(
          cancelled: Completer<void>().future,
        );
        expect(report.outcome, NeteaseAdProbeOutcome.configurationObserved);
        expect(h.calls, [
          '/eapi/ad/homepage/free/tab/continuous_rights',
          '/eapi/ad/get',
        ]);
        expect(h.api.cookies, _owner.cookies);
        final output = report.json;
        expect(output, contains('https'));
        expect(output, contains('otherScheme'));
        expect(output, contains('rightsGainDuration'));
        for (final forbidden in [
          'private-',
          '181001',
          '987653',
          'https://',
          'jd-private181',
          'secret181',
        ]) {
          expect(output, isNot(contains(forbidden)));
        }
        final root = jsonDecode(output) as Map;
        expect(root['adDisplayed'], isFalse);
        expect(root['trackingSubmitted'], isFalse);
        expect(root['rewardSubmitted'], isFalse);
        expect(root['configuration']['requestedSlotPresent'], isTrue);
        expect((jsonDecode(report.compactJson) as Map)['complete'], isTrue);
        expect(report.compactJson.length, lessThanOrEqualTo(4096));
      },
    );
  }

  for (final entry in [
    'https://private-entry181.invalid',
    '${adProbe181Entry()}&resourceId=another',
    adProbe181Entry().replaceFirst('adPosition=987654', 'adPosition=-1'),
    adProbe181Entry().replaceFirst('private-resource181', ''),
  ]) {
    test('unsupported entry stops before ad read ${entry.length}', () async {
      final h = harness(entry: entry);
      final report = await h.repository.inspect(
        cancelled: Completer<void>().future,
      );
      expect(report.outcome, NeteaseAdProbeOutcome.invalidEntry);
      expect(h.calls.length, 1);
      expect(report.json, isNot(contains('private-')));
    });
  }

  for (final adStage in [false, true]) {
    for (final httpFailure in [false, true]) {
      test('failure stage=$adStage http=$httpFailure is one attempt', () async {
        final h = harness(
          reply: (request) async {
            if (!adStage || request.url.path == '/eapi/ad/get') {
              return json({
                'code': 460,
                'message': 'private-error181',
              }, httpFailure ? 503 : 200);
            }
            return json({
              'code': 200,
              'data': {'actionUrl': adProbe181Entry()},
            });
          },
        );
        final report = await h.repository.inspect(
          cancelled: Completer<void>().future,
        );
        expect(
          report.stage,
          adStage ? NeteaseAdProbeStage.adData : NeteaseAdProbeStage.entry,
        );
        expect(
          report.outcome,
          httpFailure
              ? NeteaseAdProbeOutcome.requestFailed
              : NeteaseAdProbeOutcome.businessRejected,
        );
        expect(report.httpStatus, httpFailure ? 503 : null);
        expect(report.businessCode, httpFailure ? null : 460);
        expect(h.calls.length, adStage ? 2 : 1);
        expect(report.json, isNot(contains('private-error181')));
      });
    }
  }

  test('already cancelled read sends nothing', () async {
    final h = harness();
    final report = await h.repository.inspect(cancelled: Future<void>.value());
    expect(report.outcome, NeteaseAdProbeOutcome.cancelled);
    expect(h.calls, isEmpty);
  });

  test('signed-out service cannot request any configuration', () async {
    final h = harness();
    h.api.configure(null);
    final report = await h.repository.inspect(
      cancelled: Completer<void>().future,
    );
    expect(report.outcome, NeteaseAdProbeOutcome.noSession);
    expect(h.calls, isEmpty);
  });

  test(
    'ad identity reflects a legitimate entry response cookie update',
    () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        final body = eapiBody(request);
        if (calls == 1) {
          expect((body['header'] as Map)['os'], 'pc');
          return http.Response(
            jsonEncode({
              'code': 200,
              'data': {'actionUrl': adProbe181Entry()},
            }),
            200,
            headers: {'set-cookie': 'os=android; Path=/; Secure'},
          );
        }
        expect((body['header'] as Map)['os'], 'android');
        return json(adProbe181Response());
      });
      addTearDown(client.close);
      final api = NeteaseApi(client)..configure(_owner);
      final probe = NeteaseAdProbeRepository(NeteaseMusicRepository(api));
      final report = await probe.inspect(cancelled: Completer<void>().future);
      expect(report.identity, MusicRewardIdentity.sessionAndroid);
      expect(calls, 2);
      expect(_owner.cookies, {'MUSIC_U': 'private-cookie181'});
    },
  );

  for (final malformed in [false, true]) {
    test(
      'incomplete or undecodable response is never treated as accepted $malformed',
      () async {
        final h = harness(
          reply: (_) async => malformed
              ? http.Response('private-invalid-json181', 200)
              : json({'message': 'private-missing-code181'}),
        );
        final report = await h.repository.inspect(
          cancelled: Completer<void>().future,
        );
        expect(
          report.outcome,
          malformed
              ? NeteaseAdProbeOutcome.requestFailed
              : NeteaseAdProbeOutcome.receiptIncomplete,
        );
        expect(h.calls.length, 1);
        expect(report.json, isNot(contains('private-')));
      },
    );
  }

  for (final change in ['account', 'day', 'cancel']) {
    test('$change during progress prevents the ad request', () async {
      var current = true;
      var now = DateTime(2026, 11, 9, 23, 59);
      final cancel = Completer<void>();
      final h = harness(
        current: () => current,
        clock: () => now,
        reply: (_) async {
          if (change == 'account') current = false;
          if (change == 'day') now = DateTime(2026, 11, 10);
          if (change == 'cancel') cancel.complete();
          return json({
            'code': 200,
            'data': {'actionUrl': adProbe181Entry()},
          });
        },
      );
      final report = await h.repository.inspect(cancelled: cancel.future);
      expect(report.outcome, switch (change) {
        'account' => NeteaseAdProbeOutcome.accountChanged,
        'day' => NeteaseAdProbeOutcome.dayChanged,
        _ => NeteaseAdProbeOutcome.cancelled,
      });
      expect(h.calls.length, 1);
      expect(report.json, isNot(contains('private-')));
    });
  }

  test(
    'a replaced cookie jar cannot publish a completed ad response',
    () async {
      final pending = Completer<http.Response>();
      final h = harness(
        reply: (request) async {
          if (request.url.path == '/eapi/ad/get') return pending.future;
          return json({
            'code': 200,
            'data': {'actionUrl': adProbe181Entry()},
          });
        },
      );
      final result = h.repository.inspect(cancelled: Completer<void>().future);
      while (h.calls.length < 2) {
        await Future<void>.delayed(Duration.zero);
      }
      h.api.configure(null);
      pending.complete(json(adProbe181Response()));
      expect((await result).outcome, NeteaseAdProbeOutcome.accountChanged);
      expect(h.calls.length, 2);
    },
  );

  test('overlapping clicks cannot start a second chain', () async {
    final pending = Completer<http.Response>();
    final h = harness(reply: (_) => pending.future);
    final first = h.repository.inspect(cancelled: Completer<void>().future);
    await Future<void>.delayed(Duration.zero);
    expect(
      (await h.repository.inspect(cancelled: Completer<void>().future)).outcome,
      NeteaseAdProbeOutcome.cancelled,
    );
    pending.complete(json({'code': 460}));
    await first;
    expect(h.calls.length, 1);
  });

  for (final ads in [
    <String, Object?>{},
    <Object>[],
    {
      'other-private-slot181': {'url': 'private-url181'},
    },
    'private-ads181',
  ]) {
    test(
      'empty/mismatched ads layout never substitutes another slot ${ads.runtimeType}',
      () {
        final report = NeteaseAdProbeReport.observe(
          response: {'code': 200, 'ads': ads},
          requestedSlot: _slot,
          identity: MusicRewardIdentity.defaultPc,
          entry: const MusicRewardDiagnostic(
            step: MusicRewardStep.entry,
            reason: MusicRewardReason.accepted,
          ),
        );
        expect(
          report.outcome,
          ads is Map && ads.isEmpty || ads is List
              ? NeteaseAdProbeOutcome.noAds
              : NeteaseAdProbeOutcome.unsupportedLayout,
        );
        expect(report.json, isNot(contains('private-')));
      },
    );
  }

  test(
    'projector bounds unknown names, recursive JSON and arbitrary values',
    () {
      Object nested = {'private-key181': 'private-value181'};
      for (var i = 0; i < 20; i++) {
        nested = {'data': nested, 'videoInfo': nested};
      }
      final report = NeteaseAdProbeReport.observe(
        response: {
          'code': 200,
          'ads': {
            _slot: {
              'data': nested,
              'creativeType': 987654321,
              'extJson': 'private-invalid-json181',
              'adExtMap': 'x' * 65537,
              'imageUrl': ['private-list181'],
              'actionUrl':
                  'https://private-user181:password@private-host181.invalid',
              'generalRightsInfo': jsonEncode({
                'rightsGainMethod': 4,
                'qualified': false,
              }),
            },
          },
        },
        requestedSlot: _slot,
        identity: MusicRewardIdentity.defaultPc,
        entry: const MusicRewardDiagnostic(
          step: MusicRewardStep.entry,
          reason: MusicRewardReason.accepted,
        ),
      );
      expect(utf8.encode(report.json).length, lessThan(65536));
      expect(report.compactJson.length, lessThanOrEqualTo(4096));
      expect(jsonDecode(report.compactJson), isA<Map>());
      expect(report.json, contains('shapeLimited'));
      expect(report.json, isNot(contains('private-')));
      expect(report.json, isNot(contains('987654321')));
    },
  );

  test('file export writes only the generated bounded report', () async {
    final dir = await Directory.systemTemp.createTemp('mesting-ad181-');
    addTearDown(() => dir.delete(recursive: true));
    var shares = 0;
    final exporter = NeteaseAdProbeExport(
      supportDirectory: () async => dir,
      shareFile: (path) async {
        shares++;
        expect(
          path,
          endsWith('/netease_ad_diagnostics/${NeteaseAdProbeExport.fileName}'),
        );
        expect(
          jsonDecode(await File(path).readAsString()),
          jsonDecode(adProbe181Report().json),
        );
      },
    );
    await exporter.share(adProbe181Report());
    expect(shares, 1);
  });

  test(
    'account change while locating export directory prevents sharing',
    () async {
      final pending = Completer<Directory>();
      final dir = await Directory.systemTemp.createTemp(
        'mesting-ad181-cancel-',
      );
      addTearDown(() => dir.delete(recursive: true));
      var current = true, shared = false;
      final exporter = NeteaseAdProbeExport(
        supportDirectory: () => pending.future,
        shareFile: (_) async => shared = true,
      );
      final future = exporter.share(
        adProbe181Report(),
        isCurrent: () => current,
      );
      final result = expectLater(future, throwsStateError);
      current = false;
      pending.complete(dir);
      await result;
      expect(shared, isFalse);
      expect(await dir.list().isEmpty, isTrue);
    },
  );
}
