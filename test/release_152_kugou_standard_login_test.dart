import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesting_music/features/music_platform/data/kugou_standard_login.dart';

const _device = {
  'mid': 'fixture-mid',
  'uuid': 'fixture-uuid',
  'dfid': 'fixture-dfid',
};

final _clock = DateTime.fromMillisecondsSinceEpoch(1793772345678);

http.Response _json(Object value) => http.Response(
  jsonEncode(value),
  200,
  headers: {'content-type': 'application/json'},
);

http.Response _created([String code = 'fixture-qr']) => _json({
  'error_code': 0,
  'data': {'qrcode': code},
});

http.Response _confirmed() => _json({
  'error_code': 0,
  'data': {
    'status': 4,
    'userid': 42,
    'token': 'fixture-issued-standard-token',
    'nickname': '二维码账号',
    'pic': 'https://imge.kugou.com/fixture.jpg',
  },
});

Map<String, Object> _validGrade({int uid = 42}) => {
  'status': 1,
  'data': {
    'userid': uid,
    'd_sec': 125,
    'p_grade': 1,
    'p_grade_point': 0,
    'p_next_grade': 2,
    'p_next_grade_point': 1000,
    'p_current_point': 10,
  },
};

KugouStandardLoginService _service(
  http.Client client, {
  bool Function()? current,
  DateTime Function()? clock,
}) => KugouStandardLoginService(
  client: client,
  device: () async => _device,
  current: current ?? () => true,
  clock: clock ?? () => _clock,
);

Matcher _failure(String message) => isA<KugouStandardLoginException>().having(
  (failure) => failure.message,
  'readable error',
  contains(message),
);

