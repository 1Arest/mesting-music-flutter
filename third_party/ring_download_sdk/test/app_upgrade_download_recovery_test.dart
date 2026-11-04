import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ring_download_sdk/compat.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _source = 'https://download.csnas.asia/lifering/download';
const _session = '0123456789abcdef';
const _taskKey = 'app_upgrade.v40.task.recovery';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late AppUpgradeInfo info;
  late Uint8List bytes;
  late Dio http;
  late AppUpgradeServiceEvents events;
  late List<Map> reported;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    directory = await Directory.systemTemp.createTemp('upgrade-recovery-');
    bytes = Uint8List.fromList(List.generate(64, (index) => index));
    info = AppUpgradeInfo(
      releaseId: 'recovery',
      versionName: 'test',
      versionCode: 8904,
      releaseNotes: '',
      forceUpdate: false,
      downloadUrl: _source,
      fileSize: bytes.length,
      sha256: sha256.convert(bytes).toString(),
      downloadSlug: 'lifering',
      downloadEtag: '"release"',
      downloadProtocol: 'APK_SERVICE_V40',
    );
    http = Dio();
    reported = [];
    final telemetry = Dio();
    telemetry.interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) {
          reported.add(Map.from(request.data as Map));
          handler.resolve(Response(requestOptions: request, statusCode: 201));
        },
      ),
    );
    events = AppUpgradeServiceEvents(dio: telemetry);
  });

  tearDown(() async {
    await events.flush();
    http.close(force: true);
    await directory.delete(recursive: true);
  });

  Future<File> download() =>
      AppUpgradeV40DownloadClient(
        dio: http,
        p2pClient: AppUpgradeV40P2PClient(isAndroid: false),
        supportDirectoryLoader: () async => directory,
        serviceEvents: events,
      ).download(
        info: info,
        url: _source,
        backupUrl: null,
        refreshRelease: () async => info,
        onProgress: (_, _) {},
      );

  void respond(
    RequestOptions request,
    RequestInterceptorHandler handler,
    int status,
    Stream<Uint8List> body,
    Map<String, List<String>> headers,
  ) {
    handler.resolve(
      Response(
        requestOptions: request,
        statusCode: status,
        headers: Headers.fromMap(headers),
        data: ResponseBody(body, status, headers: headers),
      ),
    );
  }

  test(
    'a refreshed digest removes obsolete partial state and starts a verified new package',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final oldSha = 'f' * 64;
      final oldPart = File(
        '${directory.path}/app-upgrades/recovery-${oldSha.substring(0, 12)}.apk.part',
      );
      await oldPart.parent.create(recursive: true);
      await oldPart.writeAsBytes([99, 99, 99]);
      await prefs.setString(
        _taskKey,
        jsonEncode({
          'releaseId': info.releaseId,
          'slug': info.downloadSlug,
          'sha256': oldSha,
          'fileSize': 99,
          'etag': '"old"',
          'sessionId': _session,
        }),
      );
      await prefs.setString('$_taskKey.event_context', 'old-coverage');
      http.interceptors.add(
        InterceptorsWrapper(
          onRequest: (request, handler) {
            expect(request.headers['range'], isNull);
            expect(request.headers['X-Download-Session-Id'], isNull);
            expect(request.headers['if-range'], isNull);
            respond(request, handler, 200, Stream.value(bytes), {
              'content-length': ['${bytes.length}'],
              'etag': [info.downloadEtag],
            });
          },
        ),
      );
      final file = await download();
      expect(await file.readAsBytes(), bytes);
      expect(sha256.convert(await file.readAsBytes()).toString(), info.sha256);
      expect(await oldPart.exists(), isFalse);
      expect(prefs.getString(_taskKey), isNull);
      expect(prefs.getString('$_taskKey.event_context'), isNull);
    },
  );

  test(
    'recreated downloader retains persisted peer provenance on 206',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final part = File(
        '${directory.path}/app-upgrades/'
        'recovery-${info.sha256.substring(0, 12)}.apk.part',
      );
      await part.parent.create(recursive: true);
      await part.writeAsBytes(bytes.sublist(0, 10), flush: true);
      await prefs.setString(
        _taskKey,
        jsonEncode({
          'releaseId': info.releaseId,
          'slug': info.downloadSlug,
          'sha256': info.sha256,
          'fileSize': info.fileSize,
          'etag': info.downloadEtag,
          'sessionId': _session,
          'httpOrigin': 'https://download.csnas.asia',
          'p2pContributed': true,
        }),
      );
      http.interceptors.add(
        InterceptorsWrapper(
          onRequest: (request, handler) {
            expect(request.headers['range'], 'bytes=10-');
            respond(
              request,
              handler,
              206,
              Stream.value(Uint8List.fromList(bytes.sublist(10))),
              {
                'content-range': ['bytes 10-63/64'],
                'etag': [info.downloadEtag],
                'x-download-session-id': [_session],
              },
            );
          },
        ),
      );
      expect(await (await download()).readAsBytes(), bytes);
      await events.flush();
      expect(reported, isEmpty);
    },
  );

  test(
    'COS interruption cannot report site session bytes or duration',
    () async {
      var siteRequests = 0;
      Stream<Uint8List> interrupted() async* {
        yield Uint8List.fromList(bytes.sublist(0, 10));
        throw const HttpException('interrupted');
      }

      http.interceptors.add(
        InterceptorsWrapper(
          onRequest: (request, handler) {
            if (request.uri.host == 'download.csnas.asia') {
              siteRequests++;
              if (siteRequests == 1) {
                respond(request, handler, 200, interrupted(), {
                  'etag': [info.downloadEtag],
                  'x-download-session-id': [_session],
                });
              } else {
                respond(request, handler, 302, const Stream.empty(), {
                  'location': ['https://cdn.example.com/app.apk'],
                });
              }
            } else {
              expect(request.headers.containsKey('X-Device-Id'), isFalse);
              respond(request, handler, 200, interrupted(), {
                'etag': ['"cos"'],
              });
            }
          },
        ),
      );
      await expectLater(download(), throwsA(isA<HttpException>()));
      await events.flush();
      expect(reported, isEmpty);
      final prefs = await SharedPreferences.getInstance();
      final task = jsonDecode(prefs.getString(_taskKey)!) as Map;
      expect(task['nonServiceContributed'], isTrue);
      expect(task['httpOrigin'], 'https://cdn.example.com');
    },
  );

  test(
    'unfinished error body is cancelled within its total read deadline',
    () async {
      var cancelled = false;
      final body = StreamController<Uint8List>(
        onCancel: () {
          cancelled = true;
        },
      );
      http.interceptors.add(
        InterceptorsWrapper(
          onRequest: (request, handler) {
            respond(request, handler, 409, body.stream, {});
            body.add(
              Uint8List.fromList(utf8.encode('{"error":"invalid_request"}')),
            );
          },
        ),
      );
      final watch = Stopwatch()..start();
      await expectLater(download(), throwsA(isA<HttpException>()));
      expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
      expect(cancelled, isTrue);
      await body.close();
    },
  );
}
