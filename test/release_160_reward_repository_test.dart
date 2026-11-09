import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesting_music/core/network/music_network_diagnostics.dart';
import 'package:mesting_music/features/music_platform/netease/netease_api.dart';
import 'package:mesting_music/features/music_platform/netease/netease_music_repository.dart';
import 'package:mesting_music/features/music_platform/netease/netease_reward_journal.dart';
import 'package:mesting_music/features/music_platform/netease/netease_rewards_repository.dart';
import 'package:mesting_music/features/music_platform/netease/netease_session.dart';

import 'netease_v114_workflows_test.dart' show eapiBody;

// All account, entry and entitlement values below are synthetic. No fixture
// contacts NetEase or claims that a particular live source grants a reward.
const _owner = NeteaseSession(
  userId: '160001',
  cookies: {'MUSIC_U': 'synthetic-reward160-cookie'},
  deviceId: 'synthetic-reward160-device',
);
const _other = NeteaseSession(
  userId: '160002',
  cookies: {'MUSIC_U': 'synthetic-other160-cookie'},
  deviceId: 'synthetic-other160-device',
);
const _source = 987654321;
const _extension = '{"syntheticOpaque":"keep exact whitespace  and encoding"}';

String _entry({int source = _source, bool qualification = true}) => Uri(
  scheme: 'orpheus',
  host: 'nm',
  path: '/motivationAd/show',
  queryParameters: {
    'adPosition': '160000',
    'resourceId': '',
    'source': '$source',
    'isNeedGetRights': '$qualification',
    'isShowEndToast': 'true',
    'ext': jsonEncode({'bizReportInfo': 'synthetic-owner-entry'}),
    'unrelatedTracking': 'must-not-enter-qualification',
  },
).toString();

Map<String, Object?> _progress({String? actionUrl}) => {
  'code': 200,
  'data': {'actionUrl': actionUrl ?? _entry()},
};
Map<String, Object?> _qualified({Map<String, Object?> extra = const {}}) => {
  'code': 200,
  'data': {
    'qualified': true,
    // Deliberately different: the official gain constructor retains entry
    // source, not an unproved substitute from a hint with the same field name.
    'source': 987654320,
    'creativeType': 123456,
    'rightsGainMethod': 160,
    'rightsExtJson': _extension,
    ...extra,
  },
};
http.Response _json(Object value, [int status = 200]) =>
    http.Response(jsonEncode(value), status);

typedef _Reply =
    Future<http.Response> Function(String path, Map<String, dynamic> payload);

