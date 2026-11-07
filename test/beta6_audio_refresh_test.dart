import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mesting_music/core/audio/mesting_audio_handler.dart';
import 'package:mesting_music/core/audio/playback_mode.dart';
import 'package:mesting_music/shared/models/track.dart';

/// A deterministic engine boundary: tests exercise the actual audio handler's
/// queue/epoch/source transitions without network, decoders or another player.
class _Player extends AudioPlayer {
  _Player()
    : super(
        handleInterruptions: false,
        handleAudioSessionActivation: false,
        androidApplyAudioAttributes: false,
      );
  Duration at = Duration.zero;
  bool active = false;
  int loads = 0;
  List<IndexedAudioSource> sources = [];
  @override
  Stream<PlaybackEvent> get playbackEventStream => const Stream.empty();
  @override
  Stream<int?> get currentIndexStream => const Stream.empty();
  @override
  Stream<Duration> get positionStream => const Stream.empty();
  @override
  Stream<Duration?> get durationStream => const Stream.empty();
  @override
  Stream<ProcessingState> get processingStateStream => const Stream.empty();
  @override
  Duration get position => at;
  @override
  bool get playing => active;
  @override
  ProcessingState get processingState => ProcessingState.ready;
  @override
  List<IndexedAudioSource> get sequence => sources;
  @override
  int? get currentIndex => sources.isEmpty ? null : 0;
  @override
  Future<Duration?> setAudioSources(
    List<AudioSource> audioSources, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
    ShuffleOrder? shuffleOrder,
  }) async {
    sources = audioSources.cast<IndexedAudioSource>();
    at = initialPosition ?? Duration.zero;
    loads++;
    return const Duration(minutes: 4);
  }

  @override
  Future<void> setShuffleModeEnabled(bool enabled) async {}
  @override
  Future<void> setLoopMode(LoopMode mode) async {}
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> play() async {
    active = true;
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
  Future<void> seek(Duration? position, {int? index}) async {
    at = position ?? Duration.zero;
  }
}

