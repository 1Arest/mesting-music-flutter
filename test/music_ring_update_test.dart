import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:mesting_music/features/app_update/app_update_providers.dart';
import 'package:mesting_music/features/app_update/data/app_update_platform.dart';
import 'package:mesting_music/features/app_update/data/app_update_repository.dart';
import 'package:mesting_music/features/app_update/data/ring_app_update_transport.dart';
import 'package:mesting_music/features/app_update/domain/app_update_models.dart';
import 'package:ring_download_sdk/ring_download_sdk.dart';
// Internal test seams only; production uses the SDK public API.
import 'package:ring_download_sdk/src/sdk/engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _bytes = List<int>.generate(4096, (n) => n % 251);
AppUpdateManifest _manifest({String? hash, String? url, String? backup}) =>
    AppUpdateManifest(
      packageName: AppUpdateRepository.expectedPackageName,
      versionName: '1.0.3',
      versionCode: 24,
      minimumVersionCode: 1,
      mandatory: false,
      title: '更新',
      releaseNotes: const [],
      apkUrl: Uri.parse(url ?? 'https://download.csnas.asia/music/download'),
      apkBackupUrl: Uri.parse(
        backup ?? 'https://download1.csnas.asia/music/download?direct=backup',
      ),
      downloadEtag: '"fixture"',
      sha256: hash ?? sha256.convert(_bytes).toString(),
      sizeBytes: _bytes.length,
      publishedAt: DateTime.utc(2026, 10, 27),
    );

class _Platform extends AppUpdatePlatform {
  int installs = 0;
  @override
  Future<AppVersionInfo> currentVersion() async => AppVersionInfo(
    packageName: AppUpdateRepository.expectedPackageName,
    versionName: '1.0.2',
    versionCode: 23,
  );
  @override
  Future<bool> canRequestPackageInstalls() async => true;
  @override
  Future<void> installApk(String path) async {
    installs++;
  }
}

class _Engine implements RingTransferEngine {
  _Engine(this.directory);
  final Directory directory;
  final requests = <RingDownloadRequest>[];
  RingDownloadError? failure;
  bool waitForCancel = false, disposed = false, cleanupFinished = false;
  final started = Completer<void>();
  @override
  Future<File> download(
    RingDownloadRequest request,
    void Function(int, int) progress,
    CancelToken cancel,
  ) async {
    requests.add(request);
    progress(1024, request.fileSize);
    if (!started.isCompleted) started.complete();
    if (waitForCancel) {
      await cancel.whenCancel;
      // Writer cleanup must finish before cancel() completes at the host.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      cleanupFinished = true;
      throw const RingDownloadException(RingDownloadError.cancelled);
    }
    if (failure case final error?) throw RingDownloadException(error);
    await directory.create(recursive: true);
    final file = File('${directory.path}/engine.apk');
    await file.writeAsBytes(_bytes, flush: true);
    progress(_bytes.length, _bytes.length);
    return file;
  }

