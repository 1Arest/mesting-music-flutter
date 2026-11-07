import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesting_music/features/music_platform/data/embedded_music_server.dart';
import 'package:mesting_music/features/music_platform/data/music_platform_api.dart';
import 'package:mesting_music/features/music_platform/data/platform_catalog.dart';
import 'package:mesting_music/features/music_platform/data/platform_explore.dart';
import 'package:mesting_music/features/music_platform/data/platform_quality_catalog.dart';
import 'package:mesting_music/features/music_platform/data/platform_playback_resolver.dart';
import 'package:mesting_music/features/music_platform/data/platform_comments_repository.dart';
import 'package:mesting_music/features/music_platform/data/platform_song_identity.dart';
import 'package:mesting_music/features/music_platform/domain/platform_audio_quality.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/shared/models/track.dart';

class _Server implements MusicServer {
  @override
  Future<Uri> start() async => Uri.parse('http://127.0.0.1:12345');
}

const _identity = PlatformSession(userId: '7', token: 'test');
http.Response _response(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
MusicPlatformApi _api(Future<http.Response> Function(http.Request) handler) =>
    MusicPlatformApi(server: _Server(), client: MockClient(handler))
      ..session = _identity;
const _song = Track(
  id: 'kugou_hash',
  title: '歌曲',
  artist: '',
  album: '',
  duration: Duration(minutes: 4),
  audioAsset: 'mesting-platform://kugou/hash',
  coverAsset: '',
  lyricsAsset: '',
  source: TrackSource.kugou,
);

void main() {
  test(
    'real special_list and plist playlist envelopes populate featured',
    () async {
      for (final key in ['special_list', 'plist']) {
        final api = _api(
          (request) async => _response({
            'status': 1,
            'data': {
              key: [
                {'global_collection_id': 'gid', 'specialname': '真实歌单'},
              ],
            },
          }),
        );
        expect(
          (await PlatformCatalog(
            api,
          ).featured()).single['global_collection_id'],
          'gid',
        );
      }
    },
  );
  test(
    'rank/audio songlist nested metadata becomes playable ordered tracks',
    () async {
      final api = _api((request) async {
        expect(request.url.queryParameters['rankid'], '8888');
        return _response({
          'status': 1,
          'data': {
            'songlist': [
              {
                'audio_info': {'hash': 'one'},
                'base': {'audio_name': '第一首', 'album_audio_id': 123},
              },
              {
                'audio_info': {'hash': 'two'},
                'base': {'audio_name': '第二首', 'album_audio_id': 124},
              },
            ],
          },
        });
      });
      final songs = await PlatformExploreRepository(api).tracks(
        const PlatformExploreItem(
          id: '8888',
          title: '排行榜',
          cover: '',
          kind: PlatformExploreKind.rank,
        ),
      );
      expect(songs.map((t) => t.id), ['kugou_one', 'kugou_two']);
      expect(songs.every((t) => t.isPlayable), true);
    },
  );
  test(
    'quality availability comes from resource hashes, not account flags',
    () {
      expect(
        PlatformQualityCatalog.parse({
          'data': {
            'audio_info': [
              {
                'hash': 'sd',
                'hash_320': '',
                'hash_flac': '0000',
                'privilege': 15,
              },
            ],
          },
        }),
        {PlatformAudioQuality.standard},
      );
      expect(
        PlatformQualityCatalog.parse({
          'data': {
            'hash': 'sd',
            'hash_320': 'hq',
            'hash_flac': 'sq',
            'hash_high': 'hires',
          },
        }),
        PlatformAudioQuality.values.toSet(),
      );
      expect(
        PlatformQualityCatalog.parse({
          'resources': [
            {'quality': 'high', 'hash': 'hires'},
          ],
        }),
        {PlatformAudioQuality.hiRes},
      );
      expect(
        () => PlatformQualityCatalog.parse({'data': {}}),
        throwsA(isA<MusicPlatformException>()),
      );
    },
  );
  test(
    'explicit quality selection exposes membership failure without downgrade',
    () async {
      final requests = <http.Request>[];
      final api = _api((request) async {
        requests.add(request);
        return _response({
          'status': 1,
          'data': {
            'fail_process': ['buy'],
            'url': 'https://example.test/trial.mp3',
            'quality': '128',
          },
        });
      });
      await expectLater(
        PlatformPlaybackResolver(api).resolve(
          _song,
          quality: PlatformAudioQuality.hiRes,
          requireRequestedQuality: true,
        ),
        throwsA(
          isA<MusicPlatformException>().having(
            (e) => e.message,
            'permission message',
            '需要会员／相应权限',
          ),
        ),
      );
      expect(requests.map((request) => request.url.path), [
        '/audio',
        '/song/url',
      ]);
      expect(requests.last.url.queryParameters['quality'], 'high');
    },
  );
  test(
    'explicit lower quality response cannot replace the current source',
    () async {
      final api = _api(
        (_) async => _response({
          'status': 1,
          'data': {'quality': '128', 'url': 'https://example.test/low.mp3'},
        }),
      );
      await expectLater(
        PlatformPlaybackResolver(api).resolve(
          _song,
          quality: PlatformAudioQuality.lossless,
          requireRequestedQuality: true,
        ),
        throwsA(isA<MusicPlatformException>()),
      );
    },
  );
  test('specific recording ID wins over a generic parent audio ID', () {
    expect(
      PlatformSongIdentity.fromPayload({
        'audio_id': 111,
        'data': {
          'base': {'album_audio_id': 999},
        },
      }),
      '999',
    );
  });
  test('legacy failed song comments repair their recording ID once', () async {
    final paths = <String>[];
    final api = _api((request) async {
      paths.add(request.url.path);
      if (request.url.path == '/audio') {
        return _response({
          'status': 1,
          'data': {
            'audio_id': 111,
            'base': {'album_audio_id': 999},
          },
        });
      }
      if (request.url.queryParameters['mixsongid'] == '111') {
        return _response({'status': 0, 'error_code': 404}, 502);
      }
      expect(request.url.queryParameters['mixsongid'], '999');
      return _response({
        'status': 1,
        'data': {
          'list': [
            {'id': 'comment', 'content': '可正常加载'},
          ],
        },
      });
    });
    final result = await PlatformCommentsRepository(api, _identity).load(
      const PlatformCommentResource(
        kind: PlatformCommentKind.song,
        id: '111',
        name: '歌曲',
        hash: 'hash',
      ),
    );
    expect(result.comments.single.content, '可正常加载');
    expect(paths, ['/comment/music', '/audio', '/comment/music']);
  });
  test(
    'comments recover a device-registration read failure without writes',
    () async {
      var calls = 0;
      final api = _api((request) async {
        expect(request.method, 'GET');
        if (request.url.path == '/register/dev') {
          return _response({
            'status': 1,
            'data': {'dfid': 'device'},
          });
        }
        if (calls++ == 0) {
          return _response({'status': 0, 'error_code': 20028}, 502);
        }
        return _response({
          'status': 1,
          'data': {
            'list': [
              {'id': 'one', 'content': '已恢复'},
            ],
          },
        });
      });
      final result = await PlatformCommentsRepository(api, _identity).load(
        const PlatformCommentResource(
          kind: PlatformCommentKind.song,
          id: '999',
          name: '歌曲',
        ),
      );
      expect(result.comments.single.content, '已恢复');
      expect(calls, 2);
    },
  );
}
