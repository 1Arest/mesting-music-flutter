import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesting_music/core/audio/music_rhythm.dart';
import 'package:mesting_music/features/library/data/official_song_count_reader.dart';
import 'package:mesting_music/features/library/data/song_favorite_count.dart';
import 'package:mesting_music/features/music_platform/netease/footprint/official_report_extras.dart';
import 'package:mesting_music/features/themes/personal_style.dart';
import 'package:mesting_music/shared/models/track.dart';

void main() {
  test(
    'public official counts use fixed song identities without account credentials',
    () async {
      final client = MockClient((request) async {
        expect(request.headers.containsKey('cookie'), false);
        expect(request.headers.containsKey('authorization'), false);
        if (request.url.host == 'music.163.com') {
          expect(request.url.path, '/api/song/red/count');
          expect(request.url.queryParameters, {'songId': '362937'});
          return http.Response(
            jsonEncode({
              'code': 200,
              'data': {'count': 5902365},
            }),
            200,
          );
        }
        expect(request.url.host, 'gateway.kugou.com');
        expect(request.url.path, '/count/v1/audio/mget_collect');
        expect(request.url.queryParameters['mixsongids'], '368015985');
        expect(
          request.url.queryParameters['signature'],
          matches(r'^[0-9a-f]{32}$'),
        );
        return http.Response(
          jsonEncode({
            'status': 1,
            'data': {
              'list': [
                {'mixsongid': 368015984, 'count': 9},
                {'mixsongid': 368015985, 'count': 397661},
              ],
            },
          }),
          200,
        );
      });
      for (final song in [
        (TrackSource.netease, '362937'),
        (TrackSource.kugou, '368015985'),
      ]) {
        final payload = await readOfficialSongCount(client, song.$1, song.$2);
        expect(
          songFavoriteCount(payload, song),
          song.$1 == TrackSource.netease ? 5902365 : 397661,
        );
      }
      client.close();
    },
  );
  test(
    'removed frame preferences cannot restore the retired visual effect',
    () {
      for (final frame in ['stamp', 'polaroid', 'future']) {
        final value = PersonalStyle.fromJson({
          'frame': frame,
          'poster': 'ticket',
        });
        expect(value.frame, CoverFrame.none);
        expect(value.toJson().containsKey('frame'), false);
        expect(value.poster, PosterTemplate.ticket);
      }
    },
  );
  test(
    'every official achievement remains server-driven, including future labels',
    () {
      for (final label in [
        '云村夜猫子',
        '红心收藏家',
        '听歌全勤奖',
        '云村超级乐迷',
        '音乐漫游者',
        '未来官方称号',
      ]) {
        final report = OfficialReportExtras.parse({
          'listenTimeDistributionBlock': {
            'achievementTitle': {'mainTitle': label, 'subTitle': '官方解释'},
          },
        });
        expect(report.achievement, label);
        expect(report.achievementDetail, '官方解释');
        expect(report.songCount, isNull);
        expect(report.songs, isEmpty);
      }
    },
  );
  test(
    'report blocks preserve upstream song, artist, genre, era and language fields',
    () {
      final report = OfficialReportExtras.parse({
        'wallpaperBlock': {
          'songCount': 163,
          'picUrls': ['https://p1.music.126.net/cover.jpg'],
        },
        'topSongBlock': {
          'sections': [
            {
              'songId': 42,
              'songName': '官方歌曲',
              'text': '2次',
              'field': '收听TOP1',
              'picUrl': '',
            },
          ],
        },
        'topArtistBlock': {
          'sections': [
            {'artistName': '官方音乐人', 'text': '11次'},
          ],
        },
        'topStyleBlock': {
          'sections': [
            {'genreName': '流行', 'percent': 57},
          ],
        },
        'topAgeBlock': {
          'sections': [
            {'age': 2013, 'songName': '代表歌曲'},
          ],
        },
        'topLanguageBlock': {
          'sections': [
            {'language': '华语', 'percent': 74},
            {'language': '英语', 'percent': 30},
          ],
        },
      });
      expect(report.songCount, 163);
      expect(report.covers, hasLength(1));
      expect(report.songs.single.id, '42');
      expect(report.songs.single.detail, '2次 · 收听TOP1');
      expect(report.artists.single.title, '官方音乐人');
      expect(report.genres.single.percent, 57);
      expect(report.ages.single.title, '2010-2019');
      // These are independently reported categories, not a synthetic 100% pie.
      expect(report.languages.map((v) => v.percent), [74, 30]);
      expect(OfficialReportExtras.parse({}).covers, isEmpty);
    },
  );
  test('silence, bass and treble keep independent measured responses', () {
    MusicRhythmFrame frame(double rms, List<double> bands) =>
        MusicRhythmFrame.parse({
          'available': true,
          'rms': rms,
          'peak': rms,
          'bands': bands,
          'frameId': 1,
        });
    expect(frame(0, List.filled(12, 0)).level, 0);
    expect(frame(.7, []).level, greaterThan(frame(.08, []).level));
    final bass = frame(.2, [.7, .6, .5, 0, 0, 0, 0, 0, 0, 0, 0, 0]);
    final treble = frame(.2, [0, 0, 0, 0, 0, 0, 0, 0, .5, .6, .7, .4]);
    expect(bass.bass, greaterThan(bass.treble));
    expect(treble.treble, greaterThan(treble.bass));
  });
}
