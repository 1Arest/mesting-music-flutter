import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesting_music/core/audio/actual_listening_counter.dart';
import 'package:mesting_music/core/audio/mesting_audio_handler.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_api.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_listening_binding.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_listening_reporter.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_listening_repository.dart';
import 'qishui_recovery172_test.dart' show song172;
import 'qishui_social177_test.dart' show account177;
import 'qishui_signed_api167_test.dart' show reply;
import 'support/deterministic_audio_player.dart';

class _Clock implements ListeningClock {
  int ms = 0;
  @override
  int get elapsedMicroseconds => ms * 1000;
  @override
  DateTime get now => DateTime.utc(2026, 11, 7).add(Duration(milliseconds: ms));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'real single-player binding stays idle on restore and excludes paused/buffering time',
    () async {
      SharedPreferences.setMockInitialValues({});
      var calls = 0;
      final api = QishuiApi(
        MockClient((_) async {
          calls++;
          return reply({});
        }),
      )..configure(account177());
      final repository = QishuiListeningRepository(
        api: api,
        current: () => true,
        reportEnabled: false,
      );
      final clock = _Clock();
      final handler = MestingAudioHandler(
        tracks: [song172(17701)],
        player: DeterministicAudioPlayer(),
      );
      final reporter = QishuiListeningReporter(
        repository: repository,
        clock: clock,
      );
      final binding = QishuiListeningBinding(handler, reporter);
      handler.mediaItem.add(song172(17701).toMediaItem());
      handler.playbackState.add(
        PlaybackState(
          playing: false,
          processingState: AudioProcessingState.ready,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      clock.ms += 5000;
      binding.sample();
      expect(reporter.heardMilliseconds, 0);
      handler.playbackState.add(
        PlaybackState(
          playing: true,
          processingState: AudioProcessingState.ready,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      clock.ms += 1250;
      binding.sample();
      handler.playbackState.add(
        PlaybackState(
          playing: true,
          processingState: AudioProcessingState.buffering,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      clock.ms += 4000;
      binding.sample();
      handler.playbackState.add(
        PlaybackState(
          playing: false,
          processingState: AudioProcessingState.ready,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await reporter.settle();
      expect((await repository.ledger()).heardMilliseconds, 1250);
      expect(calls, 0);
      binding.dispose();
      await handler.debugDispose();
      api.dispose();
      await Future<void>.delayed(Duration.zero);
    },
  );
}
