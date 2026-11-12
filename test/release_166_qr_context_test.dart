import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_api.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_qr_login.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_session.dart';
import 'qishui_qr_protocol_test.dart' show FixtureQrGateway;
import 'qishui_protocol_test.dart' show fixtureJson;

void main() {
  test(
    'a refusal cannot echo this QR nonce or identifiers into the visible error',
    () async {
      final gateway = FixtureQrGateway();
      final login = QishuiQrLogin(gateway);
      await login.start();
      final query = gateway.requests.single.queryParameters;
      final secrets = [
        query['device_id']!,
        query['install_id']!,
        gateway.beginNonce!,
      ];
      gateway.polls.add({
        'error_code': 2156,
        'description': '请求未完成 test=${secrets.join(' ')}',
      });
      try {
        await login.poll();
        fail('A rejected confirmation must not authenticate');
      } on QishuiException catch (error) {
        expect(error.code, '2156');
        for (final value in secrets) {
          expect(error.message, isNot(contains(value)));
        }
      }
      await login.close();
    },
  );

  test(
    'one QR retains its web identity and nonce through confirmation/profile',
    () async {
      final gateway = FixtureQrGateway()
        ..polls.add({'status': 'confirmed', 'error_code': 0});
      final login = QishuiQrLogin(gateway);
      await login.start();
      final state = await login.poll();
      expect(state.phase, QishuiQrPhase.complete);
      expect(gateway.beginNonce, matches(RegExp(r'^[A-Za-z0-9_-]{118}==$')));
      final first = gateway.requests.first.queryParameters;
      for (var i = 0; i < gateway.requests.length; i++) {
        final query = gateway.requests[i].queryParameters;
        expect(query['device_id'], matches(RegExp(r'^\d{16}$')));
        expect(query['install_id'], matches(RegExp(r'^\d{15}$')));
        for (final key in [
          'device_id',
          'install_id',
          'did',
          'iid',
          'msToken',
        ]) {
          expect(query[key], first[key], reason: '$key must belong to one QR');
        }
        expect(query['msToken'], gateway.beginNonce);
        expect(query['request_host'], 'app%3A%2F%2Fresources');
        expect(query['account_sdk_source'], 'web');
        expect(query['account_sdk_source_info'], '00');
        expect(query['is_from_iesaccountsaas'], '1');
        expect(
          query['biz_trace_id'],
          gateway.headersSeen[i]['x-tt-passport-trace-id'],
        );
        final body = gateway.bodies[i];
        if (body != null) {
          expect(
            gateway.headersSeen[i]['x-ss-stub'],
            md5.convert(utf8.encode(body)).toString().toUpperCase(),
          );
        }
      }
      expect(state.session!.webDeviceId, first['device_id']);
      expect(state.session!.webInstallId, first['install_id']);
      await login.close();
    },
  );

  test(
    'regenerating creates an independent web identity rather than reusing a rejected QR',
    () async {
      final one = FixtureQrGateway(), two = FixtureQrGateway();
      final first = QishuiQrLogin(one), second = QishuiQrLogin(two);
      await first.start();
      await first.close();
      await second.start();
      expect(one.beginNonce, isNot(two.beginNonce));
      expect(
        one.requests.first.queryParameters['device_id'],
        isNot(two.requests.first.queryParameters['device_id']),
      );
      await second.close();
    },
  );

  test(
    'official scanner leaves the existing transaction and cookie acceptance unchanged',
    () async {
      final gateway = FixtureQrGateway();
      final login = QishuiQrLogin(gateway);
      expect(await login.openScanner(), false);
      await login.start();
      final url = login.scanUrl;
      expect(await login.openScanner(), true);
      expect(login.scanUrl, url);
      expect(gateway.requests, hasLength(1));
      expect(gateway.authenticated, false);
      expect(gateway.scannerOpens, 1);
      await login.close();
    },
  );

  test(
    'restored web sessions keep their own identifiers across profile refresh',
    () async {
      final gateway = FixtureQrGateway()..polls.add({'status': 'confirmed'});
      final login = QishuiQrLogin(gateway);
      await login.start();
      final accepted = (await login.poll()).session!;
      final restored = QishuiSession.fromJson(
        jsonDecode(jsonEncode(accepted.toJson())) as Map<String, dynamic>,
      );
      final api = QishuiApi(
        MockClient((request) async {
          expect(request.url.host, 'api.qishui.com');
          expect(
            request.url.queryParameters['device_id'],
            accepted.webDeviceId,
          );
          expect(request.url.queryParameters['iid'], accepted.webInstallId);
          return fixtureJson({
            'my_info': {'id': accepted.userId},
          });
        }),
        context: () async =>
            throw StateError('Web restore must not register a mobile identity'),
      );
      api.configure(restored.withProfile(name: 'refreshed'));
      await api.request('/luna/me', get: true);
      expect(api.snapshot(accepted.userId).webDeviceId, accepted.webDeviceId);
      api.dispose();
      await login.close();
    },
  );
}
