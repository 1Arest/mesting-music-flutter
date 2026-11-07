import 'dart:async';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ring_download_sdk/ring_download_sdk.dart';
import 'package:ring_download_sdk/src/sdk/engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final bytes = [1, 2, 3, 4];
  late Directory directory;
  late File file;
  late _Sharing engine;
  late RingDownloadSdk sdk;
  RingDownloadRequest request() => RingDownloadRequest(
    releaseId: 'current',
    version: '1.6.9',
    androidVersionCode: 8909,
    fileSize: bytes.length,
    sha256: sha256.convert(bytes).toString(),
    url: Uri.parse('https://download.csnas.asia/lifering/download'),
  );
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('sdk-cache-restore-');
    file = await File('${directory.path}/current.apk').writeAsBytes(bytes);
    engine = _Sharing();
    sdk = RingDownloadSdk.withEngine(
      const RingDownloadConfig(
        appId: 'lifering',
        allowSharing: true,
        observeLifecycle: false,
      ),
      engine,
    );
  });
  tearDown(() async {
    await sdk.dispose();
    await directory.delete(recursive: true);
  });
  test(
    'public restore delegates a hosted authorized snapshot without downloading',
    () async {
      expect(await sdk.restoreSharing(request(), file), true);
      expect(engine.restores, 1);
      expect(engine.downloads, 0);
      expect(await file.readAsBytes(), bytes);
    },
  );
  test(
    'external COS and explicit opt-out never invoke cache sharing',
    () async {
      expect(
        await sdk.restoreSharing(
          RingDownloadRequest(
            url: Uri.parse('https://cos.example.test/update.apk'),
          ),
          file,
        ),
        false,
      );
      sdk.setSharingEnabled(false);
      expect(await sdk.restoreSharing(request(), file), false);
      expect(engine.restores, 0);
      sdk.setSharingEnabled(true);
      expect(await sdk.restoreSharing(request(), file), true);
    },
  );
  test('a restore cannot compete with the active receive owner', () async {
    final receiving = sdk.download(request());
    expect(await sdk.restoreSharing(request(), file), false);
    expect(engine.restores, 0);
    engine.received.complete(file);
    expect((await receiving.completed).sha256, request().sha256);
  });
  test('disposed SDK refuses restoring a retained file', () async {
    await sdk.dispose();
    await expectLater(
      sdk.restoreSharing(request(), file),
      throwsA(isA<RingDownloadException>()),
    );
    expect(engine.restores, 0);
  });
  test(
    'explicit stop forgets the artifact and requires a new opt-in',
    () async {
      expect(await sdk.restoreSharing(request(), file), true);
      await sdk.stopSharing();
      expect(engine.stops, 1);
      expect(await sdk.restoreSharing(request(), file), false);
      expect(engine.downloads, 0);
    },
  );
}

class _Sharing implements RingTransferEngine, RingCachedSharing {
  int restores = 0, downloads = 0, stops = 0;
  final received = Completer<File>();
  @override
  Future<void> stopSharing() async {
    stops++;
  }

  @override
  Future<bool> restoreSharing(RingDownloadRequest request, File file) async {
    restores++;
    return true;
  }

  @override
  Future<File> download(
    RingDownloadRequest request,
    void Function(int, int) progress,
    CancelToken token,
  ) {
    downloads++;
    return received.future;
  }

  @override
  void setForeground(bool foreground) {}
  @override
  void setSharingEnabled(bool enabled) {}
  @override
  Future<void> dispose() async {}
}
