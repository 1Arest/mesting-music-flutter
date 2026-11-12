import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesting_music/shared/models/track.dart';
import 'package:mesting_music/features/music_platform/domain/platform_audio_quality.dart';
import 'package:mesting_music/features/music_platform/data/playback_quality_catalog.dart';
import 'package:mesting_music/features/music_platform/netease/netease_api.dart';
import 'package:mesting_music/features/music_platform/netease/netease_music_repository.dart';
import 'package:mesting_music/features/music_platform/netease/netease_features_repository.dart';
import 'package:mesting_music/features/music_platform/netease/netease_item_artwork.dart';
import 'package:mesting_music/features/music_platform/netease/netease_song_metadata.dart';

class Metadata148 extends NeteaseMusicRepository {
  Metadata148(this.respond)
    : super(NeteaseApi(MockClient((_) async => http.Response('', 500))));
  final Future<Map<String, dynamic>> Function(String, Map<String, Object?>)
  respond;
  final calls = <(String, Map<String, Object?>)>[];
  @override
  Future<Map<String, dynamic>> call(
    String route, [
    Map<String, Object?> query = const {},
    Future<void>? abort,
  ]) {
    calls.add((route, query));
    return respond(route, query);
  }
}

Track quality148({
  String code = '320',
  AudioOrigin? origin,
  bool preview = false,
}) => Track(
  id: 'netease_7',
  title: '同一录音',
  artist: '样本歌手',
  album: '样本专辑',
  duration: const Duration(minutes: 3),
  audioAsset: 'https://audio.invalid/$code',
  coverAsset: '',
  lyricsAsset: '',
  source: TrackSource.netease,
  playbackQuality: code,
  isPreview: preview,
  audioOrigin: origin ?? const AudioOrigin('酷狗公开音源', 'kugou_abcdef'),
);

