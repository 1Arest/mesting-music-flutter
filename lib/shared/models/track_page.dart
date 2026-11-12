import 'track.dart';

/// One ordered slice of a collection. The next offset counts source records,
/// including unavailable/duplicate rows, rather than painted widgets. Keeping
/// these separate prevents pagination from repeating or skipping source rows.
class TrackPage {
  const TrackPage(
    this.items, {
    required this.offset,
    required this.hasMore,
    this.total,
    int? nextOffset,
  }) : nextOffset = nextOffset ?? offset + items.length;

  final List<Track> items;
  final int offset, nextOffset;
  final int? total;
  final bool hasMore;
}
