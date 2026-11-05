import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../shared/models/track.dart';
import 'listening_sync_models.dart';

/// Transactional journal. No network operation occurs inside a transaction.
/// Claim-before-send makes an interrupted write uncertain rather than retryable.
class ListeningSyncStore {
  ListeningSyncStore(this.database);
  final AppDatabase database;

  ListeningSyncEntry _decode(PlatformListeningOutbox row) => ListeningSyncEntry(
    ownerId: row.ownerId,
    id: row.eventId,
    kind: row.kind,
    payload: listeningPayload(row.payload),
    state: ListeningSyncState.values.byName(row.state),
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  );

  SimpleSelectStatement<
    $PlatformListeningOutboxesTable,
    PlatformListeningOutbox
  >
  _query(String owner) => database.select(database.platformListeningOutboxes)
    ..where((r) => r.ownerId.equals(owner))
    ..orderBy([(r) => OrderingTerm.asc(r.createdAt)]);

  Future<List<ListeningSyncEntry>> entries(
    String owner, {
    Set<String>? kinds,
    Set<ListeningSyncState>? states,
  }) async {
    final query = _query(owner);
    if (kinds != null) query.where((r) => r.kind.isIn(kinds));
    if (states != null) {
      query.where((r) => r.state.isIn(states.map((s) => s.name)));
    }
    return (await query.get()).map(_decode).toList();
  }

  Future<ListeningSyncEntry?> entry(String owner, String id) async {
    final row = await (_query(
      owner,
    )..where((r) => r.eventId.equals(id))).getSingleOrNull();
    return row == null ? null : _decode(row);
  }

  Stream<List<ListeningSyncEntry>> watch(String owner) =>
      _query(owner).watch().map((rows) => rows.map(_decode).toList());

  /// Only the newest official daily observations are decoded for the status
  /// surface; checkpoints and the potentially long upload journal stay in SQL.
  Stream<List<ListeningSyncEntry>> watchOfficialDays(String owner) =>
      (database.select(database.platformListeningOutboxes)
            ..where(
              (row) =>
                  row.ownerId.equals(owner) &
                  row.kind.equals('official_day_readback'),
            )
            ..orderBy([(row) => OrderingTerm.desc(row.createdAt)])
            ..limit(14))
          .watch()
          .map((rows) => rows.map(_decode).toList());

  /// Summaries count inside SQLite instead of decoding every historical event
  /// whenever a five-second checkpoint updates the journal.
  Stream<ListeningSyncSummary> watchSummary(String owner) => database
      .customSelect(
        "SELECT state, COUNT(*) AS n FROM platform_listening_outboxes "
        "WHERE owner_id = ? AND kind IN ('history','grade','grade_v4','cscc') GROUP BY state",
        variables: [Variable.withString(owner)],
        readsFrom: {database.platformListeningOutboxes},
      )
      .watch()
      .map((rows) {
        final counts = {
          for (final row in rows) row.read<String>('state'): row.read<int>('n'),
        };
        return ListeningSyncSummary.counts(
          queued: counts['queued'] ?? 0,
          accepted: counts['accepted'] ?? 0,
          verified: counts['verified'] ?? 0,
          uncertain: (counts['unknown'] ?? 0) + (counts['dispatched'] ?? 0),
        );
      });

  Future<void> put({
    required String owner,
    required String id,
    required String kind,
    required Map<String, Object?> payload,
    required DateTime now,
    ListeningSyncState state = ListeningSyncState.queued,
  }) => database
      .into(database.platformListeningOutboxes)
      .insert(
        PlatformListeningOutboxesCompanion.insert(
          ownerId: owner,
          eventId: id,
          kind: kind,
          payload: jsonEncode(payload),
          state: Value(state.name),
          createdAt: now,
          updatedAt: now,
        ),
        mode: InsertMode.insertOrIgnore,
      )
      .then((_) {});

  Future<bool> change(
    ListeningSyncEntry entry,
    ListeningSyncState state,
    DateTime now, {
    Map<String, Object?>? payload,
    ListeningSyncState? expected,
  }) async {
    final rows =
        await (database.update(database.platformListeningOutboxes)..where(
              (r) =>
                  r.ownerId.equals(entry.ownerId) &
                  r.eventId.equals(entry.id) &
                  (expected == null
                      ? const Constant(true)
                      : r.state.equals(expected.name)),
            ))
            .write(
              PlatformListeningOutboxesCompanion(
                state: Value(state.name),
                payload: payload == null
                    ? const Value.absent()
                    : Value(jsonEncode(payload)),
                updatedAt: Value(now),
              ),
            );
    return rows == 1;
  }

