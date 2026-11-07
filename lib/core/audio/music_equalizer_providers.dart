import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../persistence/app_preferences.dart';
import 'music_equalizer.dart';
import 'playback_providers.dart';

final musicEqualizerBridgeProvider = Provider<MusicEqualizerBridge>(
  (ref) => AndroidMusicEqualizerBridge(),
);
final musicEqualizerProvider = Provider<MusicEqualizerController>((ref) {
  final handler = ref.watch(audioHandlerProvider);
  final controller = MusicEqualizerController(
    bridge: ref.watch(musicEqualizerBridgeProvider),
    preferences: ref.watch(sharedPreferencesProvider),
    sessions: handler.androidAudioSessionIdStream,
    currentSession: handler.androidAudioSessionId,
  );
  ref.onDispose(controller.dispose);
  return controller;
});
