import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mesting_music/features/app_update/app_update_providers.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesting_music/features/app_update/data/app_update_release_source.dart';
import 'package:mesting_music/features/app_update/data/app_update_repository.dart';
import 'package:mesting_music/features/app_update/data/app_update_platform.dart';
import 'package:mesting_music/features/app_update/domain/app_update_models.dart';

final _package = AppUpdateRepository.expectedPackageName;

class _Platform extends AppUpdatePlatform {
  @override
  Future<AppVersionInfo> currentVersion() async => AppVersionInfo(
    packageName: _package,
    versionName: '1.0.37-beta.21',
    versionCode: 21,
  );
}

class _InstallPlatform extends _Platform {
  final started = Completer<void>();
  final installer = Completer<void>();
  int calls = 0;
  @override
  Future<bool> canRequestPackageInstalls() async => true;
  @override
  Future<void> installApk(String path) async {
    calls++;
    if (!started.isCompleted) started.complete();
    await installer.future;
  }
}

Map<String, Object?> _health({int code = 22}) => {
  'status': 'ok',
  'app_slug': 'music',
  'version': '1.0.1',
  'android_version_code': code,
  'file_size': 4,
  'sha256': sha256.convert([1, 2, 3, 4]).toString(),
  'primary_url': 'https://download.csnas.asia/music/download',
  'backup_url': 'https://download1.csnas.asia/music/download?direct=backup',
  'etag': '"same-file"',
  'release_created_at': '2026-10-27T06:00:00Z',
};
Future<AppUpdateManifest> _release(http.Client client, {int code = 22}) async =>
    CsnasUpdateReleaseSource(
      client: MockClient(
        (_) async => http.Response(jsonEncode(_health(code: code)), 200),
      ),
      packageName: _package,
    ).latest();

