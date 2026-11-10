import '../../../shared/models/song_search_facts.dart';
import '../../../shared/models/track.dart';
import 'song_search_ranking.dart' show searchText;

String _base(String title) => searchText(title).split('(').first;
String _artists(Iterable<String> names) {
  final parts =
      names
          .expand((name) => name.split(RegExp(r'[/、&,，]')))
          .map(searchText)
          .where((name) => name.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
  return parts.join('/');
}

/// A catalogue's explicit cover -> original association describes a work.
/// Its generic "original composition" flag does not identify the work intended
/// by a title-only query: several unrelated compositions can share that title.
class _Work {
  _Work(this.id, this.title, this.artists);
  final String id, title;
  final List<String> artists;
  final supporters = <String>{};
  String get identity => '${searchText(title)}|${_artists(artists)}';

  bool matchesQuery(String query) {
    final q = searchText(query), name = searchText(title);
    return name.isNotEmpty &&
        (q == name ||
            q.contains(name) && artists.any((a) => q.contains(searchText(a))));
  }

  bool get hasArtists => _artists(artists).isNotEmpty;
  bool sameArtist(Track track) => _artists([track.artist]) == _artists(artists);
  bool direct(Track track) =>
      id.isNotEmpty &&
      track.source == TrackSource.netease &&
      track.id == 'netease_$id';
}

/// Resolve one intended work before comparing recording or playback rights.
/// Votes come only from explicit upstream links, deduplicated by recording ID.
/// An explicit artist in the query overrides title-only support. Tied evidence
/// remains unknown; no famous-song table, popularity or artist alias is used.
Map<String, SongSearchFacts> identifySearchWork(
  List<Track> tracks,
  Map<String, SongSearchFacts> facts,
  String query,
) {
  final works = <String, _Work>{};
  for (final track in tracks) {
    final f = facts[track.id] ?? const SongSearchFacts();
    if (f.originalTitle.isEmpty || f.originalArtists.isEmpty) continue;
    final work = _Work(f.originalWorkId, f.originalTitle, f.originalArtists);
    if (!work.hasArtists || !work.matchesQuery(query)) continue;
    final key = work.id.isNotEmpty ? 'netease:${work.id}' : work.identity;
    (works[key] ??= work).supporters.add(track.id);
  }
  // When the user names the actual artist, a catalogue original-composition
  // flag can establish that artist's own work, even without any cover rows.
  for (final track in tracks) {
    final f = facts[track.id] ?? const SongSearchFacts();
    final q = searchText(query),
        name = searchText(track.title),
        artist = searchText(track.artist);
    if (f.kind != SearchRecordingKind.original ||
        name.isEmpty ||
        artist.isEmpty ||
        q == name ||
        !q.contains(name) ||
        !q.contains(artist)) {
      continue;
    }
    final work = _Work('', track.title, [track.artist]);
    if (!works.values.any((w) => w.identity == work.identity)) {
      works[work.identity] = work;
    }
  }
  final candidates = works.values.toList();
  int artistMatch(_Work w) => searchText(query) == searchText(w.title)
      ? 0
      : (w.artists.any((a) => searchText(query).contains(searchText(a)))
            ? 1
            : 0);
  candidates.sort((a, b) {
    final explicit = artistMatch(b).compareTo(artistMatch(a));
    return explicit != 0
        ? explicit
        : b.supporters.length.compareTo(a.supporters.length);
  });
  final target =
      candidates.isEmpty ||
          candidates.length > 1 &&
              artistMatch(candidates[0]) == artistMatch(candidates[1]) &&
              candidates[0].supporters.length == candidates[1].supporters.length
      ? null
      : candidates.first;

  return {
    for (final track in tracks)
      track.id: (() {
        final f = facts[track.id] ?? const SongSearchFacts();
        // Recompute from raw metadata on every cumulative page. A previous
        // query/page's inference must never become new authorship evidence.
        if (target == null) return f.withWork(SearchWorkRelation.unknown);
        final linked =
            f.originalTitle.isNotEmpty &&
            (target.id.isNotEmpty && f.originalWorkId == target.id ||
                searchText(f.originalTitle) == searchText(target.title) &&
                    _artists(f.originalArtists) == _artists(target.artists));
        if (target.direct(track) ||
            target.sameArtist(track) &&
                searchText(track.title) == searchText(target.title) &&
                f.kind != SearchRecordingKind.cover &&
                f.kind != SearchRecordingKind.rework) {
          return f.withWork(SearchWorkRelation.original);
        }
        if (linked ||
            target.sameArtist(track) &&
                _base(track.title) == _base(target.title)) {
          return f.withWork(SearchWorkRelation.version);
        }
        return f.withWork(
          _base(track.title) == _base(target.title)
              ? SearchWorkRelation.other
              : SearchWorkRelation.unknown,
        );
      })(),
  };
}
