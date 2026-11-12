import '../../../shared/models/track.dart';
import '../../search/data/fused_song_search.dart' show sameSearchRecording;
import 'platform_search_repository.dart';

/// Only public catalogue identity is reconstructed. A foreign audio origin
/// never borrows the original platform's numeric ID, URL, header or credential.
Track? actualSourceRecording(Track track) {
  final origin = track.audioOrigin;
  if (origin == null) return track;
  final source = origin.isKugou
      ? TrackSource.kugou
      : origin.isNetease
      ? TrackSource.netease
      : null;
  if (source == null) return null;
  var id = origin.recordingId;
  if (source == TrackSource.kugou &&
      RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(id)) {
    id = 'kugou_$id';
  }
  if (source == TrackSource.netease && RegExp(r'^[1-9][0-9]*$').hasMatch(id)) {
    id = 'netease_$id';
  }
  if (!id.startsWith('${source.name}_')) return null;
  if (id == track.id && source == track.source) return track;
  return Track(
    id: id,
    title: track.title,
    artist: track.artist,
    album: track.album,
    duration: track.duration,
    audioAsset: '',
    coverAsset: track.coverAsset,
    lyricsAsset: '',
    source: source,
    provider: source == TrackSource.kugou ? '酷狗' : '网易云',
  );
}

class LinkedMusicRecordings {
  const LinkedMusicRecordings(this.recordings, {this.warnings = const []});
  final List<Track> recordings;
  final List<String> warnings;
}

/// Match recordings conservatively, independently of current search page state.
/// History and a restored player therefore still find the correct counterpart.
/// Exact actual artist/title and measured duration are required across sources;
/// title-only matches and unknown-duration results never bind comment pools.
Future<LinkedMusicRecordings> linkMusicRecordings(
  Track track,
  Future<PlatformSearchRepository> Function(TrackSource) repository,
) async {
  final seed = actualSourceRecording(track);
  if (seed == null ||
      ![TrackSource.kugou, TrackSource.netease].contains(seed.source)) {
    return const LinkedMusicRecordings([]);
  }
  final tracks = <Track>[seed];
  if (sameSearchRecording(seed, track)) tracks.add(track);
  final other = seed.source == TrackSource.kugou
      ? TrackSource.netease
      : TrackSource.kugou;
  if (tracks.any((t) => t.source == other)) {
    return LinkedMusicRecordings(tracks);
  }
  if (seed.artist.trim().isEmpty || seed.duration <= Duration.zero) {
    return LinkedMusicRecordings(tracks);
  }
  try {
    final search = await repository(other).timeout(const Duration(seconds: 6));
    final page = await search
        .search('${seed.title} ${seed.artist}')
        .timeout(const Duration(seconds: 12));
    final matches = page.tracks.where(
      (candidate) => sameSearchRecording(seed, candidate),
    );
    if (matches.isNotEmpty) tracks.add(matches.first);
    return LinkedMusicRecordings(List.unmodifiable(tracks));
  } on Object {
    return LinkedMusicRecordings(
      List.unmodifiable(tracks),
      warnings: ['${other == TrackSource.kugou ? '酷狗' : '网易云'}对应资源暂时无法核对，可重试'],
    );
  }
}
