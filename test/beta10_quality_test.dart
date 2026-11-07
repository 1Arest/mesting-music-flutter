import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesting_music/core/audio/mesting_audio_handler.dart';
import 'package:mesting_music/core/audio/playback_providers.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/features/music_platform/data/embedded_music_server.dart';
import 'package:mesting_music/features/music_platform/data/music_platform_api.dart';
import 'package:mesting_music/features/music_platform/data/platform_playback_resolver.dart';
import 'package:mesting_music/features/music_platform/domain/platform_audio_quality.dart';
import 'package:mesting_music/shared/models/track.dart';
import 'support/deterministic_audio_player.dart';

class _Server implements MusicServer {
  @override
  Future<Uri> start() async => Uri.parse('http://127.0.0.1:12345');
}

const _track = Track(
  id: 'same-recording',
  title: '同一首歌',
  artist: '歌手',
  album: '',
  duration: Duration(minutes: 3),
  audioAsset: 'assets/high.mp3',
  coverAsset: '',
  lyricsAsset: '',
  playbackQuality: '320',
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'same recording quality refresh notifies the UI despite MediaItem ID equality',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'mesting_beta10_quality_',
      );
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => dir.path);
      addTearDown(() async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
        if (dir.absolute.path.startsWith(Directory.systemTemp.absolute.path)) {
          await dir.delete(recursive: true);
        }
      });
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final engine = DeterministicAudioPlayer();
      final handler = MestingAudioHandler(tracks: [], player: engine);
      addTearDown(handler.debugDispose);
      await handler.replaceQueue([_track], autoplay: false);
      final c = ProviderContainer(
        overrides: [
          audioHandlerProvider.overrideWithValue(handler),
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );
      addTearDown(c.dispose);
      final observed = <String>[];
      c.listen(
        currentTrackProvider,
        (_, next) => observed.add(next.playbackQuality),
        fireImmediately: true,
      );
      for (var i = 0; i < 8; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(c.read(currentTrackProvider).playbackQuality, '320');
      handler.configureTrackPlaybackResolver(
        (track) async => track.copyWith(
          audioAsset: 'assets/standard.mp3',
          playbackQuality: '128',
        ),
      );
      expect(await handler.refreshCurrentSource(), true);
      for (var i = 0; i < 8; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(c.read(currentTrackProvider).playbackQuality, '128');
      expect(observed, containsAllInOrder(['320', '128']));
      expect(
        (engine.sources.single as dynamic).tag.extras['playbackQuality'],
        '128',
      );
    },
  );
  test(
    'strict quality rejects adapter-stamped standard when bitrate is actually high',
    () async {
      final api = MusicPlatformApi(
        server: _Server(),
        client: MockClient(
          (request) async => http.Response(
            jsonEncode({
              'status': 1,
              'data': request.url.path == '/audio'
                  ? {'hash_128': 'standard-hash', 'hash_320': 'high-hash'}
                  : {
                      'url': 'https://example.test/high.mp3',
                      'quality': '128',
                      'bitRate': '320000',
                      'priv_status': 1,
                    },
            }),
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );
      const track = Track(
        id: 'kugou_base',
        title: '',
        artist: '',
        album: '',
        duration: Duration(minutes: 3),
        audioAsset: '',
        coverAsset: '',
        lyricsAsset: '',
        source: TrackSource.kugou,
      );
      await expectLater(
        PlatformPlaybackResolver(api).resolve(
          track,
          quality: PlatformAudioQuality.standard,
          requireRequestedQuality: true,
        ),
        throwsA(isA<MusicPlatformException>()),
      );
    },
  );
  test('lossy bitrate accepts numeric and string units consistently', () {
    expect(
      PlatformPlaybackResolver.deliveredQuality({
        'quality': '128',
        'bit_rate': 320,
      }),
      PlatformAudioQuality.high,
    );
    expect(
      PlatformPlaybackResolver.deliveredQuality({
        'quality': '320',
        'bitRate': '128000',
      }),
      PlatformAudioQuality.standard,
    );
  });
}
