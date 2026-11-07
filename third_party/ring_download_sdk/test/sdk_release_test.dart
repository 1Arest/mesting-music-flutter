import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ring_download_sdk/ring_download_sdk.dart';
import 'package:ring_download_sdk/src/sdk/engine.dart';
import 'package:ring_download_sdk/src/sdk/release_source.dart';

Map<String, dynamic> metadata(String slug) => {
  'status': 'ok',
  'app_slug': slug,
  'version': '2.0.0',
  'filename': 'app.apk',
  'file_size': 4,
  'sha256': sha256.convert([1, 2, 3, 4]).toString(),
  'primary_url': 'https://download.csnas.asia/$slug/download',
  'canonical_download_url': 'https://download.csnas.asia/$slug/download',
  'backup_url': 'https://download1.csnas.asia/$slug/download',
  'etag': '"sample"',
  'android_version_code': 42,
  'android_version_code_major': 0,
  'android_long_version_code': '42',
};

Matcher errorCode(RingDownloadError code) =>
    isA<RingDownloadException>().having((e) => e.code, 'code', code);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final app in ['alpha', 'beta']) {
    test(
      'discovers $app without a LifeRing-specific URL or host credentials',
      () async {
        final adapter = _Adapter((options) async {
          expect(
            options.uri.toString(),
            'https://download.csnas.asia/api/app/$app/health',
          );
          expect(options.followRedirects, false);
          final headers = options.headers.keys
              .map((k) => k.toLowerCase())
              .toList();
          for (final forbidden in [
            'authorization',
            'cookie',
            'x-device-id',
            'x-download-session-id',
          ]) {
            expect(headers, isNot(contains(forbidden)));
          }
          return _json(metadata(app));
        });
        final source = HostedRingReleaseSource(
          http: Dio()..httpClientAdapter = adapter,
        );
        final request = await source.resolve(app);
        expect(request.version, '2.0.0');
        expect(request.androidVersionCode, 42);
        expect(request.url.path, '/$app/download');
        expect(request.sha256, metadata(app)['sha256']);
        source.dispose();
      },
    );
  }

  final bad = <String, Map<String, dynamic>>{
    'cross application': {'app_slug': 'beta'},
    'missing SHA': {'sha256': ''},
    'fractional size': {'file_size': 4.1},
    'string size': {'file_size': '4'},
    'oversized artifact': {'file_size': 1024 * 1024 * 1024 + 1},
    'bad version': {'version': '2\n.0'},
    'inactive status': {'status': 'disabled'},
    'unsupported Android major': {'android_version_code_major': 1},
    'build mismatch': {'android_long_version_code': '43'},
    'ETag header injection': {'etag': 'x\r\nAuthorization: secret'},
    'cross-app primary and canonical': {
      'primary_url': 'https://download.csnas.asia/beta/download',
      'canonical_download_url': '',
    },
    'cross-app backup': {
      'backup_url': 'https://download1.csnas.asia/beta/download',
    },
    'HTTP backup': {'backup_url': 'http://download1.csnas.asia/alpha/download'},
    'URL credentials': {
      'backup_url': 'https://secret@download1.csnas.asia/alpha/download',
    },
    'wrong port': {
      'backup_url': 'https://download1.csnas.asia:444/alpha/download',
    },
    'fragment': {
      'backup_url': 'https://download1.csnas.asia/alpha/download#secret',
    },
  };
  for (final entry in bad.entries) {
    test('rejects ${entry.key} before making a download task', () {
      expect(
        () =>
            parseHostedRelease({...metadata('alpha'), ...entry.value}, 'alpha'),
        throwsA(errorCode(RingDownloadError.invalidMetadata)),
      );
    });
  }

  test(
    'legacy omitted build stays absent and stable artifact ID follows SHA',
    () {
      final data = metadata('alpha')
        ..remove('android_version_code')
        ..remove('android_version_code_major')
        ..remove('android_long_version_code');
      final first = parseHostedRelease(data, 'alpha');
      data['etag'] = '"new-etag"';
      expect(parseHostedRelease(data, 'alpha').releaseId, first.releaseId);
      expect(first.androidVersionCode, isNull);
      data['sha256'] = 'a' * 64;
      expect(
        parseHostedRelease(data, 'alpha').releaseId,
        isNot(first.releaseId),
      );
    },
  );

  test('no cached metadata is used after a lookup failure', () async {
    var calls = 0;
    final source = HostedRingReleaseSource(
      http: Dio()
        ..httpClientAdapter = _Adapter(
          (_) async => ++calls == 1
              ? _json(metadata('alpha'))
              : _json({'error': 'gone'}, 404),
        ),
    );
    expect((await source.resolve('alpha')).version, '2.0.0');
    await expectLater(
      source.resolve('alpha'),
      throwsA(errorCode(RingDownloadError.releaseUnavailable)),
    );
    source.dispose();
  });

  for (final status in [302, 429, 503]) {
    test(
      'HTTP $status has a stable code and never follows a redirect',
      () async {
        final source = HostedRingReleaseSource(
          http: Dio()
            ..httpClientAdapter = _Adapter((o) async {
              expect(o.followRedirects, false);
              return _json({'error': 'https://private?token=secret'}, status);
            }),
        );
        try {
          await source.resolve('alpha');
          fail('expected failure');
        } on RingDownloadException catch (e) {
          expect(
            e.code,
            status == 429
                ? RingDownloadError.rateLimited
                : RingDownloadError.network,
          );
          expect(e.toString(), isNot(contains('secret')));
        } finally {
          source.dispose();
        }
      },
    );
  }

  test('metadata response has a strict body limit', () async {
    final source = HostedRingReleaseSource(
      http: Dio()
        ..httpClientAdapter = _Adapter(
          (_) async => ResponseBody.fromBytes(List.filled(65537, 32), 200),
        ),
    );
    await expectLater(
      source.resolve('alpha'),
      throwsA(errorCode(RingDownloadError.invalidMetadata)),
    );
    source.dispose();
  });

  test('dispose cancels an in-flight metadata lookup', () async {
    final started = Completer<void>();
    final source = HostedRingReleaseSource(
      http: Dio()
        ..httpClientAdapter = _Adapter((_) async {
          started.complete();
          return Completer<ResponseBody>().future;
        }),
    );
    final lookup = source.resolve('alpha');
    final expectation = expectLater(
      lookup,
      throwsA(errorCode(RingDownloadError.disposed)),
    );
    await started.future;
    source.dispose();
    await expectation;
  });

  test(
    'one-call download uses one exact metadata snapshot and verifies all bytes',
    () async {
      final temp = await Directory.systemTemp.createTemp('ring-latest-');
      final file = await File(
        '${temp.path}/app.apk',
      ).writeAsBytes([1, 2, 3, 4]);
      final engine = _Engine(file);
      var lookups = 0;
      final sdk = RingDownloadSdk.withEngine(
        RingDownloadConfig(
          appId: 'alpha',
          observeLifecycle: false,
          resolveRelease: (appId) async {
            lookups++;
            expect(appId, 'alpha');
            return parseHostedRelease(metadata(appId), appId);
          },
        ),
        engine,
      );
      try {
        final task = await sdk.downloadLatest();
        final result = await task.completed;
        expect(lookups, 1);
        expect(engine.request, same(task.request));
        expect(result.sha256, metadata('alpha')['sha256']);
        sdk.setSharingEnabled(true);
        expect(engine.sharing, true);
        sdk.setSharingEnabled(false);
        expect(engine.sharing, false);
      } finally {
        await sdk.dispose();
        await temp.delete(recursive: true);
      }
      expect(
        () => sdk.setSharingEnabled(true),
        throwsA(errorCode(RingDownloadError.disposed)),
      );
    },
  );

  test('disposing during a business lookup fences its late response', () async {
    final gate = Completer<RingDownloadRequest>();
    final sdk = RingDownloadSdk.withEngine(
      RingDownloadConfig(
        appId: 'alpha',
        observeLifecycle: false,
        resolveRelease: (_) => gate.future,
      ),
      _Engine(File('unused')),
    );
    final lookup = sdk.latestRelease();
    final expectation = expectLater(
      lookup,
      throwsA(errorCode(RingDownloadError.disposed)),
    );
    await sdk.dispose();
    gate.complete(parseHostedRelease(metadata('alpha'), 'alpha'));
    await expectation;
  });

  test('business resolver exceptions cannot expose a signed URL', () async {
    final sdk = RingDownloadSdk.withEngine(
      RingDownloadConfig(
        appId: 'alpha',
        observeLifecycle: false,
        resolveRelease: (_) async =>
            throw StateError('https://private?token=secret'),
      ),
      _Engine(File('unused')),
    );
    try {
      await sdk.latestRelease();
      fail('expected failure');
    } on RingDownloadException catch (e) {
      expect(e.code, RingDownloadError.invalidMetadata);
      expect(e.toString(), isNot(contains('secret')));
    } finally {
      await sdk.dispose();
    }
  });
}

ResponseBody _json(Object data, [int status = 200]) => ResponseBody.fromString(
  jsonEncode(data),
  status,
  headers: {
    'content-type': ['application/json'],
  },
);

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);
  final Future<ResponseBody> Function(RequestOptions) respond;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => Future.any([
    respond(options),
    if (cancelFuture != null)
      cancelFuture.then<ResponseBody>((_) => throw StateError('cancelled')),
  ]);
  @override
  void close({bool force = false}) {}
}

class _Engine implements RingTransferEngine {
  _Engine(this.file);
  final File file;
  RingDownloadRequest? request;
  bool sharing = false;
  @override
  Future<File> download(
    RingDownloadRequest request,
    void Function(int, int) progress,
    CancelToken token,
  ) async {
    this.request = request;
    progress(request.fileSize, request.fileSize);
    return file;
  }

  @override
  void setForeground(bool foreground) {}
  @override
  void setSharingEnabled(bool enabled) {
    sharing = enabled;
  }

  @override
  Future<void> dispose() async {}
}
