import '../../../shared/models/track.dart';
import '../../../shared/models/song_search_facts.dart';

/// Version words are evidence only in the recording title, never the artist.
/// A missing catalogue flag is Unknown, not proof of an original recording.
enum SongVersionFilter { all, original, live, cover, instrumental, unknown }

extension SongVersionLabel on SongVersionFilter {
  String get label => switch (this) {
    SongVersionFilter.all => '全部版本',
    SongVersionFilter.original => '原版',
    SongVersionFilter.live => '现场',
    SongVersionFilter.cover => '翻唱',
    SongVersionFilter.instrumental => '伴奏',
    SongVersionFilter.unknown => '版本未知',
  };
}

SongVersionFilter recordingVersion(Track track, SongSearchFacts? facts) {
  final title = track.title.toLowerCase();
  bool versionTag(String words) => RegExp(
    r'[（(\[【][^）)\]】]*(?:' + words + r')[^）)\]】]*[）)\]】]',
    caseSensitive: false,
  ).hasMatch(title);
  if (versionTag(r'伴奏|纯音乐|instrumental|karaoke|off vocal') ||
      RegExp(r'伴奏版$|纯音乐版$').hasMatch(title)) {
    return SongVersionFilter.instrumental;
  }
  if (versionTag(r'\blive\b|现场|演唱会') ||
      RegExp(r'(?:\s|[-·])live(?:\s|$)|现场版$|演唱会版$').hasMatch(title)) {
    return SongVersionFilter.live;
  }
  if (facts?.kind == SearchRecordingKind.cover ||
      versionTag(r'翻唱|\bcover\b') ||
      title.endsWith('翻唱版')) {
    return SongVersionFilter.cover;
  }
  if (facts?.workRelation == SearchWorkRelation.original) {
    return SongVersionFilter.original;
  }
  return SongVersionFilter.unknown;
}
