import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesting_music/core/network/music_reward_diagnostic.dart';
import 'package:mesting_music/features/music_platform/netease/ad_probe/netease_ad_probe_context.dart';
import 'package:mesting_music/features/music_platform/netease/ad_probe/netease_ad_probe_report.dart';
import 'package:mesting_music/features/music_platform/netease/ad_probe/netease_ad_probe_repository.dart';
import 'package:mesting_music/features/music_platform/netease/netease_api.dart';
import 'package:mesting_music/features/music_platform/netease/netease_free_listen_entry.dart';
import 'package:mesting_music/features/music_platform/netease/netease_music_repository.dart';
import 'package:mesting_music/features/music_platform/netease/netease_session.dart';

import 'netease_v114_workflows_test.dart' show eapiBody;

// Invented fixtures only. Decrypt the actual existing eapi POST with MockClient;
// an assertion on a constructed context alone would miss repository integration.
String _entry({Map<String, String> extra = const {}, bool defaults = false}) =>
    Uri(
      scheme: 'orpheus',
      host: 'nm',
      path: '/motivationAd/show',
      queryParameters: {
        'adPosition': '123456',
        'resourceId': 'private-resource182',
        if (!defaults) 'source': '123455',
        if (!defaults) 'backupUrl': 'https://private-backup182.invalid/task',
        ...extra,
      },
    ).toString();

