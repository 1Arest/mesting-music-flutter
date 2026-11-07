import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/core/platform/distribution_channel.dart';
import 'package:mesting_music/features/music_platform/data/platform_artwork.dart';
import 'package:mesting_music/features/music_platform/data/embedded_music_server.dart';
import 'package:mesting_music/features/music_platform/data/embedded_kugou_music_source.dart';
import 'package:mesting_music/features/music_platform/data/music_platform_api.dart';
import 'package:mesting_music/features/music_platform/domain/platform_audio_quality.dart';
import 'package:mesting_music/features/music_platform/platform_quality_providers.dart';
import 'package:mesting_music/features/themes/theme_controller.dart';
import 'package:mesting_music/shared/models/track.dart';

class _Server implements MusicServer {
  @override
  Future<Uri> start() async => Uri.parse('http://127.0.0.1:12345');
}

http.Response response(Object data) => http.Response(
  jsonEncode({'status': 1, 'data': data}),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
Track song([String hash = 'hash']) => EmbeddedKugouMusicSource.platformTrack({
  'hash': hash,
  'songname': '封面与音质验收歌曲',
})!;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'cover parser skips bare names, expands templates and handles nested aliases',
    () {
      for (final field in [
        'Image',
        'ImgUrl',
        'imgurl',
        'pic',
        'image',
        'image_320',
        'cover_pic',
        'union_cover',
        'album_sizable_cover',
      ]) {
        expect(
          PlatformArtwork.fromPayload({
            'img': 'filename.jpg',
            field: 'http://webimg.bssdl.kugou.com/{size}/cover.jpg',
          }),
          'http://webimg.bssdl.kugou.com/400/cover.jpg',
          reason: field,
        );
      }
      expect(
        PlatformArtwork.fromPayload({
          'img': 'bare.jpg',
          'albuminfo': {'sizable_cover': '//img.kugou.com/{size}/album.jpg'},
        }),
        'https://img.kugou.com/400/album.jpg',
      );
      expect(
        PlatformArtwork.fromPayload({
          'trans_param': {'union_cover': 'https://img.kugou.com/x.jpg'},
        }),
        'https://img.kugou.com/x.jpg',
      );
      expect(PlatformArtwork.normalize('javascript:alert(1)'), '');
    },
  );

  test(
    'song conversion preserves top-level empty keys without hiding nested cover',
    () {
      final track = EmbeddedKugouMusicSource.platformTrack({
        'hash': 'h',
        'img': '',
        'sizable_cover': '',
        'album_info': {'cover': 'https://img.kugou.com/nested.jpg'},
      })!;
      expect(track.coverAsset, 'https://img.kugou.com/nested.jpg');
    },
  );

  test(
    'metadata repair coalesces requests and does not permanently cache failures',
    () async {
      var calls = 0;
      final ready = Completer<void>();
      final api = MusicPlatformApi(
        server: _Server(),
        client: MockClient((request) async {
          expect(request.url.path, '/audio');
          expect(request.url.queryParameters['hash'], 'hash');
          calls++;
          if (calls == 1) {
            await ready.future;
            return response({});
          }
          return response({
            'album_info': {
              'sizable_cover': 'https://img.kugou.com/repaired.jpg',
            },
          });
        }),
      );
      final repo = PlatformArtworkRepository(api);
      final first = repo.resolve(song());
      final second = repo.resolve(song());
      ready.complete();
      expect(await first, '');
      expect(await second, '');
      expect(calls, 1);
      expect(await repo.resolve(song()), 'https://img.kugou.com/repaired.jpg');
      expect(await repo.resolve(song()), 'https://img.kugou.com/repaired.jpg');
      expect(calls, 2);
    },
  );

  test(
    'Hi-Res request downgrades through permitted tiers and reports actual tier',
    () async {
      final qualities = <String>[];
      final client = MockClient((request) async {
        final quality = request.url.queryParameters['quality']!;
        qualities.add(quality);
        if (quality == '320') {
          return response({
            'url': 'https://media.kugou.com/320.mp3',
            'quality': '320',
            'album_info': {'sizable_cover': 'https://img.kugou.com/cover.jpg'},
          });
        }
        return response({
          'fail_process': ['buy'],
        });
      });
      final source = EmbeddedKugouMusicSource(
        client,
        MusicPlatformApi(server: _Server(), client: client),
      );
      final track = await source.resolveTrack(
        song(),
        quality: PlatformAudioQuality.hiRes,
      );
      expect(qualities, ['high', 'flac', '320']);
      expect(track.playbackQuality, '320');
      expect(track.coverAsset, 'https://img.kugou.com/cover.jpg');
      expect(Track.fromJson(track.toJson()).playbackQuality, '320');
      expect(track.toMediaItem().extras!['playbackQuality'], '320');
    },
  );

  test(
    'server downgrade and absent actual tier never masquerade as requested Hi-Res',
    () async {
      for (final actual in ['128', '']) {
        final client = MockClient(
          (_) async => response({
            'url': 'https://media.kugou.com/stream',
            if (actual.isNotEmpty) 'quality': actual,
          }),
        );
        final track = await EmbeddedKugouMusicSource(
          client,
          MusicPlatformApi(server: _Server(), client: client),
        ).resolveTrack(song(), quality: PlatformAudioQuality.hiRes);
        expect(track.playbackQuality, actual);
      }
    },
  );

  test(
    'Beta appearance migration keeps explicit progress choices and removed settings default',
    () async {
      if (!DistributionChannel.isBeta) return;
      SharedPreferences.setMockInitialValues({
        musicThemePreferenceKey: 'kasukabe-sky',
        'music_progress_style': 'kuromi',
        'music_progress_character': 'helloKitty',
        'music_ip_decoration': true,
        'music_background_strength': .92,
        'theme_performance_mode': 'reduced',
        PlatformQualityController.preferenceKey: 'flac',
      });
      final prefs = await SharedPreferences.getInstance();
      await migrateBeta6Appearance(prefs);
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);
      expect(container.read(musicThemeProvider).id, 'classic');
      final visual = container.read(themeVisualSettingsProvider);
      expect(visual.progressStyle, ProgressDecoration.kuromi);
      expect(visual.progressCharacter, ProgressDecoration.helloKitty);
      expect(visual.showIpDecoration, true);
      expect(visual.backgroundStrength, .58);
      expect(
        container.read(themePerformanceProvider),
        ThemePerformanceMode.automatic,
      );
      expect(
        container.read(platformQualityProvider).preferred,
        PlatformAudioQuality.lossless,
      );
      await migrateBeta6Appearance(prefs);
      expect(prefs.getString('music_progress_character'), 'helloKitty');
    },
  );

  test(
    'retired-theme follow choices keep their former appearance on upgrade',
    () async {
      if (!DistributionChannel.isBeta) return;
      SharedPreferences.setMockInitialValues({
        musicThemePreferenceKey: 'kasukabe-sky',
        'music_progress_style': 'followTheme',
        'music_progress_character': 'followTheme',
      });
      final prefs = await SharedPreferences.getInstance();
      await migrateBeta6Appearance(prefs);
      expect(prefs.getString('music_progress_style'), 'shinchan');
      expect(prefs.getString('music_progress_character'), 'shinchan');
    },
  );
}
