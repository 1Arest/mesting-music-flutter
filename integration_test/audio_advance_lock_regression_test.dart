import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mesting_music/core/audio/mesting_audio_handler.dart';
import 'package:mesting_music/core/audio/playback_mode.dart';

import 'support/device_audio_fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'paused restore supports next, queued next, and previous without waiting for track completion',
    (tester) async {
      final fixture = await DeviceAudioFixture.create();
      addTearDown(fixture.dispose);
      final tracks = fixture.tracks.skip(1).take(3).toList(growable: false);
      final handler = MestingAudioHandler(tracks: const []);
      addTearDown(handler.debugDispose);

      await handler.restoreSession(
        tracks: tracks.take(2).toList(growable: false),
        currentIndex: 0,
        position: Duration.zero,
        mode: PlaybackMode.list,
      );
      expect(handler.playbackState.value.playing, isFalse);
      expect(handler.mediaItem.value?.id, tracks.first.id);

      await handler.skipToNext().timeout(const Duration(seconds: 2));
      await _waitUntil(
        () =>
            handler.mediaItem.value?.id == tracks[1].id &&
            handler.playbackState.value.playing,
        reason: 'the first next command did not start the restored next track',
      );

      expect(await handler.appendToUpcomingQueue(tracks[2]), isTrue);
      await handler.skipToNext().timeout(const Duration(seconds: 2));
      await _waitUntil(
        () => handler.mediaItem.value?.id == tracks[2].id,
        reason: 'the second next command did not consume the manually queued track',
      );

      await handler.skipToPrevious().timeout(const Duration(seconds: 2));
      await _waitUntil(
        () => handler.mediaItem.value?.id == tracks[1].id,
        reason: 'previous did not return after two consecutive next commands',
      );
      expect(handler.playbackState.value.playing, isTrue);
      expect(handler.debugAudioSourceCount, 1);
    },
    timeout: const Timeout(Duration(minutes: 1)),
  );
}

Future<void> _waitUntil(
  bool Function() condition, {
  required String reason,
  Duration timeout = const Duration(seconds: 8),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) throw TestFailure(reason);
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}
