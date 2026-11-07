import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesting_music/core/database/app_database.dart';
import 'package:mesting_music/features/music_platform/data/embedded_music_server.dart';
import 'package:mesting_music/features/music_platform/data/music_platform_api.dart';
import 'package:mesting_music/features/music_platform/data/platform_library_repository.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';

class _Server implements MusicServer {
  @override
  Future<Uri> start() async => Uri.parse('http://127.0.0.1:12345');
}

const _session = PlatformSession(userId: '7', token: 'fixture');
const _owned = {
  'listid': 22,
  'name': '旅行',
  'type': 0,
  'is_pri': 1,
  'sort': 8,
  'list_create_userid': 7,
  'pic': 'https://example.test/original.png',
};
http.Response _response(Object data) => http.Response(
  jsonEncode(data),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
http.Response _ok(Object data) =>
    _response({'status': 1, 'error_code': 0, 'data': data});

void main() {
  late AppDatabase db;
  late MusicPlatformApi api;
  late PlatformLibraryRepository repo;
  late List<http.Request> requests;
  late List<Map<String, dynamic>> lists;
  late bool rejectUpload;
  late bool rejectUpdate;
  late bool versionMissing;
  late Completer<http.Response>? uploadGate;
  final cover = File('assets/branding/mesting-mark-master.png').absolute.path;
  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    requests = [];
    lists = [
      {..._owned},
    ];
    rejectUpload = false;
    rejectUpdate = false;
    versionMissing = false;
    uploadGate = null;
    api = MusicPlatformApi(
      server: _Server(),
      client: MockClient((request) async {
        requests.add(request);
        switch (request.url.path) {
          case '/user/playlist':
            return _ok({'info': lists, if (!versionMissing) 'total_ver': 17});
          case '/playlist/pic/upload':
            if (uploadGate != null) return uploadGate!.future;
            return rejectUpload
                ? _response({'status': 0})
                : _response({'status': 1, 'FileName': 'cover.png'});
          case '/playlist/update':
            return rejectUpdate
                ? _response({'status': 1, 'error_code': 20017})
                : _ok({});
          case '/playlist/add':
            lists.add({
              ..._owned,
              'listid': 33,
              'name': request.url.queryParameters['name'],
            });
            return _ok({});
          default:
            return _ok({});
        }
      }),
    )..session = _session;
    repo = PlatformLibraryRepository(db, api: api, identity: _session);
  });
  tearDown(() async {
    repo.dispose();
    await db.close();
  });
  Future<void> save() => repo.updatePlaylist(
    id: 'kg:22',
    name: '夜行',
    description: '慢慢听',
    coverAsset: cover,
  );

  test(
    'cover upload precedes metadata update and preserves cloud privacy, sort and version',
    () async {
      await save();
      expect(requests.map((e) => e.url.path), [
        '/user/playlist',
        '/playlist/pic/upload',
        '/user/playlist',
        '/playlist/update',
      ]);
      final upload = requests[1];
      expect(upload.method, 'POST');
      expect(upload.url.queryParameters, containsPair('file', cover));
      expect(upload.url.queryParameters, containsPair('extendName', '.png'));
      expect(
        requests.last.url.queryParameters,
        containsPair('pic', 'custom/cover.png'),
      );
      expect(
        requests.last.url.queryParameters,
        containsPair('total_ver', '17'),
      );
      expect(requests.last.url.queryParameters, containsPair('is_pri', '1'));
      expect(requests.last.url.queryParameters, containsPair('sort', '8'));
    },
  );
  test(
    'failed upload cannot report a successful cover save or send a metadata update',
    () async {
      rejectUpload = true;
      await expectLater(save(), throwsA(isA<MusicPlatformException>()));
      expect(requests.where((e) => e.url.path == '/playlist/update'), isEmpty);
    },
  );
  test(
    'a status-200 business failure remains an error, without automatic retries',
    () async {
      rejectUpdate = true;
      await expectLater(save(), throwsA(isA<MusicPlatformException>()));
      expect(
        requests.where((e) => e.url.path == '/playlist/update'),
        hasLength(1),
      );
    },
  );
  test(
    'missing cloud version stops the write rather than guessing an optimistic lock',
    () async {
      versionMissing = true;
      await expectLater(save(), throwsA(isA<MusicPlatformException>()));
      expect(requests.where((e) => e.url.path == '/playlist/update'), isEmpty);
    },
  );
  test(
    'logging out during upload prevents the following metadata mutation',
    () async {
      uploadGate = Completer<http.Response>();
      final operation = save();
      final expectation = expectLater(
        operation,
        throwsA(isA<MusicPlatformException>()),
      );
      while (!requests.any((e) => e.url.path == '/playlist/pic/upload')) {
        await Future<void>.delayed(Duration.zero);
      }
      api.session = null;
      uploadGate!.complete(_response({'status': 1, 'FileName': 'cover.png'}));
      await expectation;
      expect(requests.where((e) => e.url.path == '/playlist/update'), isEmpty);
    },
  );
  test(
    'manual retry after partial creation resumes the same cloud list',
    () async {
      rejectUpload = true;
      await expectLater(
        repo.createPlaylist(id: 'draft', name: '新歌单', coverAsset: cover),
        throwsA(isA<MusicPlatformException>()),
      );
      rejectUpload = false;
      await repo.createPlaylist(id: 'draft', name: '新歌单', coverAsset: cover);
      expect(
        requests.where((e) => e.url.path == '/playlist/add'),
        hasLength(1),
      );
      expect(requests.last.url.queryParameters, containsPair('listid', '33'));
    },
  );
}
