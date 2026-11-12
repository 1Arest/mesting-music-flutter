import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesting_music/core/platform/distribution_channel.dart';
import 'package:mesting_music/features/app_update/data/app_update_platform.dart';
import 'package:mesting_music/features/app_update/data/app_update_repository.dart';
import 'package:mesting_music/features/app_update/domain/app_update_models.dart';

class _PublicPackage150 extends AppUpdatePlatform {
  @override
  Future<AppVersionInfo> currentVersion() async => const AppVersionInfo(
    packageName: 'com.mesting.music',
    versionName: '1.0.50',
    versionCode: 71,
  );
}

void main() {
  test(
    'public installation identity keeps current UI/native flavor and existing feed',
    () {
      expect(DistributionChannel.packageName, 'com.mesting.music');
      expect(DistributionChannel.isBeta, true);
      expect(
        Uri.parse(DistributionChannel.updateManifestUrl).path,
        '/releases/android/beta/latest.json',
      );
    },
  );
  for (final old in [false, true]) {
    test(
      'new package update ${old ? 'rejects old Beta APK identity' : 'accepts only matching future APK identity'}',
      () async {
        final client = MockClient(
          (_) async => http.Response(
            jsonEncode({
              'packageName': old
                  ? 'com.mesting.music.beta'
                  : 'com.mesting.music',
              'versionName': '1.0.51',
              'versionCode': 72,
              'title': 'Future update',
              'releaseNotes': ['Fixture'],
              'apkUrl': 'https://updates.example.com/future.apk',
              'sha256': List.filled(64, '0').join(),
              'sizeBytes': 100,
              'publishedAt': '2026-11-04T00:00:00Z',
            }),
            200,
          ),
        );
        addTearDown(client.close);
        final repository = AppUpdateRepository(
          client: client,
          platform: _PublicPackage150(),
        );
        if (old) {
          await expectLater(
            repository.check(),
            throwsA(
              isA<AppUpdateException>().having(
                (e) => e.code,
                'code',
                'package',
              ),
            ),
          );
        } else {
          expect(await repository.check(), isNotNull);
        }
      },
    );
  }
}
