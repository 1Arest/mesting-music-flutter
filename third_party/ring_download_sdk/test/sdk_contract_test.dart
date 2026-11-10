import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:ring_download_sdk/ring_download_sdk.dart';
import 'package:ring_download_sdk/src/sdk/engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  final bytes = Uint8List.fromList(List.generate(4096, (n) => n % 251));
  RingDownloadConfig config(String id) => RingDownloadConfig(
    appId: id,
    observeLifecycle: false,
    storageDirectory: directory,
  );
  RingDownloadRequest request({String? digest}) => RingDownloadRequest(
    releaseId: 'release-1',
    version: '1.0.0',
    fileSize: bytes.length,
    sha256: digest ?? sha256.convert(bytes).toString(),
    url: Uri.parse('https://cdn.example.test/app.apk?signature=PRIVATE'),
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    directory = await Directory.systemTemp.createTemp('ring-sdk-contract-');
  });
  tearDown(() async => directory.delete(recursive: true));

  test('SDK status version matches source package metadata', () async {
    // The same test may be invoked by a host project from its own root.
    // Resolve the imported package instead of reading the host's pubspec.
    final config = File('.dart_tool/package_config.json').absolute;
    final packages = jsonDecode(config.readAsStringSync())['packages'] as List;
    final package = packages.singleWhere(
      (value) => value['name'] == 'ring_download_sdk',
    );
    final root = Directory.fromUri(config.uri.resolve(package['rootUri']));
    final source = File.fromUri(
      root.uri.resolve('pubspec.yaml'),
    ).readAsStringSync();
    final packageVersion = RegExp(
      r'^version:\s*([^\r\n]+)',
      multiLine: true,
    ).firstMatch(source)!.group(1)!.trim();
    const status = RingSdkStatus(
      appId: 'alpha',
      platform: 'android',
      networkType: 'unknown',
      p2pEnabled: false,
      sharingOptIn: false,
    );
    expect(status.toJson()['sdkVersion'], packageVersion);
  });

  test('ordinary peer race configuration is bounded before engine work', () {
    expect(const RingDownloadConfig(appId: 'alpha').p8pPeerRaceLimit, 2);
    for (final limit in [2, 3, 4]) {
      expect(
        () => RingDownloadConfig(
          appId: 'alpha',
          p8pPeerRaceLimit: limit,
        ).validate(),
        returnsNormally,
      );
    }
    for (final limit in [-1, 0, 1, 5, 100]) {
      expect(
        () => RingDownloadConfig(
          appId: 'alpha',
          p8pPeerRaceLimit: limit,
        ).validate(),
        throwsA(isA<RingDownloadException>()),
      );
    }
  });

  test('sharing waits for a positively resumed lifecycle state', () async {
    final engine = _FakeEngine();
    final sdk = RingDownloadSdk.withEngine(
      const RingDownloadConfig(appId: 'alpha', allowSharing: true),
      engine,
    );
    expect(
      engine.lastForeground,
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed,
    );
    sdk.didChangeAppLifecycleState(AppLifecycleState.inactive);
    expect(engine.lastForeground, false);
    sdk.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(engine.lastForeground, true);
    sdk.didChangeAppLifecycleState(AppLifecycleState.paused);
    expect(engine.lastForeground, false);
    await sdk.dispose();
  });

  test(
    'invalid applications and insecure requests fail before transfer',
    () async {
      expect(
        () => RingDownloadSdk.withEngine(config('../escape'), _FakeEngine()),
        throwsA(isA<RingDownloadException>()),
      );
      final engine = _FakeEngine();
      final sdk = RingDownloadSdk.withEngine(config('alpha'), engine);
      final bad = RingDownloadRequest(
        releaseId: 'x',
        version: '1',
        fileSize: 1,
        sha256: '0' * 64,
        url: Uri.parse('http://example.test/apk'),
      );
      expect(() => sdk.download(bad), throwsA(isA<RingDownloadException>()));
      expect(engine.calls, 0);
      await sdk.dispose();
    },
  );

  test(
    'task resolves only after exact file size and SHA are verified',
    () async {
      final file = await File('${directory.path}/ok.apk').writeAsBytes(bytes);
      final engine = _FakeEngine(result: file);
      final sdk = RingDownloadSdk.withEngine(config('alpha'), engine);
      final task = sdk.download(request());
      final progress = <RingDownloadProgress>[];
      task.progress.listen(progress.add);
      final result = await task.completed;
      await Future<void>.delayed(Duration.zero);
      expect(result.sha256, sha256.convert(bytes).toString());
      expect(result.fileSize, bytes.length);
      expect(progress.last.state, RingDownloadState.completed);
      expect(
        progress.where((p) => p.state == RingDownloadState.verifying),
        isNotEmpty,
      );
      await sdk.dispose();
    },
  );

  test(
    'a transport returning corrupt bytes never produces a successful receipt',
    () async {
      final file = await File(
        '${directory.path}/bad.apk',
      ).writeAsBytes(List.filled(bytes.length, 0));
      final sdk = RingDownloadSdk.withEngine(
        config('alpha'),
        _FakeEngine(result: file),
      );
      final task = sdk.download(request());
      await expectLater(
        task.completed,
        throwsA(
          isA<RingDownloadException>().having(
            (e) => e.code,
            'code',
            RingDownloadError.integrity,
          ),
        ),
      );
      expect(task.latest.state, RingDownloadState.failed);
      await sdk.dispose();
    },
  );

  test(
    'truncated files and an over-optimistic progress callback are rejected',
    () async {
      final file = await File('${directory.path}/short.apk').writeAsBytes([1]);
      final sdk = RingDownloadSdk.withEngine(
        config('alpha'),
        _FakeEngine(result: file),
      );
      final task = sdk.download(request());
      await expectLater(task.completed, throwsA(isA<RingDownloadException>()));
      expect(task.latest.receivedBytes, lessThanOrEqualTo(bytes.length));
      expect(task.latest.state, isNot(RingDownloadState.completed));
      await sdk.dispose();
    },
  );

  test(
    'cancellation before scheduled start performs no engine or network work',
    () async {
      final engine = _FakeEngine();
      final sdk = RingDownloadSdk.withEngine(config('alpha'), engine);
      final task = sdk.download(request());
      task.cancel();
      await expectLater(
        task.completed,
        throwsA(
          isA<RingDownloadException>().having(
            (e) => e.code,
            'code',
            RingDownloadError.cancelled,
          ),
        ),
      );
      expect(engine.calls, 0);
      expect(task.latest.state, RingDownloadState.cancelled);
      await sdk.dispose();
    },
  );

  test(
    'active tenant is exclusive even across SDK instances; other tenants proceed',
    () async {
      final gate = Completer<File>();
      final one = RingDownloadSdk.withEngine(
        config('alpha'),
        _FakeEngine(gate: gate),
      );
      final two = RingDownloadSdk.withEngine(config('alpha'), _FakeEngine());
      final three = RingDownloadSdk.withEngine(config('beta'), _FakeEngine());
      final first = one.download(request());
      expect(
        () => two.download(request()),
        throwsA(
          isA<RingDownloadException>().having(
            (e) => e.code,
            'code',
            RingDownloadError.busy,
          ),
        ),
      );
      final separate = three.download(request());
      separate.cancel();
      first.cancel();
      await expectLater(
        separate.completed,
        throwsA(isA<RingDownloadException>()),
      );
      await expectLater(first.completed, throwsA(isA<RingDownloadException>()));
      // Lease must be released on cancellation, not leaked until process restart.
      final retry = two.download(request());
      retry.cancel();
      await expectLater(retry.completed, throwsA(isA<RingDownloadException>()));
      await one.dispose();
      await two.dispose();
      await three.dispose();
    },
  );

  test(
    'dispose cancels a running transfer, awaits cleanup, and is idempotent',
    () async {
      final engine = _FakeEngine(gate: Completer<File>());
      final sdk = RingDownloadSdk.withEngine(config('alpha'), engine);
      final task = sdk.download(request());
      final outcome = expectLater(
        task.completed,
        throwsA(isA<RingDownloadException>()),
      );
      await Future<void>.delayed(Duration.zero);
      await sdk.dispose();
      await sdk.dispose();
      await outcome;
      expect(engine.disposals, 1);
      expect(
        () => sdk.download(request()),
        throwsA(
          isA<RingDownloadException>().having(
            (e) => e.code,
            'code',
            RingDownloadError.disposed,
          ),
        ),
      );
    },
  );

  test('transport errors expose no signed URL or raw exception text', () async {
    final engine = _FakeEngine(
      error: DioException(
        requestOptions: RequestOptions(
          path: 'https://cdn.example.test/?token=DO_NOT_LEAK',
        ),
      ),
    );
    final sdk = RingDownloadSdk.withEngine(config('alpha'), engine);
    try {
      await sdk.download(request()).completed;
      fail('must fail');
    } on RingDownloadException catch (e) {
      expect(e.code, RingDownloadError.network);
      expect(e.toString(), isNot(contains('DO_NOT_LEAK')));
      expect(e.toString(), isNot(contains('https://')));
    }
    await sdk.dispose();
  });

  test(
    'standalone SDK uses actual HTTPS engine for a business-selected CDN URL',
    () async {
      final http = Dio()..httpClientAdapter = _BytesAdapter(bytes);
      final diagnostics = <RingDownloadDiagnostic>[];
      final conf = RingDownloadConfig(
        appId: 'alpha',
        observeLifecycle: false,
        storageDirectory: directory,
        onDiagnostic: (event) {
          diagnostics.add(event);
          throw StateError('a failing telemetry observer');
        },
      );
      final sdk = RingDownloadSdk.withEngine(
        conf,
        DefaultRingTransferEngine(conf, http: http),
      );
      final result = await sdk.download(request()).completed;
      expect(await result.file.readAsBytes(), bytes);
      expect(result.file.path, contains('ring_download_sdk'));
      expect(result.file.path, contains('alpha'));
      expect(diagnostics.any((event) => event.verified == true), true);
      final encoded = diagnostics.map((event) => event.toJson()).toString();
      expect(encoded, isNot(contains('PRIVATE')));
      expect(encoded, isNot(contains('https://')));
      await sdk.dispose();
    },
  );

  test(
    'sharing is opt-in and does not follow a metered or unknown network',
    () {
      expect(config('alpha').allowSharing, false);
      expect(config('alpha').enableP2P, true);
    },
  );
  test(
    'installation revalidation rejects a file changed after successful download',
    () async {
      final file = await File(
        '${directory.path}/mutable.apk',
      ).writeAsBytes(bytes);
      final sdk = RingDownloadSdk.withEngine(
        config('alpha'),
        _FakeEngine(result: file),
      );
      final receipt = await sdk.download(request()).completed;
      await receipt.revalidate();
      await file.writeAsBytes(List.filled(bytes.length, 1));
      await expectLater(
        receipt.revalidate(),
        throwsA(
          isA<RingDownloadException>().having(
            (e) => e.code,
            'code',
            RingDownloadError.integrity,
          ),
        ),
      );
      await sdk.dispose();
    },
  );

  test('missing verification file returns a stable storage error', () async {
    final receipt = RingDownloadResult(
      file: File('${directory.path}/missing.apk'),
      sha256: sha256.convert(bytes).toString(),
      fileSize: bytes.length,
      elapsed: Duration.zero,
    );
    await expectLater(
      receipt.revalidate(),
      throwsA(
        isA<RingDownloadException>().having(
          (e) => e.code,
          'code',
          RingDownloadError.storage,
        ),
      ),
    );
  });

  test(
    'hosted service URLs cannot cross the configured application boundary',
    () async {
      final engine = _FakeEngine();
      final sdk = RingDownloadSdk.withEngine(config('alpha'), engine);
      final other = RingDownloadRequest(
        releaseId: 'x',
        version: '1',
        fileSize: 1,
        sha256: '0' * 64,
        url: Uri.parse('https://download.csnas.asia/beta/download'),
      );
      expect(
        () => sdk.download(other),
        throwsA(
          isA<RingDownloadException>().having(
            (e) => e.code,
            'code',
            RingDownloadError.invalidRequest,
          ),
        ),
      );
      expect(engine.calls, 0);
      await sdk.dispose();
    },
  );
}

