import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesting_music/features/music_platform/data/platform_comments_repository.dart';
import 'package:mesting_music/features/music_platform/data/embedded_music_server.dart';
import 'package:mesting_music/features/music_platform/data/music_platform_api.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/music_platform/data/embedded_kugou_music_source.dart';
import 'package:mesting_music/shared/models/track.dart';

class _Server implements MusicServer {
  @override
  Future<Uri> start() async => Uri.parse('http://127.0.0.1:12345');
}

const _identity = PlatformSession(userId: '7', token: 'test-token');
const _song = PlatformCommentResource(
  kind: PlatformCommentKind.song,
  id: '12345',
  name: '歌曲',
);
const _playlist = PlatformCommentResource(
  kind: PlatformCommentKind.playlist,
  id: 'gid-real',
  name: '歌单',
);
const _ownComment = PlatformComment(
  id: 'comment-id',
  userId: '7',
  nickname: '昵称',
  content: '原评论',
  specialId: 'child-id',
);

void main() {
  late List<http.Request> requests;
  late MusicPlatformApi api;
  late PlatformCommentsRepository repository;
  late Map<String, dynamic> response;
  setUp(() {
    requests = [];
    response = {'status': 1, 'error_code': 0, 'data': {}};
    api = MusicPlatformApi(
      server: _Server(),
      client: MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode(response),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    )..session = _identity;
    repository = PlatformCommentsRepository(api, _identity);
  });

  test(
    'comment identity survives search, queue copy and saved track roundtrip',
    () async {
      final track = EmbeddedKugouMusicSource.platformTrack({
        'FileHash': 'HASH',
        'SongName': '认真的雪',
        'album_audio_id': 0,
        'MixSongID': '98765',
      })!;
      final stored = Track.fromJson(
        track.copyWith(audioAsset: 'https://media.example/test.mp3').toJson(),
      );
      final resource = await repository.songResource(stored);
      expect(resource.id, '98765');
      expect(stored.toMediaItem().extras?['platformSongId'], '98765');
      expect(requests, isEmpty); // Valid source IDs do not depend on /audio.
    },
  );

  test(
    'old hash-only songs resolve nested audio lists and Audioid alias',
    () async {
      response = {
        'status': 1,
        'data': {
          'audio_info': [
            {
              'base': {'album_audio_id': 0, 'Audioid': 98765},
            },
          ],
        },
      };
      final track = EmbeddedKugouMusicSource.platformTrack({
        'hash': 'HASH',
        'songname': '歌曲',
      })!;
      expect((await repository.songResource(track)).id, '98765');
      expect(requests.single.url.path, '/audio');
    },
  );

  test(
    'hot ranking uses childrenid; comments parse dates, likes and singer flags',
    () async {
      response = {
        'status': 1,
        'data': {
          'list': [
            {
              'id': 'hot',
              'user_id': 7,
              'content': '评论',
              'like': {'count': 109},
              'createtime': 1783728000,
              'isAuthor': 1,
            },
          ],
        },
      };
      final result = await repository.load(
        _song,
        hottestChildrenId: 'real-child',
      );
      expect(requests.single.url.path, '/comment/music/topliked');
      expect(requests.single.url.queryParameters['childrenid'], 'real-child');
      expect(
        requests.single.url.queryParameters.containsKey('mixsongid'),
        false,
      );
      expect(result.comments.single.likes, 109);
      expect(result.comments.single.isSinger, true);
      expect(result.comments.single.time?.year, 2026);
    },
  );

  test(
    'song and playlist comments use distinct resource identifiers and paginate',
    () async {
      response = {
        'status': 1,
        'data': {
          'childrenid': 'child-id',
          'total': 45,
          'list': [
            {
              'id': 'comment-id',
              'user_id': 7,
              'user_name': '昵称',
              'content': '评论',
              'user_pic': 'https://img.example/avatar.jpg',
            },
          ],
        },
      };
      final page = await repository.load(_song);
      expect(requests.last.url.queryParameters['mixsongid'], '12345');
      expect(page.comments.single.specialId, 'child-id');
      expect(page.comments.single.userId, '7');
      expect(page.hasMore, true);
      await repository.load(_playlist, page: 2);
      expect(requests.last.url.path, '/comment/playlist');
      expect(requests.last.url.queryParameters['id'], 'gid-real');
      expect(requests.last.url.queryParameters['page'], '2');
    },
  );

  test(
    'writes use POST, explicit content and account headers; no implicit retry',
    () async {
      await repository.send(_song, ' 一条评论 ');
      expect(requests.single.method, 'POST');
      expect(requests.single.url.path, '/comment/music/send');
      expect(requests.single.url.queryParameters['content'], '一条评论');
      expect(
        requests.single.headers['Authorization'],
        'token=test-token;userid=7',
      );
      expect(requests.single.headers['x-apicache-bypass'], '1');
      await repository.send(_playlist, '歌单评论');
      expect(requests.last.url.path, '/comment/playlist/send');
      expect(requests.last.url.queryParameters['id'], 'gid-real');
    },
  );

  test(
    'thread reply and delete carry root tid and per-resource child ID',
    () async {
      const leaf = PlatformComment(
        id: 'reply-id',
        userId: '7',
        nickname: '我',
        content: '回复',
        specialId: 'child-id',
      );
      await repository.send(
        _playlist,
        '继续回复',
        replyTo: leaf,
        thread: _ownComment,
      );
      expect(requests.last.url.path, '/comment/floor/send');
      expect(requests.last.url.queryParameters['tid'], 'comment-id');
      expect(requests.last.url.queryParameters['pid'], 'reply-id');
      expect(requests.last.url.queryParameters['special_id'], 'child-id');
      expect(requests.last.url.queryParameters['resource_type'], 'playlist');
      await repository.delete(_playlist, leaf, thread: _ownComment);
      expect(requests.last.url.path, '/comment/music/del');
      expect(requests.last.url.queryParameters['cid'], 'reply-id');
      expect(requests.last.url.queryParameters['tid'], 'comment-id');
      await repository.load(_playlist, thread: _ownComment);
      expect(requests.last.url.path, '/comment/floor');
    },
  );

  test(
    'other users comments and empty writes are rejected before HTTP',
    () async {
      const other = PlatformComment(
        id: 'other',
        userId: '8',
        nickname: '别人',
        content: '',
        specialId: 'child-id',
      );
      await expectLater(
        repository.delete(_song, other),
        throwsA(isA<MusicPlatformException>()),
      );
      await expectLater(
        repository.send(_song, '  '),
        throwsA(isA<MusicPlatformException>()),
      );
      expect(requests, isEmpty);
    },
  );

  test(
    'security challenge and failed writes remain failures without exposing the raw response',
    () async {
      response = {
        'status': 0,
        'error_code': 60045,
        'msg': 'secret-token-in-upstream-response',
      };
      await expectLater(
        repository.send(_song, '测试'),
        throwsA(
          isA<MusicPlatformException>().having(
            (error) => error.message,
            'safe message',
            allOf(contains('安全验证'), isNot(contains('secret-token'))),
          ),
        ),
      );
      expect(requests.length, 1);
      response = {'status': 0, 'error_code': 0};
      await expectLater(
        repository.send(_song, '测试'),
        throwsA(isA<MusicPlatformException>()),
      );
      expect(requests.length, 2);
    },
  );

  test(
    'logged out or different platform account cannot post through an old repository',
    () async {
      api.session = null;
      await expectLater(
        repository.send(_song, '测试'),
        throwsA(isA<MusicPlatformException>()),
      );
      api.session = const PlatformSession(userId: '8', token: 'other');
      await expectLater(
        repository.delete(_song, _ownComment),
        throwsA(isA<MusicPlatformException>()),
      );
      expect(requests, isEmpty);
    },
  );
}
