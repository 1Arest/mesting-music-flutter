import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:mesting_music/features/music_platform/netease/netease_api.dart';
import 'package:mesting_music/features/music_platform/netease/netease_session.dart';
import 'package:mesting_music/features/music_platform/netease/netease_music_repository.dart';
import 'package:mesting_music/features/music_platform/domain/platform_audio_quality.dart';
import 'package:mesting_music/features/music_platform/data/music_platform_api.dart';
import 'package:mesting_music/shared/models/track.dart';

NeteaseApi _api() =>
    NeteaseApi(
      MockClient((_) async => throw StateError('Host test network forbidden')),
    )..configure(
      const NeteaseSession(
        userId: '7',
        cookies: {'MUSIC_U': 'fixture'},
        deviceId: 'fixture',
      ),
    );

class _Music extends NeteaseMusicRepository {
  _Music(this.reply) : super(_api());
  final Map<String, dynamic> Function(String level) reply;
  final requested = <String>[];
  @override
  Future<Map<String, dynamic>> call(
    String route, [
    Map<String, Object?> query = const {},
    Future<void>? abort,
  ]) async {
    requested.add('${query['level']}');
    return reply('${query['level']}');
  }
}

const _track = Track(
  id: 'netease_1',
  platformSongId: '1',
  title: '合成测试歌曲',
  artist: '',
  album: '',
  duration: Duration(minutes: 4),
  audioAsset: '',
  coverAsset: '',
  lyricsAsset: '',
  source: TrackSource.netease,
);
void main() {
  test(
    'automatic highest quality falls back and records delivered tier',
    () async {
      final music = _Music(
        (level) => {
          'data': [
            level == 'vivid'
                ? {'url': null}
                : {
                    'url': 'https://example.test/audio',
                    'level': 'hires',
                    'br': 1200000,
                  },
          ],
        },
      );
      final track = await music.resolve(_track, PlatformAudioQuality.vivid);
      expect(music.requested, ['vivid', 'dolby']);
      expect(track.playbackQuality, PlatformAudioQuality.hiRes.code);
    },
  );
  test(
    'manual current-song switch does not pretend downgrade succeeded',
    () async {
      final music = _Music(
        (_) => {
          'data': [
            {'url': 'https://example.test/audio', 'level': 'standard'},
          ],
        },
      );
      await expectLater(
        music.resolve(_track, PlatformAudioQuality.hiRes, requireQuality: true),
        throwsA(isA<MusicPlatformException>()),
      );
      expect(music.requested, ['hires']);
    },
  );
  test('login failures stop fallback immediately', () async {
    final music = _Music(
      (_) => throw const MusicPlatformException('请登录', code: '301'),
    );
    await expectLater(
      music.resolve(_track, PlatformAudioQuality.vivid),
      throwsA(isA<MusicPlatformException>()),
    );
    expect(music.requested, ['vivid']);
  });
  test(
    'full permitted lower tier takes precedence over a higher-tier preview',
    () async {
      final music = _Music(
        (level) => {
          'data': [
            level == 'vivid'
                ? {
                    'url': 'https://example.test/preview',
                    'level': level,
                    'freeTrialInfo': {'start': 0, 'end': 30000},
                    'time': 30000,
                  }
                : {
                    'url': 'https://example.test/full',
                    'level': 'hires',
                    'time': 240000,
                  },
          ],
        },
      );
      final track = await music.resolve(_track, PlatformAudioQuality.vivid);
      expect(track.isPreview, false);
      expect(track.audioAsset, endsWith('/full'));
    },
  );
}
