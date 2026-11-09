import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/audio/mesting_audio_handler.dart';
import '../../../core/audio/playback_providers.dart';
import 'qishui_listening_providers.dart';
import 'qishui_listening_reporter.dart';
import 'qishui_providers.dart';

/// Installed once by the Beta host. It observes the existing player; creating
/// this binding never restores, resolves, starts, or replaces an audio source.
final qishuiListeningSyncProvider = Provider<void>((ref) {
  if (!ref.watch(usesQishuiProvider)) return;
  final repository = ref.watch(qishuiListeningRepositoryProvider);
  if (!repository.current) return;
  var active = true;
  final binding = QishuiListeningBinding(
    ref.watch(audioHandlerProvider),
    QishuiListeningReporter(
      repository: repository,
      onStatus: (status) => scheduleMicrotask(() {
        // The initial sample can run while the application host is building.
        // Publish later and only while this exact account binding survives.
        if (active && repository.current) {
          ref.read(qishuiListeningStatusProvider.notifier).update(status);
        }
      }),
    ),
  );
  ref.onDispose(() {
    active = false;
    binding.dispose();
  });
});

class QishuiListeningBinding with WidgetsBindingObserver {
  QishuiListeningBinding(this.handler, this.reporter) {
    WidgetsBinding.instance.addObserver(this);
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _subscriptions.addAll([
      handler.playbackState.listen((state) => sample()),
      handler.mediaItem.listen((item) => sample()),
      handler.positionStream.listen((position) => sample()),
      handler.seekingStream.listen((seeking) => sample()),
      handler.completedTrackStream.listen((track) => _completed()),
      handler.nativeRepeatBoundaryStream.listen(
        (_) => _completed(repeat: true),
      ),
    ]);
    // The real monotonic counter settles eligibility at every state edge. A
    // low-frequency pulse exposes current hearing while playback is steady;
    // media position never determines how much time was actually heard.
    _pulse = Timer.periodic(const Duration(seconds: 1), (_) => sample());
    sample();
  }
  final MestingAudioHandler handler;
  final QishuiListeningReporter reporter;
  final List<StreamSubscription<Object?>> _subscriptions = [];
  Timer? _pulse;
  bool _disposed = false, _foreground = true;

  void sample() {
    if (_disposed) return;
    final state = handler.playbackState.value;
    final item = handler.mediaItem.value;
    reporter.update(
      track: item == null ? null : handler.trackForId(item.id),
      playing: state.playing,
      ready: state.processingState == AudioProcessingState.ready,
      seeking: handler.isSeeking,
      speed: state.speed,
      position: handler.currentPosition,
      duration: item?.duration,
      foreground: _foreground,
    );
  }

  void _completed({bool repeat = false}) {
    if (_disposed) return;
    // finish settles synchronously before its asynchronous network tail. The
    // next actual source/repeat event decides whether counting can resume.
    unawaited(reporter.finish(reason: 'finished'));
    if (repeat) sample();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    sample();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _pulse?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    reporter.dispose();
  }
}
