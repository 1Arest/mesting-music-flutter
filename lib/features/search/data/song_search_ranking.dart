import '../../../shared/models/track.dart';
import '../../../shared/models/song_search_facts.dart';

String searchText(String value) => value
    .toLowerCase()
    .replaceAll('（', '(')
    .replaceAll('）', ')')
    .replaceAll(RegExp(r'\s+'), '');
String _title(String value) => searchText(value).split('(').first;

int sourceAccessRank(SongSearchFacts facts) => switch (facts.access) {
  SearchPlaybackAccess.full => 0,
  SearchPlaybackAccess.preview => 1,
  SearchPlaybackAccess.unknown => 2,
  SearchPlaybackAccess.restricted => 3,
};
int recordingRank(SongSearchFacts facts) => switch (facts.workRelation) {
  SearchWorkRelation.original => 0,
  SearchWorkRelation.version => 1,
  SearchWorkRelation.unknown => 2,
  SearchWorkRelation.other => 2,
};

/// Compare ordinary candidates after the intended work has been resolved.
/// A generic composition flag cannot promote an unrelated same-title work.
int songQueryRelevance(Track track, String query) {
  if (query.isEmpty) return 0;
  final q = searchText(query), title = _title(track.title);
  if (q == searchText(track.title)) {
    return 0;
  }
  final version = searchText(track.title).substring(title.length);
  if (version.isNotEmpty &&
      RegExp(r'live|演唱会|现场|伴奏|钢琴|女声|男声|dj|remix|翻唱').hasMatch(version) &&
      !q.contains(version)) {
    return q == title ? 1 : 2;
  }
  if (title.isNotEmpty &&
      (q == title ||
          q.contains(title) && q.contains(searchText(track.artist)))) {
    return 0;
  }
  return title.contains(q) || q.contains(title) && title.isNotEmpty ? 1 : 2;
}
