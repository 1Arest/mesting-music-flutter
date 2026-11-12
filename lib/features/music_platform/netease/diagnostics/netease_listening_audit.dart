import 'dart:convert';
import '../../listening_sync/listening_sync_models.dart';

/// Small input DTO: database rows and track snapshots never enter the export
/// builder. The adapter decides which local records are NetEase song records.
class ListeningAuditDay {
  const ListeningAuditDay({
    required this.owner,
    required this.day,
    required this.songId,
    required this.milliseconds,
    required this.neteaseSong,
  });
  final String owner, day, songId;
  final int milliseconds;
  final bool neteaseSong;
}

String auditMonth(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}';
String _day(DateTime value) =>
    '${auditMonth(value)}-${value.day.toString().padLeft(2, '0')}';

/// Original event time is preferred to the date of a recovery attempt. The
/// selected source is exported, so older rows are not presented as exact starts.
(DateTime, String) _eventDate(ListeningSyncEntry entry) {
  DateTime? date(int value, {bool micros = false}) {
    if (value <= 0) return null;
    try {
      final result = micros
          ? DateTime.fromMicrosecondsSinceEpoch(value)
          : DateTime.fromMillisecondsSinceEpoch(value * 1000);
      return result.year >= 2000 && result.year <= 2200 ? result : null;
    } on Object {
      return null;
    }
  }

  final logged = date(entry.number('startlogtime'));
  if (logged != null) return (logged, 'startlogtime');
  final match = RegExp(r'^netease-play:(\d+):').firstMatch(entry.id);
  final original = match == null
      ? null
      : date(int.tryParse(match[1]!) ?? 0, micros: true);
  return original != null
      ? (original, 'event_timestamp')
      : (entry.createdAt, 'created_at_fallback');
}

int? _nonnegative(ListeningSyncEntry entry, String key) {
  final value = int.tryParse('${entry.payload[key]}');
  return value != null && value >= 0 && value <= 100 * 366 * 86400000
      ? value
      : null;
}

/// Read-only, owner-bound monthly evidence. Export is a strict whitelist of
/// counts, durations, calendar days and anonymous report-local song groups.
/// No arbitrary payload, title, URL, cookie, real event/song/account ID or exact
/// playback clock is copied. Generating it never sends or mutates any record.
class NeteaseListeningAudit {
  NeteaseListeningAudit._(this._owner, this.month, this.months, this.data);
  final String _owner, month;
  final List<String> months;
  final Map<String, Object?> data;
  bool belongsTo(String owner) => _owner == owner;
  String get json => const JsonEncoder.withIndent('  ').convert(data);
  Map<String, Object?> get local => data['local'] as Map<String, Object?>;
  Map<String, Object?> get duration =>
      data['durationEvents'] as Map<String, Object?>;
  Map<String, Object?> get starts =>
      data['startEvents'] as Map<String, Object?>;
  Map<String, Object?> get fields =>
      data['missingFields'] as Map<String, Object?>;

