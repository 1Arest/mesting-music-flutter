import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/persistence/app_preferences.dart';
import '../../shared/models/track.dart';
import 'domain/platform_audio_quality.dart';

/// Defaults are scoped to the recording's source, independent of the current
/// library tab. A manual current-song switch remains a separate strict action.
class DefaultPlaybackQuality extends Notifier<Map<TrackSource, String>> {
  static String key(TrackSource source) =>
      'default_playback_quality_193_${source.name}';
  @override
  Map<TrackSource, String> build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return {
      for (final source in supported)
        source: prefs.getString(key(source)) ?? 'auto',
    };
  }

  static const supported = [
    TrackSource.netease,
    TrackSource.kugou,
    TrackSource.qishui,
  ];
  Future<void> select(TrackSource source, String value) async {
    if (!supported.contains(source) ||
        (value != 'auto' && !options(source).any((q) => q.code == value))) {
      return;
    }
    if (!await ref
        .read(sharedPreferencesProvider)
        .setString(key(source), value)) {
      throw StateError('音质偏好未保存');
    }
    state = {...state, source: value};
  }

  static List<PlatformAudioQuality> options(TrackSource source) =>
      source == TrackSource.netease
      ? PlatformAudioQuality.neteaseOrder
      : source == TrackSource.qishui
      ? [PlatformAudioQuality.standard, PlatformAudioQuality.high]
      : PlatformAudioQuality.values.take(4).toList();
}

final defaultPlaybackQualityProvider =
    NotifierProvider<DefaultPlaybackQuality, Map<TrackSource, String>>(
      DefaultPlaybackQuality.new,
    );

PlatformAudioQuality preferredPlaybackQuality(
  Map<TrackSource, String> settings,
  TrackSource source,
) {
  final value = settings[source] ?? 'auto';
  return PlatformAudioQuality.fromCode(value) ??
      (source == TrackSource.netease
          ? PlatformAudioQuality.vivid
          : PlatformAudioQuality.hiRes);
}
