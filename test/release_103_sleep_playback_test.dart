import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';
import 'package:mesting_music/core/audio/mesting_audio_handler.dart';
import 'package:mesting_music/shared/models/track.dart';
import 'support/deterministic_audio_player.dart';

class _CompletionPlayer extends DeterministicAudioPlayer {
  final completions = StreamController<ProcessingState>.broadcast();
  ProcessingState stage = ProcessingState.ready;
  LoopMode loop = LoopMode.off;
  @override
  Future<void> setLoopMode(LoopMode value) async {
    loop = value;
  }

  @override
  Stream<ProcessingState> get processingStateStream => completions.stream;
  @override
  ProcessingState get processingState => stage;
}

Track _song(String id) => Track(
  id: id,
  title: id,
  artist: 'Synthetic',
  album: '',
  duration: const Duration(minutes: 3),
  audioAsset: 'assets/$id.mp3',
  coverAsset: '',
  lyricsAsset: '',
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final singleRepeat in [false, true]) {
    test(
      'sleep completion suppresses queue/radio next, repeat=$singleRepeat',
      () async {
        final player = _CompletionPlayer();
        // Each assertion below uses one production handler and one active source.
        final actual = MestingAudioHandler(tracks: [], player: player);
        addTearDown(() async {
          await actual.debugDispose();
          await player.completions.close();
        });
        await actual.replaceQueue([_song('one'), _song('two')], autoplay: true);
        if (singleRepeat) {
          await actual.setRepeatMode(AudioServiceRepeatMode.one);
        }
        final loads = player.loads;
        actual.sleepTimer.afterCurrentTrack();
        await Future<void>.delayed(Duration.zero);
        expect(player.loop, LoopMode.off);
        player.stage = ProcessingState.completed;
        player.at = const Duration(minutes: 3);
        player.completions.add(ProcessingState.completed);
        for (var i = 0; i < 20; i++) {
          await Future<void>.delayed(Duration.zero);
        }
        expect(player.active, false);
        expect(actual.mediaItem.value?.id, 'one');
        expect(player.loads, loads);
        expect(actual.upcomingQueue.map((item) => item.id), ['two']);
        player.completions.add(ProcessingState.completed);
        await Future<void>.delayed(Duration.zero);
        expect(player.loads, loads);
        player.stage = ProcessingState.ready;
        await actual.play();
        expect(player.at, Duration.zero);
        expect(player.active, true);
        expect(player.loads, loads);
        expect(player.loop, singleRepeat ? LoopMode.one : LoopMode.off);
      },
    );
  }
}
