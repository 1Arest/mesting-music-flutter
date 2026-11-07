import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_api.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_auth_errors.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_login.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_qr_login.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_session.dart';
import 'qishui_protocol_test.dart' show fixtureJson, sodaSession;

class FixtureQrGateway implements QishuiQrGateway {
  final requests = <Uri>[];
  final bodies = <String?>[];
  final polls = <Map<String, dynamic>>[];
  bool authenticated = false,
      stale = false,
      wrongDomain = false,
      missingCookie = false;
  int closes = 0, verifications = 0;
  String scanUrl =
      'https://sso.douyin.com/ucenter_web/app/sdk-next?token=fixture-qr&uc_sdk=scan-auth&next=%2F';
  Map<String, dynamic> profile = {
    'my_info': {'id': 'fixture-qr-user', 'nickname': '测试汽水账号'},
  };
  Completer<void>? beginGate, profileGate, pollGate;
  @override
  Future<void> begin(String flowId) async {
    await beginGate?.future;
  }

  @override
  Future<Map<String, dynamic>> request(
    String flowId,
    String method,
    Uri uri,
    Map<String, String> headers,
    String? body,
  ) async {
    requests.add(uri);
    bodies.add(body);
    if (uri.path.endsWith('get_qrcode/')) {
      return {
        'message': 'success',
        'data': {
          'error_code': 0,
          'token': 'fixture-qr',
          'qrcode_index_url': scanUrl,
        },
      };
    }
    if (uri.path.endsWith('check_qrconnect/')) {
      await pollGate?.future;
      final value = polls.isEmpty
          ? <String, dynamic>{'status': 'new', 'error_code': 0}
          : polls.removeAt(0);
      if (!missingCookie &&
          {'confirmed', '3', 'success'}.contains('${value['status']}')) {
        authenticated = true;
      }
      return {'message': 'success', 'data': value};
    }
    if (uri.path == '/luna/pc/me') {
      await profileGate?.future;
      return profile;
    }
    if (uri.path.contains('sso')) {
      authenticated = true;
      return {};
    }
    throw StateError('Unexpected endpoint in fixture');
  }

  @override
  Future<List<Map<String, String>>> cookies(String flowId) async =>
      authenticated || stale
      ? [
          {
            'name': 'sessionid',
            'value': 'fixture-private-session',
            'domain': wrongDomain ? 'beta-luna.douyin.com' : 'api.qishui.com',
            'path': '/',
            'secure': 'true',
            'hostOnly': 'true',
          },
        ]
      : [];
  @override
  Future<bool> verify(
    String flowId,
    Map<String, dynamic> decision,
    Map<String, String> params,
  ) async {
    verifications++;
    return true;
  }