  /// Upgrade backfill contains only genuine existing song aggregates. Its
  /// duration is never copied into a grade delta or a fabricated CSCC segment.
  Future<void> bootstrapHistory(String owner, DateTime now) =>
      database.transaction(() async {
        if (await entry(owner, 'bootstrap:1.0.7') != null) return;
        final histories = await (database.select(
          database.playbackHistories,
        )..where((r) => r.ownerId.equals(owner))).get();
        for (final row in histories) {
          Track track;
          try {
            track = Track.fromJson(
              Map<String, Object?>.from(jsonDecode(row.trackSnapshot) as Map),
            );
          } on Object {
            continue;
          }
          if (!isOfficialMusicTrack(track) || row.playCount <= 0) continue;
          await put(
            owner: owner,
            id: 'count:${track.id}',
            kind: 'control',
            payload: {'count': row.playCount, 'instance': ''},
            now: now,
            state: ListeningSyncState.verified,
          );
          await put(
            owner: owner,
            id: 'history:legacy:${track.id}',
            kind: 'history',
            payload: {
              'trackId': track.id,
              'recordingId': listeningRecordingId(track),
              'playCount': row.playCount,
              'time': row.lastPlayedAt.millisecondsSinceEpoch ~/ 1000,
              'legacy': true,
            },
            now: now,
          );
        }
        await put(
          owner: owner,
          id: 'bootstrap:1.0.7',
          kind: 'control',
          payload: const {'version': 1},
          now: now,
          state: ListeningSyncState.verified,
        );
      });

  /// Checkpoints contain only already measured monotonic elapsed time. A crash
  /// can lose at most the latest sampling interval; it cannot add wall time
  /// spent with the process dead, paused, buffering or seeking.
  Future<void> checkpointSegment(
    ListeningSyncEntry segment,
    int heardMs,
    DateTime now,
  ) => database.transaction(() async {
    final current = await entry(segment.ownerId, segment.id);
    if (current == null || current.state != ListeningSyncState.open) return;
    final allocated = current.number('allocatedMs');
    final payload = {...current.payload, 'heardMs': heardMs};
    if (heardMs - allocated >= 60000) {
      final standard =
          current.text('gradeProtocol') == kugouStandardGradeProtocol;
      await put(
        owner: segment.ownerId,
        id: 'grade:${segment.id}:$heardMs',
        kind: standard ? 'grade_v4' : 'grade',
        payload: {...payload, 'heardMs': heardMs - allocated},
        now: now,
      );
      payload['allocatedMs'] = heardMs;
    }
    if (heardMs >= 15000) await _historyFor(current, payload, now);
    await change(
      current,
      ListeningSyncState.open,
      now,
      payload: payload,
      expected: ListeningSyncState.open,
    );
  });

  Future<void> _historyFor(
    ListeningSyncEntry segment,
    Map<String, Object?> payload,
    DateTime now,
  ) async {
    final countId = 'count:${segment.text('trackId')}';
    final previous = await entry(segment.ownerId, countId);
    final local =
        await (database.select(database.playbackHistories)..where(
              (r) =>
                  r.ownerId.equals(segment.ownerId) &
                  r.trackId.equals(segment.text('trackId')),
            ))
            .getSingleOrNull();
    final instance = segment.text('instanceId');
    final count = [
      local?.playCount ?? 0,
      (previous?.number('count') ?? 0) +
          (previous?.text('instance') == instance ? 0 : 1),
    ].reduce((a, b) => a > b ? a : b);
    if (previous == null) {
      await put(
        owner: segment.ownerId,
        id: countId,
        kind: 'control',
        payload: {'count': count, 'instance': instance},
        now: now,
        state: ListeningSyncState.verified,
      );
    } else {
      await change(
        previous,
        ListeningSyncState.verified,
        now,
        payload: {'count': count, 'instance': instance},
      );
    }
    await put(
      owner: segment.ownerId,
      id: 'history:${segment.id}',
      kind: 'history',
      payload: {...payload, 'playCount': count},
      now: now,
    );
  }

  Future<void> closeSegment(
    ListeningSyncEntry segment,
    int heardMs,
    DateTime now, {
    required bool live,
    String reason = '切歌',
  }) => database.transaction(() async {
    final current = await entry(segment.ownerId, segment.id);
    if (current == null) return;
    final won = await change(
      current,
      live ? ListeningSyncState.accepted : ListeningSyncState.interrupted,
      now,
      payload: {...current.payload, 'heardMs': heardMs, 'reason': reason},
      expected: ListeningSyncState.open,
    );
    if (!won || heardMs <= 0) return;
    final payload = {...current.payload, 'heardMs': heardMs, 'reason': reason};
    if (heardMs >= 15000) {
      await _historyFor(current, payload, now);
    }
    final remainder = heardMs - current.number('allocatedMs');
    if (remainder > 0) {
      final standard =
          current.text('gradeProtocol') == kugouStandardGradeProtocol;
      await put(
        owner: segment.ownerId,
        id: 'grade:${segment.id}:end',
        kind: standard ? 'grade_v4' : 'grade',
        payload: {...payload, 'heardMs': remainder},
        now: now,
        // Recovery/account changes retain the local fact but do not replay a
        // past process's standard delta under new authorization.
        state: standard && !live
            ? ListeningSyncState.interrupted
            : ListeningSyncState.queued,
      );
    }
    // A persisted old segment has no valid historical CSCC timestamp input.
    // Recover its actual measured grade delta, never invent start/end events.
    if (live && heardMs > 0) {
      await put(
        owner: segment.ownerId,
        id: 'cscc:end:${segment.id}',
        kind: 'cscc',
        payload: {...payload, 'event': 'end'},
        now: now,
      );
    }
  });

