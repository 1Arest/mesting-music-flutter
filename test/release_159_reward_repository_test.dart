import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesting_music/features/music_platform/netease/netease_api.dart';
import 'package:mesting_music/features/music_platform/netease/netease_music_repository.dart';
import 'package:mesting_music/features/music_platform/netease/netease_reward_journal.dart';
import 'package:mesting_music/features/music_platform/netease/netease_rewards_repository.dart';
import 'package:mesting_music/features/music_platform/netease/netease_session.dart';
import 'netease_v114_workflows_test.dart' show eapiBody;

const _owner = NeteaseSession(
  userId: '101',
  cookies: {'MUSIC_U': 'synthetic-reward-owner'},
  deviceId: 'synthetic-device',
);
const _other = NeteaseSession(
  userId: '202',
  cookies: {'MUSIC_U': 'synthetic-other-owner'},
  deviceId: 'synthetic-device-b',
);

class _Call {
  _Call(this.path, this.data, this.credential);
  final String path;
  final Map<String, Object?> data;
  final String? credential;
}

typedef _Reply = Future<Map<String, dynamic>> Function(_Call call);

/// These protocol fixtures cannot contact a platform. They observe the actual
/// repository contract, including its captured credential and allowed payload.
class _Api extends NeteaseApi {
  _Api(this.reply)
    : super(MockClient((_) async => throw StateError('unexpected wire call'))) {
    configure(_owner);
  }
  final _Reply reply;
  final calls = <_Call>[];

  @override
  Future<Map<String, dynamic>> request(
    String path,
    Map<String, Object?> data, {
    bool weapi = false,
    Future<void>? abortTrigger,
    bool allowBusinessError = false,
    String? expectedCredential,
    Map<String, String> additionalHeaders = const {},
    bool playbackLog = false,
    bool mobileMessages = false,
  }) {
    final call = _Call(path, Map.of(data), expectedCredential);
    calls.add(call);
    expect(expectedCredential, _owner.credentialId);
    expect(allowBusinessError, isTrue);
    expect(weapi, isFalse);
    expect(additionalHeaders, isEmpty);
    expect(playbackLog, isFalse);
    expect(mobileMessages, isFalse);
    return reply(call);
  }

  int count(String path) => calls.where((call) => call.path == path).length;
}

