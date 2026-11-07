import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesting_music/features/music_platform/data/embedded_music_server.dart';
import 'package:mesting_music/features/music_platform/data/music_platform_api.dart';
import 'package:mesting_music/features/music_platform/data/platform_rewards_repository.dart';
import 'package:mesting_music/features/music_platform/domain/platform_rewards.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';

class _Server implements MusicServer {
  @override
  Future<Uri> start() async => Uri.parse('http://127.0.0.1:12345');
}

const _owner = PlatformSession(userId: 'reward-test', token: 'fixture-token');
http.Response _json(Map<String, dynamic> data) =>
    http.Response.bytes(utf8.encode(jsonEncode(data)), 200);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final day = DateTime(2026, 10, 26);
  late List<http.Request> requests;
  late MusicPlatformApi api;
  PlatformRewardsRepository repository(
    Future<Map<String, dynamic>> Function(http.Request) respond,
  ) {
    requests = [];
    final client = MockClient((request) async {
      requests.add(request);
      expect(request.url.host, '127.0.0.1');
      return _json(await respond(request));
    });
    addTearDown(client.close);
    api = MusicPlatformApi(server: _Server(), client: client)..session = _owner;
    return PlatformRewardsRepository(api, clock: () => day);
  }

  test(
    'daily claim uses POST/date then upgrade; both confirmations are required',
    () async {
      final repo = repository((_) async => {'status': 1});
      final result = await repo.signIn(_owner, day);
      expect(result.signed, true);
      expect(requests.map((r) => r.url.path), [
        '/youth/day/vip',
        '/youth/day/vip/upgrade',
      ]);
      expect(requests.every((r) => r.method == 'POST'), true);
      expect(requests.first.url.queryParameters['receive_day'], '2026-10-26');
      expect(
        requests.every(
          (r) => r.headers['authorization']!.contains('userid=reward-test'),
        ),
        true,
      );
    },
  );

  test(
    'a successful base claim cannot disguise a failed concept upgrade',
    () async {
      final repo = repository(
        (request) async => request.url.path.endsWith('upgrade')
            ? {'status': 0, 'error_code': 20006}
            : {'status': 1},
      );
      final result = await repo.signIn(_owner, day);
      expect(result.success, false);
      expect(result.signed, false);
      expect(result.message, contains('畅听会员已领取'));
    },
  );

  test(
    'documented already-received/upgraded codes preserve a completed sign-in',
    () async {
      final repo = repository(
        (request) async => {
          'status': 0,
          'error_code': request.url.path.endsWith('upgrade') ? 20030 : 131001,
        },
      );
      expect((await repo.signIn(_owner, day)).signed, true);
    },
  );

  test(
    '20028 requires real challenge proof and permits just one verified retry',
    () async {
      var claims = 0, verifications = 0;
      final repo = repository(
        (request) async => switch (request.url.path) {
          '/youth/day/vip' =>
            ++claims == 1
                ? {'status': 0, 'error_code': 20028, 'ssaCode': 'fixture-event'}
                : {'status': 1},
          '/get/verify/info' => {
            'status': 1,
            'data': {'v_type': 23, 'txappid': '123456'},
          },
          _ => {'status': 1},
        },
      );
      final outcome = await repo.signIn(
        _owner,
        day,
        verify: (challenge) async {
          verifications++;
          expect(challenge.eventId, 'fixture-event');
          expect(challenge.appId, '123456');
          return 'KGCodeTX|fixture-proof';
        },
      );
      expect(outcome.signed, true);
      expect(verifications, 1);
      expect(claims, 2);
      final submit = requests.singleWhere(
        (r) => r.url.path == '/verify/user/info',
      );
      expect(
        submit.url.queryParameters['verifycode'],
        'KGCodeTX|fixture-proof',
      );
      expect(submit.url.queryParameters['eventid'], 'fixture-event');
    },
  );

  test('cancelled verification cannot submit proof or retry a claim', () async {
    final repo = repository(
      (request) async => request.url.path == '/get/verify/info'
          ? {
              'status': 1,
              'data': {'v_type': 23, 'txappid': '123456'},
            }
          : {'status': 0, 'error_code': 20028, 'ssaCode': 'fixture-event'},
    );
    expect(
      (await repo.signIn(_owner, day, verify: (_) async => null)).signed,
      false,
    );
    expect(requests.map((r) => r.url.path), [
      '/youth/day/vip',
      '/get/verify/info',
    ]);
  });

  test(
    'automatic sign-in stops at a challenge without opening or faking it',
    () async {
      final repo = repository(
        (_) async => {
          'status': 0,
          'error_code': 20028,
          'ssaCode': 'fixture-event',
        },
      );
      final result = await repo.signIn(_owner, day);
      expect(result.needsVerification, true);
      expect(result.signed, false);
      expect(requests.length, 1);
    },
  );

  test(
    'switching account during a challenge prevents its proof submission',
    () async {
      final repo = repository(
        (request) async => request.url.path == '/get/verify/info'
            ? {
                'status': 1,
                'data': {'v_type': 23, 'txappid': '123456'},
              }
            : {'status': 0, 'error_code': 20028, 'ssaCode': 'fixture-event'},
      );
      await expectLater(
        repo.signIn(
          _owner,
          day,
          verify: (_) async {
            api.session = const PlatformSession(
              userId: 'other',
              token: 'other-fixture',
            );
            return 'KGCodeTX|fixture-proof';
          },
        ),
        throwsA(isA<MusicPlatformException>()),
      );
      expect(requests.any((r) => r.url.path == '/verify/user/info'), false);
    },
  );

  test(
    'listen already-received and ad quota are distinct terminal outcomes',
    () async {
      final repo = repository(
        (request) async => {
          'status': 0,
          'error_code': request.url.path == '/youth/listen/song'
              ? 130012
              : 30002,
        },
      );
      expect((await repo.listen(_owner)).message, contains('已领取'));
      final ad = await repo.ad(_owner);
      expect(ad.success, true);
      expect(ad.quotaDone, true);
    },
  );

  test('record parser excludes tvip, failed days and impossible dates', () {
    expect(
      parseRewardDates({
        'data': {
          'list': [
            {'day': '2026-10-25', 'vip_type': 'svip', 'receive_vip': 1},
            {'day': '2026-10-25', 'vip_type': 'svip', 'receive_vip': 1},
            {'day': '2026-10-26', 'vip_type': 'tvip', 'receive_vip': 1},
            {'day': '2026-10-24', 'vip_type': 'svip', 'receive_vip': 0},
            {'day': '2026-02-31', 'vip_type': 'svip', 'receive_vip': 1},
          ],
        },
      }),
      {'2026-10-25'},
    );
  });

  test(
    'membership parser uses the latest active expiry, not the first reward',
    () {
      final result = VipEntitlement.parse({
        'data': {
          'busi_vip': [
            {
              'product_type': 'tvip',
              'is_vip': 1,
              'vip_end_time': '2026-10-27 14:21:00',
            },
            {
              'product_type': 'tvip',
              'is_vip': 1,
              'vip_end_time': '2027-09-22 00:00:00',
            },
            {
              'product_type': 'svip',
              'is_vip': 0,
              'vip_end_time': '2028-01-01 00:00:00',
            },
          ],
        },
      });
      expect(result.first.expires, DateTime(2027, 9, 22));
      expect(result.last.active, false);
    },
  );

  test(
    'partial read failures preserve availability truth and server date',
    () async {
      final repo = repository(
        (request) async => switch (request.url.path) {
          '/server/now' => {'timestamp': day.millisecondsSinceEpoch ~/ 1000},
          '/youth/month/vip/record' => {'status': 0, 'error_code': 500},
          _ => {
            'status': 1,
            'data': {'busi_vip': []},
          },
        },
      );
      final snapshot = await repo.load(_owner);
      expect(snapshot.now, day);
      expect(snapshot.recordsAvailable, false);
      expect(snapshot.membershipsAvailable, true);
    },
  );
}
