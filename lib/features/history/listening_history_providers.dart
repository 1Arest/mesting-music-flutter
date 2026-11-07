import 'dart:convert';
import 'package:flutter/foundation.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../../shared/models/track.dart';
import '../library/library_providers.dart';
import '../library/data/library_repository.dart';
import '../library/data/favorite_track_window.dart';
import '../../shared/models/track_page.dart';
import '../../core/platform/distribution_channel.dart';

class ListeningHistoryItem {
  const ListeningHistoryItem({
    required this.track,
    required this.completedPlayCount,
    required this.totalListened,
    required this.lastPlayedAt,
  });

  final Track track;
  final int completedPlayCount;
  final Duration totalListened;
  final DateTime lastPlayedAt;
}

final listeningRankingProvider = StreamProvider<List<ListeningHistoryItem>>((
  ref,
) {
  if (DistributionChannel.isBeta) return _historyStream(ref, true);
  final ownerId = ref.watch(activeLibraryOwnerProvider);
  return ref
      .watch(appDatabaseProvider)
      .watchListeningRanking(ownerId)
      .asyncMap(decodeListeningHistory);
});

final recentPlaybackProvider = StreamProvider<List<ListeningHistoryItem>>((
  ref,
) {
  if (DistributionChannel.isBeta) return _historyStream(ref, false);
  final ownerId = ref.watch(activeLibraryOwnerProvider);
  return ref
      .watch(appDatabaseProvider)
      .watchPlaybackHistory(ownerId)
      .asyncMap(decodeListeningHistory);
});

/// Reuse the same source-cursor/window lifecycle as cloud collections. Full
/// daily facts for Replay are independent; browsing never truncates totals.
class _HistoryRepository extends LibraryRepository {
  _HistoryRepository(this.db, String owner, this.ranking)
    : super(db, ownerId: owner);
  final AppDatabase db;
  final bool ranking;
  final details = <String, ListeningHistoryItem>{};
  Future<TrackPage> _decodePage(List<PlaybackHistory> rows, int offset) async {
    final values = await decodeListeningHistory(rows);
    final count = await db.playbackHistoryCount(ownerId);
    for (final value in values) {
      details[value.track.id] = value;
    }
    return TrackPage(
      values.map((item) => item.track).toList(),
      offset: offset,
      nextOffset: offset + rows.length,
      total: count,
      hasMore: offset + rows.length < count,
    );
  }

  @override
  Stream<TrackPage> watchFavoritePreview() => db
      .watchPlaybackHistoryPreview(ownerId, ranking: ranking)
      .asyncMap((rows) => _decodePage(rows, 0));
  @override
  Future<TrackPage> favoritePage({
    int offset = 0,
    int limit = 30,
    String query = '',
  }) async => _decodePage(
    await db.playbackHistoryPage(
      ownerId,
      ranking: ranking,
      offset: offset,
      limit: limit,
    ),
    offset,
  );
}

final historyTrackWindowProvider = Provider.autoDispose
    .family<FavoriteTrackWindow, bool>((ref, ranking) {
      final repository = _HistoryRepository(
        ref.watch(appDatabaseProvider),
        ref.watch(activeLibraryOwnerProvider),
        ranking,
      );
      final window = FavoriteTrackWindow(repository);
      ref.onDispose(window.dispose);
      return window;
    });

Stream<List<ListeningHistoryItem>> _historyStream(Ref ref, bool ranking) {
  final window = ref.watch(historyTrackWindowProvider(ranking));
  final repository = window.repository as _HistoryRepository;
  return window.stream.map(
    (tracks) => [for (final track in tracks) repository.details[track.id]!],
  );
}

Future<List<ListeningHistoryItem>> decodeListeningHistory(
  List<PlaybackHistory> rows,
) => rows.length < 100
    ? Future.value(_decodeHistory(rows))
    : compute(_decodeHistory, rows, debugLabel: 'listening-history');

List<ListeningHistoryItem> _decodeHistory(Iterable<PlaybackHistory> rows) {
  final result = <ListeningHistoryItem>[];
  for (final row in rows) {
    try {
      final snapshot = jsonDecode(row.trackSnapshot);
      if (snapshot is! Map<String, dynamic>) continue;
      result.add(
        ListeningHistoryItem(
          track: Track.fromJson(snapshot.cast<String, Object?>()),
          completedPlayCount: row.completedPlayCount,
          totalListened: Duration(milliseconds: row.totalPlayedMs),
          lastPlayedAt: row.lastPlayedAt,
        ),
      );
    } on Object {
      // Keep one obsolete snapshot from hiding the rest of the history.
    }
  }
  return List<ListeningHistoryItem>.unmodifiable(result);
}