  @override
  Future<void> close(String flowId) async {
    closes++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'confirmed cookie cannot authenticate a zero/guest profile identity',
    () async {
      final gateway = FixtureQrGateway()
        ..profile = {
          'my_info': {'id': 0},
        }
        ..polls.add({'status': 'confirmed', 'error_code': 0});
      final login = QishuiQrLogin(gateway);
      await login.start();
      await expectLater(login.poll(), throwsA(isA<QishuiException>()));
      await login.close();
    },
  );
  test(
    'SMS refusal surfaces sanitized service detail without resending or replacing the old account',
    () async {
      var sends = 0;
      final api = QishuiApi(
        MockClient((request) async {
          sends++;
          return fixtureJson({
            'message': 'error',
            'data': {
              'error_code': 2156,
              'description':
                  '参数错误 mobile=13800000000 code=123456 https://example.test/?token=private',
            },
          });
        }),
        context: () async => {},
      );
      final previous = sodaSession();
      api.configure(previous);
      final login = QishuiLogin(api);
      await expectLater(
        login.sendCode('+86', '13800000000'),
        throwsA(
          isA<QishuiException>()
              .having((e) => e.code, 'code', '2156')
              .having((e) => e.message, 'detail', contains('参数错误'))
              .having(
                (e) => e.message,
                'redacted',
                allOf(
                  isNot(contains('13800000000')),
                  isNot(contains('123456')),
                  isNot(contains('example.test')),
                ),
              ),
        ),
      );
      await expectLater(
        login.login('+86', '13800000000', '123456'),
        throwsA(isA<QishuiException>()),
      );
      expect(sends, 1);
      expect(identical(api.session, previous), true);
      login.dispose();
      api.dispose();
    },
  );
  test(
    'QR preserves the exact official URL and creates no mobile installation identity',
    () async {
      final gateway = FixtureQrGateway();
      final login = QishuiQrLogin(gateway);
      await login.start();
      expect(login.scanUrl, gateway.scanUrl);
      expect(gateway.requests.single.host, 'api.qishui.com');
      final query = gateway.requests.single.queryParameters;
      expect(query['aid'], '386088');
      for (final field in ['iid', 'device_id', 'install_id', 'did']) {
        expect(query.containsKey(field), false);
      }
      await login.close();
    },
  );
  test('scanned is not authenticated even if cookies are present', () async {
    final gateway = FixtureQrGateway();
    final login = QishuiQrLogin(gateway);
    await login.start();
    gateway.authenticated = true;
    gateway.polls.add({'status': 'scanned', 'error_code': 0});
    final state = await login.poll();
    expect(state.phase, QishuiQrPhase.scanned);
    expect(state.session, isNull);
    expect(gateway.requests.any((u) => u.path == '/luna/pc/me'), false);
    await login.close();
  });
  test(
    'confirmed requires fresh cookies plus authenticated Luna profile',
    () async {
      final gateway = FixtureQrGateway()
        ..polls.add({'status': 'confirmed', 'error_code': 0});
      final login = QishuiQrLogin(gateway);
      await login.start();
      final state = await login.poll();
      expect(state.phase, QishuiQrPhase.complete);
      expect(state.session!.userId, 'fixture-qr-user');
      expect(state.session!.protocol, QishuiSessionProtocol.web);
      expect(state.session!.cookies.single['domain'], 'api.qishui.com');
      await login.close();
    },
  );
  test('stale cookie jar cannot start a new login', () async {
    final gateway = FixtureQrGateway()..stale = true;
    final login = QishuiQrLogin(gateway);
    await expectLater(login.start(), throwsA(isA<QishuiException>()));
    expect(gateway.requests, isEmpty);
    await login.close();
  });
  test('mobile-domain credentials cannot become a web QR session', () async {
    final gateway = FixtureQrGateway()
      ..wrongDomain = true
      ..polls.add({'status': 'confirmed', 'error_code': 0});
    final login = QishuiQrLogin(gateway);
    await login.start();
    await expectLater(login.poll(), throwsA(isA<QishuiException>()));
    await login.close();
  });
  test('unknown status never becomes success from a residual cookie', () async {
    final gateway = FixtureQrGateway();
    final login = QishuiQrLogin(gateway);
    await login.start();
    gateway.authenticated = true;
    gateway.polls.add({'status': 'unexpected', 'error_code': 0});
    await expectLater(login.poll(), throwsA(isA<QishuiException>()));
    await login.close();
  });
  test('cookie without a profile identity is rejected', () async {
    final gateway = FixtureQrGateway()
      ..profile = {'data': {}}
      ..polls.add({'status': 'confirmed', 'error_code': 0});
    final login = QishuiQrLogin(gateway);
    await login.start();
    await expectLater(login.poll(), throwsA(isA<QishuiException>()));
    await login.close();
  });
  test('rate limit cools down instead of making repeated requests', () async {
    var time = DateTime.utc(2026, 11, 6);
    final gateway = FixtureQrGateway()..polls.add({'error_code': 7});
    final login = QishuiQrLogin(gateway, now: () => time);
    await login.start();
    expect((await login.poll()).phase, QishuiQrPhase.rateLimited);
    await login.poll();
    time = time.add(const Duration(seconds: 3));
    await login.poll();
    expect(gateway.requests, hasLength(2));
    time = time.add(const Duration(seconds: 2));
    expect((await login.poll()).phase, QishuiQrPhase.waiting);
    expect(gateway.requests, hasLength(3));
    await login.close();
  });
  test('expired QR stops querying upstream', () async {
    var time = DateTime.utc(2026, 11, 6);
    final gateway = FixtureQrGateway();
    final login = QishuiQrLogin(gateway, now: () => time);
    await login.start();
    time = time.add(const Duration(minutes: 4));
    expect((await login.poll()).phase, QishuiQrPhase.expired);
    expect(gateway.requests, hasLength(1));
    await login.close();
  });
  test(
    'MFA is user initiated and confirmation carries original biz_params',
    () async {
      final gateway = FixtureQrGateway()
        ..polls.addAll([
          {
            'error_code': 2046,
            'biz_params': '{"decision_key":"fixture-decision"}',
          },
          {'error_code': 0, 'status': 'confirmed'},
        ]);
      final login = QishuiQrLogin(gateway);
      await login.start();
      expect((await login.poll()).phase, QishuiQrPhase.verificationRequired);
      await login.poll();
      expect(gateway.verifications, 0);
      expect(gateway.requests, hasLength(2));
      expect((await login.verify()).phase, QishuiQrPhase.complete);
      expect(gateway.verifications, 1);
      expect(gateway.requests[2].queryParameters['isResend'], 'true');
      expect(
        Uri.splitQueryString(gateway.bodies[2]!)['decision_key'],
        'fixture-decision',
      );
      expect(gateway.requests.any((u) => u.path.contains('send_code')), false);
      await login.close();
    },
  );
  test('untrusted post-confirmation redirect is never requested', () async {
    final gateway = FixtureQrGateway()
      ..missingCookie = true
      ..polls.add({
        'error_code': 0,
        'status': 'confirmed',
        'redirect_url': 'https://example.test/passport/sso/login/',
      });
    final login = QishuiQrLogin(gateway);
    await login.start();
    await expectLater(login.poll(), throwsA(isA<QishuiException>()));
    expect(gateway.requests, hasLength(2));
    await login.close();
  });
  test('trusted redirect must lead to actual authenticated profile', () async {
    final gateway = FixtureQrGateway()
      ..missingCookie = true
      ..polls.add({
        'error_code': 0,
        'status': 'confirmed',
        'redirect_url':
            'https://api.qishui.com/passport/sso/login/?ticket=fixture',
      });
    final login = QishuiQrLogin(gateway);
    await login.start();
    expect((await login.poll()).session?.userId, 'fixture-qr-user');
    await login.close();
  });
  test('leaving during profile read rejects the late login result', () async {
    final gate = Completer<void>();
    final gateway = FixtureQrGateway()
      ..profileGate = gate
      ..polls.add({'error_code': 0, 'status': 'confirmed'});
    final login = QishuiQrLogin(gateway);
    await login.start();
    final pending = login.poll();
    final expectation = expectLater(pending, throwsA(isA<QishuiException>()));
    await Future<void>.delayed(Duration.zero);
    await login.close();
    gate.complete();
    await expectation;
    expect(gateway.closes, 1);
    await login.close();
    expect(gateway.closes, 1);
  });
  test('concurrent polls are coalesced inside the QR transaction', () async {
    final gate = Completer<void>();
    final gateway = FixtureQrGateway()..pollGate = gate;
    final login = QishuiQrLogin(gateway);
    await login.start();
    final first = login.poll();
    await login.poll();
    expect(gateway.requests, hasLength(2));
    gate.complete();
    await first;
    await login.close();
  });
  test(
    'QR URLs reject lookalike domains, userinfo, plain HTTP and foreign ports',
    () {
      for (final url in [
        'https://sso.douyin.com.evil.test/x?token=a',
        'https://u:p@sso.douyin.com/x?token=a',
        'http://sso.douyin.com/x?token=a',
        'https://sso.douyin.com:444/x?token=a',
      ]) {
        expect(QishuiQrLogin.trustedScanUrl(url), false);
      }
    },
  );
  test('SMS business details remove phone OTP mixed secrets URLs and tokens', () {
    final text = qishuiAuthDetail(
      '参数错误 +8613800000000 验证码:123456 mobile=fixture-value https://api.qishui.com/?token=secret abcdefghijklmnop 343736313033',
      secrets: ['343736313033'],
    );
    for (final secret in [
      '13800000000',
      '123456',
      'fixture-value',
      'api.qishui.com',
      'abcdefghijklmnop',
      '343736313033',
    ]) {
      expect(text.contains(secret), false);
    }
    expect(text.contains('参数错误'), true);
    expect(text.length, lessThan(180));
    expect(qishuiAuthDetail({'raw': 'not a string'}), '');
  });
  test(
    'legacy encrypted sessions restore as mobile; web scope survives roundtrip',
    () {
      final legacy = sodaSession().toJson()..remove('protocol');
      expect(
        QishuiSession.fromJson(legacy).protocol,
        QishuiSessionProtocol.mobile,
      );
      final web = QishuiSession(
        userId: 'fixture',
        cookies: [
          {'name': 'sessionid', 'value': 'private', 'domain': 'api.qishui.com'},
        ],
        protocol: QishuiSessionProtocol.web,
      );
      expect(
        QishuiSession.fromJson(
          web.toJson(),
        ).withProfile(name: 'updated').protocol,
        QishuiSessionProtocol.web,
      );
      expect(
        () => QishuiSession.fromJson({...web.toJson(), 'protocol': 'unknown'}),
        throwsFormatException,
      );
    },
  );
  test(
    'web account reads stay on web host without mobile context or credential transplantation',
    () async {
      final requests = <Uri>[];
      final api = QishuiApi(
        MockClient((r) async {
          requests.add(r.url);
          expect(r.headers['cookie'], 'sessionid=fixture-web');
          expect(r.url.queryParameters['aid'], '386088');
          return fixtureJson({
            'my_info': {'id': 'fixture'},
          });
        }),
        context: () async =>
            throw StateError('Mobile context must not be used'),
      );
      api.configure(
        QishuiSession(
          userId: 'fixture',
          protocol: QishuiSessionProtocol.web,
          cookies: [
            {
              'name': 'sessionid',
              'value': 'fixture-web',
              'domain': 'api.qishui.com',
              'path': '/',
              'hostOnly': 'true',
              'secure': 'true',
            },
          ],
        ),
      );
      await api.request('/luna/me', get: true);
      await api.request(
        '/luna/me/playlist/v2',
        body: {'cursor': '0', 'count': 50},
      );
      expect(requests.map((u) => u.host).toSet(), {'api.qishui.com'});
      expect(requests.last.path, '/luna/pc/me/playlist');
      expect(requests.last.queryParameters['count'], '50');
      await expectLater(
        api.request('/luna/me/collection/media', write: true),
        throwsA(isA<QishuiException>()),
      );
      await expectLater(
        api.request('/luna/commerce/v2/check_download'),
        throwsA(isA<QishuiException>()),
      );
      expect(requests, hasLength(2));
      api.dispose();
    },
  );
  test(
    'native transport suppresses raw platform exceptions containing credentials',
    () async {
      const channel = MethodChannel('com.mesting.music/qishui_web_auth');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (call) async => throw PlatformException(
              code: 'other',
              message: 'sessionid=must-not-escape',
            ),
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      await expectLater(
        const AndroidQishuiQrGateway().begin('a' * 32),
        throwsA(
          isA<QishuiException>().having(
            (e) => e.message,
            'message',
            isNot(contains('must-not-escape')),
          ),
        ),
      );
    },
  );
  test(
    'biz_params retain encoded values and refuse invalid nested formats',
    () {
      expect(QishuiQrLogin.bizParams('key=a%2Bb&other=%26'), {
        'key': 'a+b',
        'other': '&',
      });
      expect(QishuiQrLogin.bizParams({'x': true, 'n': null}), {'x': 'true'});
      expect(QishuiQrLogin.bizParams(['not-an-object']), isEmpty);
    },
  );
}