void main() {
  test(
    'standard QR signs exact native create/poll parameters and proves v4',
    () async {
      final requests = <http.Request>[];
      final service = _service(
        MockClient((request) async {
          requests.add(request);
          if (request.url.path == '/v2/qrcode') {
            return _created('fixture-qr+/?&');
          }
          if (request.url.path == '/v2/get_userinfo_qrcode') {
            return _confirmed();
          }
          return _json(_validGrade());
        }),
      );
      final challenge = await service.createQr();
      expect(Uri.parse(challenge.qrcodeData).queryParameters, {
        'qrcode': 'fixture-qr+/?&',
        'appid': '1005',
      });
      expect(challenge.expiresAt, _clock.add(const Duration(minutes: 5)));
      final result = await service.poll(challenge);
      expect(result?['userid'], '42');
      expect(result?['token'], 'fixture-issued-standard-token');
      expect(result?['mesting_kugou_appid'], 1005);
      expect(result?['avatar'], 'https://imge.kugou.com/fixture.jpg');
      expect(requests, hasLength(3));
      expect(requests[0].method, 'GET');
      expect(requests[1].method, 'GET');
      expect(requests[0].url.host, 'login-user.kugou.com');
      final createQuery = requests[0].url.queryParameters;
      expect(createQuery['type'], '1');
      expect(createQuery['plat'], '1');
      expect(createQuery['appid'], '1005');
      expect(createQuery['clientver'], '20869');
      expect(createQuery['clienttime'], '1793772345');
      expect(createQuery.containsKey('srcappid'), isFalse);
      expect(createQuery.containsKey('qrcode_txt'), isFalse);
      expect(requests[1].url.queryParameters['plat'], '1');
      expect(requests[1].url.queryParameters['qrcode'], 'fixture-qr+/?&');
      for (final request in requests) {
        final query = Map<String, String>.from(request.url.queryParameters);
        final signature = query.remove('signature');
        final keys = query.keys.toList()..sort();
        final pairs = keys.map((key) => '$key=${query[key]}').join();
        const appKey = 'OIlwieks28dk2k092lksi2UIkp';
        expect(
          signature,
          md5
              .convert(utf8.encode('$appKey$pairs${request.body}$appKey'))
              .toString(),
        );
        expect(request.followRedirects, isFalse);
        expect(request.url.scheme, 'https');
      }
      expect(requests[2].url.host, 'userinfoservice.kugou.com');
      expect(requests[2].url.path, '/v4/get_grade_info');
      final proof = jsonDecode(requests[2].body) as Map;
      expect(proof['d_sec'], 0);
      expect(proof['diff_sec'], 0);
      expect(proof['medal'], 0);
      expect(
        requests[2].body,
        isNot(contains('fixture-issued-standard-token')),
      );
      await expectLater(service.poll(challenge), throwsA(_failure('失效')));
    },
  );

  test(
    'waiting and scanned states do not save or verify any credential',
    () async {
      var count = 0;
      final service = _service(
        MockClient((request) async {
          if (request.url.path == '/v2/qrcode') return _created();
          count++;
          return _json({
            'error_code': 0,
            'data': {'status': count},
          });
        }),
      );
      final challenge = await service.createQr();
      expect(await service.poll(challenge), isNull);
      expect(await service.poll(challenge), isNull);
      expect(count, 2);
    },
  );

  test(
    'wrong-account or incomplete v4 proof consumes the temporary challenge',
    () async {
      for (final proof in [
        _validGrade(uid: 99),
        {
          'status': 1,
          'data': {'userid': 42, 'd_sec': 0, 'p_grade': 1},
        },
        {
          'status': 0,
          'error_code': 20018,
          'errmsg': 'fixture-issued-standard-token',
        },
      ]) {
        final service = _service(
          MockClient((request) async {
            if (request.url.path == '/v2/qrcode') return _created();
            if (request.url.path == '/v2/get_userinfo_qrcode') {
              return _confirmed();
            }
            return _json(proof);
          }),
        );
        final challenge = await service.createQr();
        await expectLater(service.poll(challenge), throwsA(_failure('验证未通过')));
        await expectLater(service.poll(challenge), throwsA(_failure('失效')));
      }
    },
  );

  test(
    'expired challenges cannot send a request or be extended by polling',
    () async {
      var now = _clock;
      var count = 0;
      final service = _service(
        MockClient((_) async {
          count++;
          return _created();
        }),
        clock: () => now,
      );
      final challenge = await service.createQr();
      now = now.add(const Duration(minutes: 5));
      await expectLater(service.poll(challenge), throwsA(_failure('过期')));
      expect(count, 1);
    },
  );

  test(
    'new challenges invalidate old ones and cannot cross service instances',
    () async {
      final client = MockClient((_) async => _created());
      final service = _service(client);
      final old = await service.createQr();
      await service.createQr();
      await expectLater(service.poll(old), throwsA(_failure('失效')));
      await expectLater(_service(client).poll(old), throwsA(_failure('失效')));
    },
  );

  test(
    'an account change discards a late confirmed response before v4 proof',
    () async {
      var current = true;
      final pending = Completer<http.Response>();
      var count = 0;
      final service = _service(
        MockClient((request) async {
          count++;
          if (request.url.path == '/v2/qrcode') return _created();
          return pending.future;
        }),
        current: () => current,
      );
      final challenge = await service.createQr();
      final result = service.poll(challenge);
      current = false;
      pending.complete(_confirmed());
      await expectLater(result, throwsA(_failure('账号已切换')));
      expect(count, 2);
    },
  );

  test(
    'redirects and raw server failures never leak challenge or token',
    () async {
      for (final response in [
        http.Response(
          '',
          302,
          headers: {'location': 'https://external.invalid/?token=secret'},
        ),
        _json({'error_code': 1, 'errmsg': 'secret-token-and-qr'}),
        http.Response('invalid json secret-token-and-qr', 200),
      ]) {
        var count = 0;
        final service = _service(
          MockClient((_) async {
            count++;
            return response;
          }),
        );
        await expectLater(
          service.createQr(),
          throwsA(
            isA<KugouStandardLoginException>().having(
              (error) => error.toString(),
              'redacted',
              isNot(contains('secret')),
            ),
          ),
        );
        expect(count, 1);
      }
    },
  );

  test(
    'cancelled owner and unregistered devices cannot create authorization',
    () async {
      var requests = 0;
      final client = MockClient((_) async {
        requests++;
        return _created();
      });
      await expectLater(
        _service(client, current: () => false).createQr(),
        throwsA(_failure('账号已切换')),
      );
      final service = KugouStandardLoginService(
        client: client,
        device: () async => {..._device, 'dfid': '-'},
        current: () => true,
        clock: () => _clock,
      );
      await expectLater(service.createQr(), throwsA(_failure('设备注册未完成')));
      expect(requests, 0);
    },
  );
}
