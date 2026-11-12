import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesting_music/features/downloads/audio_downloads.dart';
import 'package:mesting_music/features/downloads/netease_download_resolver.dart';
import 'package:mesting_music/features/music_platform/data/music_platform_api.dart';
import 'package:mesting_music/features/music_platform/domain/platform_audio_quality.dart';
import 'package:mesting_music/features/music_platform/netease/netease_track_sources.dart';
import 'package:mesting_music/features/music_platform/netease/netease_api.dart';
import 'package:mesting_music/features/music_platform/netease/netease_music_repository.dart';
import 'package:mesting_music/shared/models/track.dart';
import 'netease_v112_fallback_download_test.dart' show recording, until;

class _DownloadMetadata extends NeteaseMusicRepository {
  _DownloadMetadata()
    : super(
        NeteaseApi(MockClient((_) async => throw StateError('no real API'))),
      );
  @override
  Future<Map<String, dynamic>> call(
    String route, [
    Map<String, Object?> query = const {},
    Future<void>? abort,
  ]) async => {
    'data': {
      'id': 7,
      'url': 'https://cdn.example/preview.mp3',
      'time': 30000,
      'level': 'exhigh',
      'br': 320000,
    },
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final original = recording().copyWith(
    audioOrigin: const AudioOrigin('LX · fish', '7'),
  );
  final full = original.copyWith(
    audioAsset: 'https://cdn.example/full.mp3',
    playbackQuality: '320',
    isPreview: false,
    audioOrigin: const AudioOrigin(AudioOrigin.netease, 'netease_7'),
  );

  test(
    'official duration metadata rejects an unlabelled preview before media I/O',
    () async {
      final client = MockClient(
        (_) async => throw StateError('must not fetch a known preview'),
      );
      expect(
        await lookupOfficialNeteaseDownload(
          _DownloadMetadata(),
          original,
          PlatformAudioQuality.high,
          client: client,
        ),
        isNull,
      );
      client.close();
    },
  );

  test(
    'expired source URL after resolution returns to explicit download choice',
    () async {
      final folder = await Directory.systemTemp.createTemp(
        'mesting161-expired-',
      );
      addTearDown(() => folder.delete(recursive: true));
      var requests = 0;
      final manager = AudioDownloadManager(
        client: MockClient((_) async {
          requests++;
          return http.Response('not audio', 404);
        }),
        currentOwner: () => 'netease:7',
        directory: () async => folder,
        persist: (_) async {},
        publish: (f, t, e, m) async => throw StateError('must not publish'),
        resolveTaskMedia: (t, abort) async => full,
      );
      addTearDown(manager.dispose);
      manager.enqueue(original, quality: PlatformAudioQuality.high);
      await until(
        () => manager.tasks.single.phase == AudioDownloadPhase.awaitingSource,
      );
      expect(requests, 1);
      expect(manager.tasks.single.uri, isEmpty);
    },
  );

  test(
    'fresh download always tries official regardless of playback origin',
    () async {
      var official = 0, alternatives = 0;
      final media = await resolveNeteaseDownload(
        track: original,
        quality: PlatformAudioQuality.high,
        current: () => true,
        official: (t, q) async {
          official++;
          return full;
        },
        alternative: (t, q, s) async {
          alternatives++;
          return null;
        },
      );
      expect(official, 1);
      expect(alternatives, 0);
      expect(media.audioOrigin!.adapter, AudioOrigin.netease);
    },
  );
  for (final kind in ['missing', 'preview', 'wrongQuality', 'error']) {
    test(
      'official $kind asks user instead of silently requesting another source',
      () async {
        var alternatives = 0;
        await expectLater(
          resolveNeteaseDownload(
            track: original,
            quality: PlatformAudioQuality.high,
            current: () => true,
            official: (t, q) async => switch (kind) {
              'preview' => full.copyWith(isPreview: true),
              'wrongQuality' => full.copyWith(playbackQuality: '128'),
              'error' => throw const FormatException('invalid response'),
              _ => null,
            },
            alternative: (t, q, s) async {
              alternatives++;
              return full;
            },
          ),
          throwsA(isA<DownloadSourceSelectionRequired>()),
        );
        expect(alternatives, 0);
      },
    );
  }
  test(
    'explicit alternate choice tries exactly that source and failure remains a choice',
    () async {
      var official = 0;
      final calls = <NeteaseTrackSource>[];
      await expectLater(
        resolveNeteaseDownload(
          track: original,
          quality: PlatformAudioQuality.high,
          current: () => true,
          selectedSource: NeteaseTrackSource.lxFish,
          official: (t, q) async {
            official++;
            return full;
          },
          alternative: (t, q, s) async {
            calls.add(s);
            return null;
          },
        ),
        throwsA(isA<DownloadSourceSelectionRequired>()),
      );
      expect(official, 0);
      expect(calls, [NeteaseTrackSource.lxFish]);
    },
  );
  test(
    'account cancellation and login/security rejection never open a fallback choice',
    () async {
      await expectLater(
        resolveNeteaseDownload(
          track: original,
          quality: PlatformAudioQuality.high,
          current: () => false,
          official: (t, q) async => full,
          alternative: (t, q, s) async => null,
        ),
        throwsA(isA<MusicPlatformException>()),
      );
      await expectLater(
        resolveNeteaseDownload(
          track: original,
          quality: PlatformAudioQuality.high,
          current: () => true,
          official: (t, q) async =>
              throw const MusicPlatformException('login', code: '301'),
          alternative: (t, q, s) async => null,
        ),
        throwsA(isA<MusicPlatformException>()),
      );
    },
  );
  test(
    'awaiting choice survives restart and explicit source is independent of playback',
    () async {
      final folder = await Directory.systemTemp.createTemp(
        'mesting161-download-',
      );
      addTearDown(() => folder.delete(recursive: true));
      final manager = AudioDownloadManager(
        client: MockClient((_) async => http.Response('', 500)),
        currentOwner: () => 'netease:7',
        directory: () async => folder,
        persist: (_) async {},
        publish: (f, t, e, m) async => 'file:///never',
        resolveTaskMedia: (task, abort) async =>
            throw const DownloadSourceSelectionRequired(),
      );
      addTearDown(manager.dispose);
      manager.enqueue(original, quality: PlatformAudioQuality.high);
      await until(
        () => manager.tasks.single.phase == AudioDownloadPhase.awaitingSource,
      );
      final id = manager.tasks.single.id;
      final restored = await decodeAudioDownloadSnapshot(
        await encodeAudioDownloadSnapshot(manager.tasks),
      );
      expect(restored.single.phase, AudioDownloadPhase.awaitingSource);
      expect(restored.single.downloadSource, isNull);
      manager.selectDownloadSource(id, NeteaseTrackSource.lxHuanyin);
      await until(
        () => manager.tasks.single.phase == AudioDownloadPhase.awaitingSource,
      );
      expect(manager.tasks.single.downloadSource, NeteaseTrackSource.lxHuanyin);
      final again = await decodeAudioDownloadSnapshot(
        await encodeAudioDownloadSnapshot(manager.tasks),
      );
      expect(again.single.downloadSource, NeteaseTrackSource.lxHuanyin);
      manager.cancelPending();
      expect(manager.tasks.single.phase, AudioDownloadPhase.cancelled);
      manager.selectDownloadSource(id, NeteaseTrackSource.lxFish);
      expect(manager.tasks.single.phase, AudioDownloadPhase.cancelled);
    },
  );
}
