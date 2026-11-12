import 'netease_features_repository.dart';

/// Presentation only: repositories, permissions and destinations stay owned
/// by their existing workflows. Every catalogue category has exactly one home;
/// unknown future categories remain reachable in the extension section.
enum NeteaseLibrarySection { common, collections, history, playlists, other }

const neteaseLibraryCategorySections = <String, NeteaseLibrarySection>{
  '音乐云盘': NeteaseLibrarySection.common,
  '已购音乐': NeteaseLibrarySection.common,
  '历史与听歌报告': NeteaseLibrarySection.history,
  '歌单与收藏': NeteaseLibrarySection.playlists,
  '资料与收藏概览': NeteaseLibrarySection.playlists,
};

NeteaseLibrarySection neteaseLibrarySectionFor(String category) =>
    neteaseLibraryCategorySections[category] ?? NeteaseLibrarySection.other;

const neteaseLibrarySectionFeeds = <NeteaseLibrarySection, List<NeteaseFeed>>{
  NeteaseLibrarySection.common: [],
  NeteaseLibrarySection.collections: [
    NeteaseFeed.likedAlbums,
    NeteaseFeed.likedArtists,
    NeteaseFeed.likedMvs,
    NeteaseFeed.subscribedPodcasts,
  ],
  NeteaseLibrarySection.history: [
    NeteaseFeed.recentSongs,
    NeteaseFeed.recentPlaylists,
    NeteaseFeed.recentAlbums,
    NeteaseFeed.week,
    NeteaseFeed.allTime,
  ],
  NeteaseLibrarySection.playlists: [],
  NeteaseLibrarySection.other: [],
};
