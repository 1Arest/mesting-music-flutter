import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/features/discover/data/curated_playlists.dart';
import 'package:mesting_music/features/discover/domain/curated_playlist.dart';

void main() {
  test('40 张策划歌单分类、ID 与封面资源完整', () {
    expect(curatedPlaylists, hasLength(40));
    expect(curatedPlaylistsFor(CuratedPlaylistCategory.featured), hasLength(6));
    expect(curatedPlaylistsFor(CuratedPlaylistCategory.treasure), hasLength(4));
    expect(curatedPlaylistsFor(CuratedPlaylistCategory.editor), hasLength(6));
    expect(curatedPlaylistsFor(CuratedPlaylistCategory.explore), hasLength(24));
    expect(
      curatedPlaylists.where(
        (playlist) => playlist.language == CuratedPlaylistLanguage.chinese,
      ),
      hasLength(28),
    );
    expect(
      curatedPlaylists.where(
        (playlist) => playlist.language == CuratedPlaylistLanguage.foreign,
      ),
      hasLength(12),
    );

    final ids = curatedPlaylists.map((playlist) => playlist.id).toSet();
    final covers = curatedPlaylists
        .map((playlist) => playlist.coverAsset)
        .toSet();
    expect(ids, hasLength(curatedPlaylists.length));
    expect(covers, hasLength(curatedPlaylists.length));
    for (final playlist in curatedPlaylists) {
      expect(playlist.name.trim(), isNotEmpty);
      expect(playlist.onlineQuery.trim(), isNotEmpty);
      expect(
        File(playlist.coverAsset).existsSync(),
        isTrue,
        reason: '缺少封面：${playlist.coverAsset}',
      );
      expect(curatedPlaylistForId(playlist.id), same(playlist));
    }
  });
}
