import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesting_music/features/auth/domain/auth_models.dart';
import 'package:mesting_music/features/profile/data/profile_background_sync_api.dart';

void main() {
  test(
    'profile background cloud API loads and saves account metadata',
    () async {
      final actions = <Map<String, Object?>>[];
      final api = CloudBaseProfileBackgroundSyncApi(
        environmentId: 'music-env',
        sessionProvider: () => AuthSession(
          user: const AuthUser(uid: 'user-1', nickname: 'Mest'),
          accessToken: 'background-access-token',
          refreshToken: 'background-refresh-token',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        ),
        client: MockClient((request) async {
          expect(request.url.path, '/v1/functions/social-api');
          expect(request.url.queryParameters['webfn'], 'true');
          expect(
            request.headers['authorization'],
            'Bearer background-access-token',
          );
          final body = Map<String, Object?>.from(
            jsonDecode(request.body) as Map,
          );
          actions.add(body);
          final preset = body['action'] == 'setProfileBackground'
              ? body['value']
              : 'midnight';
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'success': true,
                'data': {
                  'profile_background': {
                    'kind': 'preset',
                    'value': preset,
                    'download_url': null,
                  },
                },
              }),
            ),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );

      final loaded = await api.load();
      final saved = await api.savePreset('aurora');

      expect(loaded?.value, 'midnight');
      expect(saved.value, 'aurora');
      expect(actions.map((item) => item['action']), [
        'getProfileBackground',
        'setProfileBackground',
      ]);
    },
  );
}
