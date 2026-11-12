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

class _Server implements MusicServer {
  @override
  Future<Uri> start() async => Uri.parse('http://127.0.0.1:12345');
}

const _session = PlatformSession(userId: '7', token: 'fixture');
const _liked = <String, dynamic>{
  'listid': 11,
  'name': '我喜欢',
  'is_def': 2,
  'type': 0,
  'list_create_userid': 7,
};
const _defaultCollection = <String, dynamic>{
  'listid': 10,
  'name': '默认收藏',
  'is_def': 0,
  'type': 0,
  'list_create_userid': 7,
};

Map<String, dynamic> _song(String hash, int recordId) => {
  'hash': hash,
  'songname': '歌曲 $hash',
  'singername': '歌手',
  'fileid': recordId,
};
http.Response _ok(Object data) => http.Response(
  jsonEncode({'status': 1, 'error_code': 0, 'data': data}),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  late AppDatabase database;
  late PlatformLibraryRepository repository;
  late List<Map<String, dynamic>> lists;
  late Map<String, List<Map<String, dynamic>>> songs;
  late List<http.Request> requests;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    // The real failure depended on ordering: the unrelated default collection
    // arrives first, so a fixture with only the liked list cannot catch it.
    lists = [
      {..._defaultCollection},
      {..._liked},
    ];
    songs = {
      '10': [_song('DEFAULT_ONLY', 100)],
      '11': [_song('LIKED', 110)],
    };
    requests = [];
    final api = MusicPlatformApi(
      server: _Server(),
      client: MockClient((request) async {
        requests.add(request);
        final query = request.url.queryParameters;
        switch (request.url.path) {
          case '/user/playlist':
            return _ok({'info': lists});
          case '/playlist/track/all/new':
            return _ok({'info': songs[query['listid']] ?? []});
          case '/audio':
            return _ok([
              {
                'album_info': {'id': 2},
                'base': {'album_audio_id': 3},
              },
            ]);
          case '/playlist/tracks/add':
            songs
                .putIfAbsent(query['listid']!, () => [])
                .add(_song(query['data']!.split('|')[1], 111));
            return _ok({});
          case '/playlist/tracks/del':
            songs[query['listid']]?.removeWhere(
              (row) => '${row['fileid']}' == query['fileids'],
            );
            return _ok({});
        }
        return _ok({});
      }),
    )..session = _session;
    repository = PlatformLibraryRepository(
      database,
      api: api,
      identity: _session,
    );
  });
  tearDown(() async {
    repository.dispose();
    await database.close();
  });

  test(
    'liked songs and heart status ignore a preceding default collection',
    () async {
      expect(
        (await repository.watchFavorites().first).map((track) => track.id),
        ['kugou_LIKED'],
      );
      expect(await repository.isFavorite('kugou_DEFAULT_ONLY'), isFalse);
      expect(await repository.isFavorite('kugou_LIKED'), isTrue);
      expect(
        requests
            .where((r) => r.url.path == '/playlist/track/all/new')
            .map((r) => r.url.queryParameters['listid']),
        everyElement('11'),
      );
    },
  );

  test(
    'heart add and remove use the liked list and its own record ids',
    () async {
      final track = PlatformCatalog.tracks([_song('NEW', 0)]).single;
      expect(await repository.toggleFavorite(track), isTrue);
      expect(await repository.toggleFavorite(track), isFalse);
      final mutations = requests
          .where(
            (r) =>
                r.url.path == '/playlist/tracks/add' ||
                r.url.path == '/playlist/tracks/del',
          )
          .toList();
      expect(mutations, hasLength(2));
      expect(
        mutations.map((r) => r.url.queryParameters['listid']),
        everyElement('11'),
      );
      expect(mutations.last.url.queryParameters['fileids'], '111');
      expect(songs['10']!.single['hash'], 'DEFAULT_ONLY');
      expect(songs['11']!.single['hash'], 'LIKED');
    },
  );

  test(
    'a system liked marker wins over an earlier same-name legacy row',
    () async {
      lists.insert(1, {..._liked, 'listid': 12, 'is_def': 0});
      songs['12'] = [_song('SAME_NAME', 120)];
      expect(
        (await repository.watchFavorites().first).single.id,
        'kugou_LIKED',
      );
    },
  );

  test('another account liked playlist cannot win by name or marker', () async {
    lists.insert(0, {..._liked, 'listid': 99, 'list_create_userid': 8});
    songs['99'] = [_song('FOREIGN', 990)];
    expect((await repository.watchFavorites().first).single.id, 'kugou_LIKED');
  });

  test(
    'a unique owned legacy liked list works when system markers are absent',
    () async {
      lists = [
        {..._defaultCollection},
        {..._liked}..remove('is_def'),
      ];
      expect(
        (await repository.watchFavorites().first).single.id,
        'kugou_LIKED',
      );
    },
  );

  test(
    'a default collection alone never becomes the heart destination',
    () async {
      lists = [
        {..._defaultCollection},
      ];
      final track = PlatformCatalog.tracks([_song('NEW', 0)]).single;
      await expectLater(
        repository.setFavorite(track, favorite: true),
        throwsA(isA<MusicPlatformException>()),
      );
      expect(requests.map((r) => r.url.path), ['/user/playlist']);
    },
  );

  test(
    'ambiguous liked lists fail without reading tracks or writing either list',
    () async {
      lists.add({..._liked, 'listid': 12});
      final track = PlatformCatalog.tracks([_song('NEW', 0)]).single;
      await expectLater(
        repository.setFavorite(track, favorite: true),
        throwsA(isA<MusicPlatformException>()),
      );
      expect(requests.map((r) => r.url.path), ['/user/playlist']);
    },
  );
}
