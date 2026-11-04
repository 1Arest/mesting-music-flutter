import 'package:flutter/foundation.dart';
import '../../../shared/models/track.dart';
import 'platform_catalog.dart';

/// The private collection protocol exposes collecttime but no reverse cursor.
/// Build one account-scoped snapshot on a worker, then page its details locally.
/// Equal/missing timestamps retain server order; never reverse each page.
class KugouFavoriteIndex {
  const KugouFavoriteIndex(this.tracks, this.fileIds);
  final List<Track> tracks;
  final Map<String, String> fileIds;
}

int _collectedAt(Object? value) {
  final numeric = num.tryParse('$value');
  if (numeric != null) {
    return (numeric < 100000000000 ? numeric * 1000 : numeric).round();
  }
  return DateTime.tryParse('$value')?.millisecondsSinceEpoch ?? 0;
}

KugouFavoriteIndex _buildIndex(List<Map<String, dynamic>> rows) {
  final ordered = rows.indexed.toList();
  ordered.sort((a, b) {
    final time = _collectedAt(
      b.$2['collecttime'],
    ).compareTo(_collectedAt(a.$2['collecttime']));
    return time == 0 ? a.$1.compareTo(b.$1) : time;
  });
  final tracks = <Track>[];
  final records = <String, String>{};
  final seen = <String>{};
  for (final entry in ordered) {
    final parsed = PlatformCatalog.tracks([entry.$2]);
    if (parsed.isEmpty || !seen.add(parsed.first.id)) continue;
    final track = parsed.first;
    tracks.add(track);
    if (entry.$2['fileid'] != null) {
      records[track.id] = '${entry.$2['fileid']}';
    }
  }
  return KugouFavoriteIndex(
    List.unmodifiable(tracks),
    Map.unmodifiable(records),
  );
}

Future<KugouFavoriteIndex> buildKugouFavoriteIndex(
  List<Map<String, dynamic>> rows,
) => rows.length < 100
    ? Future.value(_buildIndex(rows))
    : compute(_buildIndex, rows, debugLabel: 'kugou-favorite-index');
