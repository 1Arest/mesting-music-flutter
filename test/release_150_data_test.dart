import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesting_music/features/library/data/favorite_pins.dart';
import 'package:mesting_music/features/music_platform/data/song_menu_details.dart';
import 'package:mesting_music/shared/models/song_list_memory.dart';
import 'package:mesting_music/shared/models/track.dart';
import 'release_148_ui_test.dart' show song148;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<SharedPreferences> preferences() async {
    SharedPreferences.setMockInitialValues({});
    return SharedPreferences.getInstance();
  }

  test(
    'pins persist account-isolated order without audio URLs or headers',
    () async {
      final prefs = await preferences();
      final pins = FavoritePins(prefs);
      final first = song148(1).copyWith(
        audioAsset: 'https://cdn.invalid/a?secret=private',
        audioHeaders: {'X-Private': 'private'},
      );
      await Future.wait([
        pins.toggle('netease:one', first),
        pins.toggle('netease:one', song148(2)),
        pins.toggle('kugou:two', song148(3)),
      ]);
      final raw = prefs.getString(FavoritePins.storageKey)!;
      expect(raw, isNot(contains('private')));
      final restored = FavoritePins(prefs);
      final loaded = [song148(0), song148(1), song148(2), song148(4)];
      final ids = loaded.map((t) => t.id).toSet();
      expect(restored.apply('netease:one', loaded, ids).map((t) => t.id), [
        song148(2).id,
        song148(1).id,
        song148(0).id,
        song148(4).id,
      ]);
      expect(restored.apply('new-account', loaded, ids), loaded);
      await restored.toggle('netease:one', song148(2));
      expect(restored.apply('netease:one', loaded, ids).map((t) => t.id), [
        song148(1).id,
        song148(0).id,
        song148(2).id,
        song148(4).id,
      ]);
      restored.dispose();
      pins.dispose();
    },
  );
  test(
    'pinned unloaded songs require real membership; loaded rows win over saved metadata',
    () async {
      final pins = FavoritePins(await preferences());
      await pins.toggle('one', song148(80));
      final page = [song148(1), song148(2)];
      expect(pins.apply('one', page, page.map((t) => t.id).toSet()), page);
      final withPin = pins.apply('one', page, {
        ...page.map((t) => t.id),
        song148(80).id,
      });
      expect(withPin.first.id, song148(80).id);
      final fresh = song148(80).copyWith(coverAsset: 'fresh-cover');
      expect(
        pins.apply('one', [...page, fresh], {fresh.id}).first.coverAsset,
        'fresh-cover',
      );
      expect(pins.apply('other', page, {song148(80).id}), page);
      pins.dispose();
    },
  );
  test(
    'legacy bookmarks restore and new bookmarks retain actual song cover',
    () async {
      final prefs = await preferences();
      await prefs.setString(
        SongListMemory.storageKey,
        jsonEncode({
          jsonEncode(['a', 'favorites']): {
            'id': 'old',
            'title': 'old',
            'at': 1,
          },
        }),
      );
      final memory = SongListMemory(prefs);
      expect(memory.read('a', 'favorites')!.cover, '');
      memory.remember('a', 'favorites', song148(1));
      await memory.flush();
      final restored = SongListMemory(prefs);
      expect(restored.read('a', 'favorites')!.cover, song148(1).coverAsset);
      memory.dispose();
      restored.dispose();
    },
  );
  test(
    'NetEase details use exact song, genuine artists, album and explicit lyric credits',
    () async {
      final requests = <String>[];
      final repo = SongMenuDetailsRepository(
        netease: (path, query) async {
          requests.add(path);
          return path == '/song/detail'
              ? {
                  'songs': [
                    {
                      'id': 999,
                      'ar': [
                        {'id': 100, 'name': 'wrong'},
                      ],
                    },
                    {
                      'id': 9001,
                      'ar': [
                        {'id': 8, 'name': '歌手'},
                      ],
                      'al': {'id': 9, 'name': '专辑'},
                    },
                  ],
                }
              : {
                  'lrc': {
                    'lyric':
                        '[00:00.100]作词：真实作词者\n[00:01]作曲：真实作曲者\n[00:02]歌手在唱歌',
                  },
                };
        },
        kugou: (_, _) async => throw StateError('wrong platform'),
      );
      final data = await repo.load(song148(1));
      expect(requests, ['/song/detail', '/lyric']);
      expect(data.artists.single.id, '8');
      expect(data.albumId, '9');
      expect(data.creators.map((p) => p.role), ['作词', '作曲']);
      expect(data.creators.map((p) => p.name), ['真实作词者', '真实作曲者']);
    },
  );
  test(
    'optional credits failure retains verified NetEase song information',
    () async {
      final repo = SongMenuDetailsRepository(
        netease: (path, _) async {
          if (path == '/lyric') throw StateError('offline');
          return {
            'songs': [
              {
                'id': 9001,
                'ar': [
                  {'id': 8, 'name': '歌手'},
                ],
                'al': {'id': 9, 'name': '专辑'},
              },
            ],
          };
        },
        kugou: (_, _) async => {},
      );
      final data = await repo.load(song148(1));
      expect(data.albumId, '9');
      expect(data.creators, isEmpty);
    },
  );
  test(
    'wrong NetEase ID is rejected instead of assigning another recording',
    () async {
      final repo = SongMenuDetailsRepository(
        netease: (_, _) async => {
          'songs': [
            {'id': 5},
          ],
        },
        kugou: (_, _) async => {},
      );
      final result = await repo.load(song148(1));
      expect(result.failed, contains(SongDetailsSection.catalogue));
      expect(result.albumId, isEmpty);
      expect(result.artists.every((p) => p.id != '5'), true);
    },
  );
  final kugou = Track(
    id: 'kugou_HASH',
    title: '歌曲',
    artist: '歌手',
    album: '专辑',
    duration: const Duration(minutes: 3),
    audioAsset: 'mesting-platform://kugou/kugou_HASH',
    coverAsset: '',
    lyricsAsset: '',
    source: TrackSource.kugou,
  );
  test(
    'Kugou keeps album ID distinct from mix ID and does not invent singer credits',
    () async {
      final repo = SongMenuDetailsRepository(
        netease: (_, _) async => {},
        kugou: (path, query) async => path == '/audio'
            ? {
                'data': [
                  {
                    'hash': 'HASH',
                    'mixsongid': 777,
                    'album_info': {'id': 42, 'album_name': '真实专辑'},
                    'authors': [
                      {'author_id': 13, 'author_name': '真实歌手'},
                    ],
                  },
                ],
              }
            : {'candidates': []},
      );
      final data = await repo.load(kugou);
      expect(data.albumId, '42');
      expect(data.artists.single.id, '13');
      expect(data.creators, isEmpty);
    },
  );
  test(
    'Kugou credits read exact hash lyric; no playback URL request occurs',
    () async {
      final requests = <String>[];
      final repo = SongMenuDetailsRepository(
        netease: (_, _) async => {},
        kugou: (path, query) async {
          requests.add(path);
          if (path == '/audio') {
            return {
              'data': [
                {'hash': 'HASH', 'album_id': 42},
              ],
            };
          }
          if (path == '/search/lyric') {
            expect(query['hash'], 'HASH');
            return {
              'candidates': [
                {'id': 6, 'accesskey': 'public-lyric-key'},
              ],
            };
          }
          return {'decodeContent': '[00:00]作词：词作者\n[00:01]作曲：曲作者'};
        },
      );
      final data = await repo.load(kugou);
      expect(requests, ['/audio', '/search/lyric', '/lyric']);
      expect(data.creators.map((p) => p.name), ['词作者', '曲作者']);
    },
  );
  test('wrong Kugou hash is rejected', () async {
    final repo = SongMenuDetailsRepository(
      netease: (_, _) async => {},
      kugou: (_, _) async => {
        'data': [
          {'hash': 'OTHER', 'album_id': 42},
        ],
      },
    );
    final result = await repo.load(kugou);
    expect(result.failed, contains(SongDetailsSection.catalogue));
    expect(result.albumId, isEmpty);
  });
  test(
    'corrupt optional pin rows cannot prevent loading other accounts',
    () async {
      final prefs = await preferences();
      await prefs.setString(
        FavoritePins.storageKey,
        '{"bad":[{"id":2}],"empty":[]}',
      );
      final pins = FavoritePins(prefs);
      await pins.toggle('valid', song148(1));
      expect(pins.contains('valid', song148(1).id), true);
      pins.dispose();
    },
  );
}
