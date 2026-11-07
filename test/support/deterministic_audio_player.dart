import 'package:just_audio/just_audio.dart';

class DeterministicAudioPlayer extends AudioPlayer {
  DeterministicAudioPlayer()
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
