import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mesting_music/core/audio/mesting_audio_handler.dart';
import 'package:mesting_music/core/audio/playback_mode.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_api.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_playback_recovery.dart';
import 'package:mesting_music/shared/models/track.dart';
import 'support/deterministic_audio_player.dart';

Track song172(int n) => Track(
  id: 'qishui_$n',
  platformSongId: '$n',
  title: '测试歌曲 $n',
  artist: '测试歌手',
  album: '',
  duration: const Duration(minutes: 3),
  audioAsset: 'mesting-platform://qishui/$n',
  coverAsset: '',
  lyricsAsset: '',
  source: TrackSource.qishui,
);
const refused172 = QishuiException(
  '汽水拒绝了请求（301）',
  kind: QishuiFailureKind.refused,
  code: '301',
);

class Completing172 extends DeterministicAudioPlayer {
  final completed = StreamController<ProcessingState>.broadcast();
  @override
  Stream<ProcessingState> get processingStateStream => completed.stream;
}

class FailingStart172 extends DeterministicAudioPlayer {
  @override
  Future<void> play() async {
    throw PlayerException(301, 'fixture native source unavailable', 0);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    final dir = await Directory.systemTemp.createTemp('mesting172queue');
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => dir.path);
    addTearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      await dir.delete(recursive: true);
    });
  });
  for (final kind in [
    QishuiFailureKind.connection,
    QishuiFailureKind.authentication,
    QishuiFailureKind.timeout,
    QishuiFailureKind.cancelled,
    QishuiFailureKind.operation,
  ]) {
    test('global $kind never sweeps the queue', () async {
      final handler = MestingAudioHandler(
        tracks: [],
        player: DeterministicAudioPlayer(),
      );
      addTearDown(handler.debugDispose);
      final attempts = <String>[];
      handler.configureTrackPlaybackResolver((track) async {
        attempts.add(track.id);
        throw QishuiException('fixture', kind: kind);
      }, skipUnplayableTrack: qishuiCanSkipPlaybackFailure);
      await expectLater(
        handler.replaceQueue([song172(0), song172(1)]),
        throwsA(isA<QishuiException>()),
      );
      expect(attempts, [song172(0).id]);
    });
  }
  for (final command in ['replace', 'manual', 'next', 'completion']) {
    test(
      '$command skips failed resolution and binds the next playable source',
      () async {
        final player = Completing172();
        final handler = MestingAudioHandler(tracks: [], player: player);
        addTearDown(handler.debugDispose);
        addTearDown(player.completed.close);
        final attempts = <String>[];
        handler.configureTrackPlaybackResolver((track) async {
          attempts.add(track.id);
          if (track.id == song172(1).id) throw refused172;
          return track.copyWith(audioAsset: 'file:///fixture/${track.id}.m4a');
        }, skipUnplayableTrack: qishuiCanSkipPlaybackFailure);
        if (command == 'replace') {
          await handler.replaceQueue([song172(1), song172(2), song172(3)]);
        } else {
          await handler.replaceQueue([
            song172(0),
            song172(1),
            song172(2),
            song172(3),
          ]);
          attempts.clear();
          if (command == 'manual') await handler.playSingleTrack(song172(1));
          if (command == 'next') await handler.skipToNext();
          if (command == 'completion') {
            player.completed.add(ProcessingState.completed);
            for (
              var i = 0;
              i < 40 && handler.mediaItem.value?.id != song172(2).id;
              i++
            ) {
              await Future<void>.delayed(const Duration(milliseconds: 10));
            }
          }
        }
        expect(attempts, [song172(1).id, song172(2).id]);
        expect(handler.mediaItem.value?.id, song172(2).id);
        expect(handler.upcomingQueue.map((m) => m.id), contains(song172(3).id));
        expect(player.playing, true);
      },
    );
  }
  test(
    'an entirely failed round tries each recording once and then stops',
    () async {
      final player = DeterministicAudioPlayer();
      final handler = MestingAudioHandler(tracks: [], player: player);
      addTearDown(handler.debugDispose);
      final attempts = <String>[];
      handler.configureTrackPlaybackResolver((track) async {
        attempts.add(track.id);
        throw refused172;
      }, skipUnplayableTrack: qishuiCanSkipPlaybackFailure);
      await expectLater(
        handler.replaceQueue([song172(0), song172(1), song172(2), song172(0)]),
        throwsA(isA<PlaybackContinuationException>()),
      );
      expect(attempts, [song172(0).id, song172(1).id, song172(2).id]);
      expect(handler.playbackState.value.errorMessage, contains('本轮队列'));
      expect(player.playing, false);
    },
  );
  test('failure recovery is inactive for paused preparation', () async {
    final handler = MestingAudioHandler(
      tracks: [],
      player: DeterministicAudioPlayer(),
    );
    addTearDown(handler.debugDispose);
    var attempts = 0;
    handler.configureTrackPlaybackResolver((track) async {
      attempts++;
      throw refused172;
    }, skipUnplayableTrack: qishuiCanSkipPlaybackFailure);
    await expectLater(
      handler.replaceQueue([song172(0), song172(1)], autoplay: false),
      throwsA(isA<QishuiException>()),
    );
    expect(attempts, 1);
  });
  test(
    'Pause while resolving prevents the old failure from starting a next song',
    () async {
      final handler = MestingAudioHandler(
        tracks: [],
        player: DeterministicAudioPlayer(),
      );
      addTearDown(handler.debugDispose);
      final entered = Completer<void>(), finish = Completer<void>();
      var attempts = 0;
      handler.configureTrackPlaybackResolver((track) async {
        attempts++;
        entered.complete();
        await finish.future;
        throw refused172;
      }, skipUnplayableTrack: qishuiCanSkipPlaybackFailure);
      final pending = handler.replaceQueue([song172(0), song172(1)]);
      await entered.future;
      await handler.pause();
      finish.complete();
      await pending;
      expect(attempts, 1);
      expect(handler.mediaItem.value?.id, song172(0).id);
    },
  );
  test('repeat-one failure still advances to the next candidate', () async {
    final handler = MestingAudioHandler(
      tracks: [],
      player: DeterministicAudioPlayer(),
    );
    addTearDown(handler.debugDispose);
    handler.configureTrackPlaybackResolver((track) async {
      if (track.id == song172(0).id) throw refused172;
      return track.copyWith(audioAsset: 'file:///fixture/full.m4a');
    }, skipUnplayableTrack: qishuiCanSkipPlaybackFailure);
    await handler.setPlaybackMode(PlaybackMode.single);
    await handler.replaceQueue([song172(0), song172(1)]);
    expect(handler.mediaItem.value?.id, song172(1).id);
  });
  test('native Play 301 consumes one queue round without wrapping', () async {
    final player = FailingStart172();
    final handler = MestingAudioHandler(tracks: [], player: player);
    addTearDown(handler.debugDispose);
    final attempts = <String>[];
    handler.configureTrackPlaybackResolver((track) async {
      attempts.add(track.id);
      return track.copyWith(audioAsset: 'file:///fixture/${track.id}.m4a');
    }, skipUnplayableTrack: qishuiCanSkipPlaybackFailure);
    await handler.replaceQueue([song172(0), song172(1), song172(2)]);
    for (var wait = 0; wait < 100; wait++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      if (handler.playbackState.value.errorMessage?.contains('本轮队列') == true) {
        break;
      }
    }
    expect(attempts, [song172(0).id, song172(1).id, song172(2).id]);
    expect(handler.playbackState.value.errorMessage, contains('本轮队列'));
    expect(player.playing, false);
  });
}
