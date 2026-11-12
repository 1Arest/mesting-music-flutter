/// Search-only catalogue/permission evidence. Never stores URLs, credentials,
/// or audio in a Track, and never equates a VIP price flag with trial playback.
enum SearchRecordingKind { unknown, original, cover, rework }

enum SearchPlaybackAccess { unknown, full, preview, restricted }

/// Relative to the work identified by this query, not a catalogue's generic
/// "original composition" flag. Unrelated songs can share a title legitimately.
enum SearchWorkRelation { unknown, original, version, other }

class SongSearchFacts {
  const SongSearchFacts({
    this.kind = SearchRecordingKind.unknown,
    this.access = SearchPlaybackAccess.unknown,
    this.membership = false,
    this.originalArtists = const [],
    this.originalTitle = '',
    this.accessLabel = '',
    this.originalWorkId = '',
    this.originalAlbum = '',
    this.workRelation = SearchWorkRelation.unknown,
  });
  final SearchRecordingKind kind;
  final SearchPlaybackAccess access;
  final bool membership;
  final List<String> originalArtists;
  final String originalTitle, accessLabel;
  final String originalWorkId, originalAlbum;
  final SearchWorkRelation workRelation;
  SongSearchFacts withAccess(SearchPlaybackAccess value, {String label = ''}) =>
      SongSearchFacts(
        kind: kind,
        access: value,
        membership: membership,
        originalArtists: originalArtists,
        originalTitle: originalTitle,
        accessLabel: label,
        originalWorkId: originalWorkId,
        originalAlbum: originalAlbum,
        workRelation: workRelation,
      );
  SongSearchFacts withWork(SearchWorkRelation value) => SongSearchFacts(
    kind: kind,
    access: access,
    membership: membership,
    originalArtists: originalArtists,
    originalTitle: originalTitle,
    accessLabel: accessLabel,
    originalWorkId: originalWorkId,
    originalAlbum: originalAlbum,
    workRelation: value,
  );
  String get label => [
    if (workRelation == SearchWorkRelation.original) '原唱',
    if (workRelation == SearchWorkRelation.other) '其他同名结果',
    if (workRelation != SearchWorkRelation.other &&
        kind == SearchRecordingKind.cover)
      '翻唱',
    if (workRelation != SearchWorkRelation.other &&
        kind == SearchRecordingKind.rework)
      '改编',
    if (accessLabel.isNotEmpty)
      accessLabel
    else
      switch (access) {
        SearchPlaybackAccess.full => '完整版',
        SearchPlaybackAccess.preview => '试听',
        SearchPlaybackAccess.restricted => '播放受限',
        SearchPlaybackAccess.unknown => membership ? '会员歌曲' : '',
      },
  ].where((part) => part.isNotEmpty).join(' · ');
}
