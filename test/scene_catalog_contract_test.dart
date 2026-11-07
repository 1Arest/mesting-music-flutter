import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesting_music/features/music_platform/data/embedded_music_server.dart';
import 'package:mesting_music/features/music_platform/data/music_platform_api.dart';
import 'package:mesting_music/features/music_platform/data/platform_explore.dart';

class _Server implements MusicServer {
  @override
  Future<Uri> start() async => Uri.parse('http://127.0.0.1:19031');
}

http.Response _json(Object value) => http.Response(
  jsonEncode(value),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

// Reduced from an anonymous live catalogue read on 2026-10-28. In particular,
// `content` is a map, and `info` is the scene itself, not a list of modules.
const _module = {
  'status': 1,
  'data': {
    'content': {
      'info': {'scene_id': 26, 'title': '心情专区'},
      'discuss': [
        {
          'module_type': 4,
          'module_id': 660,
          'extra': {'discuss_param': '26'},
        },
      ],
      'music': [
        {
          'module_type': 2,
          'module_id': 879,
          'extra': [
            {'tag_id': 1, 'content_type': 1},
            {'tag_id': 42987, 'content_type': 6, 'types': 1},
          ],
        },
      ],
    },
  },
};

void main() {
  Future<PlatformExploreRepository> repository(
    Future<http.Response> Function(http.Request) handler,
  ) async {
    final client = MockClient(handler);
    addTearDown(client.close);
    return PlatformExploreRepository(
      MusicPlatformApi(server: _Server(), client: client),
    );
  }

  test(
    'grouped live scene module resolves its own audio tag and real tracks',
    () async {
      final queries = <http.Request>[];
      final repo = await repository((request) async {
        queries.add(request);
        return _json(
          request.url.path == '/scene/module'
              ? _module
              : {
                  'status': 1,
                  'data': {
                    'list': [
                      {
                        'hash': '2FFAF2860C7176FBC11692CC593A45C1',
                        'songname': '有名无份',
                        'author_name': '李冠霖',
                        'album_audio_id': 245396905,
                      },
                    ],
                  },
                },
        );
      });
      final tracks = await repo.tracks(
        const PlatformExploreItem(
          id: '26',
          title: '心情专区',
          cover: '',
          kind: PlatformExploreKind.scene,
        ),
      );
      expect(tracks.single.title, '有名无份');
      expect(queries.map((q) => q.url.path), [
        '/scene/module',
        '/scene/audio/list',
      ]);
      expect(
        queries.last.url.queryParameters,
        containsPair('module_id', '879'),
      );
      expect(queries.last.url.queryParameters, containsPair('tag', '42987'));
      expect(queries.last.url.queryParameters, containsPair('id', '26'));
    },
  );

  test(
    'catalogue music_tag avoids module guesswork and uses the official scene icon',
    () async {
      final paths = <String>[];
      final repo = await repository((request) async {
        paths.add(request.url.path);
        return _json({
          'status': 1,
          'data': {
            'list': [
              {
                'scene_id': 26,
                'title': '心情专区',
                'pic': '',
                'icon': 'http://mobileservice.bssdl.kugou.com/mood.png',
                'music_tag': {
                  'module_id': 879,
                  'module_extra': [
                    {'tag_id': 42987, 'content_type': 6},
                  ],
                },
              },
            ],
          },
        });
      });
      final scene = (await repo.list(PlatformExploreKind.scene)).single;
      expect(scene.moduleId, '879');
      expect(scene.tag, '42987');
      expect(scene.cover, 'http://mobileservice.bssdl.kugou.com/mood.png');
      expect((await repo.resolveScene(scene)).id, '26');
      expect(paths, ['/scene/lists']);
    },
  );

  test(
    'legacy flat module stays supported and non-audio modules are excluded',
    () async {
      final repo = await repository(
        (_) async => _json({
          'status': 1,
          'data': {
            'content': [
              {
                'module_type': 4,
                'module_id': 1,
                'extra': [
                  {'tag_id': 1, 'content_type': 6},
                ],
              },
              {
                'module_type': 2,
                'module_id': 595,
                'extra': [
                  {'tag_id': 42907, 'content_type': 6},
                ],
              },
            ],
          },
        }),
      );
      final scene = await repo.resolveScene(
        const PlatformExploreItem(
          id: '1',
          title: '助眠专区',
          cover: '',
          kind: PlatformExploreKind.scene,
        ),
      );
      expect(scene.moduleId, '595');
      expect(scene.tag, '42907');
    },
  );

  test(
    'collection-only scene retains global IDs and never sends playlist tags to audio_list',
    () async {
      final requests = <http.Request>[];
      final repo = await repository((request) async {
        requests.add(request);
        if (request.url.path == '/scene/lists') {
          return _json({
            'status': 1,
            'data': {
              'list': [
                {
                  'scene_id': 7,
                  'title': '店铺专区',
                  'music_tag': {
                    'module_id': 713,
                    'module_extra': [
                      {'tag_id': 42834, 'content_type': 1},
                    ],
                  },
                },
              ],
            },
          });
        }
        if (request.url.path == '/scene/collection/list') {
          return _json({
            'status': 1,
            'data': {
              'list': [
                {
                  'id': 'collection_3_1903561520_277_0',
                  'content_id': 'collection_3_1903561520_277_0',
                  'specialid': 5558824,
                  'title': '店铺音乐歌单',
                  'content_type': 1,
                },
                {'id': 'video', 'title': '不是音乐歌单', 'content_type': 3},
                {
                  'id': 'gone',
                  'title': '未发布内容',
                  'content_type': 1,
                  'is_publish': 0,
                },
              ],
            },
          });
        }
        return _json({
          'status': 1,
          'data': {
            'songs': [
              {
                'hash': '2FFAF2860C7176FBC11692CC593A45C1',
                'songname': '歌单里的歌曲',
                'author_name': '歌手',
              },
            ],
          },
        });
      });
      final scene = (await repo.list(PlatformExploreKind.scene)).single;
      expect(scene.sceneContent, PlatformSceneContent.collections);
      final collections = await repo.sceneCollections(scene);
      expect(collections.single.id, 'collection_3_1903561520_277_0');
      expect(collections.single.kind, PlatformExploreKind.playlist);
      expect((await repo.tracks(collections.single)).single.title, '歌单里的歌曲');
      expect(
        requests.last.url.queryParameters['global_collection_id'],
        collections.single.id,
      );
      await expectLater(
        repo.tracks(scene),
        throwsA(isA<MusicPlatformException>()),
      );
      expect(requests.any((r) => r.url.path == '/scene/audio/list'), isFalse);
      expect(requests[1].url.queryParameters['tag_id'], '42834');
    },
  );
}
