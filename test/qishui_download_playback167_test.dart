import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/features/downloads/audio_downloads.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_api.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_download_playback.dart';
import 'package:mesting_music/shared/models/track.dart';

const song = Track(
  id: 'qishui_offline167',
  platformSongId: 'offline167',
  title: 'Fixture',
  artist: 'Artist',
  album: '',
  duration: Duration(minutes: 3),
  audioAsset: 'mesting-platform://qishui/offline167',
  coverAsset: '',
  lyricsAsset: '',
  source: TrackSource.qishui,
);

void main() {
  for (final uri in [
    'content://media/external/audio/media/167',
    'file:///storage/emulated/0/Download/song.m4a',
  ]) {
    test('completed current owner download plays offline: $uri', () async {
      final local = song.copyWith(audioAsset: uri);
      final result = await resolveQishuiPlaybackSource(
        track: local,
        owner: 'owner167',
        downloads: [
          AudioDownloadTask(
            id: 'download167',
            owner: 'owner167',
            track: song,
            phase: AudioDownloadPhase.completed,
            uri: uri,
          ),
        ],
        official: () async => throw StateError(
          'Offline playback must not request a signer or official server',
        ),
      );
      expect(result.audioAsset, uri);
      expect(result.source, TrackSource.qishui);
      expect(result.audioHeaders, isEmpty);
    });
  }
  for (final mismatch in [
    'owner',
    'incomplete',
    'recording',
    'uri',
    'temporary',
  ]) {
    test('$mismatch cannot bypass the official account resolver', () async {
      final uri = mismatch == 'temporary'
          ? 'file:///private/cache/qishui_official_audio/${'a' * 32}.m4a'
          : 'content://media/external/audio/media/167';
      var requests = 0;
      final result = await resolveQishuiPlaybackSource(
        track: song.copyWith(audioAsset: uri),
        owner: 'owner167',
        downloads: [
          AudioDownloadTask(
            id: 'download167',
            owner: mismatch == 'owner' ? 'another-owner' : 'owner167',
            track: mismatch == 'recording'
                ? song.copyWith(platformSongId: 'another-recording')
                : song,
            phase: mismatch == 'incomplete'
                ? AudioDownloadPhase.saving
                : AudioDownloadPhase.completed,
            uri: mismatch == 'uri' ? '$uri-other' : uri,
          ),
        ],
        official: () async {
          requests++;
          return song.copyWith(
            audioAsset: 'https://official.example.test/fresh',
          );
        },
      );
      expect(requests, 1);
      expect(result.audioAsset, 'https://official.example.test/fresh');
    });
  }
  test(
    'hydrating download records does not trigger a misleading network request',
    () async {
      await expectLater(
        resolveQishuiPlaybackSource(
          track: song.copyWith(
            audioAsset: 'content://media/external/audio/media/167',
          ),
          owner: 'owner167',
          downloads: [],
          restoringDownloads: true,
          official: () async =>
              throw StateError('Should wait for the download directory'),
        ),
        throwsA(isA<QishuiException>()),
      );
    },
  );
}
