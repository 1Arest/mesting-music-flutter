import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/features/music_platform/data/song_menu_details.dart';
import 'package:mesting_music/features/music_platform/netease/netease_api.dart';
import 'package:mesting_music/features/music_platform/netease/netease_music_repository.dart';
import 'package:http/testing.dart';
import 'netease_data_adapters_test.dart' show json, session;
import 'release_148_ui_test.dart' show song148;

void main() {
  test('网易云资料使用真实请求适配层并在一次失败后恢复', () async {
    var catalogueCalls = 0;
    var creatorCalls = 0;
    final transport = MockClient((request) async {
      if (request.url.path.endsWith('/v3/song/detail')) {
        catalogueCalls++;
        expect(request.bodyFields['params'], isNotEmpty);
        if (catalogueCalls == 1) return json({'code': 404});
        return json({
          'code': 200,
          'songs': [
            {
              'id': 9001,
              'ar': [
                {'id': 8, 'name': '验证歌手'},
              ],
              'al': {'id': 9, 'name': '验证专辑'},
            },
          ],
        });
      }
      expect(request.url.path, endsWith('/song/other/message'));
      expect(request.bodyFields['params'], isNotEmpty);
      creatorCalls++;
      return json({
        'code': 200,
        'data': [
          {'type': 101, 'title': '乐谱'},
          {
            'type': 100,
            'title': '创作者: 验证署名',
            'jumpUrl': 'orpheus://rnpage?component=rn-creatorlist&songId=9001',
          },
        ],
      });
    });
    addTearDown(transport.close);
    final music = NeteaseMusicRepository(
      NeteaseApi(transport)..configure(session),
    );
    final details = SongMenuDetailsRepository(
      netease: music.call,
      kugou: (_, _) async => {},
    );
    final before = await details.load(song148(1));
    expect(before.failed, {SongDetailsSection.catalogue});
    final recovered = await details.load(
      song148(1),
      previous: before,
      only: SongDetailsSection.catalogue,
    );
    expect(recovered.failed, isEmpty);
    expect(recovered.artists.single.id, '8');
    expect(recovered.albumId, '9');
    expect(recovered.creators.single.name, '验证署名');
    expect(recovered.creators.single.officialCreatorSongId, '9001');
    expect(catalogueCalls, 2);
    expect(creatorCalls, 1);
  });
  test(
    'successful prior creators survive an empty or foreign catalogue result',
    () async {
      for (final songs in [
        const [],
        [
          {
            'id': 5,
            'al': {'id': 66},
          },
        ],
      ]) {
        final repository = SongMenuDetailsRepository(
          netease: (_, _) async => {'songs': songs},
          kugou: (_, _) async => {},
        );
        const old = SongMenuDetails(
          creators: [SongMenuPerson('保留署名', role: '作曲')],
          albumId: '9',
        );
        final result = await repository.load(
          song148(1),
          previous: old,
          only: SongDetailsSection.catalogue,
        );
        expect(result.creators.single.name, '保留署名');
        expect(result.albumId, '9');
        expect(result.failed, {SongDetailsSection.catalogue});
      }
    },
  );
  test(
    'initial catalogue failure still reads creators independently',
    () async {
      final paths = <String>[];
      final repository = SongMenuDetailsRepository(
        netease: (path, _) async {
          paths.add(path);
          if (path == '/song/detail') throw StateError('catalogue offline');
          return {
            'data': [
              {'type': 100, 'title': '创作者：已读取创作者'},
            ],
          };
        },
        kugou: (_, _) async => {},
      );
      final data = await repository.load(song148(1));
      expect(paths, ['/song/detail', '/song/other/message']);
      expect(data.creators.single.name, '已读取创作者');
      expect(data.failed, {SongDetailsSection.catalogue});
    },
  );
  test(
    'a failed creator request retains catalogue and retries only creators',
    () async {
      var failed = true;
      final paths = <String>[];
      final repo = SongMenuDetailsRepository(
        netease: (path, _) async {
          paths.add(path);
          if (path == '/song/detail') {
            return {
              'songs': [
                {
                  'id': 9001,
                  'ar': [
                    {'id': 8, 'name': '真实歌手'},
                  ],
                  'al': {'id': 9, 'name': '真实专辑'},
                },
              ],
            };
          }
          if (failed) throw StateError('fixture unavailable');
          return {
            'data': [
              {'type': 100, 'title': '创作者：词作者'},
            ],
          };
        },
        kugou: (_, _) async => {},
      );
      final first = await repo.load(song148(1));
      expect(first.failed, {SongDetailsSection.creators});
      expect(first.artists.single.id, '8');
      expect(first.albumId, '9');
      failed = false;
      final next = await repo.load(
        song148(1),
        previous: first,
        only: SongDetailsSection.creators,
      );
      expect(paths, [
        '/song/detail',
        '/song/other/message',
        '/song/other/message',
      ]);
      expect(next.failed, isEmpty);
      expect(next.albumId, '9');
      expect(next.artists.single.name, '真实歌手');
      expect(next.creators.single.name, '词作者');
    },
  );
  test('successful NetEase response can omit creators', () async {
    final repository = SongMenuDetailsRepository(
      netease: (path, query) async {
        if (path == '/song/detail') {
          return {
            'songs': [
              {
                'id': 9001,
                'al': {'name': '专辑', 'id': 9},
              },
            ],
          };
        }
        expect(query, {'songId': '9001'});
        return {
          'data': [
            {'type': 101, 'title': '乐谱'},
          ],
        };
      },
      kugou: (_, _) async => {},
    );
    final data = await repository.load(song148(1));
    expect(data.creators, isEmpty);
    expect(data.failed, isEmpty);
    expect(data.albumId, '9');
  });
  test('catalogue retry preserves earlier successful creators', () async {
    var fail = true;
    final paths = <String>[];
    final repo = SongMenuDetailsRepository(
      netease: (path, _) async {
        paths.add(path);
        if (fail) throw StateError('fixture offline');
        return {
          'songs': [
            {
              'id': 9001,
              'al': {'id': 99, 'name': '修正专辑'},
            },
          ],
        };
      },
      kugou: (_, _) async => {},
    );
    const old = SongMenuDetails(
      album: '旧专辑',
      albumId: '9',
      creators: [SongMenuPerson('已确认署名', role: '作曲')],
    );
    final first = await repo.load(
      song148(1),
      previous: old,
      only: SongDetailsSection.catalogue,
    );
    expect(first.albumId, '9');
    expect(first.failed, {SongDetailsSection.catalogue});
    fail = false;
    final recovered = await repo.load(
      song148(1),
      previous: first,
      only: SongDetailsSection.catalogue,
    );
    expect(recovered.albumId, '99');
    expect(recovered.creators.single.name, '已确认署名');
    expect(recovered.failed, isEmpty);
    expect(paths, ['/song/detail', '/song/detail']);
  });
  test(
    'an empty successful credit response is not a retryable failure',
    () async {
      final repo = SongMenuDetailsRepository(
        netease: (path, _) async => path == '/song/detail'
            ? {
                'songs': [
                  {'id': 9001},
                ],
              }
            : {
                'lrc': {'lyric': '[00:01]普通歌词'},
              },
        kugou: (_, _) async => {},
      );
      final result = await repo.load(song148(1));
      expect(result.creators, isEmpty);
      expect(result.failed, isEmpty);
    },
  );
}