  Future<void> recoverInterrupted(String owner, DateTime now) async {
    for (final row in await entries(
      owner,
      kinds: {'segment'},
      states: {ListeningSyncState.open},
    )) {
      if (row.kind == 'segment' && row.state == ListeningSyncState.open) {
        await closeSegment(
          row,
          row.number('heardMs'),
          now,
          live: false,
          reason: '进程中断',
        );
      }
    }
  }

  /// Merge measured queued deltas before their one allowed write. The source
  /// rows remain in the journal as coalesced facts, preventing double allocation.
  Future<ListeningSyncEntry?> claimGrade(
    String owner,
    List<ListeningSyncEntry> rows,
    int baseline,
    DateTime now,
  ) => database.transaction(() async {
    final fresh =
        (await entries(
              owner,
              kinds: {'grade'},
              states: {ListeningSyncState.queued},
            ))
            .where(
              (r) =>
                  r.kind == 'grade' &&
                  r.state == ListeningSyncState.queued &&
                  rows.any((candidate) => candidate.id == r.id),
            )
            .toList();
    final milliseconds = fresh.fold<int>(
      0,
      (sum, r) => sum + r.number('heardMs'),
    );
    final seconds = milliseconds ~/ 1000;
    if (fresh.isEmpty || seconds < 1) return null;
    final first = fresh.first;
    final payload = {
      ...first.payload,
      'heardMs': milliseconds,
      'diffSec': seconds,
      'protocol': 'kugou-lite-baseline-delta-v1',
      'baseline': baseline,
      'target': baseline + seconds,
      'sources': fresh.map((r) => r.id).toList(),
    };
    for (final row in fresh.skip(1)) {
      await change(
        row,
        ListeningSyncState.coalesced,
        now,
        expected: ListeningSyncState.queued,
      );
    }
    if (!await change(
      first,
      ListeningSyncState.dispatched,
      now,
      payload: payload,
      expected: ListeningSyncState.queued,
    )) {
      return null;
    }
    if (milliseconds % 1000 > 0) {
      await put(
        owner: owner,
        id: 'grade:carry:${first.id}',
        kind: 'grade',
        payload: {'heardMs': milliseconds % 1000},
        now: now,
      );
    }
    return ListeningSyncEntry(
      ownerId: owner,
      id: first.id,
      kind: first.kind,
      payload: payload,
      state: ListeningSyncState.dispatched,
      createdAt: first.createdAt,
      updatedAt: now,
    );
  });

  /// Claim a separately measured standard batch exactly once. Native v4 sends
  /// d_sec as (server baseline + local measured milliseconds) ~/ 1000, and
  /// diff_sec as the new elapsed whole seconds. No legacy row or ambiguous
  /// delta participates; a crash after this transaction is read-back only.
  Future<ListeningSyncEntry?> claimStandardGrade(
    String owner,
    List<ListeningSyncEntry> rows,
    int baseline,
    DateTime now,
  ) => database.transaction(() async {
    if (baseline < 0) return null;
    final eligible = rows.map((row) => row.id).toSet();
    final fresh =
        (await entries(
              owner,
              kinds: {'grade_v4'},
              states: {ListeningSyncState.queued},
            ))
            .where(
              (row) =>
                  eligible.contains(row.id) &&
                  row.text('gradeProtocol') == kugouStandardGradeProtocol &&
                  row.number('credentialAppId') == 1005,
            )
            .toList();
    final milliseconds = fresh.fold<int>(
      0,
      (sum, row) => sum + row.number('heardMs'),
    );
    final seconds = milliseconds ~/ 1000;
    if (fresh.isEmpty || seconds < 1) return null;
    final first = fresh.first;
    final payload = <String, Object?>{
      ...first.payload,
      'heardMs': milliseconds,
      'diffSec': seconds,
      'protocol': kugouStandardGradeProtocol,
      'baseline': baseline,
      'localMillis': baseline * 1000 + milliseconds,
      'target': baseline + seconds,
      'sources': fresh.map((row) => row.id).toList(),
    };
    for (final row in fresh.skip(1)) {
      await change(
        row,
        ListeningSyncState.coalesced,
        now,
        expected: ListeningSyncState.queued,
      );
    }
    if (!await change(
      first,
      ListeningSyncState.dispatched,
      now,
      payload: payload,
      expected: ListeningSyncState.queued,
    )) {
      return null;
    }
    if (milliseconds % 1000 > 0) {
      await put(
        owner: owner,
        id: 'grade-v4:carry:${first.id}',
        kind: 'grade_v4',
        payload: {
          'heardMs': milliseconds % 1000,
          'segmentId': first.text('segmentId'),
          'gradeProtocol': kugouStandardGradeProtocol,
          'credentialAppId': 1005,
        },
        now: now,
      );
    }
    return ListeningSyncEntry(
      ownerId: owner,
      id: first.id,
      kind: 'grade_v4',
      payload: payload,
      state: ListeningSyncState.dispatched,
      createdAt: first.createdAt,
      updatedAt: now,
    );
  });
}