class _FakeEngine implements RingTransferEngine {
  _FakeEngine({this.result, this.gate, this.error});
  final File? result;
  final Completer<File>? gate;
  final Object? error;
  int calls = 0, disposals = 0;
  @override
  Future<File> download(
    RingDownloadRequest request,
    void Function(int, int) onProgress,
    CancelToken token,
  ) async {
    calls++;
    if (error != null) throw error!;
    onProgress(request.fileSize + 100, request.fileSize);
    if (gate != null) {
      return Future.any([
        gate!.future,
        token.whenCancel.then<File>((e) => throw e),
      ]);
    }
    return result ?? File('not-used');
  }

  bool? lastForeground;
  @override
  void setForeground(bool foreground) => lastForeground = foreground;
  @override
  void setSharingEnabled(bool enabled) {}
  @override
  Future<void> dispose() async {
    disposals++;
  }
}

class _BytesAdapter implements HttpClientAdapter {
  _BytesAdapter(this.bytes);
  final Uint8List bytes;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    expect(
      options.headers.keys.map((k) => k.toLowerCase()),
      isNot(contains('authorization')),
    );
    expect(
      options.headers.keys.map((k) => k.toLowerCase()),
      isNot(contains('x-device-id')),
    );
    return ResponseBody.fromBytes(
      bytes,
      200,
      headers: {
        'content-length': ['${bytes.length}'],
        'content-type': ['application/vnd.android.package-archive'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
