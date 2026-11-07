import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesting_music/shared/models/track.dart';
import 'package:mesting_music/features/downloads/audio_downloads.dart';
import 'package:mesting_music/features/music_platform/netease/netease_fallback.dart';

Track recording({
  String id = 'netease_7',
  String title = '陪你去流浪',
  String artist = '薛之谦',
  String album = '尘',
  int seconds = 274,
}) => Track(
  id: id,
  title: title,
  artist: artist,
  album: album,
  duration: Duration(seconds: seconds),
  audioAsset: '',
  coverAsset: '',
  lyricsAsset: '',
  source: TrackSource.netease,
  platformSongId: id.startsWith('netease_') ? id.substring(8) : '',
);

class _Source implements NeteaseFallbackSource {
  _Source(this.items, {this.afterSearch});
  final List<Track> items;
  final void Function()? afterSearch;
  int resolutions = 0;
  @override
  String get label => '测试音源';
  @override
  Future<List<Track>> search(Track original) async {
    afterSearch?.call();
    return items;
  }

  @override
  Future<Track?> resolve(Track candidate) async {
    resolutions++;
    return candidate.copyWith(
      audioAsset: 'https://audio.example/song',
      isPreview: false,
      playbackQuality: '320',
    );
  }
}

Future<void> until(bool Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 4));
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for download state');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  test(
    'strict matching rejects live, covers, missing evidence and different albums',
    () {
      final original = recording();
      expect(isSameNeteaseRecording(original, recording(id: 'other')), isTrue);
      for (final candidate in [
        recording(title: '陪你去流浪 (Live)'),
        recording(artist: '翻唱歌手'),
        recording(album: '演唱会'),
        recording(album: ''),
        recording(seconds: 30),
        recording(seconds: 0),
      ]) {
        expect(isSameNeteaseRecording(original, candidate), isFalse);
      }
    },
  );
  test(
    'fallback retains NetEase identity for comments, likes and lyrics',
    () async {
      final source = _Source([recording(id: 'kugou_hash')]);
      final client = MockClient((r) async {
        expect(r.headers['Range'], 'bytes=0-1023');
        return http.Response.bytes(
          [73, 68, 51, 0],
          206,
          headers: {'content-type': 'audio/mpeg'},
        );
      });
      final result = await NeteaseFallbackResolver([
        source,
      ], client).resolve(recording(), current: () => true);
      expect(result!.id, 'netease_7');
      expect(result.source, TrackSource.netease);
      expect(result.platformSongId, '7');
      expect(result.playbackQuality, '320');
      expect(result.availabilityMessage, contains('测试音源'));
    },
  );
  test(
    'switching accounts during source search blocks its resolution',
    () async {
      var current = true;
      final source = _Source([
        recording(id: 'kugou_hash'),
      ], afterSearch: () => current = false);
      final result = await NeteaseFallbackResolver(
        [source],
        MockClient((_) async => throw StateError('No I/O expected')),
      ).resolve(recording(), current: () => current);
      expect(result, isNull);
      expect(source.resolutions, 0);
    },
  );
  test(
    'BugPk receives no account credentials and reports delivered quality',
    () async {
      final source = BugpkNeteaseFallback(
        MockClient((r) async {
          expect(r.url.host, 'api.bugpk.com');
          expect(r.url.queryParameters['id'], '7');
          expect(r.headers.containsKey('cookie'), isFalse);
          expect(r.headers.containsKey('authorization'), isFalse);
          expect(r.url.queryParameters['level'], 'lossless');
          return http.Response(
            jsonEncode({
              'code': 200,
              'data': [
                {
                  'id': 7,
                  'url': 'https://m8.music.126.net/test.mp3',
                  'level': 'exhigh',
                },
              ],
            }),
            200,
          );
        }),
      );
      final result = await source.resolve(
        recording().copyWith(playbackQuality: 'flac'),
      );
      expect(result!.playbackQuality, '320');
    },
  );
  test(
    'BugPk wrong-song responses are rejected before probing media',
    () async {
      final source = BugpkNeteaseFallback(
        MockClient(
          (_) async => http.Response(
            jsonEncode({
              'code': 200,
              'data': [
                {
                  'id': 99,
                  'url': 'https://m8.music.126.net/test.flac',
                  'level': 'lossless',
                },
              ],
            }),
            200,
          ),
        ),
      );
      await expectLater(
        source.resolve(recording()),
        throwsA(
          isA<NeteaseSourceFailure>().having(
            (e) => e.reason,
            'reason',
            'wrong_song_id',
          ),
        ),
      );
    },
  );
  test('containers use audio bytes rather than incorrect CDN Content-Type', () {
    expect(
      identifyAudio([
        ...ascii.encode('fLaC'),
        ...List.filled(20, 0),
      ])!.extension,
      'flac',
    );
    expect(
      identifyAudio([...ascii.encode('ID3'), ...List.filled(20, 0)])!.extension,
      'mp3',
    );
    expect(identifyAudio(ascii.encode('{"error":"not audio"}')), isNull);
  });
  group('download queue', () {
    late Directory dir;
    setUp(
      () async => dir = await Directory(
        '.codex-artifacts/2026-10-29-netease-completion/download-tests',
      ).create(recursive: true),
    );
    tearDown(() async {
      // Only files owned by this test are removed; no recursive directory delete.
      for (final file in dir.listSync().whereType<File>()) {
        if (file.path.endsWith('.part')) await file.delete();
      }
    });
    test(
      'FLAC with audio/mpeg header saves once and cleans its temporary file',
      () async {
        final body = [...ascii.encode('fLaC'), ...List.filled(100, 0)];
        var exports = 0;
        final manager = AudioDownloadManager(
          client: MockClient(
            (_) async => http.Response.bytes(
              body,
              200,
              headers: {'content-type': 'audio/mpeg'},
            ),
          ),
          resolve: (_) async => 'https://audio.example/1',
          publish: (file, track, ext, mime) async {
            exports++;
            expect(ext, 'flac');
            expect(mime, 'audio/flac');
            expect(await file.readAsBytes(), body);
            return 'content://media/1';
          },
          currentOwner: () => 'netease:7',
          directory: () async => dir,
          persist: (_) async {},
        );
        addTearDown(manager.dispose);
        manager.enqueue(recording());
        await until(
          () => manager.tasks.single.phase == AudioDownloadPhase.completed,
        );
        expect(exports, 1);
        expect(manager.tasks.single.uri, 'content://media/1');
        await until(() => dir.listSync().whereType<File>().isEmpty);
      },
    );
    test('HTML error pages cannot be published as downloaded audio', () async {
      var exports = 0;
      final manager = AudioDownloadManager(
        client: MockClient(
          (_) async => http.Response('<html>error</html>', 200),
        ),
        resolve: (_) async => 'https://audio.example/1',
        publish: (_, track, ext, mime) async {
          exports++;
          return '';
        },
        currentOwner: () => 'netease:7',
        directory: () async => dir,
        persist: (_) async {},
      );
      addTearDown(manager.dispose);
      manager.enqueue(recording());
      await until(
        () => manager.tasks.single.phase == AudioDownloadPhase.awaitingSource,
      );
      expect(exports, 0);
    });
    test('cancel while resolving does not start a file request', () async {
      final pending = Completer<String>();
      var requests = 0;
      final manager = AudioDownloadManager(
        client: MockClient((_) async {
          requests++;
          return http.Response('', 200);
        }),
        resolve: (_) => pending.future,
        publish: (_, track, ext, mime) async => '',
        currentOwner: () => 'netease:7',
        directory: () async => dir,
        persist: (_) async {},
      );
      addTearDown(manager.dispose);
      manager.enqueue(recording());
      manager.cancel(manager.tasks.single.id);
      pending.complete('https://audio.example/1');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(requests, 0);
      expect(manager.tasks.single.phase, AudioDownloadPhase.cancelled);
    });
  });
}
