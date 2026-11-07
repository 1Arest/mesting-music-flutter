import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesting_music/core/database/app_database.dart';
import 'package:mesting_music/features/music_platform/data/embedded_music_server.dart';
import 'package:mesting_music/features/music_platform/data/music_platform_api.dart';
import 'package:mesting_music/features/music_platform/netease/netease_api.dart';
import 'package:mesting_music/features/music_platform/netease/netease_comments_repository.dart';
import 'package:mesting_music/features/music_platform/netease/netease_library_repository.dart';
import 'package:mesting_music/features/music_platform/netease/netease_music_repository.dart';
import 'package:mesting_music/features/music_platform/netease/netease_mv_repository.dart';
import 'package:mesting_music/features/music_platform/netease/netease_profile_repository.dart';
import 'package:mesting_music/features/music_platform/netease/netease_session.dart';
import 'package:mesting_music/shared/models/track.dart';

const session = NeteaseSession(
  userId: '7',
  deviceId: 'test-device',
  cookies: {'MUSIC_U': 'test-cookie', '__csrf': 'test-csrf'},
);

class _Server implements MusicServer {
  @override
  Future<Uri> start() async => Uri.parse('http://127.0.0.1:12345');
}

http.Response json(Object value) => http.Response(
  jsonEncode(value),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
MusicPlatformApi dummy() => MusicPlatformApi(
  server: _Server(),
  client: MockClient(
    (_) async => throw StateError('NetEase must not call Kugou'),
  ),
);

void main() {
  test(
    'cloud playlists enforce ownership and platform-qualified IDs',
    () async {
      final calls = <String>[];
      final api = NeteaseApi(
        MockClient((req) async {
          calls.add(req.url.path);
          if (req.url.path.endsWith('/user/playlist')) {
            return json({
              'code': 200,
              'playlist': [
                {
                  'id': 10,
                  'name': '喜欢',
                  'specialType': 5,
                  'creator': {'userId': 7},
                },
                {
                  'id': 20,
                  'name': '自建',
                  'creator': {'userId': 7},
                },
                {
                  'id': 30,
                  'name': '收藏',
                  'creator': {'userId': 8},
                },
              ],
              'more': false,
            });
          }
          if (req.url.path.endsWith('/playlist/detail')) {
            return json({
              'code': 200,
              'playlist': {
                'tracks': [
                  {'id': 1, 'name': '歌曲'},
                ],
              },
            });
          }
          return json({'code': 200});
        }),
      )..configure(session);
      final db = AppDatabase(NativeDatabase.memory());
      final repo = NeteaseLibraryRepository(
        db,
        music: NeteaseMusicRepository(api),
        identity: session.identity,
      );
      try {
        final lists = await repo.watchPlaylists().first;
        expect(repo.ownerId, 'netease:7');
        expect(lists.map((l) => l.id), contains('ne:20'));
        expect(repo.canManage('ne:10'), false);
        expect(repo.canManage('ne:20'), true);
        expect(repo.canManage('ne:30'), false);
        expect(await repo.commentId('ne:20'), '20');
        final before = calls.length;
        await expectLater(
          repo.deletePlaylist('ne:30'),
          throwsA(isA<MusicPlatformException>()),
        );
        await expectLater(
          repo.setFavorite(
            Track(
              id: 'kugou_A',
              title: '',
              artist: '',
              album: '',
              duration: Duration.zero,
              audioAsset: '',
              coverAsset: '',
              lyricsAsset: '',
              source: TrackSource.kugou,
            ),
            favorite: true,
          ),
          throwsA(isA<MusicPlatformException>()),
        );
        expect(calls.length, before);
        final favorites = await repo.watchFavorites().first;
        expect(favorites.single.id, 'netease_1');
        expect((await db.loadPlaybackSession('kugou:7')), isNull);
      } finally {
        repo.dispose();
        await db.close();
      }
    },
  );

  test('profile maps native fields into the existing profile model', () async {
    final api = NeteaseApi(
      MockClient(
        (_) async => json({
          'code': 200,
          'profile': {
            'nickname': '网易昵称',
            'avatarUrl': 'https://p1.music.126.net/test.jpg',
            'gender': 2,
            'birthday': 949363200000,
            'signature': 'fixture',
          },
        }),
      ),
    )..configure(session);
    final repo = NeteaseProfileRepository(dummy(), NeteaseMusicRepository(api));
    final profile = await repo.fetch(session.identity);
    expect(profile.nickname, '网易昵称');
    expect(profile.sex, 2);
    expect(profile.avatarUrl, 'https://p1.music.126.net/test.jpg');
    expect(profile.signature, 'fixture');
  });

  test(
    'avatar upload keeps music cookies off NOS and commits only after upload',
    () async {
      final requests = <http.Request>[];
      final api = NeteaseApi(
        MockClient((req) async {
          requests.add(req);
          if (req.url.path.endsWith('/token/alloc')) {
            return json({
              'code': 200,
              'result': {
                'objectKey': 'fixture.jpg',
                'token': 'test-nos-token',
                'docId': '99',
              },
            });
          }
          return json({'code': 200});
        }),
      )..configure(session);
      final url = await api.uploadAvatar(
        Uint8List.fromList(List.filled(24, 0)),
        session.credentialId,
      );
      expect(url, 'https://p1.music.126.net/fixture.jpg');
      expect(requests.map((r) => r.url.host), [
        'music.163.com',
        'nosup-hz1.127.net',
        'interface.music.163.com',
      ]);
      expect(requests[1].headers.containsKey('cookie'), false);
      expect(requests[1].headers['x-nos-token'], 'test-nos-token');
      expect(requests.last.url.path, '/eapi/user/avatar/upload/v1');
    },
  );

  test('MV metadata and quality use existing player models', () async {
    final api = NeteaseApi(
      MockClient((req) async {
        if (req.url.path.endsWith('/song/detail')) {
          return json({
            'code': 200,
            'songs': [
              {'id': 1, 'mv': 55},
            ],
          });
        }
        if (req.url.path.endsWith('/mv/detail')) {
          return json({
            'code': 200,
            'data': {
              'name': 'MV fixture',
              'brs': [
                {'br': 720},
                {'br': 1080},
              ],
            },
          });
        }
        return json({
          'code': 200,
          'data': {'url': 'https://example.invalid/movie.mp4'},
        });
      }),
    )..configure(session);
    final repo = NeteaseMvRepository(dummy(), NeteaseMusicRepository(api));
    final mv = await repo.lookup(
      NeteaseMusicRepository.track({'id': 1, 'name': 'fixture'})!,
    );
    expect(mv!.qualities.map((q) => q.label), ['1080P', '720P']);
    expect(await repo.urls(mv.qualities.first), [
      Uri.parse('https://example.invalid/movie.mp4'),
    ]);
  });

  test(
    'comments use NetEase resources and prevent deleting another owner',
    () async {
      var writes = 0;
      final api = NeteaseApi(
        MockClient((req) async {
          if (!req.url.path.endsWith('/resource/comments')) {
            writes++;
            return json({'code': 200});
          }
          return json({
            'code': 200,
            'data': {
              'comments': [
                {
                  'commentId': 8,
                  'content': 'fixture',
                  'likedCount': 3,
                  'user': {'userId': 9, 'nickname': 'other'},
                },
              ],
              'hasMore': true,
              'totalCount': 33,
            },
          });
        }),
      )..configure(session);
      final repo = NeteaseCommentsRepository(
        dummy(),
        session.identity,
        NeteaseMusicRepository(api),
      );
      final resource = await repo.songResource(
        NeteaseMusicRepository.track({'id': 1, 'name': 'fixture'})!,
      );
      final page = await repo.load(resource);
      expect(page.total, 33);
      expect(page.comments.single.likes, 3);
      await expectLater(
        repo.delete(resource, page.comments.single),
        throwsA(isA<MusicPlatformException>()),
      );
      expect(writes, 0);
      await repo.send(resource, 'explicit fixture');
      expect(writes, 1);
    },
  );

  test('redirects are not followed with account cookies', () async {
    final api = NeteaseApi(
      MockClient((req) async {
        expect(req.followRedirects, false);
        expect(req.url.host, 'interface.music.163.com');
        return http.Response(
          '',
          302,
          headers: {'location': 'https://example.invalid/redirect'},
        );
      }),
    )..configure(session);
    await expectLater(
      api.call('/search', query: {'keywords': 'fixture'}),
      throwsA(isA<MusicPlatformException>()),
    );
  });
}
