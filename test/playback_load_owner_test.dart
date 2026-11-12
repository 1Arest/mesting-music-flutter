import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/core/audio/mesting_audio_handler.dart';
import 'package:mesting_music/shared/models/track.dart';

import 'support/deterministic_audio_player.dart';

Track song(String id) => Track(
  id: id,
  title: id,
  artist: 'fixture',
  album: '',
  duration: const Duration(minutes: 3),
  audioAsset: 'assets/$id.mp3',
  coverAsset: '',
  lyricsAsset: '',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final lateFailure in [false, true]) {
    test(
      'abandoned owner clears loading after late ${lateFailure ? "failure" : "success"}',
      () async {
        final player = DeterministicAudioPlayer();
        final handler = MestingAudioHandler(tracks: [], player: player);
        addTearDown(handler.debugDispose);
        final entered = Completer<void>(), lookup = Completer<Track>();
        handler.configureTrackPlaybackResolver((_) {
          entered.complete();
          return lookup.future;
        });
        var alive = true;
        final operation = handler.playSingleTrack(
          song('old'),
          isCurrent: () => alive,
        );
        await entered.future;
        expect(
          handler.playbackState.value.processingState,
          AudioProcessingState.loading,
        );
        final loads = player.loads;
        alive = false;
        if (lateFailure) {
          lookup.completeError(StateError('stale resolver'));
        } else {
          lookup.complete(song('old'));
        }
        await operation;
        expect(
          handler.playbackState.value.processingState,
          AudioProcessingState.idle,
        );
        expect(player.active, isFalse);
        expect(player.loads, loads);
      },
    );
  }
  test(
    'old completion cannot clear newer loading or overwrite newer selection',
    () async {
      final player = DeterministicAudioPlayer();
      final handler = MestingAudioHandler(tracks: [], player: player);
      addTearDown(handler.debugDispose);
      final oldEntered = Completer<void>(), newEntered = Completer<void>();
      final oldLookup = Completer<Track>(), newLookup = Completer<Track>();
      handler.configureTrackPlaybackResolver((track) {
        if (track.id == 'old') {
          oldEntered.complete();
          return oldLookup.future;
        }
        newEntered.complete();
        return newLookup.future;
      });
      final old = handler.playSingleTrack(song('old'));
      await oldEntered.future;
      final newer = handler.playSingleTrack(song('new'));
      await newEntered.future;
      final loads = player.loads;
      oldLookup.complete(song('old'));
      await old;
      expect(handler.mediaItem.value!.id, 'new');
      expect(
        handler.playbackState.value.processingState,
        AudioProcessingState.loading,
      );
      newLookup.complete(song('new'));
      await newer;
      expect(handler.mediaItem.value!.id, 'new');
      expect(
        handler.playbackState.value.processingState,
        AudioProcessingState.ready,
      );
      expect(player.active, isTrue);
      expect(player.loads, loads + 1);
    },
  );
}
