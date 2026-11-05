import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ring_download_sdk/ring_download_sdk.dart';
import 'package:ring_download_sdk/src/sdk/engine.dart';
import 'package:ring_download_sdk/src/sdk/release_source.dart';

final payload = Uint8List.fromList(List.generate(4096, (i) => i % 251));
final cos = Uri.parse('https://business.cos.example.test/app.apk?sign=PRIVATE');
Matcher code(RingDownloadError value) =>
    isA<RingDownloadException>().having((error) => error.code, 'code', value);

ResponseBody reply({
  int status = 200,
  Uint8List? bytes,
  bool length = true,
  String? etag,
  String? range,
  String? location,
  Stream<Uint8List>? stream,
}) {
  final data = bytes ?? payload;
  final headers = <String, List<String>>{
    if (length) 'content-length': ['${data.length}'],
    if (etag != null) 'etag': [etag],
    if (range != null) 'content-range': [range],
    if (location != null) 'location': [location],
  };
  return stream == null
      ? ResponseBody.fromBytes(data, status, headers: headers)
      : ResponseBody(stream, status, headers: headers);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late _Script transport;
  late _OfflineHosted offline;
  late List<RingDownloadDiagnostic> diagnostics;
  RingDownloadSdk? sdk;
  RingDownloadSdk create({
    Future<RingDownloadRequest?> Function(RingDownloadRequest)? refresh,
    bool enableP8P = false,
  }) {
    final config = RingDownloadConfig(
      appId: 'lifering',
      storageDirectory: directory,
      observeLifecycle: false,
      // Even an enabled P2P/share configuration cannot reroute an external URL.
      enableP2P: true,
      enableP8P: enableP8P,
      allowSharing: true,
      refreshRelease: refresh,
      onDiagnostic: diagnostics.add,
    );
    return sdk = RingDownloadSdk.withEngine(
      config,
      DefaultRingTransferEngine(
        config,
        http: Dio()..httpClientAdapter = transport,
      ),
      releaseSource: offline,
    );
  }

  RingDownloadRequest request({
    int size = 0,
    String digest = '',
    Uri? url,
    Uri? backup,
  }) => RingDownloadRequest(
    url: url ?? cos,
    fileSize: size,
    sha256: digest,
    backupUrl: backup,
  );

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('ring-external-');
    transport = _Script((_, _) => reply());
    offline = _OfflineHosted();
    diagnostics = [];
  });
  tearDown(() async {
    await sdk?.dispose();
    sdk = null;
    expect(offline.calls, 0, reason: 'COS must never require hosted health');
    await directory.delete(recursive: true);
  });

  test(
    'COS URL alone completes while hosted metadata is unavailable',
    () async {
      final result = await create().download(request()).completed;
      expect(await result.file.readAsBytes(), payload);
      expect(result.fileSize, payload.length);
      expect(result.sha256, sha256.convert(payload).toString());
      expect(result.verification, RingDownloadVerification.transportOnly);
      expect(transport.calls.single.uri, cos);
      expect(diagnostics.any((e) => e.code == 'direct_https'), true);
      expect(diagnostics.any((e) => e.verified == true), false);
      expect(diagnostics.toString(), isNot(contains('PRIVATE')));
    },
  );

  test('P8P opt-in never makes external COS depend on hosted health', () async {
    final result = await create(enableP8P: true).download(request()).completed;
    expect(await result.file.readAsBytes(), payload);
    expect(result.sha256, sha256.convert(payload).toString());
    expect(transport.calls.single.uri, cos);
    expect(offline.calls, 0);
  });

  test(
    'LifeRing COS response accepts absent size/hash and stale protocol',
    () async {
      final adapted = RingDownloadRequest.fromLifeRing({
        'hasUpdate': true,
        'releaseId': 'life-release',
        'versionName': '1.6.6',
        'versionCode': 8907,
        'downloadUrl': cos.toString(),
        'downloadProtocol': 'APK_SERVICE_V40',
        'downloadSlug': 'lifering',
        'downloadBackupUrl': 'https://download1.csnas.asia/lifering/download',
      });
      expect(adapted.backupUrl, null);
      expect(adapted.androidVersionCode, null);
      final result = await create().download(adapted).completed;
      expect(result.verification, RingDownloadVerification.transportOnly);
      expect(transport.calls, hasLength(1));
    },
  );

  test('provided SHA remains enforced for external downloads', () async {
    final result = await create()
        .download(
          request(
            size: payload.length,
            digest: sha256.convert(payload).toString(),
          ),
        )
        .completed;
    expect(result.verification, RingDownloadVerification.sha256);
    expect(diagnostics.any((e) => e.verified == true), true);
  });

  test('known size without SHA is a size-only receipt', () async {
    final result = await create()
        .download(request(size: payload.length))
        .completed;
    expect(result.verification, RingDownloadVerification.sizeOnly);
  });

  test('SHA without known size is supported for an external source', () async {
    final result = await create()
        .download(request(digest: sha256.convert(payload).toString()))
        .completed;
    expect(result.verification, RingDownloadVerification.sha256);
  });

  test('wrong supplied SHA cannot yield download success', () async {
    await expectLater(
      create().download(request(digest: 'a' * 64)).completed,
      throwsA(code(RingDownloadError.integrity)),
    );
  });

  test('wrong supplied size cannot yield download success', () async {
    await expectLater(
      create().download(request(size: 8192)).completed,
      throwsA(code(RingDownloadError.integrity)),
    );
  });

  test(
    'chunked unknown-length body reports real bytes and final actual total',
    () async {
      transport.respond = (_, _) => reply(
        length: false,
        stream: Stream.fromIterable([
          payload.sublist(0, 1024),
          payload.sublist(1024),
        ]),
      );
      final task = create().download(request());
      final events = <RingDownloadProgress>[];
      final listener = task.progress.listen(events.add);
      final result = await task.completed;
      await listener.cancel();
      expect(result.fileSize, payload.length);
      expect(events.any((e) => e.receivedBytes > 0 && !e.hasKnownTotal), true);
      expect(task.latest.receivedBytes, payload.length);
      expect(task.latest.totalBytes, payload.length);
      expect(task.latest.fraction, 1);
    },
  );

  test('truncated HTTP body fails after bounded recovery attempts', () async {
    transport.respond = (_, _) =>
        reply(stream: Stream.value(payload.sublist(0, 100)));
    await expectLater(
      create().download(request()).completed,
      throwsA(code(RingDownloadError.network)),
    );
    expect(transport.calls, hasLength(3));
  });

  Future<void> cancelAndResume({
    bool etag = true,
    bool ignored = false,
    bool badRange = false,
    bool changedEtag = false,
  }) async {
    final firstChunk = Completer<void>();
    final body = StreamController<Uint8List>();
    body.onListen = () => body.add(payload.sublist(0, 1024));
    body.onCancel = () {
      if (!body.isClosed) unawaited(body.close());
    };
    transport.respond = (options, index) {
      if (index == 0) {
        return reply(stream: body.stream, etag: etag ? '"stable"' : null);
      }
      if (!etag || ignored) {
        expect(options.headers['Range'], etag ? 'bytes=1024-' : null);
        return reply(etag: etag ? '"new"' : null);
      }
      expect(options.headers['Range'], 'bytes=1024-');
      expect(options.headers['If-Range'], '"stable"');
      return reply(
        status: 206,
        bytes: payload.sublist(1024),
        etag: changedEtag ? '"changed"' : '"stable"',
        range: 'bytes ${badRange ? 1025 : 1024}-4095/4096',
      );
    };
    final download = create();
    final first = download.download(request());
    final listen = first.progress.listen((p) {
      if (p.receivedBytes >= 1024 && !firstChunk.isCompleted) {
        firstChunk.complete();
      }
    });
    await firstChunk.future.timeout(const Duration(seconds: 3));
    first.cancel();
    await expectLater(
      first.completed,
      throwsA(code(RingDownloadError.cancelled)),
    );
    await listen.cancel();
    final second = download.download(request());
    if (badRange || changedEtag) {
      await expectLater(
        second.completed,
        throwsA(code(RingDownloadError.integrity)),
      );
    } else {
      expect(await (await second.completed).file.readAsBytes(), payload);
    }
    expect(transport.calls, hasLength(2));
  }

  test(
    'cancelled COS transfer resumes with source-scoped strong ETag',
    () => cancelAndResume(),
  );
  test(
    'unknown identity without ETag restarts safely after cancellation',
    () => cancelAndResume(etag: false),
  );
  test(
    'server ignoring Range replaces the partial instead of appending',
    () => cancelAndResume(ignored: true),
  );
  test(
    'wrong Content-Range cannot splice a resumed file',
    () => cancelAndResume(badRange: true),
  );
  test(
    'changed ETag on 206 cannot splice a resumed file',
    () => cancelAndResume(changedEtag: true),
  );

  test('HTTPS redirects stay on the direct route with clean headers', () async {
    transport.respond = (_, index) => index == 0
        ? reply(status: 302, location: 'https://cdn.example.test/next.apk')
        : reply();
    await create().download(request()).completed;
    expect(transport.calls.last.uri.host, 'cdn.example.test');
    for (final call in transport.calls) {
      final headers = call.headers.keys.map((k) => k.toLowerCase());
      expect(headers, isNot(contains('authorization')));
      expect(headers, isNot(contains('cookie')));
      expect(headers, isNot(contains('x-device-id')));
      expect(headers, isNot(contains('x-download-session')));
    }
  });

  test(
    'HTTP downgrade redirect is rejected before destination request',
    () async {
      transport.respond = (_, _) =>
          reply(status: 302, location: 'http://cdn.example.test/a.apk');
      await expectLater(
        create().download(request()).completed,
        throwsA(code(RingDownloadError.invalidRequest)),
      );
      expect(transport.calls, hasLength(1));
    },
  );

  test('redirect loops have a bounded request count', () async {
    transport.respond = (_, _) => reply(status: 302, location: cos.toString());
    await expectLater(
      create().download(request()).completed,
      throwsA(code(RingDownloadError.network)),
    );
    expect(transport.calls, hasLength(6));
  });

  test(
    'expired COS URL refreshes through business callback without health',
    () async {
      var refreshes = 0;
      transport.respond = (_, index) =>
          index == 0 ? reply(status: 403) : reply();
      final download = create(
        refresh: (original) async {
          refreshes++;
          return request(
            url: Uri.parse(
              'https://business.cos.example.test/app.apk?sign=NEW',
            ),
          );
        },
      );
      await download.download(request()).completed;
      expect(refreshes, 1);
      expect(transport.calls.last.uri.query, 'sign=NEW');
    },
  );

  test('refresh callback cannot change expected file identity', () async {
    transport.respond = (_, _) => reply(status: 403);
    final download = create(refresh: (_) async => request(digest: 'b' * 64));
    await expectLater(
      download.download(request()).completed,
      throwsA(code(RingDownloadError.invalidMetadata)),
    );
    expect(transport.calls, hasLength(1));
  });

  test('stale hosted backup never becomes a COS health dependency', () async {
    transport.respond = (_, _) => reply(status: 503);
    await expectLater(
      create()
          .download(
            request(
              backup: Uri.parse(
                'https://download1.csnas.asia/lifering/download',
              ),
            ),
          )
          .completed,
      throwsA(code(RingDownloadError.network)),
    );
    expect(transport.calls, hasLength(3));
    expect(transport.calls.every((c) => c.uri.host == cos.host), true);
  });

  test(
    'business-provided external backup works without hosted service',
    () async {
      transport.respond = (options, _) =>
          options.uri.host == cos.host ? reply(status: 503) : reply();
      final result = await create()
          .download(
            request(
              backup: Uri.parse('https://other.cdn.example.test/app.apk'),
            ),
          )
          .completed;
      expect(await result.file.readAsBytes(), payload);
      expect(transport.calls, hasLength(4));
    },
  );

  test(
    'hosted sources still require complete metadata before transfer',
    () async {
      final download = create();
      for (final host in RingDownloadRequest.hostedHosts) {
        expect(
          () => download.download(
            request(url: Uri.parse('https://$host/lifering/download')),
          ),
          throwsA(code(RingDownloadError.invalidRequest)),
        );
      }
      expect(transport.calls, isEmpty);
    },
  );

  test(
    'host boundary uses exact domain instead of substring matching',
    () async {
      final result = await create()
          .download(
            request(
              url: Uri.parse(
                'https://download.csnas.asia.external.test/app.apk',
              ),
            ),
          )
          .completed;
      expect(result.verification, RingDownloadVerification.transportOnly);
    },
  );

  test(
    'LifeRing adapter keeps actual APK build separate from business code',
    () {
      final selected = RingDownloadRequest.fromLifeRing({
        'downloadUrl': cos.toString(),
        'versionCode': 9000,
        'downloadVersionCode': 8907,
      });
      expect(selected.androidVersionCode, 8907);
      expect(selected.fileSize, 0);
      expect(selected.sha256, '');
    },
  );

  test('external receipt revalidation detects later file mutation', () async {
    final result = await create().download(request()).completed;
    await result.revalidate();
    await result.file.writeAsBytes(List.filled(payload.length, 1));
    await expectLater(
      result.revalidate(),
      throwsA(code(RingDownloadError.integrity)),
    );
  });

  test('invalid supplied metadata remains an explicit input error', () {
    expect(
      () => create().download(request(digest: 'not-a-sha')),
      throwsA(code(RingDownloadError.invalidRequest)),
    );
    expect(
      () => RingDownloadRequest.fromLifeRing({
        'downloadUrl': cos.toString(),
        'fileSize': -1,
      }),
      throwsA(code(RingDownloadError.invalidRequest)),
    );
  });
}

class _OfflineHosted implements RingReleaseSource {
  int calls = 0;
  @override
  Future<RingDownloadRequest> resolve(String appId) async {
    calls++;
    throw StateError('Hosted service is offline; COS must not call this');
  }

  @override
  void dispose() {}
}

class _Script implements HttpClientAdapter {
  _Script(this.respond);
  ResponseBody Function(RequestOptions, int) respond;
  final calls = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final index = calls.length;
    calls.add(options);
    expect(options.uri.host, isNot('download.csnas.asia'));
    expect(options.uri.host, isNot('download1.csnas.asia'));
    return respond(options, index);
  }

  @override
  void close({bool force = false}) {}
}