void main() {
  test(
    'three category cover failures recover inside bounded slots without reusing the failed URL',
    () async {
      final repository = Metadata148(
        (route, query) async => route == '/top/playlist'
            ? {
                'playlists': [
                  {
                    'id': 77,
                    'coverImgUrl': 'https://p1.music.126.net/broken.jpg',
                  },
                ],
              }
            : {
                'playlist': {
                  'coverImgUrl': 'https://p1.music.126.net/broken.jpg',
                  'tracks': [
                    {
                      'id': 7,
                      'al': {
                        'picUrl': 'https://p1.music.126.net/actual-album.jpg',
                      },
                    },
                  ],
                },
              },
      );
      final artwork = NeteaseArtworkRepository(repository);
      final covers = await Future.wait([
        for (var i = 0; i < 3; i++)
          artwork.category(
            '分类$i',
            refresh: true,
            rejected: 'https://p1.music.126.net/broken.jpg',
          ),
      ]).timeout(const Duration(seconds: 2));
      expect(covers, everyElement('https://p1.music.126.net/actual-album.jpg'));
      expect(
        repository.calls.where((entry) => entry.$1 == '/playlist/detail'),
        hasLength(3),
      );
    },
  );
  test('nested heart song wins over the outer recommendation ID', () {
    final value = NeteaseFeaturesRepository.parse({
      'id': 999,
      'songInfo': {
        'song': {
          'id': 7,
          'name': '真实歌名',
          'artists': [
            {'name': '真实歌手'},
          ],
          'album': {'picUrl': 'http://p1.music.126.net/cover.jpg'},
        },
      },
    }, NeteaseEntity.song);
    expect(value.id, '7');
    expect(value.name, '真实歌名');
    expect(value.subtitle, '真实歌手');
    expect(value.cover, 'https://p1.music.126.net/cover.jpg');
  });
  test('playlist artwork skips empty, numeric and nested primary fields', () {
    expect(
      neteaseArtwork({
        'coverImgUrl': '',
        'picUrl': 123,
        'cover': {'url': '//p2.music.126.net/actual.png'},
      }),
      'https://p2.music.126.net/actual.png',
    );
    expect(neteaseArtwork({'coverImgUrl': '12345'}), isEmpty);
  });
  test(
    'sparse metadata is hydrated by ID in batches without changing order',
    () async {
      final repository = Metadata148(
        (route, query) async => {
          'songs': [
            for (final id in (query['ids'] as List).reversed)
              {
                'id': id,
                'name': '歌曲$id',
                'ar': [
                  {'name': '歌手$id'},
                ],
                'al': {'picUrl': 'https://p1.music.126.net/$id.jpg'},
              },
            {'id': 9999, 'name': 'unrelated'},
          ],
        },
      );
      final values = await repository.hydrateSparseSongs([
        for (var i = 1; i <= 205; i++)
          {
            'id': 9000 + i,
            'songInfo': {'id': i},
          },
      ]);
      expect(repository.calls.length, 2);
      expect((repository.calls.first.$2['ids'] as List).length, 200);
      expect(values.map((r) => '${r['id']}'), [
        for (var i = 1; i <= 205; i++) '$i',
      ]);
      expect(NeteaseMusicRepository.track(values.last)!.title, '歌曲205');
    },
  );
  test('complete song metadata does not request details again', () async {
    final repository = Metadata148(
      (_, _) async => throw StateError('unexpected request'),
    );
    final values = await repository.hydrateSparseSongs([
      {
        'id': 7,
        'name': '歌曲',
        'ar': [
          {'name': '歌手'},
        ],
        'al': {'picUrl': 'https://p1.music.126.net/cover.jpg'},
      },
    ]);
    expect(values, hasLength(1));
    expect(repository.calls, isEmpty);
  });
  test(
    'category representatives are real category queries, cached and concurrency bounded',
    () async {
      var active = 0, maximum = 0;
      final repository = Metadata148((route, query) async {
        active++;
        if (active > maximum) maximum = active;
        await Future<void>.delayed(const Duration(milliseconds: 2));
        active--;
        return {
          'playlists': [
            {
              'id': 7,
              'coverImgUrl': 'https://p1.music.126.net/${query['cat']}.jpg',
            },
          ],
        };
      });
      final artwork = NeteaseArtworkRepository(repository);
      final values = await Future.wait([
        for (var i = 0; i < 12; i++) artwork.category('分类$i'),
      ]);
      expect(values.first, contains('分类0.jpg'));
      expect(maximum, lessThanOrEqualTo(3));
      await artwork.category('分类0');
      expect(repository.calls, hasLength(12));
      await artwork.category('分类0', refresh: true);
      expect(repository.calls, hasLength(13));
      expect(
        repository.calls.every(
          (c) => c.$1 == '/top/playlist' && c.$2['limit'] == 1,
        ),
        isTrue,
      );
    },
  );
  test(
    'playlist recovery preserves real cover then real contained album',
    () async {
      final repository = Metadata148(
        (_, _) async => {
          'playlist': {
            'coverImgUrl': 'http://p1.music.126.net/stale.jpg',
            'tracks': [
              {
                'id': 7,
                'al': {'picUrl': 'https://p1.music.126.net/album.jpg'},
              },
            ],
          },
        },
      );
      expect(await NeteaseArtworkRepository(repository).playlist('77'), [
        'https://p1.music.126.net/stale.jpg',
        'https://p1.music.126.net/album.jpg',
      ]);
      expect(repository.calls.single.$2, {'id': '77', 'n': 1});
    },
  );
  test(
    'actual source survives persistence and media without changing library identity',
    () {
      final track = quality148();
      final restored = Track.fromJson(track.toJson());
      expect(restored.audioOrigin, track.audioOrigin);
      expect(restored.source, TrackSource.netease);
      expect(restored.id, 'netease_7');
      expect(
        AudioOrigin.fromJson(track.toMediaItem().extras!['audioOrigin']),
        track.audioOrigin,
      );
      expect(
        Track.fromJson({...track.toJson()}..remove('audioOrigin')).audioOrigin,
        isNull,
      );
    },
  );
  test(
    'fallback menu admits only matching source, recording, full stream and tier',
    () async {
      final track = quality148();
      final values = await verifyPlaybackQualities(
        track: track,
        candidates: PlatformAudioQuality.values,
        current: () => true,
        resolve: (q) async {
          if (q == PlatformAudioQuality.standard) {
            return quality148(code: q.code);
          }
          if (q == PlatformAudioQuality.lossless) {
            return quality148(code: q.code, preview: true);
          }
          if (q == PlatformAudioQuality.hiRes) return quality148(code: '320');
          return quality148(
            code: q.code,
            origin: const AudioOrigin(AudioOrigin.netease, 'netease_7'),
          );
        },
      );
      expect(values.keys.toSet(), {
        PlatformAudioQuality.standard,
        PlatformAudioQuality.high,
      });
      expect(
        values.values.every((t) => t.audioOrigin == track.audioOrigin),
        isTrue,
      );
    },
  );
  test('same provider different matched recording is not switchable', () async {
    final values = await verifyPlaybackQualities(
      track: quality148(),
      candidates: [PlatformAudioQuality.lossless],
      current: () => true,
      resolve: (q) async => quality148(
        code: q.code,
        origin: const AudioOrigin('酷狗公开音源', 'kugou_OTHER'),
      ),
    );
    expect(values.keys, [PlatformAudioQuality.high]);
  });
  test(
    'a preview can become a confirmed full tier; failed tiers stay hidden',
    () async {
      final values = await verifyPlaybackQualities(
        track: quality148(preview: true),
        candidates: [PlatformAudioQuality.high, PlatformAudioQuality.lossless],
        current: () => true,
        resolve: (q) async {
          if (q == PlatformAudioQuality.lossless) {
            throw StateError('no entitlement');
          }
          return quality148();
        },
      );
      expect(values.keys, [PlatformAudioQuality.high]);
    },
  );
  test('account revocation discards late capability results', () async {
    var current = true;
    final completion = Completer<Track>();
    final work = verifyPlaybackQualities(
      track: quality148(),
      candidates: [PlatformAudioQuality.standard],
      current: () => current,
      resolve: (_) => completion.future,
    );
    current = false;
    completion.complete(quality148(code: '128'));
    expect(await work, isEmpty);
  });
  test(
    'legacy fallback never infers capabilities from its original NetEase platform',
    () {
      final track = Track.fromJson(
        quality148().toJson()..remove('audioOrigin'),
      ).copyWith(availabilityMessage: '备用音源 · 酷狗公开音源');
      expect(playbackAudioOrigin(track)!.isNetease, isFalse);
      expect(playbackAudioOrigin(track)!.recordingId, isEmpty);
    },
  );
}