  @override
  void setForeground(bool foreground) {}
  @override
  void setSharingEnabled(bool enabled) {}
  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

class _Payload implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? body,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (options.uri.host == 'primary.example.test') {
      return ResponseBody.fromBytes([], 503);
    }
    return ResponseBody.fromBytes(
      _bytes,
      200,
      headers: {
        'content-length': ['${_bytes.length}'],
        'etag': ['"fixture"'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late _Engine engine;
  late RingAppUpdateTransport transport;
  late _Platform platform;
  RingDownloadConfig? capturedConfig;
  var legacyRequests = 0;

  AppUpdateRepository repository({http.Client? client}) => AppUpdateRepository(
    client:
        client ??
        MockClient((_) async {
          legacyRequests++;
          throw StateError(
            'New SDK downloads must not call the legacy downloader',
          );
        }),
    platform: platform,
    directoryProvider: () async => directory,
    downloadTransport: transport,
  );
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    directory = await Directory.systemTemp.createTemp(
      'music-ring-integration-',
    );
    engine = _Engine(
      Directory('${directory.path}/app_updates/.ring-sdk/fixture'),
    );
    platform = _Platform();
    capturedConfig = null;
    legacyRequests = 0;
    transport = RingAppUpdateTransport(
      directoryProvider: () async => directory,
      sdkFactory: (config) {
        capturedConfig = config;
        return RingDownloadSdk.withEngine(config, engine);
      },
    );
  });
  tearDown(() async {
    await transport.dispose();
    await directory.delete(recursive: true);
  });

  test('hosted request binds music, real APK code, hash and both origins', () {
    final manifest = _manifest();
    final request = RingAppUpdateTransport.requestFor(manifest);
    request.validate(appId: 'music');
    expect(request.releaseId, contains(manifest.sha256));
    expect(request.androidVersionCode, 24);
    expect(request.backupUrl, manifest.apkBackupUrl);
    expect(request.etag, '"fixture"');
  });

  test(
    'external COS discards stale hosted mirror and never resolves health',
    () {
      final request = RingAppUpdateTransport.requestFor(
        _manifest(url: 'https://cos.example.test/music.apk?sign=fixture'),
      );
      request.validate(appId: 'music');
      expect(request.usesHostedService, isFalse);
      expect(request.backupUrl, isNull);
    },
  );

  test('wrong hosted app cannot start an SDK transfer', () async {
    await expectLater(
      transport.download(
        _manifest(url: 'https://download.csnas.asia/lifering/download'),
        onProgress: (_, _) {},
      ),
      throwsA(
        isA<AppUpdateException>().having((e) => e.code, 'code', 'manifest'),
      ),
    );
    expect(engine.requests, isEmpty);
  });

  test(
    'SDK completes, promotes into installer allowlist and reuses valid cache',
    () async {
      final repo = repository();
      final progress = <int>[];
      final path = await repo.download(
        _manifest(),
        onProgress: (n, _) => progress.add(n),
      );
      expect(await File(path).readAsBytes(), _bytes);
      expect(
        path,
        contains('app_updates${Platform.pathSeparator}mesting-music-'),
      );
      expect(capturedConfig!.appId, 'music');
      expect(capturedConfig!.enableP8P, isTrue);
      expect(capturedConfig!.enableP2P, isTrue);
      expect(capturedConfig!.observeLifecycle, isTrue);
      expect(capturedConfig!.allowSharing, isFalse);
      expect(progress, contains(_bytes.length));
      await repo.installApk(path);
      expect(platform.installs, 1);
      final restored = repository();
      expect((await restored.inspectDownload(_manifest())).completedPath, path);
      expect(await restored.download(_manifest(), onProgress: (_, _) {}), path);
      expect(engine.requests, hasLength(1));
      expect(legacyRequests, 0);
    },
  );

  test(
    'file changed while install permission dialog is open is rejected',
    () async {
      final repo = repository();
      final path = await repo.download(_manifest(), onProgress: (_, _) {});
      await File(path).writeAsBytes(List.filled(_bytes.length, 9));
      await expectLater(
        repo.installApk(path),
        throwsA(
          isA<AppUpdateException>().having((e) => e.code, 'code', 'sha256'),
        ),
      );
      expect(platform.installs, 0);
    },
  );

  test(
    'SDK digest failure does not install or launch a second HTTP download',
    () async {
      final repo = repository();
      await expectLater(
        repo.download(_manifest(hash: '0' * 64), onProgress: (_, _) {}),
        throwsA(
          isA<AppUpdateException>().having((e) => e.code, 'code', 'sha256'),
        ),
      );
      expect(platform.installs, 0);
      expect(legacyRequests, 0);
    },
  );

  test(
    'pause waits for cleanup, retains displayed progress and releases SDK owner',
    () async {
      engine.waitForCancel = true;
      final token = UpdateDownloadCancellationToken();
      final repo = repository();
      final flight = repo.download(
        _manifest(),
        onProgress: (_, _) {},
        cancellationToken: token,
      );
      final checked = expectLater(
        flight,
        throwsA(
          isA<AppUpdateException>().having((e) => e.code, 'code', 'paused'),
        ),
      );
      await engine.started.future;
      await token.cancel();
      expect(engine.cleanupFinished, isTrue);
      await checked;
      expect((await repo.inspectDownload(_manifest())).receivedBytes, 1024);
      engine.waitForCancel = false;
      final path = await repo.download(_manifest(), onProgress: (_, _) {});
      expect(await File(path).length(), _bytes.length);
      expect(engine.requests, hasLength(2));
    },
  );

  test(
    'cancel before asynchronous initialization performs no transfer',
    () async {
      final token = UpdateDownloadCancellationToken();
      await token.cancel();
      await expectLater(
        transport.download(
          _manifest(),
          onProgress: (_, _) {},
          cancellationToken: token,
        ),
        throwsA(
          isA<AppUpdateException>().having((e) => e.code, 'code', 'paused'),
        ),
      );
      expect(engine.requests, isEmpty);
    },
  );

  test(
    'overlap and clear during initialization cannot steal cancellation owner',
    () async {
      await transport.dispose();
      final gate = Completer<Directory>();
      transport = RingAppUpdateTransport(
        directoryProvider: () => gate.future,
        sdkFactory: (config) => RingDownloadSdk.withEngine(config, engine),
      );
      final token = UpdateDownloadCancellationToken();
      engine.waitForCancel = true;
      final first = transport.download(
        _manifest(),
        onProgress: (_, _) {},
        cancellationToken: token,
      );
      final checked = expectLater(
        first,
        throwsA(
          isA<AppUpdateException>().having((e) => e.code, 'code', 'paused'),
        ),
      );
      await expectLater(
        transport.download(_manifest(), onProgress: (_, _) {}),
        throwsA(
          isA<AppUpdateException>().having(
            (e) => e.code,
            'code',
            'download_busy',
          ),
        ),
      );
      await expectLater(
        transport.clearDownloads(),
        throwsA(isA<AppUpdateException>()),
      );
      gate.complete(directory);
      await engine.started.future;
      await token.cancel();
      await checked;
      expect(engine.cleanupFinished, isTrue);
    },
  );

  test(
    'temporary directory failure remains retryable on the same adapter',
    () async {
      await transport.dispose();
      var unavailable = true;
      transport = RingAppUpdateTransport(
        directoryProvider: () async {
          if (unavailable) throw const FileSystemException('fixture');
          return directory;
        },
        sdkFactory: (config) => RingDownloadSdk.withEngine(config, engine),
      );
      await expectLater(
        transport.download(_manifest(), onProgress: (_, _) {}),
        throwsA(isA<FileSystemException>()),
      );
      unavailable = false;
      expect(
        await (await transport.download(
          _manifest(),
          onProgress: (_, _) {},
        )).length(),
        _bytes.length,
      );
    },
  );

  test('dispose during initialization prevents late SDK creation', () async {
    await transport.dispose();
    final gate = Completer<Directory>();
    var creations = 0;
    transport = RingAppUpdateTransport(
      directoryProvider: () => gate.future,
      sdkFactory: (config) {
        creations++;
        return RingDownloadSdk.withEngine(config, engine);
      },
    );
    final download = transport.download(_manifest(), onProgress: (_, _) {});
    final checked = expectLater(download, throwsA(isA<AppUpdateException>()));
    final disposing = transport.dispose();
    gate.complete(directory);
    await disposing;
    await checked;
    expect(creations, 0);
  });

  test(
    'cache purge removes only SDK-owned files and allows a new engine',
    () async {
      final repo = repository();
      await repo.download(_manifest(), onProgress: (_, _) {});
      final unrelated = File('${directory.path}/app_updates/keep-me.txt');
      await unrelated.writeAsString('user-owned fixture');
      await repo.clearDownloads();
      expect(engine.disposed, isTrue);
      expect(await unrelated.exists(), isTrue);
      expect(
        await Directory('${directory.path}/app_updates/.ring-sdk').exists(),
        isFalse,
      );
      engine = _Engine(
        Directory('${directory.path}/app_updates/.ring-sdk/fixture'),
      );
      expect(
        await (await transport.download(
          _manifest(),
          onProgress: (_, _) {},
        )).length(),
        _bytes.length,
      );
    },
  );

  test('pre-SDK partial finishes once with original Range protocol', () async {
    final manifest = _manifest();
    final updateDir = await Directory('${directory.path}/app_updates').create();
    final stem =
        'mesting-music-1.0.3-24-${manifest.sha256.substring(0, 12)}.apk';
    await File(
      '${updateDir.path}/$stem.partial',
    ).writeAsBytes(_bytes.sublist(0, 1024));
    var requests = 0;
    final repo = repository(
      client: MockClient((request) async {
        requests++;
        expect(request.headers['range'], 'bytes=1024-');
        return http.Response.bytes(
          _bytes.sublist(1024),
          206,
          headers: {
            'content-range': 'bytes 1024-${_bytes.length - 1}/${_bytes.length}',
          },
        );
      }),
    );
    final path = await repo.download(manifest, onProgress: (_, _) {});
    expect(await File(path).readAsBytes(), _bytes);
    expect(requests, 1);
    expect(engine.requests, isEmpty);
  });

  test(
    'SDK network failure keeps host recoverable without duplicate legacy requests',
    () async {
      engine.failure = RingDownloadError.network;
      await expectLater(
        repository().download(_manifest(), onProgress: (_, _) {}),
        throwsA(
          isA<AppUpdateException>().having(
            (e) => e.code,
            'code',
            'interrupted',
          ),
        ),
      );
      expect(legacyRequests, 0);
    },
  );

  test(
    'real SDK external HTTPS mirror succeeds with every hosted socket blocked',
    () async {
      await transport.dispose();
      final payload = _Payload();
      transport = RingAppUpdateTransport(
        directoryProvider: () async => directory,
        sdkFactory: (config) => RingDownloadSdk.withEngine(
          config,
          DefaultRingTransferEngine(
            config,
            http: Dio()..httpClientAdapter = payload,
          ),
        ),
      );
      var hostedClients = 0;
      await HttpOverrides.runZoned(
        () async {
          final path = await repository().download(
            _manifest(
              url: 'https://primary.example.test/music.apk',
              backup: 'https://cos.example.test/music.apk',
            ),
            onProgress: (_, _) {},
          );
          expect(await File(path).readAsBytes(), _bytes);
          await transport.dispose();
        },
        createHttpClient: (_) {
          hostedClients++;
          throw StateError('Unmapped service socket');
        },
      );
      expect(hostedClients, 0);
      expect(payload.requests.last.uri.host, 'cos.example.test');
      expect(
        payload.requests.every((r) => !r.uri.path.contains('health')),
        isTrue,
      );
      expect(
        payload.requests.every((r) => !r.headers.containsKey('x-device-id')),
        isTrue,
      );
    },
  );

  test(
    'real hosted SDK transfer completes through HTTPS when control sockets fail',
    () async {
      await transport.dispose();
      final payload = _Payload();
      transport = RingAppUpdateTransport(
        directoryProvider: () async => directory,
        sdkFactory: (config) => RingDownloadSdk.withEngine(
          config,
          DefaultRingTransferEngine(
            config,
            http: Dio()..httpClientAdapter = payload,
          ),
        ),
      );
      await HttpOverrides.runZoned(
        () async {
          final path = await repository().download(
            _manifest(),
            onProgress: (_, _) {},
          );
          expect(await File(path).readAsBytes(), _bytes);
          await transport.dispose();
        },
        createHttpClient: (_) {
          throw StateError('Control service is unavailable');
        },
      );
      expect(
        payload.requests.any((r) => r.uri.path == '/music/download'),
        isTrue,
      );
      expect(legacyRequests, 0);
    },
  );

  test('controller with SDK reaches installer after verified completion', () async {
    // Exercise the production notifier using its existing public check contract.
    final repo = AppUpdateRepository(
      client: MockClient(
        (_) async => http.Response(
          '{"packageName":"${AppUpdateRepository.expectedPackageName}","versionName":"1.0.3",'
          '"versionCode":24,"title":"update","releaseNotes":["SDK integration"],"apkUrl":"https://download.csnas.asia/music/download",'
          '"sha256":"${_manifest().sha256}","sizeBytes":${_bytes.length},"publishedAt":"2026-10-27T00:00:00Z"}',
          200,
        ),
      ),
      platform: platform,
      directoryProvider: () async => directory,
      downloadTransport: transport,
    );
    final actual = ProviderContainer(
      overrides: [appUpdateRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(actual.dispose);
    final controller = actual.read(appUpdateControllerProvider.notifier);
    await controller.check(manual: true);
    await controller.downloadAndInstall();
    expect(
      actual.read(appUpdateControllerProvider).phase,
      AppUpdatePhase.installLaunched,
    );
    expect(platform.installs, 1);
  });
}
