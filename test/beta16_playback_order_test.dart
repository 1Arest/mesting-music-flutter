import 'dart:async';
import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mesting_music/core/audio/mesting_audio_handler.dart';
import 'package:mesting_music/core/audio/playback_mode.dart';
import 'package:mesting_music/shared/models/track.dart';
import 'support/deterministic_audio_player.dart';

class _CompletionPlayer extends DeterministicAudioPlayer {
  final completions = StreamController<ProcessingState>.broadcast();
  LoopMode loop = LoopMode.off;
  @override
  Stream<ProcessingState> get processingStateStream => completions.stream;
  @override
  Future<void> setLoopMode(LoopMode mode) async {
    loop = mode;
  }
}

Track song(String id) => Track(
  id: id,
  title: id,
  artist: '测试歌手',
  album: '',
  duration: const Duration(minutes: 3),
  audioAsset: 'assets/$id.mp3',
  coverAsset: '',
  lyricsAsset: '',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    final dir = await Directory.systemTemp.createTemp('mesting_beta16_order_');
    const path = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(path, (_) async => dir.path);
    addTearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(path, null);
      await dir.delete(recursive: true);
    });
  });
  Future<(_CompletionPlayer, MestingAudioHandler)> prepare() async {
    final player = _CompletionPlayer();
    final handler = MestingAudioHandler(tracks: [], player: player);
    await handler.setPlaybackMode(PlaybackMode.list);
    await handler.replaceQueue([
      song('A'),
      song('B'),
      song('C'),
    ], autoplay: false);
    addTearDown(() async {
      await handler.debugDispose();
      await player.completions.close();
    });
    return (player, handler);
  }

  Future<void> flush() async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test(
    'new installs default to sequential and app cycles exactly four modes',
    () async {
      final player = _CompletionPlayer();
      final handler = MestingAudioHandler(tracks: [], player: player);
      addTearDown(() async {
        await handler.debugDispose();
        await player.completions.close();
      });
      await handler.replaceQueue([
        song('A'),
        song('B'),
        song('C'),
      ], autoplay: false);
      expect(handler.playbackMode, PlaybackMode.sequential);
      final loads = player.loads;
      player.at = const Duration(seconds: 37);
      for (final expected in [
        PlaybackMode.list,
        PlaybackMode.single,
        PlaybackMode.random,
        PlaybackMode.sequential,
      ]) {
        await handler.cyclePlaybackMode();
        expect(handler.playbackMode, expected);
        expect(player.loads, loads);
        expect(player.at, const Duration(seconds: 37));
        expect(
          player.loop,
          expected == PlaybackMode.single ? LoopMode.one : LoopMode.off,
        );
      }
    },
  );

  test(
    'random visibly reorders pending songs, Next follows rows, sequential restores remaining source order',
    () async {
      final (player, handler) = await prepare();
      final tracks = ['A', 'B', 'C', 'D', 'E', 'F'].map(song).toList();
      await handler.replaceQueue(tracks, autoplay: false);
      final original = handler.upcomingQueue.map((item) => item.id).toList();
      final loads = player.loads;
      player.at = const Duration(seconds: 37);
      await handler.setRandomUpcoming(true);
      await handler.setPlaybackMode(PlaybackMode.random);
      final shuffled = handler.upcomingQueue.map((item) => item.id).toList();
      expect(shuffled.toSet(), original.toSet());
      expect(shuffled, isNot(original));
      expect(handler.randomUpcoming, false);
      expect(handler.mediaItem.value?.id, 'A');
      expect(player.loads, loads);
      expect(player.at, const Duration(seconds: 37));
      await handler.skipToNext();
      expect(handler.mediaItem.value?.id, shuffled.first);
      await handler.setPlaybackMode(PlaybackMode.sequential);
      expect(
        handler.upcomingQueue.map((item) => item.id),
        original.where((id) => id != shuffled.first),
      );
      expect(handler.playbackOrder.repeat, PlaybackRepeat.off);
    },
  );

  test('saved old preferences migrate and all four app modes restore', () {
    expect(PlaybackOrder.parse('list').legacy, PlaybackMode.list);
    expect(PlaybackOrder.parse('single').legacy, PlaybackMode.single);
    expect(PlaybackOrder.parse('random').legacy, PlaybackMode.random);
    expect(PlaybackOrder.parse('').legacy, PlaybackMode.sequential);
    for (final mode in PlaybackMode.values) {
      final saved = PlaybackOrder.fromLegacy(mode);
      expect(PlaybackOrder.parse(saved.serialized).legacy, mode);
      expect(saved.label, mode.label);
    }
  });

  test('old sessions migrate and all independent combinations round-trip', () {
    expect(PlaybackOrder.parse('single').repeat, PlaybackRepeat.one);
    expect(PlaybackOrder.parse('random').shuffle, true);
    for (final repeat in PlaybackRepeat.values) {
      for (final shuffle in [true, false]) {
        final order = PlaybackOrder(repeat: repeat, shuffle: shuffle);
        expect(PlaybackOrder.parse(order.serialized), order);
      }
    }
  });
  test(
    'shuffle survives repeat changes, source changes and session restore',
    () async {
      final (_, handler) = await prepare();
      await handler.setShuffleEnabled(true);
      await handler.cycleRepeat();
      expect(
        handler.playbackOrder,
        const PlaybackOrder(repeat: PlaybackRepeat.one, shuffle: true),
      );
      await handler.playTrack('B');
      expect(handler.playbackOrder.shuffle, true);
      expect(handler.playbackOrder.repeat, PlaybackRepeat.one);
      final order = PlaybackOrder.parse(handler.playbackOrder.serialized);
      await handler.restoreSession(
        tracks: [song('A'), song('B')],
        currentIndex: 0,
        position: Duration.zero,
        mode: order.legacy,
        order: order,
      );
      expect(handler.playbackOrder, order);
      expect(
        handler.playbackState.value.repeatMode,
        AudioServiceRepeatMode.one,
      );
      expect(
        handler.playbackState.value.shuffleMode,
        AudioServiceShuffleMode.all,
      );
    },
  );
  test(
    'repeat off stops an exhausted explicit queue instead of wrapping',
    () async {
      final (player, handler) = await prepare();
      await handler.replaceQueue([song('A')], autoplay: false);
      await handler.cycleRepeat(); // all -> one
      await handler.cycleRepeat(); // one -> off
      player.active = true;
      player.completions.add(ProcessingState.completed);
      await flush();
      expect(player.active, false);
      expect(handler.mediaItem.value?.id, 'A');
    },
  );
  test('manual next still advances when single repeat is enabled', () async {
    final (_, handler) = await prepare();
    await handler.cycleRepeat();
    await handler.skipToNext();
    expect(handler.mediaItem.value?.id, 'B');
    expect(handler.playbackOrder.repeat, PlaybackRepeat.one);
  });
  test(
    'reordering pending songs preserves current audio source and position',
    () async {
      final (player, handler) = await prepare();
      final loads = player.loads;
      player.at = const Duration(seconds: 37);
      await handler.reorderUpcoming(0, 2);
      expect(handler.upcomingQueue.map((i) => i.id), ['C', 'B']);
      expect(player.loads, loads);
      expect(player.at, const Duration(seconds: 37));
      expect(handler.persistedQueue.map((t) => t.id), ['A', 'C', 'B']);
      await handler.skipToNext();
      expect(handler.mediaItem.value?.id, 'C');
    },
  );
  test(
    'shuffle Next follows the visible pending order and unshuffle restores the source order',
    () async {
      final (_, handler) = await prepare();
      await handler.setShuffleEnabled(true);
      final next = handler.upcomingQueue.first.id;
      await handler.skipToNext();
      expect(handler.mediaItem.value?.id, next);
      await handler.replaceQueue([
        song('A'),
        song('B'),
        song('C'),
      ], autoplay: false);
      await handler.setShuffleEnabled(false);
      expect(handler.upcomingQueue.map((item) => item.id), ['B', 'C']);
    },
  );
  test(
    'system shuffle and repeat controls keep their independent state',
    () async {
      final (_, handler) = await prepare();
      await handler.setRepeatMode(AudioServiceRepeatMode.none);
      await handler.setShuffleMode(AudioServiceShuffleMode.all);
      expect(
        handler.playbackOrder,
        const PlaybackOrder(repeat: PlaybackRepeat.off, shuffle: true),
      );
      await handler.setRepeatMode(AudioServiceRepeatMode.one);
      expect(handler.playbackOrder.shuffle, true);
    },
  );
}
