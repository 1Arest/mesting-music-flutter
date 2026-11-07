import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/features/app_update/app_update_providers.dart';
import 'package:mesting_music/features/app_update/data/app_update_platform.dart';
import 'package:mesting_music/features/app_update/data/app_update_repository.dart';
import 'package:mesting_music/features/app_update/domain/app_update_models.dart';
import 'package:mesting_music/features/app_update/presentation/app_update_sheet.dart';
import 'package:mesting_music/shared/widgets/liquid_glass_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _currentVersion = AppVersionInfo(
  packageName: 'com.mesting.music',
  versionName: '1.0.14',
  versionCode: 15,
);

Map<String, Object?> _manifestJson({
  required List<int> apkBytes,
  int versionCode = 16,
  int minimumVersionCode = 1,
  String? sha,
}) {
  return {
    'packageName': 'com.mesting.music',
    'versionName': '1.0.15',
    'versionCode': versionCode,
    'minimumVersionCode': minimumVersionCode,
    'mandatory': false,
    'title': '发现新版本',
    'releaseNotes': ['新增应用内更新', '优化我的喜欢页面'],
    'apkUrl': 'https://updates.example.com/mesting.apk',
    'sha256': sha ?? sha256.convert(apkBytes).toString(),
    'sizeBytes': apkBytes.length,
    'publishedAt': '2026-07-24T12:00:00Z',
  };
}

class _FakeUpdatePlatform extends AppUpdatePlatform {
  _FakeUpdatePlatform();

  bool installPermission = true;
  bool permissionOpened = false;
  String? installedPath;

  @override
  Future<AppVersionInfo> currentVersion() async => _currentVersion;

  @override
  Future<bool> canRequestPackageInstalls() async => installPermission;

  @override
  Future<void> openInstallPermission() async {
    permissionOpened = true;
  }

  @override
  Future<void> installApk(String path) async {
    installedPath = path;
  }
}

class _AvailableUpdateController extends AppUpdateController {
  @override
  AppUpdateState build() {
    final manifest = AppUpdateManifest.fromJson(
      _manifestJson(apkBytes: const [1, 2, 3], minimumVersionCode: 16),
    );
    return AppUpdateState(
      phase: AppUpdatePhase.available,
      currentVersion: _currentVersion,
      manifest: manifest,
    );
  }
}

class _DownloadingUpdateController extends AppUpdateController {
  @override
  AppUpdateState build() {
    final manifest = AppUpdateManifest.fromJson(
      _manifestJson(apkBytes: const [1, 2, 3, 4], minimumVersionCode: 16),
    );
    return AppUpdateState(
      phase: AppUpdatePhase.downloading,
      currentVersion: _currentVersion,
      manifest: manifest,
      receivedBytes: 2,
      totalBytes: 4,
    );
  }
}

class _StreamClient extends http.BaseClient {
  _StreamClient(this.handler);

  final Future<http.StreamedResponse> Function(http.BaseRequest request)
  handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      handler(request);
}

