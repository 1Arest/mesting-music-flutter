import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesting_music/core/network/music_network_diagnostics.dart';
import 'package:mesting_music/core/network/music_reward_diagnostic.dart';
import 'package:mesting_music/features/music_platform/netease/netease_api.dart';
import 'package:mesting_music/features/music_platform/netease/netease_music_repository.dart';
import 'package:mesting_music/features/music_platform/netease/netease_rewards_repository.dart';
import 'package:mesting_music/features/music_platform/netease/netease_session.dart';

import 'netease_v114_workflows_test.dart' show eapiBody;

// The nm/ne routing shape is based on official 9.6.15 lg.M -> wp.a. Every
// account, ad and entitlement value below is synthetic; HTTP stays in MockClient.
const _owner = NeteaseSession(
  userId: '180001',
  deviceId: 'private-device180-marker',
  cookies: {'MUSIC_U': 'private-cookie180-marker'},
);

String _entry({
  String host = 'nm',
  Map<String, String> fields = const {},
  Set<String> omit = const {},
}) => Uri(
  scheme: 'orpheus',
  host: host,
  path: host == 'motivationAd' ? '/show' : '/motivationAd/show',
  queryParameters: {
    for (final e in {
      'adPosition': '987654',
      'resourceId': 'private-resource180-marker',
      'source': '987653',
      'isNeedGetRights': 'true',
      'ext': '{"bizReportInfo":"private-extension180-marker"}',
      ...fields,
    }.entries)
      if (!omit.contains(e.key)) e.key: e.value,
  },
).toString();

http.Response _json(Object value, [int status = 200]) =>
    http.Response(jsonEncode(value), status);

