import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/track.dart';
import 'mesting_audio_handler.dart';
import 'playback_mode.dart';
import '../../features/music_platform/platform_artwork_providers.dart';
import '../platform/distribution_channel.dart';

final audioHandlerProvider = Provider<MestingAudioHandler>((ref) {
  throw StateError('audioHandlerProvider 必须在应用启动时覆盖');
});

final playbackStateProvider = StreamProvider<PlaybackState>((ref) {
  return ref.watch(audioHandlerProvider).playbackState;
});

bool shouldAnimateVinyl(PlaybackState? state) {
  return state?.playing == true &&
      state?.processingState == AudioProcessingState.ready;
}

final currentMediaItemProvider = StreamProvider<MediaItem?>((ref) {
  return ref.watch(audioHandlerProvider).mediaItem;
});

/// audio_service MediaItem equality compares only the recording ID. Riverpod
/// therefore suppresses a same-song quality update unless we also observe an
/// event revision. This stream never subscribes to playback position ticks.
final currentMediaRevisionProvider = StreamProvider<int>((ref) {
  var revision = 0;
  return ref.watch(audioHandlerProvider).mediaItem.map((_) => ++revision);
});

final queueProvider = StreamProvider<List<MediaItem>>((ref) {
  return ref.watch(audioHandlerProvider).queue;
});

final upcomingQueueProvider = StreamProvider<List<MediaItem>>((ref) {
  return ref.watch(audioHandlerProvider).upcomingQueueStream;
});

final randomUpcomingProvider = StreamProvider<bool>(
  (ref) => ref.watch(audioHandlerProvider).randomUpcomingStream,
);

final positionProvider = StreamProvider<Duration>((ref) {
  return ref.watch(audioHandlerProvider).positionStream;
});

final durationProvider = StreamProvider<Duration?>((ref) {
  return ref.watch(audioHandlerProvider).durationStream;
});

final playbackModeProvider = StreamProvider<PlaybackMode>((ref) {
  return ref.watch(audioHandlerProvider).playbackModeStream;
});

final playbackOrderProvider = StreamProvider<PlaybackOrder>(
  (ref) => ref.watch(audioHandlerProvider).playbackOrderStream,
);

final currentTrackProvider = Provider<Track>((ref) {
  ref.watch(currentMediaRevisionProvider);
  final item = ref.watch(currentMediaItemProvider).value;
  final handler = ref.watch(audioHandlerProvider);
  final track =
      handler.trackForId(item?.id ?? '') ??
      Track(
        id: item?.id ?? 'empty_player',
        title: item?.title ?? '暂无播放',
        artist: item?.artist ?? '从在线曲库选择一首歌',
        album: item?.album ?? '',
        duration: item?.duration ?? Duration.zero,
        audioAsset: item?.extras?['audioAsset']?.toString() ?? '',
        coverAsset:
            item?.extras?['coverAsset']?.toString() ??
            item?.artUri?.toString() ??
            '',
        lyricsAsset: item?.extras?['lyricsAsset']?.toString() ?? '',
        coverAlternatives: publicArtworkAlternatives(
          item?.extras?['coverAlternatives'],
        ),
        platformSongId: item?.extras?['platformSongId']?.toString() ?? '',
        playbackQuality: item?.extras?['playbackQuality']?.toString() ?? '',
        audioOrigin: AudioOrigin.fromJson(item?.extras?['audioOrigin']),
        source: TrackSource.values.firstWhere(
          (source) => source.name == item?.extras?['source'],
          orElse: () => TrackSource.local,
        ),
      );
  if (DistributionChannel.isBeta &&
      track.source == TrackSource.kugou &&
      track.coverAsset.trim().isEmpty) {
    final cover = ref.watch(platformArtworkProvider(track)).value;
    if (cover?.isNotEmpty == true) return track.copyWith(coverAsset: cover);
  }
  return track;
});
