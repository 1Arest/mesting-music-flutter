import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:mesting_music/app/startup_video_surface.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/features/themes/startup_style.dart';
import 'package:mesting_music/core/platform/distribution_channel.dart';

class _Video extends VideoPlayerPlatform {
  final events = StreamController<VideoEvent>.broadcast();
  final bool stalls;
  _Video({this.stalls = false});
  int creates = 0, plays = 0, pauses = 0, seeks = 0, disposals = 0;
  double? volume;
  @override
  Future<void> init() async {}
  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async =>
      ++creates;
  @override
  Stream<VideoEvent> videoEventsFor(int playerId) {
    if (!stalls) {
      scheduleMicrotask(
        () => events.add(
          VideoEvent(
            eventType: VideoEventType.initialized,
            duration: const Duration(seconds: 3),
            size: const Size(608, 1280),
          ),
        ),
      );
    }
    return events.stream;
  }

  @override
  Widget buildViewWithOptions(VideoViewOptions options) =>
      const ColoredBox(color: Colors.red);
  @override
  Future<void> dispose(int playerId) async {
    disposals++;
  }

  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;
  @override
  Future<void> pause(int playerId) async {
    pauses++;
  }

  @override
  Future<void> play(int playerId) async {
    plays++;
  }

  @override
  Future<void> seekTo(int playerId, Duration position) async {
    seeks++;
  }

  @override
  Future<void> setLooping(int playerId, bool looping) async {
    expect(looping, false);
  }

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}
  @override
  Future<void> setVolume(int playerId, double volume) async {
    this.volume = volume;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'channel default persists independently and survives a new container',
    () async {
      SharedPreferences.setMockInitialValues({
        'music_app_brand_style': 'coral',
      });
      final prefs = await SharedPreferences.getInstance();
      expect(
        savedStartupStyle(prefs),
        DistributionChannel.isBeta
            ? StartupStyle.staticOne
            : StartupStyle.companionsOne,
      );
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      await container
          .read(startupStyleProvider.notifier)
          .select(StartupStyle.companionsTwo);
      container.dispose();
      expect(savedStartupStyle(prefs), StartupStyle.companionsTwo);
      expect(prefs.getString('music_app_brand_style'), 'coral');
      final second = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      await second
          .read(startupStyleProvider.notifier)
          .select(StartupStyle.classic);
      expect(savedStartupStyle(prefs), StartupStyle.classic);
      second.dispose();
    },
  );

  testWidgets(
    'foreground resumes same film, soundtrack stays on, completion and disposal happen once',
    (tester) async {
      final original = VideoPlayerPlatform.instance;
      addTearDown(() => VideoPlayerPlatform.instance = original);
      final video = _Video();
      // Texture disposal completes in Flutter's end-of-test frame cleanup;
      // verify it before restoring the process-wide platform implementation.
      addTearDown(() => expect(video.disposals, 1));
      VideoPlayerPlatform.instance = video;
      var completed = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: StartupVideoSurface(
            style: StartupStyle.companionsOne,
            onFinished: () => completed++,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(video.creates, 1);
      expect(video.volume, 1);
      expect(video.plays, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 4));
      expect(completed, 0);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(video.creates, 1);
      expect(video.plays, 2);
      expect(video.seeks, 0);
      video.events.add(VideoEvent(eventType: VideoEventType.completed));
      await tester.pump();
      await tester.pump();
      expect(completed, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(video.plays, 2);
      expect(completed, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      for (var frame = 0; frame < 10; frame++) {
        await tester.pump(const Duration(milliseconds: 1));
      }
      expect(find.byType(StartupVideoSurface), findsNothing);
      await video.events.close();
      await tester.pump();
    },
  );

  testWidgets(
    'decoder initialization timeout falls back and releases startup',
    (tester) async {
      final original = VideoPlayerPlatform.instance;
      addTearDown(() => VideoPlayerPlatform.instance = original);
      final video = _Video(stalls: true);
      addTearDown(() => expect(video.disposals, 1));
      VideoPlayerPlatform.instance = video;
      var completed = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: StartupVideoSurface(
            style: StartupStyle.companionsTwo,
            onFinished: () => completed++,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('mesting-branded-launch-screen')),
        findsOneWidget,
      );
      await tester.pump(const Duration(milliseconds: 750));
      expect(completed, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      for (var frame = 0; frame < 10; frame++) {
        await tester.pump(const Duration(milliseconds: 1));
      }
      await video.events.close();
      await tester.pump();
    },
  );
}
