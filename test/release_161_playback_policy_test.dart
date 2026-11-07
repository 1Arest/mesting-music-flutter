import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesting_music/features/music_platform/domain/platform_audio_quality.dart';
import 'package:mesting_music/features/music_platform/netease/netease_api.dart';
import 'package:mesting_music/features/music_platform/netease/netease_music_repository.dart';
import 'package:mesting_music/features/music_platform/netease/netease_fallback.dart';
import 'package:mesting_music/features/music_platform/netease/netease_track_sources.dart';
import 'package:mesting_music/shared/models/track.dart';
import 'netease_v112_fallback_download_test.dart' show recording;
import 'netease_v116_recovery_test.dart' show mp3Response;

class _Music extends NeteaseMusicRepository {
  _Music(this.result)
    : super(NeteaseApi(MockClient((_) async => http.Response('', 500))));
  final Track? result;
  int calls = 0;
  @override
  Future<Track> resolve(
    Track track,
    PlatformAudioQuality quality, {
    bool requireQuality = false,
    Future<void>? abortTrigger,
  }) async {
    calls++;
    if (result == null) throw const FormatException('official unavailable');
    return result!;
  }
}

class _Source implements NeteaseExactIdSource {
  _Source(this.label, {this.available = true});
  @override
  final String label;
  final bool available;
  int calls = 0;
  @override
  Future<List<Track>> search(Track original) async => [original];
  @override
  Future<Track?> resolve(Track track) async {
    calls++;
    return available
        ? track.copyWith(
            audioAsset: 'https://cdn.example/full.mp3',
            playbackQuality: '128',
          )
        : null;
  }
}

void main() {
  final song = recording();
  for (final officialFull in [true, false]) {
    test(
      'manual source failure resumes automatic order, officialFull=$officialFull',
      () async {
        final selected = _Source('LX · fish', available: false),
            other = _Source('LX · huibq');
        final music = _Music(
          officialFull
              ? song.copyWith(
                  audioAsset: 'https://official.example/full',
                  audioOrigin: const AudioOrigin(
                    AudioOrigin.netease,
                    'netease_7',
                  ),
                )
              : null,
        );
        final fallback = NeteaseFallbackResolver([
          selected,
          other,
        ], MockClient((_) async => mp3Response(274)));
        final result = await resolveNeteaseTrack(
          music: music,
          fallback: fallback,
          allowFallback: true,
          current: () => true,
          track: song,
          quality: PlatformAudioQuality.standard,
          selectedSource: NeteaseTrackSource.lxFish,
        );
        expect(selected.calls, 1);
        expect(music.calls, 1);
        expect(other.calls, officialFull ? 0 : 1);
        expect(
          result.audioOrigin!.adapter,
          officialFull ? AudioOrigin.netease : 'LX · huibq',
        );
      },
    );
  }
  test(
    'availability detection cannot advertise automatic rescue as selected-source availability',
    () async {
      final selected = _Source('LX · fish', available: false),
          other = _Source('LX · huibq');
      final music = _Music(
        song.copyWith(audioAsset: 'https://official.example/full'),
      );
      await expectLater(
        resolveNeteaseTrack(
          music: music,
          fallback: NeteaseFallbackResolver([
            selected,
            other,
          ], MockClient((_) async => mp3Response(274))),
          allowFallback: true,
          current: () => true,
          track: song,
          quality: PlatformAudioQuality.standard,
          selectedSource: NeteaseTrackSource.lxFish,
          fallbackOnSelectedFailure: false,
        ),
        throwsException,
      );
      expect(music.calls, 0);
      expect(other.calls, 0);
    },
  );
  test('successful manual source stays ahead of automatic sources', () async {
    final selected = _Source('LX · fish'), other = _Source('LX · huibq');
    final music = _Music(null);
    final result = await resolveNeteaseTrack(
      music: music,
      fallback: NeteaseFallbackResolver([
        selected,
        other,
      ], MockClient((_) async => mp3Response(274))),
      allowFallback: true,
      current: () => true,
      track: song,
      quality: PlatformAudioQuality.standard,
      selectedSource: NeteaseTrackSource.lxFish,
    );
    expect(result.audioOrigin!.adapter, 'LX · fish');
    expect(music.calls, 0);
    expect(other.calls, 0);
  });
}
