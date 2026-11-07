import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesting_music/features/lyrics/data/lyrics_repository.dart';

http.Response _jsonResponse(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  test('embedded lyrics transport works without a hosted base URL', () async {
    final requested = <String>[];
    final repository = LyricsRepository(
      client: MockClient(
        (_) async => throw StateError('Must use injected adapter'),
      ),
      kugouApiBaseUrl: '',
      neteaseApiBaseUrl: '',
      kugouRequest: (path, query) async {
        requested.add(path);
        if (path == '/search/lyric') {
          expect(query['hash'], 'hash123');
          return {
            'candidates': [
              {'id': 'one', 'accesskey': 'key'},
            ],
          };
        }
        return {'decodeContent': '[00:01.00]本机服务歌词'};
      },
    );
    final lyrics = await repository.loadAsset('mesting-lyrics://kugou/hash123');
    expect(lyrics.isSynced, true);
    expect(lyrics.lines.single.text, '本机服务歌词');
    expect(requested, ['/search/lyric', '/lyric']);
  });
  test('酷狗歌词按搜索与下载两步解析为同步歌词', () async {
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/search/lyric')) {
        return _jsonResponse({
          'candidates': [
            {'id': 'lyric-1', 'accesskey': 'key-1'},
          ],
        });
      }
      if (request.url.path.endsWith('/lyric')) {
        return _jsonResponse({'decodeContent': '[00:01.00]第一句\n[00:03.50]第二句'});
      }
      throw StateError('unexpected request: ${request.url}');
    });
    final repository = LyricsRepository(
      client: client,
      kugouApiBaseUrl: 'https://kugou.test',
      neteaseApiBaseUrl: '',
    );

    final lyrics = await repository.loadAsset(
      'mesting-lyrics://kugou/hash123?albumAudioId=8&durationMs=10000',
    );

    expect(lyrics.isSynced, isTrue);
    expect(lyrics.lines, hasLength(2));
    expect(lyrics.lines.first.text, '第一句');
  });

  test('网易云歌词使用标准歌词接口内容', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/lyric/new');
      expect(request.url.queryParameters['id'], '42');
      return _jsonResponse({
        'lrc': {'lyric': '[00:02.00]网易云歌词'},
      });
    });
    final repository = LyricsRepository(
      client: client,
      kugouApiBaseUrl: '',
      neteaseApiBaseUrl: 'https://netease.test',
    );

    final lyrics = await repository.loadAsset('mesting-lyrics://netease/42');

    expect(lyrics.lines.single.text, '网易云歌词');
  });

  test('未配置自建服务时直接读取酷狗公开同步歌词', () async {
    final requests = <Uri>[];
    final client = MockClient((request) async {
      requests.add(request.url);
      if (request.url.path == '/search') {
        return _jsonResponse({
          'candidates': [
            {'id': 'public-lyric-1', 'accesskey': 'public-key-1'},
          ],
        });
      }
      if (request.url.path == '/download') {
        return _jsonResponse({
          'content': base64Encode(
            utf8.encode('[00:02.00]公开歌词第一句\n[00:05.00]公开歌词第二句'),
          ),
        });
      }
      throw StateError('unexpected request: ${request.url}');
    });
    final repository = LyricsRepository(
      client: client,
      kugouApiBaseUrl: '',
      neteaseApiBaseUrl: '',
      kugouPublicLyricsBaseUrl: 'https://lyrics.test',
    );

    final lyrics = await repository.loadAsset(
      'mesting-lyrics://kugou/hash123?durationMs=240000',
    );

    expect(lyrics.isSynced, isTrue);
    expect(lyrics.lines, hasLength(2));
    expect(requests.map((uri) => uri.path), ['/search', '/download']);
    expect(requests.first.queryParameters['hash'], 'hash123');
  });
}
