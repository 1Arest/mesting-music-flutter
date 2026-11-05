import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ring_download_sdk/ring_download_sdk.dart';
import 'package:ring_download_sdk/src/sdk/engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  RingDownloadRequest hosted() => RingDownloadRequest(
    releaseId: 'release',
    version: '1.6.6',
    fileSize: 4,
    sha256: 'a' * 64,
    androidVersionCode: 8907,
    url: Uri.parse('https://download.csnas.asia/lifering/download'),
  );

  test('host installation events retain actual build reconciliation', () async {
    final engine = _Events();
    final sdk = RingDownloadSdk.withEngine(
      const RingDownloadConfig(appId: 'lifering', observeLifecycle: false),
      engine,
    );
    await sdk.rememberInstallation(hosted());
    await sdk.reportInstallationFailure(hosted());
    await sdk.reconcileInstalledBuild(8907);
    expect(engine.calls, ['remember:8907', 'failed', 'installed:8907']);
    await sdk.dispose();
    await sdk.reconcileInstalledBuild(8907);
    expect(engine.calls.length, 3);
  });

  test(
    'COS install never depends on hosted events even with empty metadata',
    () async {
      final engine = _Events()..fail = true;
      final sdk = RingDownloadSdk.withEngine(
        const RingDownloadConfig(appId: 'lifering', observeLifecycle: false),
        engine,
      );
      final external = RingDownloadRequest(
        url: Uri.parse('https://cos.example.test/file.apk'),
      );
      await sdk.rememberInstallation(external);
      await sdk.reportInstallationFailure(external);
      expect(engine.calls, isEmpty);
      await sdk.dispose();
    },
  );

  test(
    'unavailable installation telemetry never blocks the host installer',
    () async {
      final engine = _Events()..fail = true;
      final sdk = RingDownloadSdk.withEngine(
        const RingDownloadConfig(appId: 'lifering', observeLifecycle: false),
        engine,
      );
      await sdk.rememberInstallation(hosted());
      await sdk.reportInstallationFailure(hosted());
      await sdk.reconcileInstalledBuild(8907);
      expect(engine.calls.length, 3);
      await sdk.dispose();
    },
  );
}

class _Events implements RingTransferEngine, RingInstallationEvents {
  final calls = <String>[];
  bool fail = false;
  void record(String call) {
    calls.add(call);
    if (fail) throw StateError('offline');
  }

  @override
  Future<void> rememberInstallation(RingDownloadRequest request) async =>
      record('remember:${request.androidVersionCode}');
  @override
  Future<void> reportInstallationFailure(RingDownloadRequest request) async =>
      record('failed');
  @override
  Future<void> reconcileInstalledBuild(int build) async =>
      record('installed:$build');
  @override
  Future<File> download(
    RingDownloadRequest request,
    void Function(int, int) progress,
    CancelToken token,
  ) => throw UnimplementedError();
  @override
  void setForeground(bool foreground) {}
  @override
  void setSharingEnabled(bool enabled) {}
  @override
  Future<void> dispose() async {}
}