const first = Track(
  id: 'one',
  title: '当前歌曲',
  artist: '测试歌手',
  album: '',
  duration: Duration(minutes: 4),
  audioAsset: 'assets/first.mp3',
  coverAsset: '',
  lyricsAsset: '',
);
const second = Track(
  id: 'two',
  title: '下一首',
  artist: '测试歌手',
  album: '',
  duration: Duration(minutes: 4),
  audioAsset: 'assets/second.mp3',
  coverAsset: '',
  lyricsAsset: '',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<(_Player, MestingAudioHandler)> prepare({bool playing = false}) async {
    final player = _Player();
    final handler = MestingAudioHandler(tracks: [], player: player);
    await handler.replaceQueue([first, second], autoplay: playing);
    player.at = const Duration(seconds: 73);
    addTearDown(handler.debugDispose);
    return (player, handler);
  }

  test(
    'upstream continuation preserves file order and ignores local fallback pool',
    () async {
      final cache = await Directory.systemTemp.createTemp(
        'mesting_beta7_audio_',
      );
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => cache.path);
      addTearDown(() async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
        if (cache.absolute.path.startsWith(
          Directory.systemTemp.absolute.path,
        )) {
          await cache.delete(recursive: true);
        }
      });
      final (_, handler) = await prepare();
      Track song(String hash) => Track(
        id: 'kugou_$hash',
        title: '同名歌曲',
        artist: '同一歌手',
        album: '',
        duration: const Duration(minutes: 3),
        audioAsset: 'https://example.test/$hash.mp3',
        coverAsset: '',
        lyricsAsset: '',
        source: TrackSource.kugou,
      );
      final a = song('A'), b = song('B');
      await handler.replaceQueue([first], autoplay: false);
      handler.configureRadioTrackLoader(
        (excluded) async => [a, b],
        preserveServerOrder: true,
      );
      await handler.prefetchRadioTracks(force: true);
      expect(handler.upcomingQueue.map((item) => item.id), [
        'kugou_A',
        'kugou_B',
      ]);
      await handler.skipToNext();
      expect(handler.mediaItem.value?.id, 'kugou_A');
      await handler.skipToNext();
      expect(handler.mediaItem.value?.id, 'kugou_B');
    },
  );

  test(
    'quality refresh preserves position, pause state, mode and upcoming queue',
    () async {
      for (final playing in [false, true]) {
        final (player, handler) = await prepare(playing: playing);
        await handler.setPlaybackMode(PlaybackMode.single);
        handler.configureTrackPlaybackResolver(
          (track) async => track.copyWith(
            audioAsset: 'assets/lossless.flac',
            playbackQuality: 'flac',
          ),
        );
        expect(await handler.refreshCurrentSource(), true);
        expect(player.at, const Duration(seconds: 73));
        expect(player.active, playing);
        expect(handler.mediaItem.value!.id, first.id);
        expect(handler.trackForId(first.id)!.playbackQuality, 'flac');
        expect(handler.upcomingQueue.map((item) => item.id), [second.id]);
        expect(handler.playbackMode, PlaybackMode.single);
        expect(player.sequence, hasLength(1));
      }
    },
  );

  test(
    'a newer seek discards slow quality response without replacing the stream',
    () async {
      final (player, handler) = await prepare();
      final pending = Completer<Track>();
      handler.configureTrackPlaybackResolver((_) => pending.future);
      final operation = handler.refreshCurrentSource();
      await Future<void>.delayed(Duration.zero);
      final loads = player.loads;
      await handler.seek(const Duration(seconds: 100));
      pending.complete(
        first.copyWith(
          audioAsset: 'assets/stale.flac',
          playbackQuality: 'high',
        ),
      );
      expect(await operation, false);
      expect(player.loads, loads);
      expect(player.at, const Duration(seconds: 100));
      expect(handler.trackForId(first.id)!.playbackQuality, '');
    },
  );

  test(
    'failed resolution keeps the working stream, queue and current position',
    () async {
      final (player, handler) = await prepare();
      final loads = player.loads;
      handler.configureTrackPlaybackResolver(
        (_) async => throw StateError('tier unavailable'),
      );
      await expectLater(handler.refreshCurrentSource(), throwsStateError);
      expect(player.loads, loads);
      expect(player.at, const Duration(seconds: 73));
      expect(handler.upcomingQueue.single.id, second.id);
    },
  );

  test(
    'beta8 ordinary search context still advances with the global radio loader installed',
    () async {
      final (_, handler) = await prepare();
      handler.configureRadioTrackLoader(
        (_) async => [],
        preserveServerOrder: true,
      );
      await handler.playSingleTrack(first, playbackContext: [first, second]);
      // Explicit queue exhausted: this is the state of a search-selected song.
      await handler.removeFromUpcomingQueue(second.id);
      await handler.skipToNext();
      expect(handler.mediaItem.value!.id, second.id);
      await handler.skipToPrevious();
      expect(handler.mediaItem.value!.id, first.id);
      await handler.skipToNext();
      expect(handler.mediaItem.value!.id, second.id);
    },
  );

  test(
    'beta8 cold Previous chooses the prior list item and Next returns to the original',
    () async {
      final (_, handler) = await prepare();
      const third = Track(
        id: 'three',
        title: '第三首',
        artist: '测试歌手',
        album: '',
        duration: Duration(minutes: 4),
        audioAsset: 'assets/third.mp3',
        coverAsset: '',
        lyricsAsset: '',
      );
      handler.configureRadioTrackLoader(
        (_) async => [],
        preserveServerOrder: true,
      );
      await handler.replaceQueue(
        [first, second, third],
        initialIndex: 1,
        autoplay: false,
      );
      expect(handler.mediaItem.value!.id, second.id);
      await handler.skipToPrevious();
      expect(handler.mediaItem.value!.id, first.id);
      expect(handler.upcomingQueue.first.id, second.id);
      await handler.skipToNext();
      expect(handler.mediaItem.value!.id, second.id);
      await handler.replaceQueue([first, second, third], autoplay: false);
      await handler.skipToPrevious();
      expect(handler.mediaItem.value!.id, third.id);
      await handler.skipToNext();
      expect(handler.mediaItem.value!.id, first.id);
    },
  );

  test(
    'beta8 FM Previous with no history leaves the next recommendation pending',
    () async {
      final (_, handler) = await prepare();
      handler.configureRadioTrackLoader(
        (_) async => [],
        preserveServerOrder: true,
      );
      await handler.replaceQueue(
        [first, second],
        recommendationContext: true,
        autoplay: false,
      );
      await handler.skipToPrevious();
      expect(handler.mediaItem.value!.id, first.id);
      expect(handler.upcomingQueue.single.id, second.id);
      await handler.skipToNext();
      expect(handler.mediaItem.value!.id, second.id);
    },
  );
}