Map<String, dynamic> _qualified({Map<String, Object?> extra = const {}}) => {
  'code': 200,
  'data': {
    'qualified': true,
    'source': 'SYNTHETIC_PLATFORM_ISSUED_ENTRY',
    'rightsGainMethod': 'DIRECT',
    'rightsGainDuration': 1800000,
    ...extra,
  },
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;
  late DateTime now;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    now = DateTime(2026, 11, 5, 12);
  });

  NeteaseRewardsRepository repository(_Api api, {bool Function()? allowed}) =>
      NeteaseRewardsRepository(
        NeteaseMusicRepository(api),
        preferences: prefs,
        clock: () => now,
        allowMutation: allowed,
      );

  for (final code in [200, -2]) {
    test(
      'daily sign accepts explicit code $code and sends mobile type zero',
      () async {
        final api = _Api(
          (call) async => call.path.contains('/user/detail/')
              ? {'code': 200, 'mobileSign': false}
              : {'code': code, 'point': 3},
        );
        final result = await repository(api).signIn();
        expect(result.success, isTrue);
        expect(result.signed, isTrue);
        expect(result.signedDate, '2026-11-05');
        final sign = api.calls.singleWhere(
          (c) => c.path == '/api/point/dailyTask',
        );
        expect(sign.data, {'type': 0});
        expect(
          prefs.getString(NeteaseRewardJournal.key('netease:101', 'sign')),
          isNull,
        );
      },
    );
  }

  test(
    'today signed profile confirms state without sending daily task',
    () async {
      final api = _Api((_) async => {'code': 200, 'mobileSign': true});
      final result = await repository(api).signIn();
      expect(result.signed, isTrue);
      expect(api.count('/api/point/dailyTask'), 0);
    },
  );

  test(
    'profile mobileSign is root data and cannot be guessed from code alone',
    () async {
      final api = _Api((call) async {
        if (call.path.contains('/user/detail/')) {
          return {
            'code': 200,
            'profile': {'mobileSign': true},
          };
        }
        return {'code': 200};
      });
      final snapshot = await repository(api).load();
      expect(snapshot.signedToday, isNull);
      expect(snapshot.signedDates, isEmpty);
      expect(snapshot.recordsAvailable, isFalse);
    },
  );

  test(
    'known sign refusal is not a checked day and allows a later explicit attempt',
    () async {
      final api = _Api(
        (call) async => call.path.contains('/user/detail/')
            ? {'code': 200, 'mobileSign': false}
            : {
                'code': 415,
                'message': 'synthetic private detail must not leak',
              },
      );
      final repo = repository(api);
      final first = await repo.signIn();
      expect(first.success, isFalse);
      expect(first.signed, isFalse);
      expect(first.needsVerification, isTrue);
      expect(first.message, isNot(contains('synthetic private')));
      await repo.signIn();
      expect(api.count('/api/point/dailyTask'), 2);
    },
  );

  test(
    'lost sign reply remains pending across repository reconstruction',
    () async {
      final api = _Api((call) async {
        if (call.path.contains('/user/detail/')) {
          return {'code': 200, 'mobileSign': false};
        }
        throw TimeoutException('synthetic response loss');
      });
      final first = await repository(api).signIn();
      expect(first.uncertain, isTrue);
      final second = await repository(api).signIn();
      expect(second.uncertain, isTrue);
      expect(api.count('/api/point/dailyTask'), 1);
      final marker = prefs.getString(
        NeteaseRewardJournal.key('netease:101', 'sign'),
      )!;
      expect(jsonDecode(marker), {'day': '2026-11-05'});
      expect(marker, isNot(contains('synthetic-reward-owner')));
    },
  );

  test(
    'a missing sign code is uncertain and cannot automatically replay',
    () async {
      final api = _Api(
        (call) async => call.path.contains('/user/detail/')
            ? {'code': 200, 'mobileSign': false}
            : {'message': 'no receipt'},
      );
      expect((await repository(api).signIn()).uncertain, isTrue);
      expect((await repository(api).signIn()).uncertain, isTrue);
      expect(api.count('/api/point/dailyTask'), 1);
    },
  );

  test(
    'pending sign is reconciled only by authoritative signed state',
    () async {
      var signed = false;
      final api = _Api((call) async {
        if (call.path.contains('/user/detail/')) {
          return {'code': 200, 'mobileSign': signed};
        }
        throw TimeoutException('synthetic lost reply');
      });
      await repository(api).signIn();
      signed = true;
      final result = await repository(api).signIn();
      expect(result.signed, isTrue);
      expect(api.count('/api/point/dailyTask'), 1);
      expect(
        prefs.getString(NeteaseRewardJournal.key('netease:101', 'sign')),
        isNull,
      );
    },
  );

  test(
    'credential change while reading sign state prevents a sign write',
    () async {
      final gate = Completer<Map<String, dynamic>>();
      final api = _Api((_) => gate.future);
      final pending = repository(api).signIn();
      await Future<void>.delayed(Duration.zero);
      api.configure(_other);
      gate.complete({'code': 200, 'mobileSign': false});
      expect((await pending).success, isFalse);
      expect(api.count('/api/point/dailyTask'), 0);
    },
  );

  for (final confirmedToday in [true, false]) {
    test(
      'cross-midnight receipt marks new day only with signedToday=$confirmedToday',
      () async {
        var profiles = 0;
        final api = _Api((call) async {
          if (call.path.contains('/user/detail/')) {
            return {
              'code': 200,
              'mobileSign': ++profiles > 1 && confirmedToday,
            };
          }
          now = DateTime(2026, 11, 6);
          return {'code': 200};
        });
        final result = await repository(api).signIn();
        expect(result.success, isTrue);
        expect(result.signed, confirmedToday);
        expect(result.signedDate, confirmedToday ? '2026-11-06' : null);
        expect(api.count('/api/point/dailyTask'), 1);
      },
    );
  }

  test(
    'read-only snapshot uses milliseconds asset and server task labels',
    () async {
      final api = _Api((call) async {
        if (call.path.contains('/user/detail/')) {
          return {'code': 200, 'mobileSign': true};
        }
        if (call.path == NeteaseRewardsRepository.balancePath) {
          return {
            'code': 200,
            'data': {
              'freeListen': {'rightsRemainingTime': 1834999},
            },
          };
        }
        expect(call.path, NeteaseRewardsRepository.progressPath);
        expect(call.data, {'entranceType': 'FREE_LISTEN'});
        return {
          'code': 200,
          'data': {
            'stride': 5,
            'title': '再领一次，继续免费听',
            'subTitle': '奖励说明',
            'tasks': [
              {'label': '30分钟免费听', 'state': 'DONE', 'doneCount': 1},
              {'label': '今日免费听', 'state': 'TODO', 'doneCount': 0},
            ],
          },
        };
      });
      final result = await repository(api).load();
      expect(result.signedDates, {'2026-11-05'});
      final free = result.freeListen!;
      expect(free.remainingSeconds, 1834);
      expect(free.progressTitle, '再领一次，继续免费听');
      expect(free.progressSubtitle, '奖励说明');
      expect(free.milestones.first.done, isTrue);
      expect(free.milestones.first.count, 1);
      expect(free.milestones.last.done, isNull);
      expect(free.adTarget, isNull);
      expect(free.adLimit, isNull);
      expect(
        api.calls.map((c) => c.path),
        isNot(contains('/api/free/listen/data/v2')),
      );
      expect(api.calls.any((c) => c.path.contains('/direct/')), isFalse);
      expect(api.count(NeteaseRewardsRepository.claimPath), 0);
    },
  );

  test(
    'missing fields and failed reads do not synthesize zero or quotas',
    () async {
      final api = _Api((_) async => {'code': 500});
      final snapshot = await repository(api).load();
      expect(snapshot.freeListen, isNull);
      expect(snapshot.signedToday, isNull);
      final unknown = NeteaseRewardsRepository.parseFreeListen(
        {
          'code': 200,
          'data': {
            'freeListen': {'rightsRemainingTime': -1},
          },
        },
        {
          'code': 200,
          'data': {'stride': 7, 'tasks': []},
        },
      );
      expect(unknown, isNull);
    },
  );

  test(
    'direct claim forwards server entitlement allowlist without ad proof',
    () async {
      final api = _Api((call) async {
        if (call.path == NeteaseRewardsRepository.qualificationPath) {
          expect(call.data['reqParam'], {'userId': 101});
          return _qualified(
            extra: {
              'creativeType': 'AUDIO',
              'reqUid': 'must-not-forward',
              'exposureTime': 123,
              'clickTime': 456,
              'appInfo': 'must-not-forward',
              'fakeCompletion': true,
            },
          );
        }
        expect(call.path, NeteaseRewardsRepository.claimPath);
        final payload = jsonDecode(call.data['reqParam'] as String) as Map;
        expect(payload, {
          'userId': 101,
          'source': 'SYNTHETIC_PLATFORM_ISSUED_ENTRY',
          'rightsGainMethod': 'DIRECT',
          'rightsGainDuration': 1800000,
          'creativeType': 'AUDIO',
        });
        return {
          'code': 200,
          'data': {'gainFlag': true},
        };
      });
      final result = await repository(api).claimAd();
      expect(result.success, isTrue);
      expect(api.count(NeteaseRewardsRepository.claimPath), 1);
      expect(api.calls.any((c) => c.path.contains('/direct/')), isFalse);
      expect(
        prefs.getString(NeteaseRewardJournal.key('netease:101', 'ad')),
        isNull,
      );
    },
  );

  test(
    'code 200 with gainFlag false is a refusal rather than a success',
    () async {
      final api = _Api(
        (call) async => call.path == NeteaseRewardsRepository.qualificationPath
            ? _qualified()
            : {
                'code': 200,
                'data': {'gainFlag': false},
              },
      );
      final first = await repository(api).claimAd();
      expect(first.success, isFalse);
      expect(first.uncertain, isFalse);
      // A known refusal may be retried only through a later explicit call.
      await repository(api).claimAd();
      expect(api.count(NeteaseRewardsRepository.claimPath), 2);
    },
  );

  test(
    'code 200 without gainFlag stays pending across reconstructed services',
    () async {
      final api = _Api(
        (call) async => call.path == NeteaseRewardsRepository.qualificationPath
            ? _qualified()
            : {'code': 200, 'data': {}},
      );
      expect((await repository(api).claimAd()).uncertain, isTrue);
      expect((await repository(api).claimAd()).uncertain, isTrue);
      expect(api.count(NeteaseRewardsRepository.qualificationPath), 1);
      expect(api.count(NeteaseRewardsRepository.claimPath), 1);
      final marker = prefs.getString(
        NeteaseRewardJournal.key('netease:101', 'ad'),
      )!;
      expect(jsonDecode(marker), {'day': '2026-11-05'});
    },
  );

  test(
    'an explicit rights upper limit stops without counting a reward',
    () async {
      final api = _Api(
        (call) async => call.path == NeteaseRewardsRepository.qualificationPath
            ? _qualified()
            : {
                'code': 200,
                'data': {'gainFlag': false, 'rightsUpperLimit': true},
              },
      );
      final result = await repository(api).claimAd();
      expect(result.success, isFalse);
      expect(result.quotaDone, isTrue);
      expect(result.uncertain, isFalse);
      expect(api.count(NeteaseRewardsRepository.claimPath), 1);
    },
  );

  test(
    'lost gain reply cannot be inferred from a later higher balance',
    () async {
      final api = _Api((call) async {
        if (call.path == NeteaseRewardsRepository.qualificationPath) {
          return _qualified();
        }
        if (call.path == NeteaseRewardsRepository.claimPath) {
          throw TimeoutException('synthetic loss');
        }
        if (call.path == NeteaseRewardsRepository.balancePath) {
          return {
            'code': 200,
            'data': {
              'freeListen': {'rightsRemainingTime': 9999999},
            },
          };
        }
        return {'code': 200};
      });
      expect((await repository(api).claimAd()).uncertain, isTrue);
      final rebuilt = repository(api);
      await rebuilt.load();
      expect((await rebuilt.claimAd()).uncertain, isTrue);
      expect(api.count(NeteaseRewardsRepository.claimPath), 1);
    },
  );

  test(
    'an unknown previous-day claim does not become a permanent new-day block',
    () async {
      final api = _Api(
        (call) async => call.path == NeteaseRewardsRepository.qualificationPath
            ? _qualified()
            : {'code': 200, 'data': {}},
      );
      await repository(api).claimAd();
      now = DateTime(2026, 11, 6, 12);
      await repository(api).claimAd();
      expect(api.count(NeteaseRewardsRepository.claimPath), 2);
    },
  );

  for (final hint in [
    {
      'code': 200,
      'data': {'qualified': false, 'source': 'not-entitled'},
    },
    {
      'code': 200,
      'data': {'qualified': true},
    },
    {
      'code': 200,
      'data': {'source': 'missing-qualified'},
    },
    {'code': 415},
  ]) {
    test(
      'unusable qualification cannot create a gain request: $hint',
      () async {
        final api = _Api((_) async => hint);
        final result = await repository(api).claimAd();
        expect(result.success, isFalse);
        expect(api.count(NeteaseRewardsRepository.claimPath), 0);
      },
    );
  }

  test(
    'stop while qualification is in flight prevents the subsequent gain',
    () async {
      final gate = Completer<Map<String, dynamic>>();
      var current = true;
      final api = _Api((_) => gate.future);
      final pending = repository(api).claimAd(stillCurrent: () => current);
      await Future<void>.delayed(Duration.zero);
      current = false;
      gate.complete(_qualified());
      expect((await pending).success, isFalse);
      expect(api.count(NeteaseRewardsRepository.claimPath), 0);
    },
  );

  test(
    'credential change while qualification is in flight prevents gain',
    () async {
      final gate = Completer<Map<String, dynamic>>();
      final api = _Api((_) => gate.future);
      final pending = repository(api).claimAd();
      await Future<void>.delayed(Duration.zero);
      api.configure(_other);
      gate.complete(_qualified());
      expect((await pending).success, isFalse);
      expect(api.count(NeteaseRewardsRepository.claimPath), 0);
    },
  );

  test(
    'diagnostic gate blocks reward writes before any qualification request',
    () async {
      final api = _Api((_) async => throw StateError('must not request'));
      final repo = repository(api, allowed: () => false);
      expect((await repo.claimAd()).success, isFalse);
      expect((await repo.signIn()).success, isFalse);
      expect(api.calls, isEmpty);
    },
  );

  test(
    'unreadable pending marker is conservative rather than silently deleted',
    () async {
      await prefs.setString(
        NeteaseRewardJournal.key('netease:101', 'ad'),
        '{broken',
      );
      final api = _Api((_) async => throw StateError('must not request'));
      expect((await repository(api).claimAd()).uncertain, isTrue);
      expect(api.calls, isEmpty);
    },
  );

  test(
    'real encrypted eapi write is sent once and is not retried after reply loss',
    () async {
      var signs = 0;
      final client = MockClient((request) async {
        expect(request.url.host, 'interface.music.163.com');
        final data = eapiBody(request);
        if (request.url.path == '/eapi/v1/user/detail/101') {
          return http.Response(
            jsonEncode({'code': 200, 'mobileSign': false}),
            200,
          );
        }
        expect(request.url.path, '/eapi/point/dailyTask');
        expect(data['type'], 0);
        expect(data.keys.toSet(), {'type', 'header', 'e_r'});
        signs++;
        throw http.ClientException('synthetic connection lost after dispatch');
      });
      addTearDown(client.close);
      final api = NeteaseApi(client)..configure(_owner);
      NeteaseRewardsRepository create() => NeteaseRewardsRepository(
        NeteaseMusicRepository(api),
        preferences: prefs,
        clock: () => now,
      );
      expect((await create().signIn()).uncertain, isTrue);
      expect((await create().signIn()).uncertain, isTrue);
      expect(signs, 1);
    },
  );

  test('already-stopped claim never starts a qualification read', () async {
    final api = _Api((_) async => throw StateError('must not request'));
    expect(
      (await repository(api).claimAd(stillCurrent: () => false)).success,
      isFalse,
    );
    expect(api.calls, isEmpty);
  });

  test('a slower balance cannot date yesterday sign as today', () async {
    final balance = Completer<Map<String, dynamic>>();
    final api = _Api((call) async {
      if (call.path.contains('/user/detail/')) {
        return {'code': 200, 'mobileSign': true};
      }
      if (call.path == NeteaseRewardsRepository.balancePath) {
        return balance.future;
      }
      return {
        'code': 200,
        'data': {'title': 'yesterday progress'},
      };
    });
    final operation = repository(api).load();
    await Future<void>.delayed(Duration.zero);
    now = DateTime(2026, 11, 6);
    balance.complete({
      'code': 200,
      'data': {
        'freeListen': {'rightsRemainingTime': 1834000},
      },
    });
    final snapshot = await operation;
    expect(snapshot.now.day, 6);
    expect(snapshot.signedToday, isNull);
    expect(snapshot.signedDates, isEmpty);
    expect(snapshot.freeListen, isNull);
  });

  test(
    'a qualification crossing midnight cannot issue a new-day gain',
    () async {
      final gate = Completer<Map<String, dynamic>>();
      final api = _Api((_) => gate.future);
      final operation = repository(api).claimAd();
      await Future<void>.delayed(Duration.zero);
      now = DateTime(2026, 11, 6);
      gate.complete(_qualified());
      final result = await operation;
      expect(result.success, isFalse);
      expect(api.count(NeteaseRewardsRepository.claimPath), 0);
      expect(
        prefs.getString(NeteaseRewardJournal.key('netease:101', 'ad')),
        isNull,
      );
    },
  );

  test(
    'a profile response spanning midnight cannot mark the new day signed',
    () async {
      final api = _Api((call) async {
        if (call.path.contains('/user/detail/')) {
          now = DateTime(2026, 11, 6);
          return {'code': 200, 'mobileSign': true};
        }
        return {'code': 200};
      });
      final result = await repository(api).load();
      expect(result.now, DateTime(2026, 11, 6));
      expect(result.signedToday, isNull);
      expect(result.signedDates, isEmpty);
    },
  );
}
