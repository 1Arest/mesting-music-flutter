import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesting_music/core/cache/browse_response_cache.dart';
import 'package:mesting_music/core/cache/browse_cache_routes.dart';
import 'package:mesting_music/core/database/app_database.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/features/library/library_providers.dart';
import 'package:mesting_music/features/history/listening_history_providers.dart';
import 'package:mesting_music/features/music_platform/data/embedded_music_server.dart';
import 'package:mesting_music/features/music_platform/data/music_platform_api.dart';
import 'package:mesting_music/features/music_platform/discovery_startup_cache.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/music_platform/netease/netease_api.dart';
import 'package:mesting_music/features/music_platform/netease/netease_providers.dart';
import 'package:mesting_music/features/music_platform/netease/netease_session.dart';
import 'package:mesting_music/features/music_platform/platform_catalog_providers.dart';
import 'package:mesting_music/shared/media/artwork_refresh_coordinator.dart';

const _netease = NeteaseSession(
  userId: '7',
  deviceId: 'fixture',
  cookies: {'MUSIC_U': 'synthetic'},
);

class _NetAccount extends PlatformAccountController {
  @override
  Future<PlatformSession?> build() async => _netease.identity;
}

class _KgAccount extends PlatformAccountController {
  @override
  Future<PlatformSession?> build() async =>
      const PlatformSession(userId: '7', token: 'synthetic');
}

class _Server implements MusicServer {
  @override
  Future<Uri> start() async => Uri.parse('http://127.0.0.1:12950');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'successful edits retain discovery across restart while invalidating the edited library',
    () async {
      final root = await Directory.systemTemp.createTemp('discovery129-edit-');
      final cache = BrowseResponseCache(
        directory: () async => root,
        initializeOnRead: true,
      );
      final watch = BrowseCacheWatch(() {});
      Future<BrowseJson> read(BrowseResponseCache c, String route) => watch.run(
        () => c.read(
          scope: 'netease:7',
          route: route,
          query: const {},
          checkCurrent: () {},
          load: () async => {'code': 200, 'name': route},
        ),
      );
      // Include the exact mounted NetEase rank/artist/MV shelf contracts,
      // rather than similarly named catalogue alternatives.
      const discoveryRoutes = [
        '/recommend/songs',
        '/toplist',
        '/toplist/artist',
        '/mv/all',
      ];
      for (final route in discoveryRoutes) {
        await read(cache, route);
      }
      await read(cache, '/user/playlist');
      await read(cache, '/user/detail');
      var writes = 0;
      final api = NeteaseApi(
        MockClient((_) async {
          writes++;
          return http.Response.bytes(utf8.encode('{"code":200}'), 200);
        }),
        browseCache: cache,
      )..configure(_netease);
      await api.call('/like', query: {'id': 1, 'like': true});
      expect(writes, 1);
      final restarted = BrowseResponseCache(
        directory: () async => root,
        initializeOnRead: true,
      );
      for (final route in discoveryRoutes) {
        expect(BrowseCacheRoutes.discoveryRead(route), true);
        expect(
          (await BrowseResponseCache.restoreOnly(
            () => read(restarted, route),
          ))['name'],
          route,
        );
      }
      await expectLater(
        BrowseResponseCache.restoreOnly(
          () => read(restarted, '/user/playlist'),
        ),
        throwsA(isA<BrowseSnapshotUnavailable>()),
      );
      await expectLater(
        BrowseResponseCache.restoreOnly(() => read(restarted, '/user/detail')),
        throwsA(isA<BrowseSnapshotUnavailable>()),
      );
      watch.dispose();
      await root.delete(recursive: true);
    },
  );
  for (final netease in [true, false]) {
    test(
      'cold ${netease ? 'NetEase' : 'Kugou'} discovery mounts AsyncData before background network',
      () async {
        final fixtures = Directory(
          '.codex-artifacts/2026-11-01-release129/discovery-fixtures',
        )..createSync(recursive: true);
        final directory = await fixtures.createTemp('boot-');
        final database = AppDatabase(NativeDatabase.memory());
        SharedPreferences.setMockInitialValues({});
        final preferences = await SharedPreferences.getInstance();
        final coordinator = ArtworkRefreshCoordinator();
        Future<ProviderContainer> container(
          Future<http.Response> Function(http.Request) reply,
        ) async {
          final cache = BrowseResponseCache(directory: () async => directory);
          await cache.initialize();
          final netApi = NeteaseApi(MockClient(reply), browseCache: cache)
            ..configure(_netease);
          final kgApi = MusicPlatformApi(
            server: _Server(),
            client: MockClient(reply),
            browseCache: cache,
          )..session = const PlatformSession(userId: '7', token: 'synthetic');
          return ProviderContainer(
            overrides: [
              platformAccountProvider.overrideWith(
                netease ? _NetAccount.new : _KgAccount.new,
              ),
              neteaseApiProvider.overrideWithValue(netApi),
              musicPlatformApiProvider.overrideWithValue(kgApi),
              sharedPreferencesProvider.overrideWithValue(preferences),
              appDatabaseProvider.overrideWithValue(database),
              // Local-only sections have independent SQLite tests. Avoid cloud
              // synchronization so this assertion measures only the live feed seam.
              recentPlaybackProvider.overrideWith((ref) => Stream.value([])),
              favoriteTracksProvider.overrideWith((ref) => Stream.value([])),
            ],
          );
        }

        http.Response response(String title) => http.Response.bytes(
          utf8.encode(
            jsonEncode(
              netease
                  ? {
                      'code': 200,
                      'data': {
                        'dailySongs': [
                          {'id': 1, 'name': title},
                        ],
                      },
                    }
                  : {
                      'status': 1,
                      'data': {
                        'lists': [
                          {
                            'FileHash': 'song',
                            'SongName': title,
                            'SingerName': '歌手',
                          },
                        ],
                      },
                    },
            ),
          ),
          200,
        );
        final first = await container((_) async => response('saved-song'));
        expect(
          (await first.read(platformDailyProvider.future)).single.title,
          'saved-song',
        );
        first.dispose();
        var requests = 0;
        final network = Completer<http.Response>();
        final restarted = await container((_) {
          requests++;
          return network.future;
        });
        final lease = await DiscoveryStartupCache.prepare(
          restarted,
          artwork: coordinator,
        ).timeout(const Duration(seconds: 3));
        expect(
          requests,
          0,
          reason:
              'Cold hydration must never depend on live responses or cache misses.',
        );
        expect(restarted.read(platformDailyProvider).isLoading, false);
        expect(
          restarted.read(platformDailyProvider).value?.single.title,
          'saved-song',
        );
        lease.resume();
        // First invalidate retains data, then starts revalidation outside the
        // disk-only zone. A provider permanently trapped in that zone fails here.
        await restarted.read(platformDailyProvider.future);
        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(requests, greaterThan(0));
        expect(
          restarted.read(platformDailyProvider).value?.single.title,
          'saved-song',
        );
        network.complete(response('fresh-song'));
        final deadline = DateTime.now().add(const Duration(seconds: 3));
        while (restarted
                    .read(platformDailyProvider)
                    .value
                    ?.firstOrNull
                    ?.title !=
                'fresh-song' &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(
          restarted.read(platformDailyProvider).value?.single.title,
          'fresh-song',
        );
        lease.dispose();
        restarted.dispose();
        coordinator.dispose();
        await database.close();
        // Keep synthetic snapshots while the host engine releases background
        // atomic commits. Eager Windows deletion would test handle timing
        // rather than the restart assertions above.
      },
    );
  }
}
