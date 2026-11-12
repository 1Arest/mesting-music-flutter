import '../../shared/models/track.dart';
import '../music_platform/data/music_platform_api.dart';
import '../music_platform/domain/platform_audio_quality.dart';
import '../music_platform/netease/netease_fallback.dart';
import '../music_platform/netease/netease_music_repository.dart';
import '../music_platform/netease/netease_track_sources.dart';
import 'package:http/http.dart' as http;

/// A durable queue state, not an automatic fallback request. UI coordinators
/// and the download manager communicate through this typed outcome only.
class DownloadSourceSelectionRequired implements Exception {
  const DownloadSourceSelectionRequired([this.reason = '此音源暂时无法下载所选音质的完整版']);
  final String reason;
  @override
  String toString() => '$reason，请选择其他下载音源';
}

typedef OfficialDownloadLookup =
    Future<Track?> Function(Track track, PlatformAudioQuality quality);
typedef AlternativeDownloadLookup =
    Future<Track?> Function(
      Track track,
      PlatformAudioQuality quality,
      NeteaseTrackSource source,
    );

/// Playback source preferences deliberately do not appear in this contract.
/// A new task tries official only. The sole route to a third-party request is
/// an explicit choice made after the official attempt has failed.
Future<Track> resolveNeteaseDownload({
  required Track track,
  required PlatformAudioQuality quality,
  required OfficialDownloadLookup official,
  required AlternativeDownloadLookup alternative,
  required bool Function() current,
  NeteaseTrackSource? selectedSource,
  bool requireQuality = true,
  bool allowAlternative = true,
}) async {
  Track? media;
  try {
    media =
        selectedSource == null || selectedSource == NeteaseTrackSource.official
        ? await official(track, quality)
        : selectedSource != NeteaseTrackSource.automatic
        ? await alternative(track, quality, selectedSource)
        : null;
  } catch (error) {
    // A login/security rejection must remain visible rather than turning into
    // an anonymous download prompt for an invalidated platform session.
    if (error is MusicPlatformException &&
        {'301', '302', '415', '405', '460'}.contains(error.code)) {
      rethrow;
    }
  }
  if (!current()) throw const MusicPlatformException('下载已取消或账号已变化');
  if (media != null &&
      media.isPlayable &&
      !media.isPreview &&
      (!requireQuality || media.playbackQuality == quality.code)) {
    return media;
  }
  if (allowAlternative) throw const DownloadSourceSelectionRequired();
  throw const MusicPlatformException('网易云官方未提供所选音质的完整下载音频，备用音源已关闭');
}

/// Official download resolution is shared by queue execution and tests. The
/// download entitlement endpoint owns this path; playback/preview URLs cannot
/// satisfy it merely because they were already present on the incoming Track.
Future<Track?> lookupOfficialNeteaseDownload(
  NeteaseMusicRepository music,
  Track track,
  PlatformAudioQuality quality, {
  required http.Client client,
  Future<void>? abortTrigger,
}) async {
  final payload = await music.call('/song/download/url/v1', {
    'id': NeteaseMusicRepository.songId(track.id),
    'level': quality.neteaseLevel,
  }, abortTrigger);
  final raw = payload['data'];
  final row = NeteaseMusicRepository.object(
    raw is List && raw.isNotEmpty ? raw.first : raw,
  );
  final url = '${row['url'] ?? ''}';
  if (row['freeTrialInfo'] != null || !url.startsWith('http')) return null;
  final deliveredMs = int.tryParse('${row['time']}') ?? 0;
  if (deliveredMs > 0 &&
      deliveredMs <= 90000 &&
      track.duration.inMilliseconds > deliveredMs + 2000) {
    return null;
  }
  final id = NeteaseMusicRepository.songId(track.id);
  if (row['id'] != null && '${row['id']}' != id) return null;
  final measured = await inspectNeteaseAudio(
    client,
    url,
    expectedDuration: track.duration,
    abortTrigger: abortTrigger,
    requireLossless:
        quality == PlatformAudioQuality.lossless ||
        quality == PlatformAudioQuality.hiRes,
  );
  if (!measured.playable) return null;
  return track.copyWith(
    audioAsset: url,
    audioHeaders: const {},
    isPreview: false,
    audioOrigin: AudioOrigin(AudioOrigin.netease, track.id),
    playbackQuality:
        PlatformAudioQuality.fromNeteaseLevel(row['level'])?.code ?? '',
    audioBitrate: measured.bitrate > 0
        ? measured.bitrate
        : int.tryParse('${row['br']}') ?? 0,
  );
}