void main() {
  test(
    'unavailable update storage is recoverable and releases the owner',
    () async {
      final platform = _InstallPlatform()..installer.complete();
      final client = MockClient(
        (_) async => http.Response.bytes([1, 2, 3, 4], 200),
      );
      final dir = await Directory.systemTemp.createTemp('mesting_csnas_');
      addTearDown(() => dir.delete(recursive: true));
      var storageUnavailable = false;
      final repository = AppUpdateRepository(
        client: client,
        platform: platform,
        directoryProvider: () async {
          if (storageUnavailable) throw const FileSystemException('fixture');
          return dir;
        },
        releaseSource: CsnasUpdateReleaseSource(
          client: MockClient(
            (_) async => http.Response(jsonEncode(_health()), 200),
          ),
          packageName: _package,
        ),
      );
      final container = ProviderContainer(
        overrides: [appUpdateRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      final controller = container.read(appUpdateControllerProvider.notifier);
      await controller.check(manual: true);
      storageUnavailable = true;
      await controller.downloadAndInstall();
      expect(
        container.read(appUpdateControllerProvider).phase,
        AppUpdatePhase.failed,
      );
      expect(platform.calls, 0);
      storageUnavailable = false;
      await controller.downloadAndInstall();
      expect(
        container.read(appUpdateControllerProvider).phase,
        AppUpdatePhase.installLaunched,
      );
      expect(platform.calls, 1);
    },
  );
  test(
    'repeated download/install actions share one owner and one installer intent',
    () async {
      final platform = _InstallPlatform();
      final client = MockClient(
        (_) async => http.Response.bytes([1, 2, 3, 4], 200),
      );
      final dir = await Directory.systemTemp.createTemp('mesting_csnas_');
      addTearDown(() => dir.delete(recursive: true));
      final repository = AppUpdateRepository(
        client: client,
        platform: platform,
        directoryProvider: () async => dir,
        releaseSource: CsnasUpdateReleaseSource(
          client: MockClient(
            (_) async => http.Response(jsonEncode(_health()), 200),
          ),
          packageName: _package,
        ),
      );
      final container = ProviderContainer(
        overrides: [appUpdateRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      final controller = container.read(appUpdateControllerProvider.notifier);
      await controller.check(manual: true);
      final first = controller.downloadAndInstall();
      final second = controller.downloadAndInstall();
      await platform.started.future;
      await controller.continueInstall();
      expect(platform.calls, 1);
      platform.installer.complete();
      await Future.wait([first, second]);
      expect(
        container.read(appUpdateControllerProvider).phase,
        AppUpdatePhase.installLaunched,
      );
    },
  );
  test(
    'public metadata orders real APK build codes across the public-name migration',
    () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode(_health(code: 20)..['version'] = '1.0.0'),
          200,
        ),
      );
      final dir = await Directory.systemTemp.createTemp('mesting_csnas_');
      addTearDown(() => dir.delete(recursive: true));
      final repository = AppUpdateRepository(
        client: client,
        platform: _Platform(),
        directoryProvider: () async => dir,
        releaseSource: CsnasUpdateReleaseSource(
          client: client,
          packageName: _package,
        ),
      );
      expect((await repository.check()).updateAvailable, false);
      final newer = await _release(client);
      expect(newer.isNewerThan(await _Platform().currentVersion()), true);
      expect(newer.versionName, '1.0.1');
      expect(newer.releaseNotes, isNotEmpty); // Exact known release has bundled notes.
      expect(newer.mandatory, false);
    },
  );

  test(
    'missing build/foreign slug/foreign URL/invalid SHA are rejected before download',
    () async {
      for (final mutate in <void Function(Map<String, Object?>)>[
        (m) => m.remove('android_version_code'),
        (m) => m['app_slug'] = 'other',
        (m) => m['primary_url'] =
            'https://download.csnas.asia.evil.test/music/download',
        (m) => m['backup_url'] = 'https://download1.csnas.asia/other/download',
        (m) => m['sha256'] = 'not-a-sha',
        (m) => m['etag'] = 'bad\r\nheader',
      ]) {
        final json = _health();
        mutate(json);
        final source = CsnasUpdateReleaseSource(
          client: MockClient((_) async => http.Response(jsonEncode(json), 200)),
          packageName: _package,
        );
        await expectLater(source.latest(), throwsA(isA<AppUpdateException>()));
      }
    },
  );

  test(
    'one bounded HTTPS mirror attempt uses the same verified release',
    () async {
      final hosts = <String>[];
      final client = MockClient((request) async {
        hosts.add(request.url.host);
        expect(
          request.headers['x-device-id'],
          matches(RegExp(r'^[a-f0-9-]{36}$')),
        );
        expect(request.headers['x-client-app-version'], '1.0.37-beta.21+21');
        return request.url.host == 'download.csnas.asia'
            ? http.Response('temporarily unavailable', 503)
            : http.Response.bytes([1, 2, 3, 4], 200);
      });
      final dir = await Directory.systemTemp.createTemp('mesting_csnas_');
      addTearDown(() => dir.delete(recursive: true));
      final repo = AppUpdateRepository(
        client: client,
        platform: _Platform(),
        directoryProvider: () async => dir,
      );
      final path = await repo.download(
        await _release(client),
        onProgress: (_, _) {},
      );
      expect(await File(path).readAsBytes(), [1, 2, 3, 4]);
      expect(hosts, ['download.csnas.asia', 'download1.csnas.asia']);
    },
  );

  test('429 does not loop or silently switch mirrors', () async {
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      return http.Response('limited', 429, headers: {'retry-after': '60'});
    });
    final dir = await Directory.systemTemp.createTemp('mesting_csnas_');
    addTearDown(() => dir.delete(recursive: true));
    final repo = AppUpdateRepository(
      client: client,
      platform: _Platform(),
      directoryProvider: () async => dir,
    );
    await expectLater(
      repo.download(await _release(client), onProgress: (_, _) {}),
      throwsA(isA<AppUpdateException>()),
    );
    expect(calls, 1);
  });

  test(
    'resume persists origin session and If-Range; a 200 fully replaces Ring partial bytes',
    () async {
      var calls = 0;
      String? id;
      final client = MockClient((request) async {
        calls++;
        if (calls == 1) {
          id = request.headers['x-device-id'];
          return http.Response.bytes(
            [1, 2],
            200,
            headers: {
              'x-download-session-id': 'test-session',
              'etag': '"same-file"',
            },
          );
        }
        expect(request.headers['x-device-id'], id);
        expect(request.headers['range'], 'bytes=2-');
        expect(request.headers['if-range'], '"same-file"');
        expect(request.headers['x-download-session-id'], 'test-session');
        return http.Response.bytes([1, 2, 3, 4], 200);
      });
      final dir = await Directory.systemTemp.createTemp('mesting_csnas_');
      addTearDown(() => dir.delete(recursive: true));
      final withMirror = await _release(client);
      final manifest = AppUpdateManifest(
        packageName: _package,
        versionName: '1.0.1',
        versionCode: 22,
        minimumVersionCode: 1,
        mandatory: false,
        title: '发现新版本',
        releaseNotes: const [],
        apkUrl: withMirror.apkUrl,
        sha256: withMirror.sha256,
        sizeBytes: 4,
        publishedAt: DateTime.utc(2026),
        downloadEtag: '"same-file"',
      );
      final repo = AppUpdateRepository(
        client: client,
        platform: _Platform(),
        directoryProvider: () async => dir,
      );
      await expectLater(
        repo.download(manifest, onProgress: (_, _) {}),
        throwsA(isA<AppUpdateException>()),
      );
      final resumedRepo = AppUpdateRepository(
        client: client,
        platform: _Platform(),
        directoryProvider: () async => dir,
      );
      final path = await resumedRepo.download(manifest, onProgress: (_, _) {});
      expect(await File(path).readAsBytes(), [1, 2, 3, 4]);
      expect(calls, 2);
    },
  );

  test(
    'external HTTPS redirects never receive platform session/device headers',
    () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        if (request.url.host == 'download.csnas.asia') {
          return http.Response(
            '',
            302,
            headers: {'location': 'https://cdn.example.com/public.apk'},
          );
        }
        expect(request.headers.containsKey('x-device-id'), false);
        expect(request.headers.containsKey('x-download-session-id'), false);
        return http.Response.bytes([1, 2, 3, 4], 200);
      });
      final dir = await Directory.systemTemp.createTemp('mesting_csnas_');
      addTearDown(() => dir.delete(recursive: true));
      final repo = AppUpdateRepository(
        client: client,
        platform: _Platform(),
        directoryProvider: () async => dir,
      );
      expect(
        await File(
          await repo.download(await _release(client), onProgress: (_, _) {}),
        ).readAsBytes(),
        [1, 2, 3, 4],
      );
      expect(calls, 2);
    },
  );
}
