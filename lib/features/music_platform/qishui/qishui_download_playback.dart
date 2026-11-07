import '../../../shared/models/track.dart';
import '../../downloads/audio_downloads.dart';
import 'qishui_api.dart';

/// Published downloads and temporary playback cache have different lifetimes.
/// A completed current-owner download can play offline. A restored temporary
/// file must go through the official account/media checks again. The caller
/// supplies the existing download snapshot and resolver; no new worker, store,
/// player or network client is created here.
Future<Track> resolveQishuiPlaybackSource({
  required Track track,
  required String owner,
  required List<AudioDownloadTask> downloads,
  required Future<Track> Function() official,
  bool restoringDownloads = false,
}) async {
  final uri = Uri.tryParse(track.audioAsset);
  final publishedLocal =
      track.source == TrackSource.qishui &&
      uri != null &&
      (uri.scheme == 'content' ||
          uri.scheme == 'file' &&
              !uri.pathSegments.contains('qishui_official_audio'));
  if (publishedLocal) {
    if (restoringDownloads) {
      throw const QishuiException('正在恢复汽水下载记录，请稍后重试');
    }
    for (final saved in downloads) {
      if (saved.owner == owner &&
          saved.phase == AudioDownloadPhase.completed &&
          saved.track.source == TrackSource.qishui &&
          saved.track.id == track.id &&
          saved.track.platformSongId == track.platformSongId &&
          saved.uri == track.audioAsset) {
        return downloadedPlaybackTrack(saved);
      }
    }
  }
  // An unmatched local URI never becomes an unverified playback bypass. It
  // may resolve the same recording afresh for the current official account.
  return official();
}
