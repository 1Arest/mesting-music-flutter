import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesting_music/core/database/app_database.dart';
import 'package:mesting_music/features/music_platform/data/embedded_music_server.dart';
import 'package:mesting_music/features/music_platform/data/music_platform_api.dart';
import 'package:mesting_music/features/music_platform/data/platform_catalog.dart';
import 'package:mesting_music/features/music_platform/data/platform_library_repository.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';

class _LocalServer implements MusicServer {
  @override
  Future<Uri> start() async => Uri.parse('http://127.0.0.1:12345');
}

const _identity = PlatformSession(userId: '7', token: 'test-session');
Map<String, dynamic> _song(String hash, {int fileid = 42}) => {
  'hash': hash,
  'songname': '云端歌曲 $hash',
  'singername': '歌手',
  'fileid': fileid,
};
const _likes = {
  'listid': 11,
  'name': '我喜欢',
  'is_def': 2,
  'type': 0,
  'list_create_userid': 7,
};
const _own = {
  'listid': 22,
  'name': '自建歌单',
  'type': 0,
  'list_create_userid': 7,
  'is_pri': 1,
  'sort': 8,
};
http.Response _ok(Object data) => http.Response(
  jsonEncode({'status': 1, 'error_code': 0, 'data': data}),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  late AppDatabase database;
  late List<http.Request> requests;
  late List<Map<String, dynamic>> favorites;
  late MusicPlatformApi api;
  late PlatformLibraryRepository repository;
  late bool rejectWrite;
  late Map<String, dynamic>? created;
  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    requests = [];
    favorites = [_song('AAA')];
    rejectWrite = false;
    created = null;
    api = MusicPlatformApi(
      server: _LocalServer(),
      client: MockClient((request) async {
        requests.add(request);
        switch (request.url.path) {
          case '/user/playlist':
            return _ok({
              'info': [_likes, _own, ?created],
              'total_ver': 17,
            });
          case '/playlist/track/all/new':
            return _ok({'info': favorites, 'total': favorites.length});
          case '/audio':
            return _ok([
              {
                'album_info': {'id': 123},
                'base': {'album_audio_id': 456},
              },
            ]);
          case '/playlist/add':
            created = {
              ..._own,
              'listid': 33,
              'name': request.url.queryParameters['name'],
            };
            return _ok({});
          case '/playlist/tracks/add':
            if (rejectWrite) return http.Response('{"status":0}', 502);
            favorites.add(
              _song(
                request.url.queryParameters['data']!.split('|')[1],
                fileid: 43,
              ),
            );
            return _ok({});
          case '/playlist/tracks/del':
            favorites.removeWhere(
              (row) =>
                  '${row['fileid']}' == request.url.queryParameters['fileids'],
            );
            return _ok({});
          default:
            return _ok({});
        }
      }),
    )..session = _identity;
    repository = PlatformLibraryRepository(
      database,
      api: api,
      identity: _identity,
    );
  });
  tearDown(() async {
    repository.dispose();
    await database.close();
  });

  test(
    'cloud lists and favorites load without copying into the guest database',
    () async {
      final playlists = await repository.watchPlaylists().first;
      final tracks = await repository.watchFavorites().first;
      expect(playlists.map((row) => row.id), ['kg:11', 'kg:22']);
      expect(tracks.single.id, 'kugou_AAA');
      expect(tracks.single.audioAsset, startsWith('mesting-platform:'));
      expect(
        await database.watchFavorites(legacyLibraryOwnerId).first,
        isEmpty,
      );
      expect(
        requests.every(
          (request) =>
              request.headers['Authorization'] == 'token=test-session;userid=7',
        ),
        true,
      );
      expect(
        requests.any(
          (request) =>
              request.url.path == '/playlist/track/all/new' &&
              request.url.queryParameters['listid'] == '11',
        ),
        true,
      );
    },
  );

  test(
    'favorite writes refresh cloud state and use playlist record IDs for deletion',
    () async {
      final target = PlatformCatalog.tracks([_song('BBB')]).single;
      await repository.setFavorite(target, favorite: true);
      expect(await repository.isFavorite(target.id), true);
      final add = requests.singleWhere(
        (request) => request.url.path == '/playlist/tracks/add',
      );
      expect(add.url.queryParameters['listid'], '11');
      expect(add.url.queryParameters['data'], '云端歌曲 BBB|BBB|123|456');
      await repository.setFavorite(
        PlatformCatalog.tracks([_song('AAA')]).single,
        favorite: false,
      );
      expect(await repository.isFavorite('kugou_AAA'), false);
      expect(
        requests
            .singleWhere(
              (request) => request.url.path == '/playlist/tracks/del',
            )
            .url
            .queryParameters['fileids'],
        '42',
      );
    },
  );

  test('a rejected cloud mutation never becomes a local success', () async {
    rejectWrite = true;
    final target = PlatformCatalog.tracks([_song('BBB')]).single;
    await expectLater(
      repository.setFavorite(target, favorite: true),
      throwsA(isA<MusicPlatformException>()),
    );
    expect(await repository.isFavorite(target.id), false);
    expect(
      requests
          .where((request) => request.url.path == '/playlist/tracks/add')
          .length,
      1,
    );
  });

  test('old repository cannot write with the next user credential', () async {
    await repository.watchPlaylists().first;
    api.session = const PlatformSession(userId: '8', token: 'next-session');
    final count = requests.length;
    await expectLater(
      repository.deletePlaylist('kg:22'),
      throwsA(isA<MusicPlatformException>()),
    );
    expect(requests.length, count);
  });

  test(
    'create, rename and delete use cloud IDs and preserve privacy and sort',
    () async {
      await repository.createPlaylist(id: 'local-uuid', name: '新歌单');
      final create = requests.singleWhere((r) => r.url.path == '/playlist/add');
      expect(create.url.queryParameters['is_pri'], '1');
      await repository.updatePlaylist(
        id: 'kg:22',
        name: '改名',
        description: '简介',
        coverAsset: null,
      );
      expect(
        requests.last.url.queryParameters,
        containsPair('total_ver', '17'),
      );
      expect(requests.last.url.queryParameters, containsPair('sort', '8'));
      expect(requests.last.url.queryParameters, containsPair('is_pri', '1'));
      await repository.deletePlaylist('kg:22');
      expect(requests.last.url.queryParameters['listid'], '22');
      await expectLater(
        repository.deletePlaylist('kg:11'),
        throwsA(isA<MusicPlatformException>()),
      );
    },
  );

  test(
    'parallel toggles serialize and end in the original favorite state',
    () async {
      final target = PlatformCatalog.tracks([_song('BBB')]).single;
      expect(
        await Future.wait([
          repository.toggleFavorite(target),
          repository.toggleFavorite(target),
        ]),
        [true, false],
      );
      expect(await repository.isFavorite(target.id), false);
    },
  );

  test(
    'catalog follows upstream daily endpoint for both guest and account requests',
    () async {
      final paths = <String>[];
      final catalogApi = MusicPlatformApi(
        server: _LocalServer(),
        client: MockClient((request) async {
          paths.add(request.url.path);
          return _ok([
            {
              'base': {'hash': 'NESTED', 'songname': '概念版推荐'},
            },
          ]);
        }),
      );
      final catalog = PlatformCatalog(catalogApi);
      expect((await catalog.daily()).single.title, '概念版推荐');
      catalogApi.session = _identity;
      await catalog.daily();
      await catalog.discovery();
      await catalog.newSongs();
      expect(paths, [
        '/everyday/recommend',
        '/everyday/recommend',
        '/home/discover',
        '/top/song',
      ]);
    },
  );

  test('private response finishing after logout is rejected', () async {
    final gate = Completer<http.Response>();
    api = MusicPlatformApi(
      server: _LocalServer(),
      client: MockClient((_) => gate.future),
    )..session = _identity;
    final request = api.get('/user/playlist', expectedSession: _identity);
    await Future<void>.delayed(Duration.zero);
    api.session = null;
    gate.complete(
      _ok({
        'info': [_likes],
      }),
    );
    await expectLater(request, throwsA(isA<MusicPlatformException>()));
  });

  test(
    'cloud pagination keeps collected playlists and all 201 favorite songs',
    () async {
      final pages = <String>[];
      final paginated = MusicPlatformApi(
        server: _LocalServer(),
        client: MockClient((request) async {
          final page = int.parse(request.url.queryParameters['page'] ?? '1');
          pages.add('${request.url.path}:$page');
          if (request.url.path == '/user/playlist') {
            return _ok({
              'info': page == 1
                  ? [
                      _likes,
                      for (var i = 0; i < 29; i++)
                        {'listid': 100 + i, 'name': '歌单 $i', 'type': 0},
                    ]
                  : [
                      {
                        'listid': 200,
                        'name': '收藏歌单',
                        'type': 0,
                        'source': 2,
                        'list_create_userid': 99,
                      },
                      {'listid': 201, 'name': '专辑', 'type': 1, 'source': 2},
                    ],
            });
          }
          return _ok({
            'info': page == 1
                ? [for (var i = 0; i < 200; i++) _song('HASH$i', fileid: i + 1)]
                : [_song('LAST', fileid: 201)],
          });
        }),
      )..session = _identity;
      final pagedRepository = PlatformLibraryRepository(
        database,
        api: paginated,
        identity: _identity,
      );
      addTearDown(pagedRepository.dispose);
      final playlists = await pagedRepository.watchPlaylists().first;
      expect(playlists.length, 31);
      expect(playlists.last.name, '收藏歌单');
      expect(pagedRepository.canManage('kg:200'), false);
      final songs = await pagedRepository.watchFavorites().first;
      expect(songs.length, 201);
      expect(songs.last.id, 'kugou_LAST');
      expect(
        pages,
        containsAll(['/user/playlist:2', '/playlist/track/all/new:2']),
      );
    },
  );
}
