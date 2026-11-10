import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesting_music/features/downloads/audio_downloads.dart';
import 'package:mesting_music/features/music_platform/netease/netease_track_sources.dart';
import 'package:mesting_music/features/music_platform/domain/platform_audio_quality.dart';
import 'package:mesting_music/features/music_platform/netease/messages/netease_emojis.dart';
import 'package:mesting_music/features/music_platform/netease/messages/netease_messages_repository.dart';
import 'package:mesting_music/features/music_platform/netease/netease_api.dart';
import 'package:mesting_music/features/music_platform/netease/netease_music_repository.dart';
import 'package:mesting_music/features/music_platform/netease/netease_session.dart';
import 'package:mesting_music/shared/media/persistent_network_image_cache.dart';
import 'package:mesting_music/shared/utils/media_uri.dart';
import 'netease_v112_fallback_download_test.dart' show recording, until;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'official bracket faces render inline, unknown attachments retain their text',
    () {
      expect(
        displayNeteaseEmojis('收到[便便]和[玫瑰]，未知[自定义贴纸]'),
        '收到💩和🌹，未知[自定义贴纸]',
      );
      final message = NeteaseChatMessage.parse({
        'msg': jsonEncode({'msg': '[便便]'}),
      });
      expect(message.text, '[便便]');
      expect(displayNeteaseEmojis(message.text), '💩');
    },
  );
  test(
    'thumbnail bounds bare photos and preserves supplied processing queries',
    () {
      final uri = Uri.parse(
        sizedArtworkUri(
          'http://p1.music.126.net/a==/cover.jpg',
          width: 192,
          height: 510,
        ),
      );
      expect(uri.scheme, 'https');
      expect(uri.path, '/a==/cover.jpg');
      expect(uri.queryParameters, {'param': '192y510'});
      expect(
        Uri.parse(
          sizedArtworkUri(uri.toString(), width: 9000, height: 1),
        ).queryParameters['param'],
        '1024y32',
      );
      expect(
        sizedArtworkUri('https://other.example/a?sign=keep'),
        'https://other.example/a?sign=keep',
      );
      expect(sizedArtworkUri('assets/cover.webp'), 'assets/cover.webp');
      expect(
        sizedArtworkUri('http://p1.music.126.net/a.jpg?x=kept'),
        'https://p1.music.126.net/a.jpg?x=kept',
      );
    },
  );
  test('a bare primary image ID cannot hide the later CDN URL', () {
    expect(
      firstArtworkUri(['12345', 'cover.jpg', 'http://p1.music.126.net/a.jpg']),
      'https://p1.music.126.net/a.jpg',
    );
  });
  test(
    'disk thumbnails separate size variants while sharing renewed signatures',
    () async {
      final root = await Directory.systemTemp.createTemp('mesting119-covers-');
      addTearDown(() => root.delete(recursive: true));
      var calls = 0;
      final cache = PersistentNetworkImageCache(
        directoryProvider: () async => root,
        client: MockClient((_) async {
          calls++;
          return http.Response.bytes([255, 216, 255, 0], 200);
        }),
      );
      final small = await cache.resolve(
        cacheKey: 'playlist:7',
        url: 'https://p1.music.126.net/a.jpg?param=192y192&sign=a',
      );
      final large = await cache.resolve(
        cacheKey: 'playlist:7',
        url: 'https://p1.music.126.net/a.jpg?param=630y630&sign=a',
      );
      final renewed = await cache.resolve(
        cacheKey: 'playlist:7',
        url: 'https://p1.music.126.net/a.jpg?sign=b&param=192y192',
      );
      expect(small, isNotNull);
      expect(large, isNotNull);
      expect(small!.path, isNot(large!.path));
      expect(renewed!.path, small.path);
      expect(calls, 2);
    },
  );
  test(
    'song quality metadata excludes null and zero-sized invented tiers',
    () async {
      final api =
          NeteaseApi(
            MockClient(
              (_) async => http.Response(
                jsonEncode({
                  'code': 200,
                  'songs': [
                    {
                      'l': {'size': 1},
                      'm': {'br': 192000},
                      'h': {'size': 2},
                      'sq': {'size': 3},
                      'hr': {},
                      'je': {'size': 0},
                    },
                  ],
                }),
                200,
              ),
            ),
          )..configure(
            const NeteaseSession(
              userId: '7',
              cookies: {'MUSIC_U': 'fixture'},
              deviceId: 'fixture',
            ),
          );
      expect(await NeteaseMusicRepository(api).qualities('netease_7'), {
        PlatformAudioQuality.standard,
        PlatformAudioQuality.higher,
        PlatformAudioQuality.high,
        PlatformAudioQuality.lossless,
      });
    },
  );
  for (final mismatch in [false, true]) {
    test(
      'download ${mismatch ? 'rejects downgrade before fetching' : 'retains queued quality and persists it'}',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'mesting119-download-',
        );
        addTearDown(() async {
          try {
            await root.delete(recursive: true);
          } on PathNotFoundException {
            // The completed download's staging cleanup may already have
            // removed this temporary fixture directory. Other I/O errors fail.
          }
        });
        var fetched = 0, published = 0;
        final gate = Completer<void>();
        final requested = <PlatformAudioQuality?>[];
        final manager = AudioDownloadManager(
          client: MockClient((_) async {
            fetched++;
            return http.Response.bytes(ascii.encode('fLaC000000000000'), 200);
          }),
          currentOwner: () => 'netease:7',
          directory: () async => root,
          persist: (_) async {},
          resolveRequestedMedia: (track, quality) async {
            requested.add(quality);
            await gate.future;
            return track.copyWith(
              audioAsset: 'https://audio.example/a.flac',
              playbackQuality: mismatch ? '128' : quality!.code,
            );
          },
          publish: (_, _, _, _) async {
            published++;
            return 'content://download/7';
          },
        );
        addTearDown(manager.dispose);
        manager.enqueue(recording(), quality: PlatformAudioQuality.lossless);
        manager.enqueue(
          recording(id: 'netease_8'),
          quality: PlatformAudioQuality.standard,
        );
        expect(manager.tasks.first.toJson()['requestedQuality'], 'flac');
        gate.complete();
        await until(
          () => manager.tasks.every(
            (t) =>
                t.phase == AudioDownloadPhase.completed ||
                t.phase == AudioDownloadPhase.awaitingSource,
          ),
        );
        expect(requested, [
          PlatformAudioQuality.lossless,
          PlatformAudioQuality.standard,
        ]);
        expect(
          manager.tasks.first.requestedQuality,
          PlatformAudioQuality.lossless,
        );
        expect(
          manager.tasks.first.phase,
          mismatch
              ? AudioDownloadPhase.awaitingSource
              : AudioDownloadPhase.completed,
        );
        expect(fetched, mismatch ? 1 : 2);
        expect(published, fetched);
        if (mismatch) {
          manager.selectDownloadSource(
            manager.tasks.first.id,
            NeteaseTrackSource.lxFish,
          );
          await until(() => requested.length == 3);
          expect(requested.last, PlatformAudioQuality.lossless);
        }
      },
    );
  }
  test('preview response never becomes a downloaded full song', () async {
    final root = await Directory.systemTemp.createTemp('mesting119-preview-');
    addTearDown(() => root.delete(recursive: true));
    final manager = AudioDownloadManager(
      client: MockClient((_) async {
        fail('Must not fetch preview');
      }),
      currentOwner: () => 'netease:7',
      directory: () async => root,
      persist: (_) async {},
      resolveMedia: (track) async => track.copyWith(
        audioAsset: 'https://audio.example/preview',
        isPreview: true,
      ),
      publish: (_, _, _, _) async {
        fail('Must not publish preview');
      },
    );
    addTearDown(manager.dispose);
    manager.enqueue(recording());
    await until(
      () => manager.tasks.single.phase == AudioDownloadPhase.awaitingSource,
    );
    expect(manager.tasks.single.error, contains('试听'));
  });
}
