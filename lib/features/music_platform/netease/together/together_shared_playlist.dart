import '../../../../shared/models/track.dart';
import '../netease_music_repository.dart';

/// The shared playback snapshot is also a command source. Room status/check
/// and heartbeat replies may contain no command at all (observed on device),
/// so this read must not be restricted to entering/resuming a page.
class TogetherSharedPlaylist {
  TogetherSharedPlaylist(Map<String, dynamic> data) {
    final playlist = NeteaseMusicRepository.object(data['playlist']);
    final display = playlist['displayList'];
    final raw = display is List
        ? display
        : NeteaseMusicRepository.object(display)['result'];
    // Retain the existing bounded song-detail contract. The command envelope
    // is parsed separately by TogetherPlaybackCommand and never inferred here.
    ids = List.unmodifiable(
      (raw is List ? raw : const [])
          .map((id) => '$id')
          .where((id) => RegExp(r'^\d+$').hasMatch(id))
          .take(500),
    );
  }
  late final List<String> ids;

  /// Reuse metadata even when the authoritative queue is reordered. Repeated
  /// five-second reads should not fetch hundreds of identical song records.
  /// Missing metadata is explicit; a partial cache cannot stand in for a queue.
  List<Track>? reuse(List<Track> tracks) {
    final byId = {for (final track in tracks) track.platformSongId: track};
    if (ids.isEmpty || ids.any((id) => !byId.containsKey(id))) return null;
    return [for (final id in ids) byId[id]!];
  }
}
