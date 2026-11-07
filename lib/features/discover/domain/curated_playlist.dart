enum CuratedPlaylistCategory { featured, treasure, editor, explore }

enum CuratedPlaylistLanguage { chinese, foreign }

class CuratedPlaylist {
  const CuratedPlaylist({
    required this.id,
    required this.name,
    required this.coverAsset,
    required this.onlineQuery,
    required this.category,
    this.language = CuratedPlaylistLanguage.chinese,
  });

  final String id;
  final String name;
  final String coverAsset;
  final String onlineQuery;
  final CuratedPlaylistCategory category;
  final CuratedPlaylistLanguage language;

  String get languageLabel => switch (language) {
    CuratedPlaylistLanguage.chinese => '纯国语',
    CuratedPlaylistLanguage.foreign => '纯外语',
  };
}
