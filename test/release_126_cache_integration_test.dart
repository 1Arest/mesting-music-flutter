import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesting_music/core/cache/browse_response_cache.dart';
import 'package:mesting_music/core/database/app_database.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/music_platform/data/embedded_music_server.dart';
import 'package:mesting_music/features/music_platform/data/music_platform_api.dart';
import 'package:mesting_music/features/music_platform/data/platform_library_repository.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/music_platform/netease/netease_api.dart';
import 'package:mesting_music/features/music_platform/netease/netease_library_repository.dart';
import 'package:mesting_music/features/music_platform/netease/netease_music_repository.dart';
import 'package:mesting_music/features/music_platform/netease/netease_providers.dart';
import 'package:mesting_music/features/music_platform/netease/netease_session.dart';
import 'package:mesting_music/features/music_platform/platform_catalog_providers.dart';

const _session = NeteaseSession(
  userId: '7',
  deviceId: 'fixture',
  cookies: {'MUSIC_U': 'private-fixture-cookie'},
);

class _Account extends PlatformAccountController {
  @override
  Future<PlatformSession?> build() async => _session.identity;
}

class _Server implements MusicServer {
  @override
  Future<Uri> start() async => Uri.parse('http://127.0.0.1:12647');
}

http.Response _json(Object body) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), 200);
void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp(
      'mesting-cache-integration-126-',
    );
  });
  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await root.delete(recursive: true);
  });
  Future<BrowseResponseCache> cache() async {
    final result = BrowseResponseCache(directory: () async => root);
    await result.initialize();
    return result;
  }

  test(
    'a rejected Kugou edit retains the snapshot; a confirmed edit invalidates it',
    () async {
      var reads = 0, accepted = false;
      const identity = PlatformSession(userId: '7', token: 'fixture');
      final api = MusicPlatformApi(
        server: _Server(),
        browseCache: await cache(),
        client: MockClient((request) async {
          if (request.method == 'POST') {
            return _json({
              'status': accepted ? 1 : 0,
              'error_code': accepted ? 0 : 123,
            });
          }
          reads++;
          return _json({'status': 1, 'name': accepted ? 'fresh' : 'saved'});
        }),
      )..session = identity;
      final watch = BrowseCacheWatch(() {});
      addTearDown(watch.dispose);
      expect(
        (await watch.run(() => api.get('/user/playlist')))['name'],
        'saved',
      );
      await api.post(
        '/playlist/update',
        query: {'name': 'new'},
        expectedSession: identity,
      );
      expect(
        (await watch.run(() => api.get('/user/playlist')))['name'],
        'saved',
      );
      expect(reads, 1);
      accepted = true;
      await api.post(
        '/playlist/update',
        query: {'name': 'new'},
        expectedSession: identity,
      );
      expect(
        (await watch.run(() => api.get('/user/playlist')))['name'],
        'fresh',
      );
      expect(reads, 2);
    },
  );

  Map<String, dynamic> songs(String title) => {
    'code': 200,
    'data': {
      'dailySongs': [
        {'id': 1, 'name': title},
      ],
    },
  };
  Map<String, dynamic> lists(String title) => {
    'code': 200,
    'more': false,
    'playlist': [
      {
        'id': 10,
        'name': title,
        'creator': {'userId': 7},
      },
    ],
  };

  test(
    'actual daily provider restores disk data and re-emits the fresh response after a restart',
    () async {
      final before = NeteaseApi(
        MockClient((_) async => _json(songs('saved-song'))),
        browseCache: await cache(),
      )..configure(_session);
      ProviderContainer container(NeteaseApi api) => ProviderContainer(
        overrides: [
          platformAccountProvider.overrideWith(_Account.new),
          neteaseApiProvider.overrideWithValue(api),
        ],
      );
      final oldContainer = container(before);
      expect(
        (await oldContainer.read(platformDailyProvider.future)).single.title,
        'saved-song',
      );
      oldContainer.dispose();
      final network = Completer<http.Response>();
      var calls = 0;
      final after = NeteaseApi(
        MockClient((_) {
          calls++;
          return network.future;
        }),
        browseCache: await cache(),
      )..configure(_session);
      final current = container(after);
      addTearDown(current.dispose);
      final refreshed = Completer<void>();
      current.listen(platformDailyProvider, (_, value) {
        if (value.value?.firstOrNull?.title == 'fresh-song' &&
            !refreshed.isCompleted) {
          refreshed.complete();
        }
      });
      expect(
        (await current.read(platformDailyProvider.future)).single.title,
        'saved-song',
      );
      network.complete(_json(songs('fresh-song')));
      await refreshed.future.timeout(const Duration(seconds: 5));
      expect(
        current.read(platformDailyProvider).value?.single.title,
        'fresh-song',
      );
      expect(
        calls,
        1,
        reason: 'Provider invalidation must not start a second refresh loop.',
      );
      for (final entity in await Directory(
        '${root.path}/mesting_browse_cache_v1',
      ).list().toList()) {
        expect(
          await (entity as File).readAsString(),
          isNot(contains('private-fixture-cookie')),
        );
      }
    },
  );
  test(
    'actual personal library stream emits saved playlists then the updated list',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final before = NeteaseApi(
        MockClient((_) async => _json(lists('saved-playlist'))),
        browseCache: await cache(),
      )..configure(_session);
      final first = NeteaseLibraryRepository(
        db,
        music: NeteaseMusicRepository(before),
        identity: _session.identity,
      );
      expect(
        (await first.watchPlaylists().first).single.name,
        'saved-playlist',
      );
      first.dispose();
      final network = Completer<http.Response>();
      final after = NeteaseApi(
        MockClient((_) => network.future),
        browseCache: await cache(),
      )..configure(_session);
      final repository = NeteaseLibraryRepository(
        db,
        music: NeteaseMusicRepository(after),
        identity: _session.identity,
      );
      addTearDown(repository.dispose);
      final stream = StreamIterator(repository.watchPlaylists());
      addTearDown(stream.cancel);
      expect(await stream.moveNext(), isTrue);
      expect(stream.current.single.name, 'saved-playlist');
      network.complete(_json(lists('fresh-playlist')));
      expect(
        await stream.moveNext().timeout(const Duration(seconds: 5)),
        isTrue,
      );
      expect(stream.current.single.name, 'fresh-playlist');
    },
  );
  test(
    'Kugou personal library also restores first and updates without a platform switch',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      const identity = PlatformSession(
        userId: '7',
        token: 'private-kugou-fixture',
      );
      Map<String, Object?> response(String name) => {
        'status': 1,
        'data': {
          'list': [
            {'listid': 12, 'name': name},
          ],
        },
      };
      final firstApi = MusicPlatformApi(
        server: _Server(),
        client: MockClient((_) async => _json(response('saved-kugou'))),
        browseCache: await cache(),
      )..session = identity;
      final first = PlatformLibraryRepository(
        db,
        api: firstApi,
        identity: identity,
      );
      expect((await first.watchPlaylists().first).single.name, 'saved-kugou');
      first.dispose();
      final network = Completer<http.Response>();
      final api = MusicPlatformApi(
        server: _Server(),
        client: MockClient((_) => network.future),
        browseCache: await cache(),
      )..session = identity;
      final repository = PlatformLibraryRepository(
        db,
        api: api,
        identity: identity,
      );
      addTearDown(repository.dispose);
      final stream = StreamIterator(repository.watchPlaylists());
      addTearDown(stream.cancel);
      expect(await stream.moveNext(), isTrue);
      expect(stream.current.single.name, 'saved-kugou');
      network.complete(_json(response('fresh-kugou')));
      expect(
        await stream.moveNext().timeout(const Duration(seconds: 5)),
        isTrue,
      );
      expect(stream.current.single.name, 'fresh-kugou');
      expect(api.session, identity);
    },
  );
}