class _Wire {
  _Wire(this.reply) {
    client = MockClient((request) async {
      // Parsing an actionUrl must not trigger a request to its destination.
      expect(request.url.host, 'interface.music.163.com');
      expect(request.method, 'POST');
      final path = request.url.path.replaceFirst('/eapi/', '/api/');
      calls.add(path);
      final body = eapiBody(request);
      expect(body['header']['MUSIC_U'], _owner.cookies['MUSIC_U']);
      return reply(path, body);
    });
    api = NeteaseApi(client)..configure(_owner);
  }
  final _Reply reply;
  final calls = <String>[];
  late final MockClient client;
  late final NeteaseApi api;
  int count(String path) => calls.where((entry) => entry == path).length;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;
  late DateTime now;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    now = DateTime(2026, 11, 5, 12);
    MusicNetworkDiagnostics.shared.clear();
  });
  tearDown(MusicNetworkDiagnostics.shared.clear);

  NeteaseRewardsRepository repository(_Wire wire) {
    addTearDown(wire.client.close);
    return NeteaseRewardsRepository(
      NeteaseMusicRepository(wire.api),
      preferences: prefs,
      clock: () => now,
    );
  }

  String? pending() =>
      prefs.getString(NeteaseRewardJournal.key('netease:160001', 'ad'));

  test(
    'actual eapi serializes the issued entry before one direct gain',
    () async {
      final wire = _Wire((path, payload) async {
        if (path == NeteaseRewardsRepository.progressPath) {
          expect(payload['entranceType'], 'FREE_LISTEN');
          return _json(_progress());
        }
        final encoded = payload['reqParam'];
        expect(encoded, isA<String>());
        final params = jsonDecode(encoded as String) as Map;
        if (path == NeteaseRewardsRepository.qualificationPath) {
          expect(params['adPosition'], 160000);
          expect(params['resourceId'], '');
          expect(params['source'], _source);
          expect(params['isNeedGetRights'], isTrue);
          expect(params.containsKey('userId'), isFalse);
          expect(params.containsKey('unrelatedTracking'), isFalse);
          expect(params['ext'], isA<String>());
          expect(jsonDecode(params['ext'] as String), {
            'bizReportInfo': 'synthetic-owner-entry',
          });
          return _json(
            _qualified(
              extra: {
                'reqUid': 'not-a-watched-ad',
                'exposureTime': 160,
                'clickTime': 160,
                'appInfo': {'not': 'a-proof'},
              },
            ),
          );
        }
        expect(path, NeteaseRewardsRepository.claimPath);
        expect(params, {
          'userId': 160001,
          'source': _source,
          'creativeType': 123456,
          'rightsGainMethod': 160,
          'rightsExtJson': _extension,
        });
        return _json({
          'code': 200,
          'data': {'gainFlag': true},
        });
      });
      expect((await repository(wire).claimAd()).success, isTrue);
      expect(wire.calls, [
        NeteaseRewardsRepository.progressPath,
        NeteaseRewardsRepository.qualificationPath,
        NeteaseRewardsRepository.claimPath,
      ]);
      expect(pending(), isNull);
      final log = MusicNetworkDiagnostics.shared.export();
      for (final private in [
        'synthetic-reward160-cookie',
        'synthetic-owner-entry',
        _extension,
        'orpheus:',
        'not-a-watched-ad',
      ]) {
        expect(log, isNot(contains(private)));
      }
    },
  );

  test(
    'progress business error stops before qualification with its stage',
    () async {
      final wire = _Wire((_, _) async => _json({'code': 500}));
      final result = await repository(wire).claimAd();
      expect(result.message, contains('领取进度失败（业务码 500）'));
      expect(result.uncertain, isFalse);
      expect(wire.calls, [NeteaseRewardsRepository.progressPath]);
      expect(pending(), isNull);
    },
  );

  for (final actionUrl in [
    null,
    'https://example.invalid/steal?adPosition=1&resourceId=x',
    'orpheus://motivationAd/other?adPosition=1&resourceId=x',
  ]) {
    test(
      'an absent or unsupported actionUrl cannot dispatch: $actionUrl',
      () async {
        final wire = _Wire(
          (_, _) async => _json({
            'code': 200,
            'data': {'actionUrl': actionUrl},
          }),
        );
        final result = await repository(wire).claimAd();
        expect(result.success, isFalse);
        expect(result.uncertain, isFalse);
        expect(result.message, contains('领取入口'));
        expect(wire.calls, [NeteaseRewardsRepository.progressPath]);
        final event = MusicNetworkDiagnostics.shared.rows.last;
        expect(event['operation'], 'rewardQualification');
        expect(event['transport'], 'local');
        expect(event['outcome'], 'format');
      },
    );
  }

  test('the official no-qualification gate is respected', () async {
    final wire = _Wire(
      (_, _) async => _json(_progress(actionUrl: _entry(qualification: false))),
    );
    final result = await repository(wire).claimAd();
    expect(result.message, contains('未提供直接领取资格流程'));
    expect(result.success, isFalse);
    expect(wire.calls, [NeteaseRewardsRepository.progressPath]);
    expect(pending(), isNull);
  });

  for (final change in ['stop', 'account', 'day']) {
    test('$change during progress prevents a qualification request', () async {
      final gate = Completer<http.Response>();
      final wire = _Wire((_, _) => gate.future);
      var current = true;
      final work = repository(wire).claimAd(stillCurrent: () => current);
      await Future<void>.delayed(Duration.zero);
      if (change == 'stop') current = false;
      if (change == 'account') wire.api.configure(_other);
      if (change == 'day') now = DateTime(2026, 11, 6);
      gate.complete(_json(_progress()));
      expect((await work).success, isFalse);
      expect(wire.calls, [NeteaseRewardsRepository.progressPath]);
      expect(pending(), isNull);
    });
  }

  test('a hint source cannot replace a missing entry source', () async {
    final wire = _Wire((path, _) async {
      if (path == NeteaseRewardsRepository.progressPath) {
        return _json(_progress(actionUrl: _entry(source: 0)));
      }
      return _json(_qualified());
    });
    final result = await repository(wire).claimAd();
    expect(result.message, contains('未提供有效来源'));
    expect(wire.count(NeteaseRewardsRepository.qualificationPath), 1);
    expect(wire.count(NeteaseRewardsRepository.claimPath), 0);
    expect(pending(), isNull);
  });

  test('each confirmed attempt obtains a fresh owner-bound entry', () async {
    var source = _source;
    final gained = <int>[];
    final wire = _Wire((path, body) async {
      if (path == NeteaseRewardsRepository.progressPath) {
        return _json(_progress(actionUrl: _entry(source: source)));
      }
      if (path == NeteaseRewardsRepository.qualificationPath) {
        return _json(_qualified());
      }
      gained.add(
        (jsonDecode(body['reqParam'] as String) as Map)['source'] as int,
      );
      return _json({
        'code': 200,
        'data': {'gainFlag': true},
      });
    });
    final repo = repository(wire);
    expect((await repo.claimAd()).success, isTrue);
    source--;
    expect((await repo.claimAd()).success, isTrue);
    expect(gained, [_source, _source - 1]);
    expect(wire.count(NeteaseRewardsRepository.progressPath), 2);
  });

  for (final httpFailure in [false, true]) {
    test(
      'gain ${httpFailure ? 'HTTP' : 'business'} 500 stays pending across rebuild',
      () async {
        final wire = _Wire((path, _) async {
          if (path == NeteaseRewardsRepository.progressPath) {
            return _json(_progress());
          }
          if (path == NeteaseRewardsRepository.qualificationPath) {
            return _json(_qualified());
          }
          return _json({
            'code': 500,
            'message': 'private body',
          }, httpFailure ? 500 : 200);
        });
        final first = await repository(wire).claimAd();
        expect(first.success, isFalse);
        expect(first.uncertain, isTrue);
        expect(first.message, contains('奖励领取'));
        expect(first.message, contains(httpFailure ? 'HTTP 500' : '业务码 500'));
        expect(first.message, isNot(contains('private body')));
        expect(jsonDecode(pending()!), {'day': '2026-11-05'});
        final second = await repository(wire).claimAd();
        expect(second.uncertain, isTrue);
        expect(wire.count(NeteaseRewardsRepository.progressPath), 1);
        expect(wire.count(NeteaseRewardsRepository.qualificationPath), 1);
        expect(wire.count(NeteaseRewardsRepository.claimPath), 1);
      },
    );
  }

  for (final httpFailure in [false, true]) {
    test(
      'qualification ${httpFailure ? 'HTTP' : 'business'} 500 never submits gain',
      () async {
        final wire = _Wire((path, _) async {
          if (path == NeteaseRewardsRepository.progressPath) {
            return _json(_progress());
          }
          return _json({'code': 500}, httpFailure ? 500 : 200);
        });
        final repo = repository(wire);
        final first = await repo.claimAd();
        expect(first.success, isFalse);
        expect(first.uncertain, isFalse);
        expect(first.message, contains('领取资格'));
        expect(first.message, contains(httpFailure ? 'HTTP 500' : '业务码 500'));
        expect(pending(), isNull);
        await repo
            .claimAd(); // A separate deliberate attempt, not an auto-retry.
        expect(wire.count(NeteaseRewardsRepository.qualificationPath), 2);
        expect(wire.count(NeteaseRewardsRepository.claimPath), 0);
      },
    );
  }

  test(
    'non-string rightsExtJson is not invented as JSON or forwarded',
    () async {
      final wire = _Wire((path, body) async {
        if (path == NeteaseRewardsRepository.progressPath) {
          return _json(_progress());
        }
        if (path == NeteaseRewardsRepository.qualificationPath) {
          return _json(
            _qualified(
              extra: {
                'rightsExtJson': {'not': 'a string'},
              },
            ),
          );
        }
        expect(
          (jsonDecode(body['reqParam'] as String) as Map).containsKey(
            'rightsExtJson',
          ),
          isFalse,
        );
        return _json({
          'code': 200,
          'data': {'gainFlag': false},
        });
      });
      expect((await repository(wire).claimAd()).success, isFalse);
      expect(pending(), isNull);
    },
  );
}
