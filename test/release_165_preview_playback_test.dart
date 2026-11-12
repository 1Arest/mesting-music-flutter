import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesting_music/features/music_platform/domain/platform_audio_quality.dart';
import 'package:mesting_music/features/music_platform/netease/netease_api.dart';
import 'package:mesting_music/features/music_platform/netease/netease_fallback.dart';
import 'package:mesting_music/features/music_platform/netease/netease_music_repository.dart';
import 'package:mesting_music/features/music_platform/netease/netease_preview.dart';
import 'package:mesting_music/features/music_platform/netease/netease_session.dart';
import 'package:mesting_music/shared/models/track.dart';
import 'netease_v112_fallback_download_test.dart' show recording;
import 'netease_v116_recovery_test.dart' show mp3Response;

/// The user-supplied original recording's public catalogue identity/duration.
/// HTTP and media below are deterministic fixtures, not account acceptance.
final example = recording(
  id: 'netease_2163637432',
  title: '可我只是海',
  artist: 'LBI 利比',
  album: '可我只是海',
).copyWith(duration: const Duration(milliseconds: 175474));

class Full165Source implements NeteaseExactIdSource {
  int calls = 0;
  @override
  String get label => '测试完整音源';
  @override
  Future<List<Track>> search(Track original) async => [original];
  @override
  Future<Track?> resolve(Track candidate) async {
    calls++;
    return candidate.copyWith(
      audioAsset: 'https://full.example/audio.mp3',
      isPreview: false,
      playbackQuality: '128',
    );
  }
}

NeteaseMusicRepository fixtureMusic(
  Map<String, Object?> row, {
  int? catalogMs,
}) => NeteaseMusicRepository(
  NeteaseApi(
    MockClient(
      (request) async => http.Response(
        jsonEncode(
          request.url.path.contains('detail')
              ? {
                  'code': 200,
                  'songs': [
                    {'id': 2163637432, 'dt': catalogMs ?? 175474},
                  ],
                }
              : {
                  'code': 200,
                  'data': [
                    {
                      'id': 2163637432,
                      'url': 'https://official.example/audio.mp3',
                      'level': 'standard',
                      'br': 128000,
                      ...row,
                    },
                  ],
                },
        ),
        200,
        headers: {'content-type': 'application/json'},
      ),
    ),
  )..configure(
    const NeteaseSession(
      userId: 'fixture',
      deviceId: 'fixture',
      cookies: {'MUSIC_U': 'fixture-private'},
    ),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('numeric milliseconds and previews longer than 90s are not lost', () {
    for (final value in [30000, 30000.0, '30000.0']) {
      expect(neteaseResponseIsPreview({'time': value}, example.duration), true);
    }
    expect(neteaseResponseIsPreview({'time': 120000}, example.duration), true);
    expect(neteaseMilliseconds(double.nan), 0);
    expect(
      neteaseResponseIsPreview({
        'time': 175474,
        'freeTrialPrivilege': {'resConsumable': true},
      }, example.duration),
      false,
    );
  });

  for (final marker in ['absent', 'decimal', 'trial']) {
    test(
      'automatic playback replaces $marker official preview with full recording',
      () async {
        var officialReads = 0;
        final source = Full165Source();
        final client = MockClient((request) async {
          expect(request.headers['cookie'], isNull);
          expect(request.headers['authorization'], isNull);
          expect(request.headers['Range'], isNotNull);
          if (request.url.host == 'official.example') {
            officialReads++;
            return mp3Response(30);
          }
          return mp3Response(175);
        });
        final result = await resolveNeteaseTrack(
          music: fixtureMusic(switch (marker) {
            'decimal' => {'time': 30000.0},
            'trial' => {
              'time': 175474,
              'freeTrialInfo': {'start': 0, 'end': 30},
            },
            _ => {'time': 175474, 'freeTrialInfo': null},
          }),
          fallback: NeteaseFallbackResolver([source], client),
          allowFallback: true,
          current: () => true,
          track: example,
          quality: PlatformAudioQuality.standard,
        );
        expect(result.id, example.id);
        expect(result.platformSongId, '2163637432');
        expect(result.duration, example.duration);
        expect(result.isPreview, false);
        expect(result.audioOrigin!.adapter, source.label);
        expect(source.calls, 1);
        expect(officialReads, marker == 'absent' ? 1 : 0);
      },
    );
  }

  test(
    'a stale 30s queue row is enriched before matching alternate recordings',
    () async {
      final source = Full165Source();
      final result = await resolveNeteaseTrack(
        music: fixtureMusic({'time': 30000.0}),
        fallback: NeteaseFallbackResolver([
          source,
        ], MockClient((_) async => mp3Response(175))),
        allowFallback: true,
        current: () => true,
        track: example.copyWith(duration: const Duration(seconds: 30)),
        quality: PlatformAudioQuality.standard,
      );
      expect(result.duration, example.duration);
      expect(result.isPreview, false);
      expect(source.calls, 1);
    },
  );

  for (final seconds in [80, 175]) {
    test('a genuine full $seconds second recording stays official', () async {
      final source = Full165Source();
      final result = await resolveNeteaseTrack(
        music: fixtureMusic({
          'time': seconds * 1000,
          'freeTrialPrivilege': {'resConsumable': true},
        }, catalogMs: seconds * 1000),
        fallback: NeteaseFallbackResolver([
          source,
        ], MockClient((_) async => mp3Response(seconds))),
        allowFallback: true,
        current: () => true,
        track: example.copyWith(duration: Duration(seconds: seconds)),
        quality: PlatformAudioQuality.standard,
      );
      expect(result.audioOrigin!.adapter, AudioOrigin.netease);
      expect(result.isPreview, false);
      expect(source.calls, 0);
    });
  }

  test('disabled fallback keeps a visibly marked preview', () async {
    final source = Full165Source();
    final result = await resolveNeteaseTrack(
      music: fixtureMusic({'time': 175474}),
      fallback: NeteaseFallbackResolver([
        source,
      ], MockClient((_) async => mp3Response(30))),
      allowFallback: false,
      current: () => true,
      track: example,
      quality: PlatformAudioQuality.standard,
    );
    expect(result.isPreview, true);
    expect(result.availabilityMessage, contains('备用音源已关闭'));
    expect(source.calls, 0);
  });

  test(
    'account change while official prefix is pending cancels rescue',
    () async {
      var current = true;
      final source = Full165Source();
      final gate = Completer<void>(), started = Completer<void>();
      final future = resolveNeteaseTrack(
        music: fixtureMusic({'time': 175474}),
        fallback: NeteaseFallbackResolver(
          [source],
          MockClient((_) async {
            started.complete();
            await gate.future;
            return mp3Response(30);
          }),
        ),
        allowFallback: true,
        current: () => current,
        track: example,
        quality: PlatformAudioQuality.standard,
      );
      await started.future;
      current = false;
      gate.complete();
      await expectLater(future, throwsException);
      expect(source.calls, 0);
    },
  );
}
