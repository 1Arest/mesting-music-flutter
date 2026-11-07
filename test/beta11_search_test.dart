import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/features/music_platform/data/embedded_music_server.dart';
import 'package:mesting_music/features/music_platform/data/music_platform_api.dart';
import 'package:mesting_music/features/music_platform/data/platform_category_search.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/music_platform/platform_category_search_providers.dart';

class _Server implements MusicServer {
  @override
  Future<Uri> start() async => Uri.parse('http://127.0.0.1:12345');
}

class _Account extends PlatformAccountController {
  @override
  Future<PlatformSession?> build() async => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'five wire types preserve actual ids, markup, lyric snippet and duration',
    () async {
      final requests = <Uri>[];
      final api = MusicPlatformApi(
        server: _Server(),
        client: MockClient((request) async {
          requests.add(request.url);
          final Object data = switch (request.url.path) {
            '/search/artist' => [
              {'singerid': 3060, 'singername': '薛之谦'},
            ],
            '/search/album' => {
              'total': 50,
              'info': [
                {
                  'albumid': 960327,
                  'albumname': '意外',
                  'singername': '<em>薛之谦</em>',
                  'imgurl': 'http://image.test/{size}/cover.jpg',
                },
              ],
            },
            '/search/special' => {
              'total': 50,
              'info': [
                {
                  'specialid': 7,
                  'gid': 'collection_real_7',
                  'specialname': '<em>薛之谦</em>歌单',
                  'songcount': 139,
                },
              ],
            },
            _ => {
              'total': 1000,
              'lists': [
                {
                  'FileHash': 'HASH',
                  'SongName': '演员',
                  'SingerName': '薛之谦',
                  'TimeLength': 261,
                  'Lyric': '词：薛之谦 <em>演员</em>',
                },
              ],
            },
          };
          return http.Response(
            jsonEncode({'status': 1, 'data': data}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      final repo = PlatformCategorySearchRepository(api);
      final album = await repo.search('薛之谦', PlatformSearchKind.albums);
      expect(album.items.single.id, '960327');
      expect(album.items.single.subtitle, '薛之谦');
      expect(album.items.single.cover, 'http://image.test/400/cover.jpg');
      expect(album.hasMore, true);
      final artist = await repo.search('薛之谦', PlatformSearchKind.artists);
      expect(artist.items.single.id, '3060');
      final playlist = await repo.search('薛之谦', PlatformSearchKind.playlists);
      expect(playlist.items.single.globalId, 'collection_real_7');
      expect(playlist.items.single.count, 139);
      final lyric = await repo.search('薛之谦', PlatformSearchKind.lyrics);
      expect(lyric.items.single.track!.duration, const Duration(seconds: 261));
      expect(lyric.items.single.lyric, '词：薛之谦 演员');
      expect(requests.last.path, '/search');
      expect(requests.last.queryParameters['type'], 'lyric');
    },
  );
  test(
    'categories cache independently and a late old query never replaces reset state',
    () async {
      SharedPreferences.setMockInitialValues({});
      final delayed = Completer<http.Response>();
      final calls = <String>[];
      final api = MusicPlatformApi(
        server: _Server(),
        client: MockClient((request) async {
          final q = request.url.queryParameters['keywords'];
          calls.add('$q:${request.url.path}');
          if (q == 'old') return delayed.future;
          return http.Response(
            jsonEncode({
              'status': 1,
              'data': {
                'total': 1,
                'info': [
                  {'albumid': 1, 'albumname': '新专辑'},
                ],
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      final c = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(
            await SharedPreferences.getInstance(),
          ),
          musicPlatformApiProvider.overrideWithValue(api),
          platformAccountProvider.overrideWith(_Account.new),
        ],
      );
      addTearDown(c.dispose);
      final control = c.read(categorySearchProvider.notifier);
      control.reset('old');
      final old = control.select(PlatformSearchKind.albums);
      await Future<void>.delayed(Duration.zero);
      control.reset('new');
      await control.select(PlatformSearchKind.albums);
      expect(c.read(categorySearchProvider).current.error, isNull);
      expect(c.read(categorySearchProvider).current.items.single.title, '新专辑');
      await control.select(PlatformSearchKind.songs);
      await control.select(PlatformSearchKind.albums);
      expect(calls.where((s) => s.startsWith('new')).length, 1);
      delayed.complete(
        http.Response(
          jsonEncode({
            'status': 1,
            'data': {
              'info': [
                {'albumid': 2, 'albumname': '旧专辑'},
              ],
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );
      await old;
      expect(c.read(categorySearchProvider).query, 'new');
      expect(c.read(categorySearchProvider).current.items.single.title, '新专辑');
      control.reset('');
      expect(c.read(categorySearchProvider).pages, isEmpty);
      expect(c.read(categorySearchProvider).selected, PlatformSearchKind.songs);
    },
  );
}