  static NeteaseListeningAudit build({
    required String owner,
    required String month,
    required Iterable<ListeningAuditDay> days,
    required Iterable<ListeningSyncEntry> entries,
    required DateTime now,
    int detailLimit = 5000,
  }) {
    if (!RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(month) ||
        detailLimit < 0 ||
        detailLimit > 10000) {
      throw ArgumentError('Invalid month or diagnostic detail limit');
    }
    final available = <String>{
      month,
      auditMonth(now),
      auditMonth(DateTime(now.year, now.month - 1)),
    };
    final localDays = <Map<String, Object?>>[];
    var localMs = 0, songMs = 0, localRows = 0;
    final groups = <String, String>{};
    String? group(String raw) {
      final id = raw.replaceFirst('netease_', '');
      if (!RegExp(r'^\d+$').hasMatch(id)) return null;
      return groups.putIfAbsent(id, () => 'song-${groups.length + 1}');
    }

    final scopedDays = days.where((d) => d.owner == owner).toList()
      ..sort((a, b) => a.day.compareTo(b.day));
    for (final day in scopedDays) {
      if (!RegExp(r'^\d{4}-(0[1-9]|1[0-2])-\d{2}$').hasMatch(day.day)) continue;
      available.add(day.day.substring(0, 7));
      if (!day.day.startsWith('$month-')) continue;
      localRows++;
      final ms = day.milliseconds.clamp(0, 100 * 366 * 86400000);
      localMs += ms;
      if (day.neteaseSong) songMs += ms;
      localDays.add({
        'day': day.day,
        'neteaseSong': day.neteaseSong,
        'songGroup': day.neteaseSong ? group(day.songId) : null,
        'actualMs': ms,
      });
    }
    final states = <String, Object?>{
      for (final state in ListeningSyncState.values)
        state.name: <String, Object?>{
          'events': 0,
          'knownActualMs': 0,
          'unknownActualEvents': 0,
        },
    };
    final detail = <Map<String, Object?>>[];
    var durationCount = 0,
        actualMs = 0,
        unknownActual = 0,
        startCount = 0,
        recent = 0;
    var missingReal = 0, missingStart = 0, missingMedia = 0, legacy = 0;
    var detailCount = 0;
    final seen = <String>{};
    final scoped =
        entries
            .where(
              (e) =>
                  e.ownerId == owner &&
                  {'netease-scrobble', 'netease-startplay'}.contains(e.kind),
            )
            .toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    for (final entry in scoped) {
      if (!seen.add(entry.id)) continue;
      final (date, source) = _eventDate(entry);
      available.add(auditMonth(date));
      if (auditMonth(date) != month) continue;
      final isDuration = entry.kind == 'netease-scrobble';
      final real = _nonnegative(entry, 'realtime'),
          media = _nonnegative(entry, 'time');
      final heard =
          _nonnegative(entry, 'heardMs') ?? (real == null ? null : real * 1000);
      final startMissing = source != 'startlogtime';
      if (isDuration) {
        durationCount++;
        if (heard == null) {
          unknownActual++;
        } else {
          actualMs += heard;
        }
        final state = states[entry.state.name] as Map<String, Object?>;
        state['events'] = (state['events'] as int) + 1;
        state['knownActualMs'] = (state['knownActualMs'] as int) + (heard ?? 0);
        state['unknownActualEvents'] =
            (state['unknownActualEvents'] as int) + (heard == null ? 1 : 0);
        if (real == null) missingReal++;
        if (media == null) missingMedia++;
        if (startMissing) missingStart++;
        if (entry.number('protocolVersion') < 2) legacy++;
      } else {
        startCount++;
        if (entry.payload['cloudConfirmed'] == true) recent++;
      }
      detailCount++;
      if (detail.length < detailLimit) {
        detail.add({
          'entry': 'entry-$detailCount',
          'kind': isDuration ? 'duration' : 'start',
          'day': _day(date),
          'dateSource': source,
          'songGroup': group(entry.text('id')),
          'state': entry.state.name,
          'actualMs': isDuration ? heard : null,
          'mediaSeconds': isDuration ? media : null,
          'realtimeSeconds': isDuration ? real : null,
          'missingStartlogtime': startMissing,
          'protocolV2': entry.number('protocolVersion') >= 2,
          'recentPlayConfirmed':
              !isDuration && entry.payload['cloudConfirmed'] == true,
        });
      }
    }
    final months = available.toList()..sort((a, b) => b.compareTo(a));
    final result = <String, Object?>{
      'schema': 'mesting-netease-monthly-audit-v1',
      'month': month,
      'generatedDay': _day(now),
      'readOnly': true,
      'cloudFootprintInclusionVerified': false,
      'local': <String, Object?>{
        'daySongRows': localRows,
        'allTracksActualMs': localMs,
        'neteaseSongsActualMs': songMs,
        'otherTracksActualMs': localMs - songMs,
      },
      'durationEvents': <String, Object?>{
        'events': durationCount,
        'knownActualMs': actualMs,
        'unknownActualEvents': unknownActual,
        'states': states,
      },
      'startEvents': <String, Object?>{
        'events': startCount,
        'recentPlayConfirmed': recent,
      },
      'missingFields': <String, Object?>{
        'durationMissingRealtime': missingReal,
        'durationMissingStartlogtime': missingStart,
        'durationMissingMediaTime': missingMedia,
        'durationLegacyProtocol': legacy,
      },
      'localDays': localDays,
      'entries': detail,
      'totalDetailEntries': detailCount,
      'detailTruncated': detail.length < detailCount,
      'limitations': [
        'Local daily durations and per-play start-month durations use different calendar attribution; do not subtract them as exact missing cloud time.',
        'Accepted is a log receipt; recent confirmation applies to start logs, not cloud-footprint duration inclusion.',
        'Missing fields describe saved local payloads. Older transmission-time headers/fields are not recoverable from these rows.',
        'Daily aggregates do not reconstruct exact plays. No log is replayed, rewritten, or fabricated by this report.',
      ],
    };
    return NeteaseListeningAudit._(
      owner,
      month,
      List.unmodifiable(months),
      Map.unmodifiable(result),
    );
  }
}
