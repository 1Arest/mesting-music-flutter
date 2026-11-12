import '../../shared/models/track.dart';

/// Exact title/version, artist and measured duration must agree. Similar titles
/// alone never collapse live takes, covers, remasters or unrelated recordings.
List<List<Track>> duplicateRecordings(List<Track> tracks) {
  String text(String v) => v
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), '')
      .replaceAll('（', '(')
      .replaceAll('）', ')');
  final groups = <List<Track>>[];
  for (final t in tracks) {
    final existing = groups.where((g) {
      final a = g.first;
      return a.id == t.id ||
          a.title.trim().isNotEmpty &&
              a.artist.trim().isNotEmpty &&
              text(a.title) == text(t.title) &&
              text(a.artist) == text(t.artist) &&
              a.duration > Duration.zero &&
              t.duration > Duration.zero &&
              (a.duration - t.duration).inMilliseconds.abs() <= 2000;
    }).firstOrNull;
    if (existing == null) {
      groups.add([t]);
    } else {
      existing.add(t);
    }
  }
  return groups.where((g) => g.length > 1).toList();
}

/// Only explicit catalogue restrictions already attached to an unplayable
/// recording are surfaced. Empty unresolved URLs, previews, login changes and
/// transient network errors are not evidence of an unavailable recording.
bool hasRecordedRestriction(Track track) {
  if (track.isPlayable || track.source == TrackSource.local) return false;
  final reason = track.availabilityMessage;
  if (RegExp(r'网络|超时|登录|账号已变化|获取播放地址|联网').hasMatch(reason)) return false;
  return RegExp(r'下架|版权限制|地区.*限制|购买或会员权限|无播放权限|歌曲不存在').hasMatch(reason);
}
