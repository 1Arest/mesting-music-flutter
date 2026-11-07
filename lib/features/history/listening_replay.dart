import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/database/app_database.dart';
import '../../shared/models/track.dart';
import '../library/library_providers.dart';

/// One owner-bound stream also invalidates immediately when accounts switch.
final playbackDaysProvider = StreamProvider<List<PlaybackDailyHistory>>(
  (ref) => ref
      .watch(appDatabaseProvider)
      .watchPlaybackDays(ref.watch(activeLibraryOwnerProvider))
      .asyncMap(preparePlaybackDays),
);

final _replayCache = Expando<Map<(int, int?), ListeningReplay>>(
  'listening-replay',
);

/// Build complete monthly/yearly aggregates once for a new immutable snapshot.
/// Calendar taps and unrelated player rebuilds then do constant-time lookups.
Map<(int, int?), ListeningReplay> _prepareReplays(
  List<PlaybackDailyHistory> days,
) {
  final periods = <(int, int?)>{};
  for (final day in days) {
    final date = DateTime.tryParse(day.dayKey);
    if (date != null) {
      periods.add((date.year, null));
      periods.add((date.year, date.month));
    }
  }
  return {
    for (final period in periods)
      period: ListeningReplay._aggregate(days, period.$1, period.$2),
  };
}

Future<List<PlaybackDailyHistory>> preparePlaybackDays(
  List<PlaybackDailyHistory> rows,
) async {
  final snapshot = List<PlaybackDailyHistory>.unmodifiable(rows);
  final cache = rows.length < 100
      ? _prepareReplays(snapshot)
      : await compute(
          _prepareReplays,
          snapshot,
          debugLabel: 'listening-replay',
        );
  _replayCache[snapshot] = cache;
  return snapshot;
}

/// Calendar availability is independent of listening totals. A future month
/// must never become selectable simply because the UI renders a whole year.
List<int?> replayMonthsForYear(int year, DateTime today) => [
  null,
  if (year <= today.year)
    ...List.generate(year == today.year ? today.month : 12, (i) => i + 1),
];

class ReplayTrack {
  const ReplayTrack(this.track, this.milliseconds, this.plays);
  final Track track;
  final int milliseconds;
  final int plays;
}

class ReplayArtist {
  const ReplayArtist(this.name, this.cover, this.milliseconds);
  final String name;
  final String cover;
  final int milliseconds;
}

class ListeningReplay {
  const ListeningReplay(this.milliseconds, this.tracks, this.artists);
  final int milliseconds;
  final List<ReplayTrack> tracks;
  final List<ReplayArtist> artists;

  /// Uses local calendar keys written at listening time. Legacy cumulative
  /// totals are never redistributed into invented past months.
  factory ListeningReplay.fromDays(
    List<PlaybackDailyHistory> days,
    int year,
    int? month,
  ) {
    final cache = _replayCache[days] ??= {};
    return cache[(year, month)] ??= ListeningReplay._aggregate(
      days,
      year,
      month,
    );
  }

  static ListeningReplay _aggregate(
    List<PlaybackDailyHistory> days,
    int year,
    int? month,
  ) {
    final prefix = month == null
        ? '$year-'
        : '$year-${month.toString().padLeft(2, '0')}-';
    final byTrack = <String, ReplayTrack>{};
    var total = 0;
    for (final day in days) {
      if (!day.dayKey.startsWith(prefix)) continue;
      final duration = day.totalPlayedMs.clamp(0, 1 << 53);
      total += duration;
      try {
        final json = jsonDecode(day.trackSnapshot);
        if (json is! Map) continue;
        final track = Track.fromJson(json.cast<String, Object?>());
        final old = byTrack[track.id];
        byTrack[track.id] = ReplayTrack(
          track,
          (old?.milliseconds ?? 0) + duration,
          (old?.plays ?? 0) + day.playCount.clamp(0, 1 << 31),
        );
      } on Object {
        /* A retired snapshot must not hide the rest of the month. */
      }
    }
    final tracks = byTrack.values.toList()
      ..sort((a, b) {
        final duration = b.milliseconds.compareTo(a.milliseconds);
        return duration != 0 ? duration : b.plays.compareTo(a.plays);
      });
    final artists = <String, ReplayArtist>{};
    for (final item in tracks) {
      // Artist display strings can describe a collaboration. Keep that credit
      // intact rather than attributing the full duration to each participant.
      final name = item.track.artist.trim();
      if (name.isEmpty) continue;
      final old = artists[name];
      artists[name] = ReplayArtist(
        name,
        old?.cover ?? item.track.coverAsset,
        (old?.milliseconds ?? 0) + item.milliseconds,
      );
    }
    return ListeningReplay(
      total,
      tracks,
      artists.values.toList()
        ..sort((a, b) => b.milliseconds.compareTo(a.milliseconds)),
    );
  }
}
