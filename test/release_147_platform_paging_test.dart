import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/music_platform/platform_backend_providers.dart';
import 'package:mesting_music/features/music_platform/platform_catalog_providers.dart';
import 'package:mesting_music/features/music_platform/platform_explore_providers.dart';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesting_music/core/database/app_database.dart';
import 'package:mesting_music/features/music_platform/data/embedded_music_server.dart';
import 'package:mesting_music/features/music_platform/data/music_platform_api.dart';
import 'package:mesting_music/features/music_platform/data/platform_library_repository.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/music_platform/netease/netease_api.dart';
import 'package:mesting_music/features/music_platform/netease/netease_music_repository.dart';
import 'package:mesting_music/features/music_platform/netease/netease_library_repository.dart';

const _identity = PlatformSession(userId: '7', token: 'paging-fixture');

class _SwitchingAccount extends PlatformAccountController {
  @override
  Future<PlatformSession?> build() async => _identity;
  void select(PlatformSession session) => state = AsyncData(session);
}

const _liked = {
  'listid': 11,
  'name': '我喜欢',
  'is_def': 2,
  'type': 0,
  'list_create_userid': 7,
};

class _Server implements MusicServer {
  @override
  Future<Uri> start() async => Uri.parse('http://127.0.0.1:12345');
}

/// Logical route fixtures keep request-count measurements independent of TLS,
/// provider credentials, media URLs and HTTP cache timing.
class _NeteaseFixture extends NeteaseMusicRepository {
  _NeteaseFixture(this.count)
    : super(
        NeteaseApi(MockClient((_) async => throw StateError('No network'))),
      );
  final int count;
  Set<String> unavailable = {};
  final requests = <(String, Map<String, Object?>)>[];
  @override
  Future<Map<String, dynamic>> call(
    String route, [
    Map<String, Object?> query = const {},
    Future<void>? abort,
  ]) async {
    requests.add((route, Map.of(query)));
    if (route == '/playlist/detail') {
      return {
        'playlist': {
          'trackIds': [
            for (var id = 1; id <= count; id++) {'id': id},
          ],
          'tracks': <Object?>[],
        },
      };
    }
    if (route == '/song/detail') {
      return {
        'songs': [
          for (final id in query['ids']! as List)
            if (!unavailable.contains('$id')) {'id': id, 'name': '歌曲 $id'},
        ],
      };
    }
    if (route == '/user/playlist') {
      return {
        'playlist': [
          {
            'id': 10,
            'specialType': 5,
            'creator': {'userId': 7},
          },
        ],
      };
    }
    if (route == '/likelist') {
      return {
        'ids': [for (var id = 1; id <= count; id++) id],
      };
    }
    throw StateError('Unexpected route $route');
  }
}

