import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesting_music/core/platform/distribution_channel.dart';
import 'package:mesting_music/features/app_update/data/app_update_platform.dart';
import 'package:mesting_music/features/app_update/data/app_update_repository.dart';
import 'package:mesting_music/features/app_update/domain/app_update_models.dart';

/// The existing native/UI flavor now installs under the public package.
/// An old .beta package manifest must still be rejected, not cross-installed.
class _BetaUpdatePlatform extends AppUpdatePlatform {
  @override
  Future<AppVersionInfo> currentVersion() async => const AppVersionInfo(
    packageName: 'com.mesting.music',
    versionName: '1.0.50',
    versionCode: 71,
  );
}

void main() {
  test(
    'current flavor keeps its feed and rejects the old Beta package manifest',
    () async {
      Uri? requestedUrl;
      final client = MockClient((request) async {
        requestedUrl = request.url;
        return http.Response(
          jsonEncode({
            'packageName': 'com.mesting.music.beta',
            'versionName': '1.0.51',
            'versionCode': 72,
            'title': 'Old package accidentally in current feed',
            'releaseNotes': ['Must never change installation package'],
            'apkUrl': 'https://updates.example.com/formal.apk',
            'sha256': List.filled(64, '0').join(),
            'sizeBytes': 100,
            'publishedAt': '2026-10-25T00:00:00Z',
          }),
          200,
        );
      });
      addTearDown(client.close);
      final repository = AppUpdateRepository(
        client: client,
        platform: _BetaUpdatePlatform(),
      );

      await expectLater(
        repository.check(),
        throwsA(
          isA<AppUpdateException>().having(
            (error) => error.code,
            'code',
            'package',
          ),
        ),
      );
      expect(requestedUrl?.path, '/releases/android/beta/latest.json');
      expect(requestedUrl?.queryParameters.containsKey('t'), true);
    },
    skip: !DistributionChannel.isBeta,
  );
}
