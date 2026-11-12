import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/features/music_platform/data/song_menu_details.dart';
import 'release_148_ui_test.dart' show song148;

void main() {
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
            'lrc': {'lyric': '[00:00]作曲：已读取创作者'},
          };
        },
        kugou: (_, _) async => {},
      );
      final data = await repository.load(song148(1));
      expect(paths, ['/song/detail', '/lyric']);
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
            'lrc': {'lyric': '[00:00]作词：词作者'},
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
      expect(paths, ['/song/detail', '/lyric', '/lyric']);
      expect(next.failed, isEmpty);
      expect(next.albumId, '9');
      expect(next.artists.single.name, '真实歌手');
      expect(next.creators.single.name, '词作者');
    },
  );
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
