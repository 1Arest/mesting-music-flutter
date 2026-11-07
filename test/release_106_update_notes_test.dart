import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mesting_music/features/app_update/app_update_providers.dart';
import 'package:mesting_music/features/app_update/data/app_update_release_source.dart';
import 'package:mesting_music/features/app_update/data/public_apk_release_notes.dart';
import 'package:mesting_music/features/app_update/domain/app_update_models.dart';
import 'package:mesting_music/features/app_update/presentation/beta_app_update_sheet.dart';
import 'package:mesting_music/features/music_platform/data/platform_effects_repository.dart';

final _release = AppUpdateManifest(
  packageName: 'com.mesting.music.beta',
  versionName: '99.0.1',
  versionCode: 9901,
  minimumVersionCode: 1,
  mandatory: false,
  title: '发现新版本',
  releaseNotes: const ['未来版本的在线更新内容'],
  apkUrl: Uri.parse('https://download.csnas.asia/music/download'),
  sha256: 'a' * 64,
  sizeBytes: 80477,
  downloadEtag: '"fixture"',
  publishedAt: DateTime.utc(2026, 10, 28),
);

class _Update extends AppUpdateController {
  @override
  AppUpdateState build() => AppUpdateState(
    phase: AppUpdatePhase.available,
    currentVersion: const AppVersionInfo(
      packageName: 'com.mesting.music.beta',
      versionName: '1.0.6',
      versionCode: 27,
    ),
    manifest: _release,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(LiquidGlassWidgets.initialize);
  test(
    'official effect icons retain each effect identity even for the same preset',
    () {
      for (final field in ['icon_url', 'model_icon', 'logo']) {
        final effects = List.generate(
          2,
          (i) => MusicSoundEffect.parse({
            'id': i + 1,
            'name': 'HiFi 人声 $i',
            'sound': 'https://fixture.test/effect.irs',
            field: 'https://imge.kugou.com/fixture/official-$i.png',
          })!,
        );
        expect(effects[0].preset, effects[1].preset);
        expect(effects[0].cover, isNot(effects[1].cover));
        expect(
          effects[0].cover,
          'https://imge.kugou.com/fixture/official-0.png',
        );
      }
    },
  );
  final apk = File(
    'test/support/release_notes_apk_fixture.zip',
  ).readAsBytesSync();
  Map<String, Object?> health() => {
    'status': 'ok',
    'app_slug': 'music',
    'version': '99.0.1',
    'android_version_code': 9901,
    'file_size': apk.length,
    'sha256': 'a' * 64,
    'primary_url': _release.apkUrl.toString(),
    'etag': '"fixture"',
  };
  http.Response range(http.Request request, {bool changed = false}) {
    final match = RegExp(
      r'^bytes=(\d+)-(\d+)$',
    ).firstMatch(request.headers['range']!)!;
    final start = int.parse(match[1]!), end = int.parse(match[2]!);
    return http.Response.bytes(
      apk.sublist(start, end + 1),
      206,
      headers: {
        'content-range': 'bytes $start-$end/${apk.length}',
        'etag': changed ? '"different"' : '"fixture"',
      },
    );
  }

  test('unknown future notes are read before downloading the APK', () async {
    var transferred = 0, reads = 0;
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/health')) {
        return http.Response.bytes(utf8.encode(jsonEncode(health())), 200);
      }
      expect(request.headers['if-match'], '"fixture"');
      final response = range(request);
      reads++;
      transferred += response.bodyBytes.length;
      return response;
    });
    final release = await CsnasUpdateReleaseSource(
      client: client,
      packageName: _release.packageName,
    ).latest();
    expect(release.versionName, '99.0.1');
    expect(release.releaseNotes, ['修复未来版本示例问题', '升级前即可阅读的更新说明']);
    expect(reads, 3);
    expect(transferred, lessThan(apk.length));
  });
  test(
    'publisher metadata avoids ZIP requests and unknown notes never inherit current-version notes',
    () async {
      var calls = 0;
      final source = CsnasUpdateReleaseSource(
        client: MockClient((request) async {
          calls++;
          final data = health()..['releaseNotes'] = ['后台提供的新版本说明'];
          return http.Response.bytes(utf8.encode(jsonEncode(data)), 200);
        }),
        packageName: _release.packageName,
      );
      expect((await source.latest()).releaseNotes, ['后台提供的新版本说明']);
      expect(calls, 1);
      expect(PublicApkReleaseNotes.parse(List.filled(51, 'line')), isEmpty);
      expect(PublicApkReleaseNotes.parse(['x' * 1001]), isEmpty);
    },
  );
  test(
    'ignored Range and changed ETag fail closed without blocking update discovery',
    () async {
      for (final ignored in [true, false]) {
        var reads = 0;
        final client = MockClient((request) async {
          if (request.url.path.endsWith('/health')) {
            return http.Response.bytes(utf8.encode(jsonEncode(health())), 200);
          }
          reads++;
          return ignored
              ? http.Response('range ignored', 200)
              : range(request, changed: true);
        });
        final result = await CsnasUpdateReleaseSource(
          client: client,
          packageName: _release.packageName,
        ).latest();
        expect(result.versionCode, 9901);
        expect(result.releaseNotes, isEmpty);
        expect(reads, 1);
      }
    },
  );
  test(
    'notes with a different version identity or damaged ZIP are rejected',
    () async {
      final wrongVersion = health()
        ..['version'] = '99.0.1'
        ..['android_version_code'] = 9902;
      final result = await CsnasUpdateReleaseSource(
        client: MockClient(
          (request) async => request.url.path.endsWith('/health')
              ? http.Response.bytes(utf8.encode(jsonEncode(wrongVersion)), 200)
              : range(request),
        ),
        packageName: _release.packageName,
      ).latest();
      expect(result.releaseNotes, isEmpty);
      final damaged = MockClient((request) async {
        final response = range(request);
        final bytes = response.bodyBytes.toList();
        bytes.fillRange(0, bytes.length, 0);
        return http.Response.bytes(bytes, 206, headers: response.headers);
      });
      expect(
        await PublicApkReleaseNotes(damaged).load(
          AppUpdateManifest(
            packageName: _release.packageName,
            versionName: '99.0.1',
            versionCode: 9901,
            minimumVersionCode: 1,
            mandatory: false,
            title: '更新',
            releaseNotes: const [],
            apkUrl: _release.apkUrl,
            sha256: 'a' * 64,
            sizeBytes: apk.length,
            downloadEtag: '"fixture"',
            publishedAt: DateTime.utc(2026),
          ),
        ),
        isEmpty,
      );
    },
  );
  testWidgets('installed 1.0.6 opens target 99.0.1 notes before installation', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appUpdateControllerProvider.overrideWith(_Update.new)],
        child: LiquidGlassWidgets.wrap(
          adaptiveQuality: false,
          child: const MaterialApp(home: Scaffold(body: BetaAppUpdateSheet())),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('app-update-view-notes')),
    );
    await tester.tap(find.byKey(const ValueKey('app-update-view-notes')));
    await tester.pumpAndSettle();
    expect(find.text('Mesting Music 99.0.1'), findsOneWidget);
    expect(find.text('未来版本的在线更新内容'), findsWidgets);
    expect(find.text('Mesting Music 1.0.6'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
