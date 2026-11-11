import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mesting_music/core/audio/mesting_audio_handler.dart';
import 'package:mesting_music/core/audio/playback_preferences.dart';
import 'package:mesting_music/core/audio/playback_transition.dart';
import 'package:mesting_music/shared/models/track.dart';

/// Real handler, fake decoder boundary: no URL lookup, actual sound or session
/// is created. Events exercise queue ownership and cancellation, not UI mocks.
class Decoder extends AudioPlayer {
  Decoder({this.produceProgress = false})
    : super(
        handleInterruptions: false,
        handleAudioSessionActivation: false,
        androidApplyAudioAttributes: false,
      );
  final bool produceProgress;
  final positions = StreamController<Duration>.broadcast(sync: true);
  final states = StreamController<ProcessingState>.broadcast(sync: true);
  final events = StreamController<PlaybackEvent>.broadcast(sync: true);
  bool active = false, released = false;
  int loads = 0;
  Duration at = Duration.zero;
  double gain = 1;
  Completer<void>? handoffGate;
  final gains = <double>[];
  List<IndexedAudioSource> sources = [];
  @override
  Stream<PlaybackEvent> get playbackEventStream => events.stream;
  @override
  Stream<int?> get currentIndexStream => const Stream.empty();
  @override
  Stream<Duration> get positionStream => positions.stream;
  @override
  Stream<Duration?> get durationStream =>
      Stream.value(const Duration(seconds: 20));
  @override
  Stream<ProcessingState> get processingStateStream => states.stream;
  @override
  Duration get position => at;
  @override
  Duration? get duration => const Duration(seconds: 20);
  @override
  bool get playing => active;
  @override
  ProcessingState get processingState => ProcessingState.ready;
  @override
  double get volume => gain;
  @override
  List<IndexedAudioSource> get sequence => sources;
  @override
  int? get currentIndex => sources.isEmpty ? null : 0;
  @override
  Future<Duration?> setAudioSources(
    List<AudioSource> input, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
    ShuffleOrder? shuffleOrder,
  }) async {
    sources = input.cast<IndexedAudioSource>();
    at = initialPosition ?? Duration.zero;
    loads++;
    return duration;
  }

  @override
  Future<void> setMusicOutputOwner(String owner) async {
    if (owner == 'mesting-tail') await handoffGate?.future;
  }

  @override
  Future<void> setShuffleModeEnabled(bool value) async {}
  @override
  Future<void> setLoopMode(LoopMode mode) async {}
  @override
  Future<void> setVolume(double value) async {
    gain = value;
    gains.add(value);
  }

  @override
  Future<void> play() async {
    active = true;
    // Native progress is delivered after the play command, not synchronously.
    if (produceProgress) {
      Future<void>.delayed(const Duration(milliseconds: 5), () {
        if (!released && active) emit(const Duration(milliseconds: 50));
      });
    }
  }

  @override
  Future<void> pause() async {
    active = false;
  }

  @override
  Future<void> stop() async {
    active = false;
  }

  @override
  Future<void> seek(Duration? value, {int? index}) async {
    at = value ?? Duration.zero;
  }

  void emit(Duration value) {
    at = value;
    positions.add(value);
  }

  @override
  Future<void> dispose() async {
    if (released) return;
    released = true;
    active = false;
    await positions.close();
    await states.close();
    await events.close();
    await super.dispose();
  }
}

