import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesting_music/core/audio/mesting_audio_handler.dart';
import 'package:mesting_music/core/audio/playback_providers.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/features/music_platform/platform_quality_providers.dart';
import 'package:mesting_music/features/music_platform/data/embedded_music_server.dart';
import 'package:mesting_music/features/music_platform/data/music_platform_api.dart';
import 'package:mesting_music/features/music_platform/data/platform_playback_resolver.dart';
import 'package:mesting_music/features/music_platform/data/platform_quality_catalog.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/music_platform/domain/platform_audio_quality.dart';
import 'package:mesting_music/shared/models/track.dart';
import 'support/deterministic_audio_player.dart';

Track song(String id, {String quality = ''}) => Track(
  id: 'kugou_$id',
  title: id,
  artist: '测试歌手',
  album: '',
  duration: const Duration(minutes: 4),
  audioAsset: 'assets/$id.mp3',
  coverAsset: '',
  lyricsAsset: '',
  source: TrackSource.kugou,
  playbackQuality: quality,
);

class _Server implements MusicServer {
  @override
  Future<Uri> start() async => Uri.parse('http://127.0.0.1:12345');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    final dir = await Directory.systemTemp.createTemp('mesting_beta9_engine_');
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
  });
  Future<(DeterministicAudioPlayer, MestingAudioHandler)> prepare() async {
    final player = DeterministicAudioPlayer();
    final handler = MestingAudioHandler(tracks: [], player: player);
    await handler.replaceQueue([song('A')], autoplay: false);
    addTearDown(handler.debugDispose);
    return (player, handler);
  }

  Future<void> flush() async {
    for (var i = 0; i < 15; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test(
    'empty explicit single selection continues into recommendations on the first Next',
    () async {
      final (_, handler) = await prepare();
      final batch = Completer<List<Track>>();
      handler.configureRadioTrackLoader(
        (_) => batch.future,
        preserveServerOrder: true,
        continueAfterExplicitQueue: true,
      );
      await handler.playSingleTrack(
        song('A'),
        playbackContext: [song('A')],
        replaceUpcoming: true,
      );
      expect(handler.manuallyQueuedItems, isEmpty);
      final next = handler.skipToNext();
      await flush();
      batch.complete([song('B'), song('C')]);
      await next;
      await flush();
      expect(handler.mediaItem.value!.id, 'kugou_B');
      expect(handler.upcomingQueue.map((item) => item.id), contains('kugou_C'));
      expect(handler.manuallyQueuedItems, isEmpty);
    },
  );
  test(
    'history works while the native index stays zero; Previous then Next is reversible',
    () async {
      final (player, handler) = await prepare();
      handler.configureRadioTrackLoader(
        (_) async => [],
        preserveServerOrder: true,
        continueAfterExplicitQueue: true,
      );
      await handler.playSingleTrack(
        song('A'),
        playbackContext: [song('A')],
        replaceUpcoming: true,
      );
      player.at = const Duration(seconds: 40);
      await handler.skipToPrevious();
      expect(player.at, Duration.zero);
      await handler.playSingleTrack(song('B'), playbackContext: [song('B')]);
      await handler.skipToPrevious();
      expect(handler.mediaItem.value!.id, 'kugou_A');
      await handler.skipToNext();
      expect(handler.mediaItem.value!.id, 'kugou_B');
      expect(player.currentIndex, 0);
    },
  );
  test(
    'single selection preserves or replaces only the deliberately queued tail',
    () async {
      final (_, handler) = await prepare();
      handler.configureRadioTrackLoader(
        (_) async => [],
        preserveServerOrder: true,
        continueAfterExplicitQueue: true,
      );
      await handler.replaceQueue([
        song('A'),
        song('B'),
        song('C'),
      ], autoplay: false);
      await handler.playSingleTrack(
        song('D'),
        playbackContext: [song('D')],
        discardRecommendations: true,
      );
      expect(handler.manuallyQueuedItems.map((item) => item.id), [
        'kugou_B',
        'kugou_C',
      ]);
      await handler.playSingleTrack(
        song('E'),
        playbackContext: [song('E')],
        replaceUpcoming: true,
        discardRecommendations: true,
      );
      expect(handler.manuallyQueuedItems, isEmpty);
      expect(handler.mediaItem.value!.id, 'kugou_E');
    },
  );
  test(
    'recommendation failure reaches the Next caller and leaves the current source playing',
    () async {
      final (_, handler) = await prepare();
      handler.configureRadioTrackLoader(
        (_) async => [],
        preserveServerOrder: true,
        continueAfterExplicitQueue: true,
      );
      await handler.playSingleTrack(
        song('A'),
        playbackContext: [song('A')],
        replaceUpcoming: true,
      );
      await flush();
      await expectLater(
        handler.skipToNext(),
        throwsA(isA<PlaybackContinuationException>()),
      );
      expect(handler.mediaItem.value!.id, 'kugou_A');
    },
  );

  test(
    'Next taps while a source is resolving serialize into two real transitions',
    () async {
      final (_, handler) = await prepare();
      handler.configureRadioTrackLoader(
        (_) async => [],
        preserveServerOrder: true,
        continueAfterExplicitQueue: true,
      );
      await handler.replaceQueue([
        song('A'),
        song('B'),
        song('C'),
      ], autoplay: false);
      final resolving = Completer<Track>();
      handler.configureTrackPlaybackResolver(
        (track) =>
            track.id == 'kugou_B' ? resolving.future : Future.value(track),
      );
      final first = handler.skipToNext();
      await flush();
      final second = handler.skipToNext();
      await flush();
      resolving.complete(song('B'));
      await Future.wait([first, second]);
      expect(handler.mediaItem.value!.id, 'kugou_C');
    },
  );

  test(
    'a manually appended song takes priority over generated recommendations',
    () async {
      final (_, handler) = await prepare();
      handler.configureRadioTrackLoader(
        (_) async => [song('AUTO')],
        preserveServerOrder: true,
        continueAfterExplicitQueue: true,
      );
      await handler.playSingleTrack(
        song('A'),
        playbackContext: [song('A')],
        replaceUpcoming: true,
      );
      await flush();
      await handler.appendToUpcomingQueue(song('MANUAL'));
      await handler.skipToNext();
      expect(handler.mediaItem.value!.id, 'kugou_MANUAL');
      expect(handler.isAutomaticallyQueued('kugou_AUTO'), true);
    },
  );

  for (final command in ['pause', 'stop', 'seek']) {
    test('delayed Next cannot override a later $command command', () async {
      final (player, handler) = await prepare();
      handler.configureRadioTrackLoader(
        (_) async => [],
        preserveServerOrder: true,
        continueAfterExplicitQueue: true,
      );
      await handler.replaceQueue([song('A'), song('B')], autoplay: false);
      final resolving = Completer<Track>();
      handler.configureTrackPlaybackResolver((track) => resolving.future);
      final loads = player.loads;
      final next = handler.skipToNext();
      await flush();
      switch (command) {
        case 'pause':
          await handler.pause();
        case 'stop':
          await handler.stop();
        case 'seek':
          await handler.seek(const Duration(seconds: 37));
      }
      resolving.complete(song('B'));
      await next;
      // The new selection is visible immediately; transport cancellation
      // prevents its delayed lookup from starting playback.
      expect(handler.mediaItem.value!.id, 'kugou_B');
      expect(player.active, false);
      expect(player.loads, loads);
      if (command == 'seek') expect(player.at, const Duration(seconds: 37));
    });
  }

  test(
    'cancelled Previous retains history for a later Previous then Next',
    () async {
      final (_, handler) = await prepare();
      handler.configureRadioTrackLoader(
        (_) async => [],
        continueAfterExplicitQueue: true,
      );
      await handler.playSingleTrack(song('A'), autoplay: false);
      await handler.playSingleTrack(song('B'), autoplay: false);
      final resolving = Completer<Track>();
      handler.configureTrackPlaybackResolver((track) => resolving.future);
      final previous = handler.skipToPrevious();
      await flush();
      await handler.pause();
      resolving.complete(song('A'));
      await previous;
      // Pause retains the selected identity while its source remains stopped.
      expect(handler.mediaItem.value!.id, 'kugou_A');
      handler.configureTrackPlaybackResolver(Future.value);
      await handler.skipToPrevious();
      expect(handler.mediaItem.value!.id, 'kugou_A');
      await handler.skipToNext();
      expect(handler.mediaItem.value!.id, 'kugou_B');
    },
  );

  test(
    'a second shared toggle cancels the pause fade and keeps playback',
    () async {
      final (player, handler) = await prepare();
      await handler.play();
      final pause = handler.togglePlayPause();
      await Future<void>.delayed(const Duration(milliseconds: 40));
      await handler.togglePlayPause();
      await pause;
      expect(player.active, true);
      await handler.stop();
    },
  );

  test(
    'lossless to high and standard uses tier hashes and verifies the applied engine source',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'mesting_beta9_quality_',
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
      final (player, handler) = await prepare();
      await handler.replaceQueue([
        song('A', quality: 'flac'),
        song('B'),
      ], autoplay: false);
      player.at = const Duration(seconds: 73);
      final requests = <Uri>[];
      final api =
          MusicPlatformApi(
              server: _Server(),
              client: MockClient((request) async {
                requests.add(request.url);
                final q = request.url.queryParameters['quality'];
                final data = request.url.path == '/audio'
                    ? {
                        'audio_info': [
                          {
                            'hash': 'base',
                            'hash_128': 'sd',
                            'hash_320': 'hq',
                            'hash_flac': 'sq',
                            'hash_high': '0000',
                          },
                        ],
                      }
                    : request.url.path == '/song/url/new'
                    ? {
                        'url': 'https://example.test/sq.flac',
                        'quality': 'flac',
                        'priv_status': 1,
                      }
                    : q == 'high'
                    ? {
                        'fail_process': ['buy'],
                        'priv_status': 0,
                      }
                    : {
                        'url':
                            'https://example.test/${q == '320' ? 'hq' : 'sd'}.mp3',
                        'quality': q,
                        'priv_status': 1,
                      };
                return http.Response(
                  jsonEncode({'status': 1, 'data': data}),
                  200,
                  headers: {'content-type': 'application/json'},
                );
              }),
            )
            ..session = const PlatformSession(
              userId: '7',
              token: 'test',
              vipToken: 'vip',
            );
      SharedPreferences.setMockInitialValues({
        PlatformQualityController.preferenceKey: 'flac',
      });
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          audioHandlerProvider.overrideWithValue(handler),
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );
      addTearDown(container.dispose);
      final resolver = PlatformPlaybackResolver(api);
      handler.configureTrackPlaybackResolver((track) {
        final state = container.read(platformQualityProvider);
        return resolver.resolve(
          track,
          quality: state.preferred,
          requireRequestedQuality: state.switching,
        );
      });
      for (final quality in [
        PlatformAudioQuality.high,
        PlatformAudioQuality.standard,
      ]) {
        expect(
          await container
              .read(platformQualityProvider.notifier)
              .select(quality),
          true,
        );
        final applied = handler.trackForId(handler.mediaItem.value!.id)!;
        expect(applied.playbackQuality, quality.code);
        expect(
          (player.sources.single as dynamic).tag.extras['playbackQuality'],
          quality.code,
        );
        expect(player.at, const Duration(seconds: 73));
        expect(player.active, false);
        expect(handler.upcomingQueue.single.id, 'kugou_B');
      }
      final old = handler.trackForId(handler.mediaItem.value!.id)!.audioAsset;
      await expectLater(
        container
            .read(platformQualityProvider.notifier)
            .select(PlatformAudioQuality.hiRes),
        throwsA(isA<MusicPlatformException>()),
      );
      expect(handler.trackForId(handler.mediaItem.value!.id)!.audioAsset, old);
      expect(
        container.read(platformQualityProvider).preferred,
        PlatformAudioQuality.standard,
      );
      expect(
        requests
            .where((uri) => uri.path == '/song/url')
            .map((uri) => uri.queryParameters['hash']),
        containsAll(['hq', 'sd']),
      );
      expect(
        PlatformQualityCatalog.parse({
          'data': {'hash': 'sd', 'hash_flac': 'sq'},
        }),
        {PlatformAudioQuality.standard, PlatformAudioQuality.lossless},
      );
    },
  );
}
