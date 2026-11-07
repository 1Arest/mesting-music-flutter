import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mesting_music/core/audio/mesting_audio_handler.dart';

import 'support/device_audio_fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const runSystemControls = bool.fromEnvironment(
    'RUN_ANDROID_SYSTEM_CONTROL_REGRESSION',
  );

  testWidgets(
    '前后台切换及 Android 媒体会话暂停继续切歌',
    (tester) async {
      final fixture = await DeviceAudioFixture.create();
      addTearDown(fixture.dispose);
      final tracks = fixture.tracks;
      final handler = await AudioService.init<MestingAudioHandler>(
        builder: () =>
            MestingAudioHandler(tracks: [tracks[1], tracks[2], tracks[3]]),
        config: const AudioServiceConfig(
          androidNotificationChannelId:
              'com.mesting.music.playback.integration',
          androidNotificationChannelName: 'Mesting 音频系统控制回归',
          androidStopForegroundOnPause: false,
        ),
      );
      final states = <bool>[];
      final subscription = handler.playbackState.listen(
        (state) => states.add(state.playing),
      );
      addTearDown(() async {
        await handler.stop();
        await subscription.cancel();
      });

      unawaited(handler.replaceQueue([tracks[1], tracks[2], tracks[3]]));
      await _waitUntil(
        () => handler.playbackState.value.playing,
        reason: '媒体会话初始播放未启动',
      );
      states.clear();
      // The host-side regression script sends HOME, pause, play, next and then
      // brings this Activity back while this window remains open.
      // ignore: avoid_print
      print('[AudioSystemRegression] READY_FOR_ANDROID_MEDIA_COMMANDS');
      await Future<void>.delayed(const Duration(seconds: 55));

      expect(states, contains(false), reason: 'Android 媒体会话没有传入暂停命令');
      final firstPause = states.indexOf(false);
      expect(firstPause, isNonNegative);
      expect(
        states.skip(firstPause + 1),
        contains(true),
        reason: 'Android 媒体会话暂停后没有继续播放',
      );
      expect(handler.mediaItem.value?.id, tracks[2].id);
      expect(handler.playbackState.value.playing, isTrue);
      expect(handler.currentPosition, greaterThan(const Duration(seconds: 2)));
      expect(handler.debugAudioSourceCount, 1);
    },
    skip: !runSystemControls,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

Future<void> _waitUntil(
  bool Function() condition, {
  required String reason,
  Duration timeout = const Duration(seconds: 15),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) throw TestFailure(reason);
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}
