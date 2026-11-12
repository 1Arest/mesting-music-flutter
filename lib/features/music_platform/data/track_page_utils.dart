import '../../../shared/models/track.dart';
import '../../../shared/models/track_page.dart';
import 'package:flutter/foundation.dart';

TrackPage _searchSlice((List<Track>, int, int, String) request) =>
    sliceTrackPage(
      request.$1,
      offset: request.$2,
      limit: request.$3,
      query: request.$4,
    );

Future<TrackPage> sliceTrackPageAsync(
  List<Track> tracks, {
  int offset = 0,
  int limit = 30,
  String query = '',
}) => query.trim().isNotEmpty && tracks.length >= 100
    ? compute(_searchSlice, (
        tracks,
        offset,
        limit,
        query,
      ), debugLabel: 'collection-search')
    : Future.value(
        sliceTrackPage(tracks, offset: offset, limit: limit, query: query),
      );

/// Fixed-response protocols can still publish bounded rows. Their full result
/// is fetched once by the repository, never disguised as server pagination.
TrackPage sliceTrackPage(
  List<Track> tracks, {
  int offset = 0,
  int limit = 30,
  String query = '',
}) {
  final words = query.trim().toLowerCase().split(RegExp(r'\s+'));
  final matching = query.trim().isEmpty
      ? tracks
      : tracks
            .where((track) {
              final searchable = '${track.title} ${track.artist} ${track.album}'
                  .toLowerCase();
              return words.every(searchable.contains);
            })
            .toList(growable: false);
  final start = offset.clamp(0, matching.length);
  final end = (start + limit.clamp(1, 500)).clamp(start, matching.length);
  return TrackPage(
    matching.sublist(start, end),
    offset: start,
    nextOffset: end,
    total: matching.length,
    hasMore: end < matching.length,
  );
}