MusicPlatformApi _kugou(int count, List<http.Request> requests) =>
    MusicPlatformApi(
      server: _Server(),
      client: MockClient((request) async {
        requests.add(request);
        final query = request.url.queryParameters;
        final page = int.parse(query['page'] ?? '1');
        final size = int.parse(query['pagesize'] ?? '30');
        return http.Response(
          jsonEncode({
            'status': 1,
            'data': request.url.path == '/user/playlist'
                ? {
                    'info': [_liked],
                  }
                : {
                    'total': count,
                    'info': [
                      for (
                        var id = (page - 1) * size;
                        id < page * size && id < count;
                        id++
                      )
                        {
                          'hash': 'HASH$id',
                          'songname': '歌曲 $id',
                          'fileid': id + 1,
                        },
                    ],
                  },
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    )..session = _identity;

void main() {
  test(
    'catalogue and fixed-feed caches are replaced for both owner and credential changes',
    () async {
      final requests = <http.Request>[];
      final api = _kugou(10, requests);
      final container = ProviderContainer(
        overrides: [
          musicPlatformApiProvider.overrideWithValue(api),
          platformAccountProvider.overrideWith(_SwitchingAccount.new),
          usesNeteaseProvider.overrideWithValue(false),
        ],
      );
      addTearDown(container.dispose);
      await container.read(platformAccountProvider.future);
      final firstCatalog = container.read(platformCatalogProvider);
      final firstExplore = container.read(platformExploreRepositoryProvider);
      final account =
          container.read(platformAccountProvider.notifier) as _SwitchingAccount;
      account.select(
        const PlatformSession(userId: '7', token: 'renewed-credential'),
      );
      expect(
        identical(firstCatalog, container.read(platformCatalogProvider)),
        false,
      );
      expect(
        identical(
          firstExplore,
          container.read(platformExploreRepositoryProvider),
        ),
        false,
      );
      final renewed = container.read(platformExploreRepositoryProvider);
      account.select(
        const PlatformSession(userId: '8', token: 'different-owner'),
      );
      expect(
        identical(renewed, container.read(platformExploreRepositoryProvider)),
        false,
      );
      expect(requests, isEmpty);
    },
  );
  test(
    'Kugou preview and next page request only their metadata windows',
    () async {
      final requests = <http.Request>[];
      final database = AppDatabase(NativeDatabase.memory());
      final repository = PlatformLibraryRepository(
        database,
        api: _kugou(401, requests),
        identity: _identity,
      );
      addTearDown(() async {
        repository.dispose();
        await database.close();
      });
      final first = await repository.playlistPage('kg:11');
      expect(first.items.length, 30);
      expect(first.nextOffset, 30);
      expect(first.total, 401);
      expect(first.hasMore, true);
      expect(
        requests.where((r) => r.url.path == '/playlist/track/all/new'),
        hasLength(1),
      );
      await repository.playlistPage('kg:11');
      expect(
        requests.where((r) => r.url.path == '/playlist/track/all/new'),
        hasLength(1),
      );
      final next = await repository.playlistPage(
        'kg:11',
        offset: first.nextOffset,
      );
      expect(next.items.first.id, 'kugou_HASH30');
      expect(next.nextOffset, 60);
      expect(
        requests.where((r) => r.url.path == '/playlist/track/all/new'),
        hasLength(2),
      );
    },
  );

  test(
    'NetEase preview uses IDs plus thirty details and reuses its index',
    () async {
      final music = _NeteaseFixture(1001);
      final first = await music.playlistPage('10');
      expect(first.items.length, 30);
      expect(first.total, 1001);
      expect(first.nextOffset, 30);
      expect(music.requests.first.$2['n'], 0);
      expect(music.requests.last.$2['ids'], hasLength(30));
      await music.playlistPage('10');
      expect(music.requests, hasLength(2));
      final next = await music.playlistPage('10', offset: first.nextOffset);
      expect(next.items.first.id, 'netease_31');
      expect(music.requests, hasLength(3));
      expect(music.requests.last.$2['ids'], hasLength(30));
    },
  );

  test(
    'missing NetEase songs advance the source index without repeating',
    () async {
      final music = _NeteaseFixture(65)..unavailable = {'2', '5', '30'};
      final first = await music.playlistPage('10');
      expect(first.items, hasLength(27));
      expect(first.nextOffset, 30);
      expect(first.hasMore, true);
      final next = await music.playlistPage('10', offset: first.nextOffset);
      expect(next.items.first.id, 'netease_31');
      final last = await music.playlistPage('10', offset: 60);
      expect(last.items, hasLength(5));
      expect(last.nextOffset, 65);
      expect(last.hasMore, false);
    },
  );

  test('NetEase membership reads only the complete ID endpoint', () async {
    final music = _NeteaseFixture(1001);
    final database = AppDatabase(NativeDatabase.memory());
    final repository = NeteaseLibraryRepository(
      database,
      music: music,
      identity: _identity,
    );
    addTearDown(() async {
      repository.dispose();
      await database.close();
    });
    expect(await repository.isFavorite('netease_1001'), true);
    expect(await repository.isFavorite('netease_1002'), false);
    expect(music.requests.map((r) => r.$1), ['/likelist']);
    expect(await repository.favoriteIds(), hasLength(1001));
    expect(music.requests, hasLength(1));
  });

  test('explicit complete Kugou collection keeps all 401 records', () async {
    final requests = <http.Request>[];
    final database = AppDatabase(NativeDatabase.memory());
    final repository = PlatformLibraryRepository(
      database,
      api: _kugou(401, requests),
      identity: _identity,
    );
    addTearDown(() async {
      repository.dispose();
      await database.close();
    });
    final songs = await repository.watchFavorites().first;
    expect(songs.length, 401);
    final details = requests
        .where((request) => request.url.path == '/playlist/track/all/new')
        .toList();
    expect(details.length, 3);
    expect(details.first.url.queryParameters['pagesize'], '200');
    // Baseline before 1.0.47: the first stream event waits for all three pages.
    // ignore: avoid_print
    print(
      'paging baseline Kugou: 401 metadata rows, 3 song requests before emit',
    );
  });

  test('explicit complete NetEase playlist keeps all 1001 IDs', () async {
    final music = _NeteaseFixture(1001);
    final songs = await music.playlist('10');
    expect(songs.length, 1001);
    final details = music.requests.where(
      (request) => request.$1 == '/song/detail',
    );
    expect(details.length, 3);
    expect(details.first.$2['ids'], hasLength(500));
    // ignore: avoid_print
    print('paging baseline NetEase: 1001 metadata rows, batches 500/500/1');
  });
}