Track tune(String id) => Track(
  id: id,
  title: id,
  artist: 'Test',
  album: '',
  duration: const Duration(seconds: 20),
  audioAsset: 'assets/$id.mp3',
  coverAsset: '',
  lyricsAsset: '',
);
Future<void> until(bool Function() check) async {
  for (var i = 0; i < 200 && !check(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(check(), isTrue);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('equal power envelope endpoints and energy', () {
    expect(crossfadeGains(0).$1, 1);
    expect(crossfadeGains(1).$2, 1);
    final midpoint = crossfadeGains(.5);
    expect(
      midpoint.$1 * midpoint.$1 + midpoint.$2 * midpoint.$2,
      closeTo(1, .00001),
    );
  });
  Future<(Decoder, MestingAudioHandler, List<Decoder>)> setup({
    bool fade = false,
  }) async {
    final primary = Decoder(), prepared = <Decoder>[];
    final handler = MestingAudioHandler(
      tracks: [],
      player: primary,
      preparedPlayerFactory: () {
        final d = Decoder(produceProgress: true);
        prepared.add(d);
        return d;
      },
    );
    handler.configurePlaybackPreferences(
      PlaybackPreferences(crossfade: fade, seconds: 1),
    );
    await handler.replaceQueue([tune('first'), tune('second'), tune('third')]);
    await Future<void>.delayed(const Duration(milliseconds: 15));
    addTearDown(handler.debugDispose);
    return (primary, handler, prepared);
  }

  test(
    'silent preparation emits no listening; manual Next reuses its decoder',
    () async {
      final (primary, handler, prepared) = await setup();
      final consumed = <String>[];
      final sub = handler.consumedTrackStream.listen((t) => consumed.add(t.id));
      addTearDown(sub.cancel);
      primary.emit(const Duration(seconds: 8));
      await until(() => prepared.isNotEmpty && prepared.first.loads > 0);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(handler.mediaItem.value!.id, 'first');
      expect(prepared.first.active, isFalse);
      expect(prepared.first.gain, 0);
      expect(consumed, isEmpty);
      await handler.skipToNext();
      expect(handler.mediaItem.value!.id, 'second');
      expect(primary.released, isTrue);
      expect(prepared.first.loads, 1);
      expect(prepared.first.gain, 1);
    },
  );
  test(
    'queue removal rejects late resolver and never changes current track',
    () async {
      final (primary, handler, prepared) = await setup();
      final late = Completer<Track>();
      handler.configureTrackPlaybackResolver(
        (track) => track.id == 'second' ? late.future : Future.value(track),
      );
      primary.emit(const Duration(seconds: 8));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await handler.removeFromUpcomingQueue('second');
      late.complete(tune('second'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(handler.mediaItem.value!.id, 'first');
      expect(prepared, isEmpty);
    },
  );
  test(
    'automatic overlap transfers metadata once; seek immediately stops tail',
    () async {
      final (primary, handler, prepared) = await setup(fade: true);
      primary.emit(const Duration(seconds: 8));
      await until(() => prepared.isNotEmpty && prepared.first.loads > 0);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      primary.emit(const Duration(milliseconds: 19000));
      await until(() => handler.mediaItem.value!.id == 'second');
      expect(primary.active, isTrue);
      expect(prepared.first.active, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(prepared.first.gain, greaterThan(0));
      expect(primary.gain, lessThan(1));
      await handler.seek(const Duration(seconds: 4));
      await until(() => primary.released);
      expect(prepared.first.gain, 1);
      expect(handler.mediaItem.value!.id, 'second');
      expect(handler.currentPosition, const Duration(seconds: 4));
    },
  );
  test(
    'source configuration invalidation during overlap restores active volume',
    () async {
      final (primary, handler, prepared) = await setup(fade: true);
      primary.emit(const Duration(seconds: 8));
      await until(() => prepared.isNotEmpty && prepared.first.loads > 0);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      primary.emit(const Duration(seconds: 19));
      await until(() => handler.mediaItem.value!.id == 'second');
      handler.configureTrackPlaybackResolver((t) async => t);
      await until(() => primary.released);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(prepared.first.gain, 1);
      expect(prepared.first.active, isTrue);
    },
  );
  test(
    'slow native handoff cannot leave old metadata after a newer seek',
    () async {
      final (primary, handler, prepared) = await setup(fade: true);
      primary.handoffGate = Completer<void>();
      primary.emit(const Duration(seconds: 8));
      await until(() => prepared.isNotEmpty && prepared.first.loads > 0);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      primary.emit(const Duration(seconds: 19));
      await until(() => handler.mediaItem.value!.id == 'second');
      await handler.seek(const Duration(seconds: 7));
      primary.handoffGate!.complete();
      await until(() => primary.released);
      expect(handler.mediaItem.value!.id, 'second');
      expect(handler.currentPosition, const Duration(seconds: 7));
      expect(prepared.first.gain, 1);
    },
  );
  test(
    'natural overlap completes old recording once and never skips incoming',
    () async {
      final (primary, handler, prepared) = await setup(fade: true);
      final completions = <String>[];
      final sub = handler.completedTrackStream.listen(
        (t) => completions.add(t.id),
      );
      addTearDown(sub.cancel);
      primary.emit(const Duration(seconds: 8));
      await until(() => prepared.isNotEmpty && prepared.first.loads > 0);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      primary.emit(const Duration(seconds: 19));
      await until(() => handler.mediaItem.value!.id == 'second');
      primary.states.add(ProcessingState.completed);
      await until(() => primary.released);
      expect(completions, ['first']);
      expect(handler.mediaItem.value!.id, 'second');
      expect(prepared.first.gain, 1);
      expect(prepared.first.active, isTrue);
    },
  );
  test(
    'pause during overlap never lets a late envelope resume playback',
    () async {
      final (primary, handler, prepared) = await setup(fade: true);
      primary.emit(const Duration(seconds: 8));
      await until(() => prepared.isNotEmpty && prepared.first.loads > 0);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      primary.emit(const Duration(seconds: 19));
      await until(() => handler.mediaItem.value!.id == 'second');
      await handler.pause();
      await until(() => primary.released);
      expect(prepared.first.active, isFalse);
      expect(prepared.first.gain, 1);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(prepared.first.active, isFalse);
    },
  );
  test(
    'sleep boundary and together suppress speculative preparation',
    () async {
      final (primary, handler, prepared) = await setup(fade: true);
      handler.sleepTimer.afterCurrentTrack();
      primary.emit(const Duration(seconds: 8));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(prepared, isEmpty);
      handler.sleepTimer.cancel();
      handler.configureSynchronizedPlayback(() => true);
      primary.emit(const Duration(seconds: 8));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(prepared, isEmpty);
    },
  );
}
