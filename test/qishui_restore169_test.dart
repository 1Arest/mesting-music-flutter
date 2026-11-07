import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mesting_music/core/audio/playback_providers.dart';
import 'package:mesting_music/features/experience/presentation/floating_playback_pill.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/core/audio/mesting_audio_handler.dart';
import 'package:mesting_music/core/audio/playback_mode.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_api.dart';
import 'package:mesting_music/shared/models/track.dart';

import 'support/deterministic_audio_player.dart';

Track _song(String id, {TrackSource source = TrackSource.qishui}) => Track(
  id: '${source.name}_$id',
  platformSongId: id,
  title: id,
  artist: 'fixture',
  album: '',
  duration: const Duration(minutes: 3),
  source: source,
  audioAsset: 'mesting-platform://${source.name}/$id',
  coverAsset: '',
  lyricsAsset: '',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(LiquidGlassWidgets.initialize);
  setUp(() async {
    final directory = await Directory.systemTemp.createTemp(
      'mesting_restore169_',
    );
    const path = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(path, (_) async => directory.path);
    addTearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(path, null);
      await directory.delete(recursive: true);
    });
  });

  test(
    'cold Qishui restore publishes paused metadata and position without resolving media',
    () async {
      final player = DeterministicAudioPlayer();
      final handler = MestingAudioHandler(tracks: [], player: player);
      addTearDown(handler.debugDispose);
      var resolutions = 0;
      handler.configureTrackPlaybackResolver((track) async {
        resolutions++;
        return track;
      });
      await handler.restoreSession(
        tracks: [_song('a'), _song('b'), _song('c')],
        currentIndex: 1,
        position: const Duration(seconds: 77),
        mode: PlaybackMode.list,
      );
      expect(resolutions, 0);
      expect(player.sources, isEmpty);
      expect(player.active, isFalse);
      expect(handler.mediaItem.value?.id, 'qishui_b');
      expect(handler.persistedQueue.map((track) => track.id), [
        'qishui_b',
        'qishui_c',
        'qishui_a',
      ]);
      expect(handler.currentPosition, const Duration(seconds: 77));
      expect(await handler.positionStream.first, const Duration(seconds: 77));
      expect(
        handler.playbackState.value.processingState,
        AudioProcessingState.idle,
      );
      expect(handler.playbackState.value.playing, isFalse);
    },
  );
  test(
    'missing settings fails one explicit Play and stops loading, later Play retains position',
    () async {
      final player = DeterministicAudioPlayer();
      final handler = MestingAudioHandler(tracks: [], player: player);
      addTearDown(handler.debugDispose);
      var configured = false, resolutions = 0;
      handler.configureTrackPlaybackResolver((track) async {
        resolutions++;
        if (!configured) {
          throw const QishuiException('请先配置访问令牌', code: 'signer');
        }
        return track.copyWith(audioAsset: 'assets/fixture169.mp3');
      });
      await handler.restoreSession(
        tracks: [_song('a'), _song('b')],
        currentIndex: 0,
        position: const Duration(seconds: 41),
        mode: PlaybackMode.list,
      );
      expect(resolutions, 0);
      await expectLater(handler.play(), throwsA(isA<QishuiException>()));
      expect(resolutions, 1);
      expect(
        handler.playbackState.value.processingState,
        AudioProcessingState.error,
      );
      expect(handler.playbackState.value.playing, isFalse);
      expect(handler.currentPosition, const Duration(seconds: 41));
      configured = true;
      await handler.play();
      expect(resolutions, 2);
      expect(player.active, isTrue);
      expect(player.at, const Duration(seconds: 41));
      expect(handler.upcomingQueue.map((item) => item.id), ['qishui_b']);
    },
  );
  test(
    'a lyric seek on restored metadata changes the resume point without a request',
    () async {
      final player = DeterministicAudioPlayer();
      final handler = MestingAudioHandler(tracks: [], player: player);
      addTearDown(handler.debugDispose);
      var resolutions = 0;
      handler.configureTrackPlaybackResolver((track) async {
        resolutions++;
        return track.copyWith(audioAsset: 'assets/fixture169.mp3');
      });
      await handler.restoreSession(
        tracks: [_song('a')],
        currentIndex: 0,
        position: const Duration(seconds: 21),
        mode: PlaybackMode.single,
      );
      await handler.seek(const Duration(seconds: 58));
      expect(resolutions, 0);
      expect(player.sources, isEmpty);
      expect(handler.currentPosition, const Duration(seconds: 58));
      await handler.play();
      expect(resolutions, 1);
      expect(player.at, const Duration(seconds: 58));
    },
  );
  test(
    'NetEase restore retains its established source-loading behavior',
    () async {
      final player = DeterministicAudioPlayer();
      final handler = MestingAudioHandler(tracks: [], player: player);
      addTearDown(handler.debugDispose);
      var resolutions = 0;
      handler.configureTrackPlaybackResolver((track) async {
        resolutions++;
        return track.copyWith(audioAsset: 'assets/fixture169.mp3');
      });
      await handler.restoreSession(
        tracks: [_song('n', source: TrackSource.netease)],
        currentIndex: 0,
        position: const Duration(seconds: 12),
        mode: PlaybackMode.list,
      );
      expect(resolutions, 1);
      expect(player.sources, hasLength(1));
      expect(player.active, isFalse);
      expect(player.at, const Duration(seconds: 12));
    },
  );
  testWidgets(
    'cold-restored real handler presents a Play control instead of a spinning pill',
    (tester) async {
      // The real handler initializes filesystem caches. Keep that I/O outside
      // the widget test's simulated clock, while retaining real pill providers.
      late MestingAudioHandler handler;
      await tester.runAsync(() async {
        handler = MestingAudioHandler(
          tracks: [],
          player: DeterministicAudioPlayer(),
        );
        await handler.restoreSession(
          tracks: [_song('a')],
          currentIndex: 0,
          position: const Duration(seconds: 32),
          mode: PlaybackMode.list,
        );
      });
      addTearDown(() => tester.runAsync(handler.debugDispose));
      var requests = 0;
      handler.configureTrackPlaybackResolver((track) async {
        requests++;
        return track;
      });
      final container = ProviderContainer(
        overrides: [
          audioHandlerProvider.overrideWithValue(handler),
          qishuiNavigationProvider.overrideWithValue(true),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: LiquidGlassWidgets.wrap(
            adaptiveQuality: false,
            child: const MaterialApp(
              home: Scaffold(
                body: Center(
                  child: SizedBox(width: 340, child: FloatingPlaybackPill()),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byIcon(CupertinoIcons.play_fill), findsOneWidget);
      expect(
        handler.playbackState.value.processingState,
        AudioProcessingState.idle,
      );
      expect(requests, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
}
