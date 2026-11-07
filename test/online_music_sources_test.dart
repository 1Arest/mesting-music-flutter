import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesting_music/features/search/data/kugou_music_source.dart';
import 'package:mesting_music/features/search/data/netease_music_source.dart';
import 'package:mesting_music/shared/models/track.dart';

http.Response _jsonResponse(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  group('酷狗概念版来源', () {
    test('公开搜索结果可解析，并只使用官方返回的播放地址', () async {
      final requestedPaths = <String>[];
      final client = MockClient((request) async {
        requestedPaths.add(request.url.path);
        if (request.url.path.endsWith('/search/song')) {
          return _jsonResponse({
            'status': 1,
            'data': {
              'info': [
                {
                  'hash': 'ABC123',
                  'songname_original': '测试国语歌',
                  'singername': '测试歌手',
                  'album_name': '测试专辑',
                  'album_id': '99',
                  'album_audio_id': 1001,
                  'duration': 205,
                  'trans_param': {
                    'union_cover': 'http://img.test/{size}/cover.jpg',
                  },
                },
              ],
            },
          });
        }
        if (request.url.path.endsWith('/getSongInfo.php')) {
          return _jsonResponse({
            'status': 1,
            'url': 'http://audio.test/song.mp3',
          });
        }
        throw StateError('unexpected request: ${request.url}');
      });
      final source = KugouMusicSource(
        client,
        apiBaseUrl: '',
        publicSearchBaseUrl: 'https://api.test/search/song',
        legacySongInfoBaseUrl: 'https://api.test/getSongInfo.php',
      );

      final tracks = await source.search('测试', limit: 1);

      expect(tracks, hasLength(1));
      expect(tracks.single.source, TrackSource.kugou);
      expect(tracks.single.title, '测试国语歌');
      expect(tracks.single.audioAsset, 'https://audio.test/song.mp3');
      expect(tracks.single.coverAsset, 'https://img.test/400/cover.jpg');
      expect(tracks.single.isPlayable, isTrue);
      expect(tracks.single.hasLyrics, isTrue);
      expect(tracks.single.lyricsAsset, startsWith('mesting-lyrics://kugou/'));
      expect(requestedPaths, contains('/getSongInfo.php'));
    });
  });

  group('网易云 Enhanced 来源', () {
    test('标准播放请求明确关闭解灰', () async {
      Uri? playbackRequest;
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/cloudsearch')) {
          return _jsonResponse({
            'result': {
              'songs': [
                {
                  'id': 42,
                  'name': '可播放歌曲',
                  'dt': 180000,
                  'ar': [
                    {'name': '歌手'},
                  ],
                  'al': {'name': '专辑', 'picUrl': 'http://img.test/cover.jpg'},
                  'privilege': {'pl': 128000},
                },
              ],
            },
          });
        }
        if (request.url.path.endsWith('/song/url/v1')) {
          playbackRequest = request.url;
          return _jsonResponse({
            'data': [
              {
                'id': 42,
                'url': 'http://audio.test/netease.mp3',
                'fee': 8,
                'payed': 0,
                'freeTrialInfo': null,
              },
            ],
          });
        }
        throw StateError('unexpected request: ${request.url}');
      });
      final source = NeteaseMusicSource(
        client,
        apiBaseUrl: 'https://netease.test',
      );

      final tracks = await source.search('歌曲', limit: 1);

      expect(playbackRequest?.queryParameters['unblock'], 'false');
      expect(tracks.single.audioAsset, contains('/song/url/v1/302'));
      expect(Uri.parse(tracks.single.audioAsset).queryParameters['id'], '42');
      expect(tracks.single.source, TrackSource.netease);
      expect(tracks.single.hasLyrics, isTrue);
    });

    test('原始版权状态不可播时不请求也不接受替换音源', () async {
      var playbackCalls = 0;
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/cloudsearch')) {
          return _jsonResponse({
            'result': {
              'songs': [
                {
                  'id': 88,
                  'name': '受限歌曲',
                  'dt': 200000,
                  'fee': 1,
                  'ar': [
                    {'name': '歌手'},
                  ],
                  'al': {'name': '专辑', 'picUrl': ''},
                  'privilege': {'pl': 0, 'fee': 1},
                },
              ],
            },
          });
        }
        playbackCalls += 1;
        return _jsonResponse({
          'data': [
            {'url': 'https://unblock.test/forbidden.mp3'},
          ],
        });
      });
      final source = NeteaseMusicSource(
        client,
        apiBaseUrl: 'https://netease.test',
      );

      final tracks = await source.search('受限歌曲', limit: 1);

      expect(playbackCalls, 0);
      expect(tracks.single.isPlayable, isFalse);
      expect(tracks.single.availabilityMessage, contains('未使用解灰'));
    });
  });
}
