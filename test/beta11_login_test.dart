import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesting_music/features/music_platform/data/embedded_music_server.dart';
import 'package:mesting_music/features/music_platform/data/music_platform_api.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';

class _Server implements MusicServer {
  @override
  Future<Uri> start() async => Uri.parse('http://127.0.0.1:12345');
}

void main() {
  test(
    'SMS registers the signing device first, sends once and preserves business rejection',
    () async {
      final paths = <String>[];
      final api = MusicPlatformApi(
        server: _Server(),
        client: MockClient((r) async {
          paths.add(r.url.path);
          if (r.url.path == '/register/dev') {
            return http.Response(
              jsonEncode({
                'status': 1,
                'data': {'dfid': 'real-device'},
              }),
              200,
            );
          }
          expect(r.url.queryParameters['dfid'], 'real-device');
          return http.Response(
            jsonEncode({'status': 0, 'error_code': 20015}),
            502,
          );
        }),
      );
      await expectLater(
        PlatformLoginService(api).sendCode('13800138000'),
        throwsA(
          isA<MusicPlatformException>().having((e) => e.code, 'code', '20015'),
        ),
      );
      expect(paths, ['/register/dev', '/captcha/sent']);
    },
  );
  test(
    'SMS success requires actual confirmation and initialization is reused',
    () async {
      var registrations = 0, sends = 0;
      final api = MusicPlatformApi(
        server: _Server(),
        client: MockClient((r) async {
          if (r.url.path == '/register/dev') {
            registrations++;
            return http.Response('{"status":1,"data":{"dfid":"device"}}', 200);
          }
          sends++;
          return http.Response('{"status":1}', 200);
        }),
      );
      final service = PlatformLoginService(api);
      await service.sendCode('13800138000');
      await service.sendCode('13800138000');
      expect(registrations, 1);
      expect(sends, 2);
      await expectLater(
        service.sendCode('invalid'),
        throwsA(isA<MusicPlatformException>()),
      );
      expect(sends, 2);
    },
  );
}