typedef _Reply = http.Response Function(String path, Map<String, dynamic> body);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences preferences;
  final diagnostics = MusicNetworkDiagnostics.shared;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
    diagnostics.clear();
  });
  tearDown(diagnostics.clear);

  ({NeteaseRewardsRepository repository, List<String> calls}) harness({
    required Object? entry,
    _Reply? reply,
    Map<String, String> extraCookies = const {},
  }) {
    final calls = <String>[];
    final client = MockClient((request) async {
      expect(request.url.host, 'interface.music.163.com');
      final path = request.url.path.replaceFirst('/eapi/', '/api/');
      final body = eapiBody(request);
      calls.add(path);
      // This fix must not silently migrate all reward requests to a new os/UA.
      expect((body['header'] as Map)['os'], extraCookies['os'] ?? 'pc');
      expect(request.headers['user-agent'], contains('NeteaseMusic/9.0.65'));
      if (path == NeteaseRewardsRepository.progressPath) {
        return _json({
          'code': 200,
          'data': {'actionUrl': entry},
        });
      }
      if (reply != null) return reply(path, body);
      if (path == NeteaseRewardsRepository.qualificationPath) {
        final params = jsonDecode(body['reqParam'] as String) as Map;
        expect(params['source'], 987653);
        expect(params['resourceId'], 'private-resource180-marker');
        return _json({
          'code': 200,
          'data': {'qualified': true},
        });
      }
      expect(path, NeteaseRewardsRepository.claimPath);
      final params = jsonDecode(body['reqParam'] as String) as Map;
      expect(params, {'userId': 180001, 'source': 987653});
      return _json({
        'code': 200,
        'data': {'gainFlag': true},
      });
    });
    addTearDown(client.close);
    final api = NeteaseApi(client)
      ..configure(
        NeteaseSession(
          userId: _owner.userId,
          deviceId: _owner.deviceId,
          cookies: {..._owner.cookies, ...extraCookies},
        ),
      );
    return (
      repository: NeteaseRewardsRepository(
        NeteaseMusicRepository(api),
        preferences: preferences,
        clock: () => DateTime(2026, 11, 8, 12),
      ),
      calls: calls,
    );
  }

  for (final row in [
    ('nm', 'officialNm'),
    ('ne', 'officialNe'),
    ('motivationAd', 'legacyHost'),
  ]) {
    test('${row.$1} entry reaches one qualification and one gain', () async {
      final h = harness(entry: _entry(host: row.$1));
      expect((await h.repository.claimAd()).success, isTrue);
      expect(h.calls, [
        NeteaseRewardsRepository.progressPath,
        NeteaseRewardsRepository.qualificationPath,
        NeteaseRewardsRepository.claimPath,
      ]);
      final entry = diagnostics.rows.singleWhere(
        (e) => e['rewardStep'] == 'entry',
      );
      expect(entry['rewardReason'], 'accepted');
      expect(entry['entryRoute'], row.$2);
      expect(entry['qualificationRequested'], isTrue);
      expect(entry['rewardIdentity'], 'defaultPc');
      expect(diagnostics.rows.last['rewardStep'], 'claim');
      for (final private in [
        'private-cookie180-marker',
        'private-device180-marker',
        'private-resource180-marker',
        'private-extension180-marker',
        'orpheus:',
        '987653',
      ]) {
        expect(diagnostics.export(), isNot(contains(private)));
      }
    });
  }

  final invalid = <(Object?, String)>[
    (null, 'entryMissing'),
    ('', 'entryMissing'),
    (180, 'entryWrongType'),
    ('orpheus://nm/motivationAd/unrelated', 'entryUnsupportedRoute'),
    (_entry(omit: {'resourceId'}), 'entryMissingField'),
    (_entry(fields: {'adPosition': 'not-an-int'}), 'entryInvalidPosition'),
    (_entry(fields: {'ext': '{private-broken-json'}), 'entryInvalidExt'),
    (_entry(fields: {'ext': '["private-list"]'}), 'entryInvalidExt'),
    ('${_entry()}&source=private-duplicate', 'entryDuplicateField'),
    ('${_entry()}&unrelated=%FF', 'entryInvalidEncoding'),
    ('${_entry()}&unrelated=${'x' * 65536}', 'entryTooLong'),
  ];
  for (var i = 0; i < invalid.length; i++) {
    final row = invalid[i];
    test('invalid entry $i exports ${row.$2} before reward dispatch', () async {
      final h = harness(entry: row.$1);
      final result = await h.repository.claimAd();
      expect(result.success, isFalse);
      expect(result.uncertain, isFalse);
      expect(result.message, contains('领取入口'));
      expect(h.calls, [NeteaseRewardsRepository.progressPath]);
      expect(diagnostics.rows.last['rewardStep'], 'entry');
      expect(diagnostics.rows.last['rewardReason'], row.$2);
      expect(diagnostics.rows.last['transport'], 'local');
      expect(diagnostics.export(), isNot(contains('private-')));
    });
  }

  test(
    'no-qualification entry reports its gate and never forces a write',
    () async {
      final h = harness(entry: _entry(fields: {'isNeedGetRights': 'false'}));
      expect((await h.repository.claimAd()).success, isFalse);
      expect(h.calls, [NeteaseRewardsRepository.progressPath]);
      expect(
        diagnostics.rows.last['rewardReason'],
        'qualificationNotRequested',
      );
      expect(diagnostics.rows.last['entryRoute'], 'officialNm');
    },
  );

  for (final qualified in [false, null]) {
    test(
      'qualification $qualified is distinct from entry or gain failure',
      () async {
        final h = harness(
          entry: _entry(),
          reply: (_, _) => _json({
            'code': 200,
            'data': {'qualified': ?qualified},
          }),
        );
        expect((await h.repository.claimAd()).success, isFalse);
        expect(h.calls.length, 2);
        expect(diagnostics.rows.last['rewardStep'], 'qualification');
        expect(
          diagnostics.rows.last['rewardReason'],
          qualified == false ? 'qualificationDenied' : 'receiptIncomplete',
        );
      },
    );
  }

  for (final row in [
    ('denied', 'gainDenied', false),
    ('business', 'businessRejected', true),
    ('http', 'httpFailure', true),
    ('missing', 'receiptIncomplete', true),
  ]) {
    test(
      'gain ${row.$1} exports its stage and preserves unknown-write protection',
      () async {
        final h = harness(
          entry: _entry(host: 'ne'),
          reply: (path, _) {
            if (path == NeteaseRewardsRepository.qualificationPath) {
              return _json({
                'code': 200,
                'data': {'qualified': true},
              });
            }
            return switch (row.$1) {
              'denied' => _json({
                'code': 200,
                'data': {'gainFlag': false},
              }),
              'business' => _json({'code': 500}),
              'http' => _json({'private-body': 'not exported'}, 500),
              _ => _json({'code': 200, 'data': {}}),
            };
          },
        );
        final result = await h.repository.claimAd();
        expect(result.success, isFalse);
        expect(result.uncertain, row.$3);
        expect(diagnostics.rows.last['rewardStep'], 'claim');
        expect(diagnostics.rows.last['rewardReason'], row.$2);
        if (row.$3) {
          expect((await h.repository.claimAd()).uncertain, isTrue);
          expect(h.calls.length, 3);
        }
      },
    );
  }

  test(
    'unrecognized session os becomes a closed category, never an exported value',
    () async {
      final h = harness(
        entry: null,
        extraCookies: {'os': 'private-os180-marker'},
      );
      await h.repository.claimAd();
      expect(diagnostics.rows.last['rewardIdentity'], 'sessionOther');
      expect(diagnostics.export(), isNot(contains('private-os180-marker')));
    },
  );

  test('extended reward events keep compact JSON complete and bounded', () {
    for (var i = 0; i < 90; i++) {
      diagnostics.record(
        platform: 'netease',
        operation: MusicNetworkOperation.rewardQualification,
        outcome: MusicNetworkOutcome.format,
        reward: const MusicRewardDiagnostic(
          step: MusicRewardStep.entry,
          reason: MusicRewardReason.entryMissingField,
          route: MusicRewardEntryRoute.officialNe,
          valueType: MusicRewardValueType.text,
          hasAdPosition: true,
          hasResourceId: false,
          hasSource: true,
          hasExt: true,
          qualificationRequested: true,
          identity: MusicRewardIdentity.defaultPc,
        ),
      );
    }
    expect(diagnostics.rows.length, 80);
    final compact = diagnostics.exportCompact();
    expect(compact.length, lessThanOrEqualTo(4096));
    final decoded = jsonDecode(compact) as Map;
    expect(decoded['complete'], isTrue);
    final last = (decoded['events'] as List).last as Map;
    expect(last['rewardReason'], 'entryMissingField');
    expect(last['entryRoute'], 'officialNe');
  });
}