void main() {
  test('更新清单严格比较包名、版本号与强制更新范围', () {
    final manifest = AppUpdateManifest.fromJson(
      _manifestJson(apkBytes: const [4, 5, 6], minimumVersionCode: 16),
    );

    expect(manifest.isNewerThan(_currentVersion), isTrue);
    expect(manifest.isMandatoryFor(_currentVersion), isTrue);
    expect(manifest.sizeLabel, '0.0 MB');

    final invalid = _manifestJson(apkBytes: const [4, 5, 6])
      ..['apkUrl'] = 'http://updates.example.com/app.apk';
    expect(
      () => AppUpdateManifest.fromJson(invalid),
      throwsA(isA<FormatException>()),
    );
  });

  test('仓库下载 APK 后校验大小和 SHA-256 再交给安装桥接', () async {
    final apkBytes = List<int>.generate(1024 * 8, (index) => index % 251);
    final manifestJson = _manifestJson(apkBytes: apkBytes);
    final client = MockClient((request) async {
      if (request.url.path.endsWith('latest.json')) {
        return http.Response(
          jsonEncode(manifestJson),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response.bytes(
        apkBytes,
        200,
        headers: {'content-type': 'application/vnd.android.package-archive'},
      );
    });
    final platform = _FakeUpdatePlatform();
    final directory = await Directory.systemTemp.createTemp(
      'mesting_update_test_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final repository = AppUpdateRepository(
      client: client,
      platform: platform,
      manifestUrl: Uri.parse('https://updates.example.com/latest.json'),
      directoryProvider: () async => directory,
    );

    final check = await repository.check();
    expect(check.updateAvailable, isTrue);
    var received = 0;
    final path = await repository.download(
      check.manifest,
      onProgress: (value, _) => received = value,
    );

    expect(received, apkBytes.length);
    expect(await File(path).readAsBytes(), apkBytes);
    expect(path, endsWith('.apk'));
    await repository.installApk(path);
    expect(platform.installedPath, path);
  });

  test('SHA-256 不匹配时删除临时安装包并阻止安装', () async {
    final directory = await Directory.systemTemp.createTemp(
      'mesting_update_bad_hash_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final bytes = const <int>[7, 8, 9, 10];
    final manifest = AppUpdateManifest.fromJson(
      _manifestJson(apkBytes: bytes, sha: List.filled(64, '0').join()),
    );
    final repository = AppUpdateRepository(
      client: MockClient((_) async => http.Response.bytes(bytes, 200)),
      platform: _FakeUpdatePlatform(),
      directoryProvider: () async => directory,
    );

    await expectLater(
      repository.download(manifest, onProgress: (_, _) {}),
      throwsA(
        isA<AppUpdateException>().having(
          (error) => error.code,
          'code',
          'sha256',
        ),
      ),
    );
    final updateDirectory = Directory('${directory.path}/app_updates');
    expect(
      updateDirectory.existsSync()
          ? updateDirectory.listSync().whereType<File>()
          : const <File>[],
      isEmpty,
    );
  });

  test('主动暂停会保留已写入的安装包进度', () async {
    final bytes = List<int>.generate(1024 * 1024, (index) => index % 251);
    final firstChunkLength = 600 * 1024;
    final manifest = AppUpdateManifest.fromJson(_manifestJson(apkBytes: bytes));
    final directory = await Directory.systemTemp.createTemp(
      'mesting_update_pause_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final client = _StreamClient((_) async {
      return http.StreamedResponse(
        (() async* {
          yield bytes.sublist(0, firstChunkLength);
          await Future<void>.delayed(Duration.zero);
          yield bytes.sublist(firstChunkLength);
        })(),
        200,
        contentLength: bytes.length,
      );
    });
    final repository = AppUpdateRepository(
      client: client,
      platform: _FakeUpdatePlatform(),
      directoryProvider: () async => directory,
    );
    final cancellation = UpdateDownloadCancellationToken();

    await expectLater(
      repository.download(
        manifest,
        cancellationToken: cancellation,
        onProgress: (received, _) {
          if (received >= firstChunkLength) {
            unawaited(cancellation.cancel());
          }
        },
      ),
      throwsA(
        isA<AppUpdateException>().having(
          (error) => error.code,
          'code',
          'paused',
        ),
      ),
    );

    final snapshot = await repository.inspectDownload(manifest);
    expect(snapshot.receivedBytes, firstChunkLength);
    expect(snapshot.completedPath, isNull);
  });

  test('下载流仍未结束时已把已报告进度直接写入持久文件', () async {
    final bytes = List<int>.generate(768 * 1024, (index) => index % 241);
    final firstChunkLength = 320 * 1024;
    final manifest = AppUpdateManifest.fromJson(_manifestJson(apkBytes: bytes));
    final directory = await Directory.systemTemp.createTemp(
      'mesting_update_durable_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final stream = StreamController<List<int>>();
    addTearDown(stream.close);
    final repository = AppUpdateRepository(
      client: _StreamClient(
        (_) async => http.StreamedResponse(
          stream.stream,
          200,
          contentLength: bytes.length,
        ),
      ),
      platform: _FakeUpdatePlatform(),
      directoryProvider: () async => directory,
    );
    final cancellation = UpdateDownloadCancellationToken();
    final progressWritten = Completer<void>();

    final download = repository.download(
      manifest,
      cancellationToken: cancellation,
      onProgress: (received, _) {
        if (received >= firstChunkLength && !progressWritten.isCompleted) {
          progressWritten.complete();
        }
      },
    );
    stream.add(bytes.sublist(0, firstChunkLength));
    await progressWritten.future.timeout(const Duration(seconds: 2));

    final liveSnapshot = await repository.inspectDownload(manifest);
    expect(liveSnapshot.receivedBytes, firstChunkLength);
    expect(liveSnapshot.completedPath, isNull);

    await cancellation.cancel();
    await expectLater(
      download,
      throwsA(
        isA<AppUpdateException>().having(
          (error) => error.code,
          'code',
          'paused',
        ),
      ),
    );
  });

  test('进程重建后识别残片并使用 HTTP Range 继续下载', () async {
    final bytes = List<int>.generate(256 * 1024, (index) => index % 239);
    final prefixLength = 72 * 1024;
    final manifestJson = _manifestJson(apkBytes: bytes);
    final manifest = AppUpdateManifest.fromJson(manifestJson);
    final directory = await Directory.systemTemp.createTemp(
      'mesting_update_resume_',
    );
    addTearDown(() => directory.delete(recursive: true));

    final interruptedRepository = AppUpdateRepository(
      client: _StreamClient((_) async {
        return http.StreamedResponse(
          (() async* {
            yield bytes.sublist(0, prefixLength);
            throw const SocketException('connection lost');
          })(),
          200,
          contentLength: bytes.length,
        );
      }),
      platform: _FakeUpdatePlatform(),
      directoryProvider: () async => directory,
    );
    await expectLater(
      interruptedRepository.download(manifest, onProgress: (_, _) {}),
      throwsA(
        isA<AppUpdateException>().having(
          (error) => error.code,
          'code',
          'interrupted',
        ),
      ),
    );
    expect(
      (await interruptedRepository.inspectDownload(manifest)).receivedBytes,
      prefixLength,
    );

    String? resumeRange;
    final platform = _FakeUpdatePlatform();
    final resumedRepository = AppUpdateRepository(
      client: MockClient((request) async {
        if (request.url.path.endsWith('latest.json')) {
          return http.Response(
            jsonEncode(manifestJson),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        resumeRange = request.headers['range'];
        return http.Response.bytes(
          bytes.sublist(prefixLength),
          206,
          headers: {
            'content-type': 'application/vnd.android.package-archive',
            'content-range':
                'bytes $prefixLength-${bytes.length - 1}/${bytes.length}',
          },
        );
      }),
      platform: platform,
      manifestUrl: Uri.parse('https://updates.example.com/latest.json'),
      directoryProvider: () async => directory,
    );
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        appUpdateRepositoryProvider.overrideWithValue(resumedRepository),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(appUpdateControllerProvider.notifier);

    await controller.check(manual: true);
    var state = container.read(appUpdateControllerProvider);
    expect(state.phase, AppUpdatePhase.paused);
    expect(state.receivedBytes, prefixLength);
    expect(state.totalBytes, bytes.length);

    await controller.downloadAndInstall();
    state = container.read(appUpdateControllerProvider);
    expect(resumeRange, 'bytes=$prefixLength-');
    expect(state.phase, AppUpdatePhase.installLaunched);
    expect(state.receivedBytes, bytes.length);
    expect(platform.installedPath, isNotNull);
    expect(await File(platform.installedPath!).readAsBytes(), bytes);
  });

  test('服务器忽略 Range 时校验重复前缀且进度不归零', () async {
    final bytes = List<int>.generate(128 * 1024, (index) => index % 227);
    final prefixLength = 36 * 1024;
    final manifest = AppUpdateManifest.fromJson(_manifestJson(apkBytes: bytes));
    final directory = await Directory.systemTemp.createTemp(
      'mesting_update_range_fallback_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final interruptedRepository = AppUpdateRepository(
      client: _StreamClient((_) async {
        return http.StreamedResponse(
          (() async* {
            yield bytes.sublist(0, prefixLength);
            throw const SocketException('connection lost');
          })(),
          200,
          contentLength: bytes.length,
        );
      }),
      platform: _FakeUpdatePlatform(),
      directoryProvider: () async => directory,
    );
    await expectLater(
      interruptedRepository.download(manifest, onProgress: (_, _) {}),
      throwsA(isA<AppUpdateException>()),
    );

    String? requestedRange;
    final progress = <int>[];
    final repository = AppUpdateRepository(
      client: MockClient((request) async {
        requestedRange = request.headers['range'];
        return http.Response.bytes(bytes, 200);
      }),
      platform: _FakeUpdatePlatform(),
      directoryProvider: () async => directory,
    );
    final path = await repository.download(
      manifest,
      onProgress: (received, _) => progress.add(received),
    );

    expect(requestedRange, 'bytes=$prefixLength-');
    expect(progress, isNot(contains(0)));
    expect(progress.first, prefixLength);
    expect(progress.last, bytes.length);
    expect(await File(path).readAsBytes(), bytes);
  });

  testWidgets('更新抽屉展示版本、更新内容和强制更新状态', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          appUpdateControllerProvider.overrideWith(
            _AvailableUpdateController.new,
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: AppUpdateSheet())),
      ),
    );

    expect(find.text('发现新版本'), findsOneWidget);
    expect(find.text('v1.0.15 · 0.0 MB'), findsOneWidget);
    expect(find.text('新增应用内更新'), findsOneWidget);
    expect(find.text('优化我的喜欢页面'), findsOneWidget);
    expect(find.text('必须更新'), findsOneWidget);
    expect(find.byKey(const ValueKey('app-update-primary')), findsOneWidget);
    expect(find.byKey(const ValueKey('app-update-later')), findsNothing);
    expect(find.textContaining('当前版本 v1.0.14 ·'), findsOneWidget);
    expect(find.textContaining('当前版本 v1.0.14（15）'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('版本更新入口使用共享液态玻璃且内容层保持透明', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          appUpdateControllerProvider.overrideWith(
            _AvailableUpdateController.new,
          ),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                key: const ValueKey('open-app-update-sheet'),
                onPressed: () => showAppUpdateSheet(context),
                child: const Text('打开更新'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('open-app-update-sheet')));
    await tester.pumpAndSettle();

    final glassSurface = tester.widget<LiquidGlassSurface>(
      find.byKey(liquidGlassSheetSurfaceKey),
    );
    expect(glassSurface.blurSigma, 24);
    expect(
      find.descendant(
        of: find.byKey(liquidGlassSheetSurfaceKey),
        matching: find.byType(BackdropFilter),
      ),
      findsOneWidget,
    );
    final contentMaterial = tester.widget<Material>(
      find.byKey(appUpdateSheetContentKey),
    );
    expect(contentMaterial.type, MaterialType.transparency);
    expect(tester.takeException(), isNull);
  });

  testWidgets('下载抽屉可以暂停并显示持久化续传进度', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          appUpdateControllerProvider.overrideWith(
            _DownloadingUpdateController.new,
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: AppUpdateSheet())),
      ),
    );

    expect(find.byKey(const ValueKey('app-update-progress')), findsOneWidget);
    expect(find.text('下载进度会保存在本机，关闭应用后可继续'), findsOneWidget);
    expect(find.text('暂停下载 50%'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('app-update-primary')));
    await tester.pumpAndSettle();

    expect(find.text('下载已暂停，进度已保存在本机'), findsOneWidget);
    expect(find.text('继续下载 50%'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
