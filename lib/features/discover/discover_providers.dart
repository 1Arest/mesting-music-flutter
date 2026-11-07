import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../search/data/music_search_repository.dart';
import '../search/search_providers.dart';
import 'data/curated_playlists.dart';
import 'domain/curated_playlist_tracks.dart';

final curatedPlaylistTracksProvider =
    FutureProvider.family<CuratedPlaylistTracks, String>((
      ref,
      playlistId,
    ) async {
      final playlist = curatedPlaylistForId(playlistId);
      if (playlist == null) {
        throw StateError('策划歌单不存在');
      }
      try {
        final result = await ref
            .watch(musicSearchRepositoryProvider)
            .search(playlist.onlineQuery, limit: 30, allowCache: false);
        final playableOnlineTracks = result.onlineTracks
            .where((track) => track.isPlayable)
            .toList(growable: false);
        if (playableOnlineTracks.isNotEmpty) {
          return CuratedPlaylistTracks(
            tracks: playableOnlineTracks,
            source: CuratedPlaylistTrackSource.online,
            warnings: result.warnings,
          );
        }
        return CuratedPlaylistTracks(
          tracks: const [],
          source: CuratedPlaylistTrackSource.unavailable,
          warnings: const <String>['在线曲库暂时没有返回可播放歌曲，请稍后重试'],
        );
      } on http.RequestAbortedException {
        rethrow;
      } on MusicSearchException {
        return CuratedPlaylistTracks(
          tracks: const [],
          source: CuratedPlaylistTrackSource.unavailable,
          warnings: const <String>['当前无法连接在线曲库，请检查网络后重试'],
        );
      } on Object {
        return CuratedPlaylistTracks(
          tracks: const [],
          source: CuratedPlaylistTrackSource.unavailable,
          warnings: const <String>['网络状态异常，暂时没有可显示的歌曲'],
        );
      }
    });