NeteaseAdProbeContext? _context(String url) {
  final inspection = NeteaseFreeListenEntry.inspect(url);
  return inspection.entry == null
      ? null
      : NeteaseAdProbeContext.fromEntry(
          inspection.entry!,
          inspection.diagnostic,
        );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<({NeteaseAdProbeReport report, List<String> calls})> read({
    required String entry,
    required void Function(Map<String, dynamic>) onAd,
    Map<String, Object?> response = const {'code': 200, 'ads': {}},
  }) async {
    final calls = <String>[];
    final client = MockClient((request) async {
      calls.add(request.url.path);
      expect(request.url.host, 'interface.music.163.com');
      final body = eapiBody(request);
      expect((body['header'] as Map)['os'], 'pc');
      expect(request.headers['user-agent'], contains('NeteaseMusic/9.0.65'));
      if (request.url.path.endsWith('/continuous_rights')) {
        expect(body['entranceType'], 'FREE_LISTEN');
        return http.Response(
          jsonEncode({
            'code': 200,
            'data': {'actionUrl': entry},
          }),
          200,
        );
      }
      expect(request.url.path, '/eapi/ad/get');
      expect(jsonDecode(body['type_ids'] as String), [
        '123456_private-resource182',
      ]);
      expect(body.containsKey('reqParam'), isFalse);
      onAd(
        Map<String, dynamic>.from(
          jsonDecode(body['adextjson'] as String) as Map,
        ),
      );
      return http.Response(jsonEncode(response), 200);
    });
    addTearDown(client.close);
    const owner = NeteaseSession(
      userId: '182001',
      deviceId: 'private-device182',
      cookies: {'MUSIC_U': 'private-cookie182'},
    );
    final api = NeteaseApi(client)..configure(owner);
    final report = await NeteaseAdProbeRepository(
      NeteaseMusicRepository(api),
    ).inspect(cancelled: Completer<void>().future);
    expect(api.cookies, owner.cookies);
    expect(report.json, isNot(contains('private-')));
    expect(report.json, isNot(contains('182001')));
    expect(report.json, isNot(contains('123455')));
    expect(utf8.encode(report.json).length, lessThanOrEqualTo(65536));
    expect(report.compactJson.length, lessThanOrEqualTo(4096));
    return (report: report, calls: calls);
  }

  test(
    'same-task source and backup are sent, without qualification flags',
    () async {
      final result = await read(
        entry: _entry(extra: {'isNeedGetRights': 'true'}),
        onAd: (context) => expect(context, {
          'source': 123455,
          'backupUrl': 'https://private-backup182.invalid/task',
          'bizReportInfo': '',
        }),
      );
      expect(result.report.outcome, NeteaseAdProbeOutcome.noAds);
      expect(result.calls, [
        '/eapi/ad/homepage/free/tab/continuous_rights',
        '/eapi/ad/get',
      ]);
      final root = jsonDecode(result.report.json) as Map;
      expect(root['schema'], 2);
      expect(root['appVersion'], '1.0.91');
      expect(root['appVersionCode'], 112);
      expect(root['requestContext']['extFromEntry'], isFalse);
      expect(root['requestContext']['deviceSdkContextAdded'], isFalse);
      expect(root['adDisplayed'], isFalse);
      expect(root['trackingSubmitted'], isFalse);
      expect(root['rewardSubmitted'], isFalse);
    },
  );

  test(
    'native defaults are disclosed, no source or entrance URL guessed',
    () async {
      final result = await read(
        entry: _entry(defaults: true),
        onAd: (context) => expect(context, {
          'source': 0,
          'backupUrl': '',
          'bizReportInfo': '',
        }),
      );
      final info = (jsonDecode(result.report.json) as Map)['requestContext'];
      expect(info['sourceFromEntry'], isFalse);
      expect(info['backupUrlFromEntry'], isFalse);
      expect(info['rightsCommonExtFromEntry'], isFalse);
    },
  );

  test(
    'ext overrides base fields and keeps native bizReportInfo conversion',
    () async {
      final result = await read(
        entry: _entry(
          extra: {
            'ext': jsonEncode({
              'source': 'private-source182',
              'backupUrl': 'https://private-override182.invalid',
              'bizReportInfo': {'issued': 'private-report182'},
              'issuedExt': {
                'nested': [null, true, 7],
                'omitted': null,
              },
              'rightsCommonExt': 'private-issued-rights182',
            }),
          },
        ),
        onAd: (context) => expect(context, {
          'source': 'private-source182',
          'backupUrl': 'https://private-override182.invalid',
          'bizReportInfo': jsonEncode({'issued': 'private-report182'}),
          'issuedExt': {
            'nested': [null, true, 7],
          },
          'rightsCommonExt': 'private-issued-rights182',
        }),
      );
      final info = (jsonDecode(result.report.json) as Map)['requestContext'];
      expect(info['extFromEntry'], isTrue);
      expect(info['rightsCommonExtFromEntry'], isTrue);
    },
  );

  for (final payload in [
    {'issued': List.filled(260, 1)},
    {'issued': '界' * 22000},
    {
      'data': {
        'data': {
          'data': {
            'data': {
              'data': {
                'data': {
                  'data': {
                    'data': {'data': 1},
                  },
                },
              },
            },
          },
        },
      },
    },
  ]) {
    test(
      'excessive context is rejected before ad POST ${jsonEncode(payload).length}',
      () async {
        final result = await read(
          entry: _entry(extra: {'ext': jsonEncode(payload)}),
          onAd: (_) => fail('oversized context must not be transmitted'),
        );
        // A too-long URI may be rejected by the existing parser even earlier.
        expect(
          result.report.outcome,
          anyOf(
            NeteaseAdProbeOutcome.invalidContext,
            NeteaseAdProbeOutcome.invalidEntry,
          ),
        );
        expect(result.calls.length, 1);
      },
    );
  }

  test('in-bound context remains byte-complete rather than truncated', () {
    final context = _context(
      _entry(
        extra: {
          'ext': jsonEncode({
            'issued': 'private-context182' * 100,
            'items': List.filled(100, 42),
          }),
        },
      ),
    );
    expect(context, isNotNull);
    final decoded = jsonDecode(context!.adextjson) as Map;
    expect(decoded['issued'], 'private-context182' * 100);
    expect((decoded['items'] as List).length, 100);
  });

  test(
    'context byte limit rejects raw Unicode below the URI character limit',
    () {
      // Raw Unicode is legal URI input too; percent-encoded fixtures alone would
      // hit the older URL character limit before exercising the new byte bound.
      final url = '${_entry(defaults: true)}&ext={"issued":"${'界' * 22000}"}';
      final inspection = NeteaseFreeListenEntry.inspect(url);
      expect(inspection.entry, isNotNull);
      expect(_context(url), isNull);
    },
  );

  test(
    'compact omission retains hints and never descends into message objects',
    () {
      Object nested = {'videoUrl': 'https://private-video182.invalid'};
      for (var i = 0; i < 8; i++) {
        nested = {
          'data': nested,
          'videoInfo': nested,
          'materials': [nested],
        };
      }
      final report = NeteaseAdProbeReport.observe(
        response: {
          'code': 200,
          'ads': {'private-request182': nested},
          'message': {'rightsGainDuration': 123455},
          'noRetry': '0',
          'mainMsg': null,
        },
        requestedSlot: 'private-request182',
        identity: MusicRewardIdentity.defaultPc,
        entry: const MusicRewardDiagnostic(
          step: MusicRewardStep.entry,
          reason: MusicRewardReason.accepted,
        ),
      );
      final compact = jsonDecode(report.compactJson) as Map;
      expect(compact['configurationOmitted'], isTrue);
      expect(compact['receiptHints']['noRetry']['value'], 0);
      expect(compact['receiptHints']['mainMsg'], {
        'present': true,
        'type': 'missing',
      });
      expect(compact['receiptHints']['image'], {
        'present': false,
        'type': 'missing',
      });
      expect(report.compactJson.length, lessThanOrEqualTo(4096));
      expect(report.json, isNot(contains('123455')));
      expect(report.json, isNot(contains('private-')));
    },
  );

  for (final code in [200, 51201, null]) {
    test(
      'empty/rejected/incomplete receipt keeps safe hints code=$code',
      () async {
        final result = await read(
          entry: _entry(),
          onAd: (_) {},
          response: {
            'code': ?code,
            'ads': {},
            'noRetry': 1,
            'message': 'private-message182',
            'mainMsg': {
              'rightsGainDuration': 123455,
              'private-key182': 'secret',
            },
            'image': 'https://private-image182.invalid',
          },
        );
        expect(result.calls.length, 2);
        final hints =
            (jsonDecode(result.report.json)
                as Map)['configuration']['receiptHints'];
        expect(hints['noRetry'], {
          'present': true,
          'type': 'number',
          'value': 1,
        });
        expect(hints['message'], {'present': true, 'type': 'text'});
        expect(hints['mainMsg'], {'present': true, 'type': 'object'});
        expect(hints['image'], {'present': true, 'type': 'text'});
        expect(
          result.report.outcome,
          code == 200
              ? NeteaseAdProbeOutcome.noAds
              : code == null
              ? NeteaseAdProbeOutcome.receiptIncomplete
              : NeteaseAdProbeOutcome.businessRejected,
        );
      },
    );
  }

  for (final noRetry in [
    0,
    '1',
    999999999,
    true,
    null,
    {'source': 'private-noRetry182'},
  ]) {
    test(
      'noRetry stays bounded and never triggers retry ${noRetry.runtimeType}/$noRetry',
      () async {
        final result = await read(
          entry: _entry(),
          onAd: (_) {},
          response: {'code': 200, 'ads': {}, 'noRetry': noRetry},
        );
        expect(result.calls.length, 2);
        final hint =
            (jsonDecode(result.report.json)
                    as Map)['configuration']['receiptHints']['noRetry']
                as Map;
        expect(hint.containsKey('value'), noRetry == 0 || noRetry == '1');
      },
    );
  }

  test('single alias is structural evidence, never an exact-match success', () {
    final report = NeteaseAdProbeReport.observe(
      response: {
        'code': 200,
        'ads': {
          'private-alias182': {'videoUrl': 'https://private-video182.invalid'},
        },
      },
      requestedSlot: 'private-request182',
      identity: MusicRewardIdentity.defaultPc,
      entry: const MusicRewardDiagnostic(
        step: MusicRewardStep.entry,
        reason: MusicRewardReason.accepted,
      ),
    );
    final config = (jsonDecode(report.json) as Map)['configuration'];
    expect(report.outcome, NeteaseAdProbeOutcome.unsupportedLayout);
    expect(config['requestedSlotPresent'], isFalse);
    expect(config['singleSlotAliasObserved'], isTrue);
    expect(
      config['singleSlotAliasShape']['fields']['videoUrl']['linkKind'],
      'https',
    );
    expect(report.json, isNot(contains('private-')));
  });

  test('single alias uses its own bounded budget and reports clipping', () {
    Object nested = {'videoUrl': 'https://private-video182.invalid'};
    for (var i = 0; i < 8; i++) {
      nested = {'data': nested, 'videoInfo': nested};
    }
    final report = NeteaseAdProbeReport.observe(
      response: {
        'code': 200,
        'ads': {'private-alias182': nested},
      },
      requestedSlot: 'private-request182',
      identity: MusicRewardIdentity.defaultPc,
      entry: const MusicRewardDiagnostic(
        step: MusicRewardStep.entry,
        reason: MusicRewardReason.accepted,
      ),
    );
    final config = (jsonDecode(report.json) as Map)['configuration'];
    expect(config['singleSlotAliasObserved'], isTrue);
    expect(config['shapeLimited'], isTrue);
    expect(utf8.encode(report.json).length, lessThan(65536));
    expect(report.json, isNot(contains('private-')));
  });
}
