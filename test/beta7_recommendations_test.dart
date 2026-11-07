import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesting_music/core/platform/distribution_channel.dart';
import 'package:mesting_music/features/music_platform/data/embedded_music_server.dart';
import 'package:mesting_music/features/music_platform/data/music_platform_api.dart';
import 'package:mesting_music/features/music_platform/data/platform_recommendations.dart';
import 'package:mesting_music/features/music_platform/data/platform_explore.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/themes/theme_controller.dart';

class _Server implements MusicServer {
  @override
  Future<Uri> start() async => Uri.parse('http://127.0.0.1:12345');
}

const _identity = PlatformSession(userId: '7', token: 'test-token');
Map<String, Object?> _song(String id, {String token = 'mark'}) => {
  'hash': id,
  'songname': '同名歌曲',
  'singername': '同一歌手',
  'duration': 180,
  'rec_song_info': {'cur_mark': token},
  'album_audio_id': '123',
};
http.Response _response(Object data) => http.Response.bytes(
  utf8.encode(jsonEncode({'status': 1, 'data': data})),
  200,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences preferences;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
  });
  test(
    'FM uses upstream login fallback and preserves recordings/server order',
    () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        if (request.url.queryParameters['action'] == 'login') {
          return _response({'song_list': []});
        }
        return _response({
          'song_list': [_song('C'), _song('A'), _song('B')],
        });
      });
      addTearDown(client.close);
      final api = MusicPlatformApi(server: _Server(), client: client)
        ..session = _identity;
      final repo = PlatformRecommendations(api, preferences, _identity);
      final tracks = await repo.personalFm(PlatformFmStation.heart);
      expect(requests.length, 2);
      expect(requests.first.url.path, '/personal/fm');
      expect(requests.first.url.queryParameters['action'], 'login');
      expect(requests.first.url.queryParameters.containsKey('mode'), false);
      expect(requests.last.url.queryParameters.containsKey('action'), false);
      expect(tracks.map((t) => t.id), ['kugou_C', 'kugou_A', 'kugou_B']);
      expect(
        requests.every((r) => r.headers['x-apicache-bypass'] == '1'),
        true,
      );
      expect(
        requests.every((r) => r.url.queryParameters.containsKey('t')),
        true,
      );
    },
  );
  test(
    'FM feedback retains cur_mark and real played seconds without refetch',
    () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        return _response({
          'song_list': [_song('A', token: 'source-token')],
        });
      });
      addTearDown(client.close);
      final api = MusicPlatformApi(server: _Server(), client: client)
        ..session = _identity;
      final repo = PlatformRecommendations(api, preferences, _identity);
      final tracks = await repo.personalFm(PlatformFmStation.niche);
      expect(
        requests.single.url.queryParameters,
        containsPair('mode', 'small'),
      );
      expect(
        requests.single.url.queryParameters,
        containsPair('song_pool_id', '1'),
      );
      await repo.feedback(tracks.first, 'play', seconds: 178, complete: true);
      expect(
        requests.last.url.queryParameters,
        allOf(
          containsPair('cur_mark', 'source-token'),
          containsPair('action', 'play'),
          containsPair('playtime', '178'),
          containsPair('is_overplay', '1'),
        ),
      );
      await repo.feedback(tracks.first, 'click_red');
      expect(requests.last.url.queryParameters.containsKey('playtime'), false);
      expect(requests.last.url.queryParameters['action'], 'click_red');
      expect(requests.length, 3);
    },
  );
  test(
    'discovery advances unique cursor, coalesces reads and persists per account',
    () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        final cursor = request.url.queryParameters['today_play_num'];
        return _response(
          cursor == '0' ? [_song('A'), _song('A'), _song('B')] : [_song('C')],
        );
      });
      addTearDown(client.close);
      final api = MusicPlatformApi(server: _Server(), client: client)
        ..session = _identity;
      final repo = PlatformRecommendations(api, preferences, _identity);
      final batch = await Future.wait([repo.discover(), repo.discover()]);
      expect(requests.length, 1);
      expect(batch.first.map((e) => e.id), ['kugou_A', 'kugou_B']);
      expect(requests.first.url.queryParameters['pagesize'], '4');
      expect(repo.cursor, 2);
      final restored = PlatformRecommendations(api, preferences, _identity);
      expect(restored.cursor, 2);
      await restored.discover();
      expect(requests.last.url.queryParameters['today_play_num'], '2');
      api.session = const PlatformSession(userId: '8', token: 'next');
      final other = PlatformRecommendations(api, preferences, api.session);
      expect(other.cursor, 0);
    },
  );
  test(
    'discovery refill follows 30-row cursor retries without resetting history',
    () async {
      final cursors = <String?>[];
      final client = MockClient((request) async {
        cursors.add(request.url.queryParameters['today_play_num']);
        expect(request.url.queryParameters['pagesize'], '30');
        expect(request.url.queryParameters.containsKey('page'), false);
        return _response(
          cursors.length == 1 ? [] : List.generate(30, (i) => _song('R$i')),
        );
      });
      addTearDown(client.close);
      final api = MusicPlatformApi(server: _Server(), client: client);
      final repo = PlatformRecommendations(api, preferences, null);
      final tracks = await repo.discover(more: true);
      expect(cursors, ['0', '30']);
      expect(tracks.length, 30);
      expect(repo.cursor, 60);
    },
  );
  test('late recommendation responses cannot cross account switch', () async {
    final gate = Completer<http.Response>();
    final client = MockClient((_) => gate.future);
    addTearDown(client.close);
    final api = MusicPlatformApi(server: _Server(), client: client)
      ..session = _identity;
    final repo = PlatformRecommendations(api, preferences, _identity);
    final pending = repo.discover();
    await Future<void>.delayed(Duration.zero);
    api.session = const PlatformSession(userId: '8', token: 'next');
    gate.complete(_response([_song('OLD')]));
    await expectLater(pending, throwsA(isA<MusicPlatformException>()));
    expect(repo.cursor, 0);
  });
  test(
    'hot search parses ordered boards and keywords, never board names as songs',
    () {
      final boards = PlatformHotSearchBoard.parse({
        'data': {
          'list': [
            {
              'name': '热搜榜',
              'keywords': [
                {'keyword': '歌曲甲'},
                {'keyword': '歌手乙'},
              ],
            },
            {
              'name': '飙升热词',
              'keywords': ['新词'],
            },
            {'name': '空榜', 'keywords': []},
          ],
        },
      });
      expect(boards.map((b) => b.name), ['热搜榜', '飙升热词']);
      expect(boards.first.keywords, ['歌曲甲', '歌手乙']);
    },
  );
  test(
    'scene labels use the scene catalogue and parse grouped scene names',
    () async {
      final client = MockClient((request) async {
        if (request.url.path != '/scene/lists') {
          return http.Response('{"status":0,"error_code":400}', 200);
        }
        return _response({
          'scene_list': [
            {'scene_id': 'work', 'scene_name': '专注工作'},
            {'scene_id': 'rest', 'scene_name': '放松休息'},
          ],
        });
      });
      addTearDown(client.close);
      final repo = PlatformExploreRepository(
        MusicPlatformApi(server: _Server(), client: client),
      );
      final scenes = await repo.list(PlatformExploreKind.scene);
      expect(scenes.map((s) => s.id), ['work', 'rest']);
      expect(scenes.map((s) => s.title), ['专注工作', '放松休息']);
    },
  );

  test(
    'exploration preserves album language buckets and rank request contract',
    () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        return _response(
          request.url.path == '/top/album'
              ? {
                  'chn': [
                    {'albumid': 'c', 'albumname': '华语'},
                  ],
                  'eur': [
                    {'albumid': 'e', 'albumname': '欧美'},
                  ],
                }
              : {
                  'info': [
                    {'rankid': '8888', 'rankname': '实时榜'},
                  ],
                },
        );
      });
      addTearDown(client.close);
      final repo = PlatformExploreRepository(
        MusicPlatformApi(server: _Server(), client: client),
      );
      final albums = await repo.list(PlatformExploreKind.album, page: 2);
      expect(albums.map((a) => a.id), ['c', 'e']);
      expect(requests.first.url.queryParameters['page'], '2');
      final ranks = await repo.list(PlatformExploreKind.rank);
      expect(ranks.single.id, '8888');
      expect(requests.last.url.queryParameters['withsong'], '1');
    },
  );
  test(
    'Beta.7 removes follow aliases, fixes brand and preserves explicit characters',
    () async {
      await preferences.setString('music_progress_style', 'followTheme');
      await preferences.setString('music_progress_character', 'kuromi');
      await preferences.setString('app_brand_style', 'midnight_vinyl');
      await migrateBeta7Appearance(preferences);
      expect(preferences.getString('music_progress_style'), 'classic');
      expect(preferences.getString('music_progress_character'), 'kuromi');
      expect(preferences.getString('app_brand_style'), 'coral');
    },
    skip: !DistributionChannel.isBeta,
  );
  test('FM garbage replacements use their own feedback token', () async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      return _response({
        'song_list': [
          request.url.queryParameters['action'] == 'garbage'
              ? _song('B', token: 'new-token')
              : _song('A', token: 'old-token'),
        ],
      });
    });
    addTearDown(client.close);
    final api = MusicPlatformApi(server: _Server(), client: client)
      ..session = _identity;
    final repo = PlatformRecommendations(api, preferences, _identity);
    final initial = await repo.personalFm(PlatformFmStation.heart);
    final replacements = await repo.feedback(initial.first, 'garbage');
    await repo.feedback(replacements.first, 'click_red');
    expect(requests.last.url.queryParameters['hash'], 'B');
    expect(requests.last.url.queryParameters['cur_mark'], 'new-token');
  });
}
