import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/core/platform/distribution_channel.dart';
import 'package:mesting_music/features/auth/auth_providers.dart';
import 'package:mesting_music/features/auth/data/auth_repository.dart';
import 'package:mesting_music/features/music_platform/data/embedded_music_server.dart';
import 'package:mesting_music/features/music_platform/data/music_platform_api.dart';
import 'package:mesting_music/features/music_platform/data/platform_search_repository.dart';
import 'package:mesting_music/features/music_platform/data/platform_session_store.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/search/search_providers.dart';

class _Server implements MusicServer {
  @override
  Future<Uri> start() async => Uri.parse('http://127.0.0.1:12345');
}

class _Store implements PlatformSessionStore {
  @override
  Future<PlatformSession?> read() async => null;
  @override
  Future<void> write(PlatformSession session) async {}
  @override
  Future<void> clear() async {}
}

http.Response _response(int page, {String prefix = 'H', int total = 65}) =>
    http.Response(
      jsonEncode({
        'status': 1,
        'data': {
          'total': total,
          'lists': [
            for (var i = (page - 1) * 30; i < page * 30 && i < total; i++)
              {
                'FileHash': '$prefix$i',
                'SongName': '同名的不同录音',
                'SingerName': '歌手',
                'MixSongID': 1000 + i,
              },
          ],
        },
      }),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

void main() {
  test(
    'concept search retains server ordering, recording IDs and totals',
    () async {
      final requests = <http.Request>[];
      final api = MusicPlatformApi(
        server: _Server(),
        client: MockClient((request) async {
          requests.add(request);
          return _response(int.parse(request.url.queryParameters['page']!));
        }),
      );
      final repo = PlatformSearchRepository(api);
      final first = await repo.search('薛之谦');
      final second = await repo.search('薛之谦', page: 2);
      expect(first.tracks.length, 30);
      expect(first.total, 65);
      expect(first.tracks.first.id, 'kugou_H0');
      expect(first.tracks.last.id, 'kugou_H29');
      expect(second.tracks.first.platformSongId, '1030');
      expect(first.hasMore, true);
      expect(
        requests.first.url.queryParameters,
        containsPair('pagesize', '30'),
      );
      expect(requests.last.url.queryParameters, containsPair('page', '2'));
      expect((await repo.search('薛之谦', page: 3)).hasMore, false);
    },
  );

  Future<ProviderContainer> containerFor(
    Future<http.Response> Function(http.Request) respond,
  ) async {
    SharedPreferences.setMockInitialValues({});
    return ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(
          await SharedPreferences.getInstance(),
        ),
        authRepositoryProvider.overrideWithValue(
          const UnconfiguredAuthRepository(),
        ),
        platformSessionStoreProvider.overrideWithValue(_Store()),
        musicPlatformApiProvider.overrideWithValue(
          MusicPlatformApi(server: _Server(), client: MockClient(respond)),
        ),
      ],
    );
  }

  test(
    'Beta loads 65 rows across three pages without legacy semantic deduplication',
    () async {
      final pages = <String>[];
      final container = await containerFor((request) async {
        pages.add(request.url.queryParameters['page']!);
        return _response(int.parse(pages.last));
      });
      addTearDown(container.dispose);
      final controller = container.read(musicSearchControllerProvider.notifier);
      await controller.submit('薛之谦');
      await controller.loadMore();
      await controller.loadMore();
      final state = container.read(musicSearchControllerProvider);
      expect(state.onlineTracks.length, 65);
      expect(state.total, 65);
      expect(state.hasMore, false);
      expect(pages, ['1', '2', '3']);
      await controller.loadMore();
      expect(pages.length, 3);
    },
    skip: !DistributionChannel.isBeta,
  );

  test(
    'failed append preserves visible songs and retries the same page',
    () async {
      var fail = true;
      final pages = <int>[];
      final container = await containerFor((request) async {
        final page = int.parse(request.url.queryParameters['page']!);
        pages.add(page);
        if (page == 2 && fail) return http.Response('{"status":0}', 200);
        return _response(page);
      });
      addTearDown(container.dispose);
      final controller = container.read(musicSearchControllerProvider.notifier);
      await controller.submit('薛之谦');
      await controller.loadMore();
      expect(
        container.read(musicSearchControllerProvider).onlineTracks.length,
        30,
      );
      expect(
        container.read(musicSearchControllerProvider).moreError,
        isNotNull,
      );
      fail = false;
      await controller.loadMore();
      expect(pages, [1, 2, 2]);
      expect(
        container.read(musicSearchControllerProvider).onlineTracks.length,
        60,
      );
      expect(container.read(musicSearchControllerProvider).moreError, null);
    },
    skip: !DistributionChannel.isBeta,
  );

  test(
    'new query rejects late old results and repeated pages stop pagination',
    () async {
      final delayed = Completer<http.Response>();
      final container = await containerFor((request) async {
        if (request.url.queryParameters['keywords'] == 'old') {
          return delayed.future;
        }
        return _response(
          1,
          prefix: 'new',
        ); // Deliberately repeated page from service.
      });
      addTearDown(container.dispose);
      final controller = container.read(musicSearchControllerProvider.notifier);
      final old = controller.submit('old');
      await Future<void>.delayed(Duration.zero);
      await controller.submit('new');
      delayed.complete(_response(1, prefix: 'old'));
      await old;
      expect(
        container.read(musicSearchControllerProvider).onlineTracks.first.id,
        'kugou_new0',
      );
      await controller.loadMore();
      expect(container.read(musicSearchControllerProvider).hasMore, false);
      expect(
        container.read(musicSearchControllerProvider).onlineTracks.length,
        30,
      );
    },
    skip: !DistributionChannel.isBeta,
  );
}
