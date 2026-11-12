import '../domain/platform_session.dart';
import 'listening_sync_models.dart';
import 'listening_sync_store.dart';

/// A dated value returned by the official statistics service, in seconds.
/// This type deliberately has no constructor accepting a local listening delta.
class OfficialListeningDayFact {
  const OfficialListeningDayFact({
    required this.day,
    required this.seconds,
    required this.readAt,
    this.totalSeconds,
  });
  final DateTime day, readAt;
  final int seconds;
  final int? totalSeconds;
}

typedef OfficialListeningDayReader =
    Future<OfficialListeningDayFact> Function(
      PlatformSession identity,
      DateTime day,
    );

/// Independent official observations, never an acknowledgement of a specific
/// CSCC/grade/history write. Other clients can also change official totals.
class OfficialListeningDayStatus {
  const OfficialListeningDayStatus({
    required this.ownerId,
    required this.day,
    required this.attemptedAt,
    required this.readFailed,
    this.baselineSeconds,
    this.seconds,
    this.baselineReadAt,
    this.readAt,
    this.totalSeconds,
  });
  final String ownerId, day;
  final DateTime attemptedAt;
  final bool readFailed;
  final int? baselineSeconds, seconds, totalSeconds;
  final DateTime? baselineReadAt, readAt;

  /// A server-observed change only. It must not be labelled as the amount
  /// credited for this app, nor used to replay or verify an uncertain upload.
  int? get observedIncreaseSeconds => baselineSeconds == null || seconds == null
      ? null
      : (seconds! - baselineSeconds!).clamp(0, seconds!).toInt();
  bool get correctedDownward =>
      baselineSeconds != null && seconds != null && seconds! < baselineSeconds!;

  static String dayKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}'
      '${value.month.toString().padLeft(2, '0')}'
      '${value.day.toString().padLeft(2, '0')}';

  static DateTime dayStart(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static String entryId(DateTime value) => 'official-day:${dayKey(value)}';

  static OfficialListeningDayStatus? fromEntry(ListeningSyncEntry? entry) {
    if (entry == null || entry.kind != 'official_day_readback') return null;
    final day = entry.text('day');
    if (!RegExp(r'^\d{8}$').hasMatch(day)) return null;
    int? number(String key) {
      final value = int.tryParse('${entry.payload[key]}');
      return value != null && value >= 0 ? value : null;
    }

    DateTime? time(String key) =>
        DateTime.tryParse('${entry.payload[key] ?? ''}');
    return OfficialListeningDayStatus(
      ownerId: entry.ownerId,
      day: day,
      attemptedAt: time('attemptedAt') ?? entry.updatedAt,
      readFailed: entry.payload['readFailed'] == true,
      baselineSeconds: number('baselineSeconds'),
      seconds: number('seconds'),
      baselineReadAt: time('baselineReadAt'),
      readAt: time('readAt'),
      totalSeconds: number('totalSeconds'),
    );
  }
}

/// Records only independent reads of the current account's official daily
/// statistics. A failed read retains the last official value. No write receipt,
/// local timer or previous-version history is converted into an official fact.
class ListeningDailyReadback {
  ListeningDailyReadback({
    required this.store,
    required this.reader,
    required this.identity,
    required this.isCurrent,
    required this.now,
    this.minimumInterval = const Duration(minutes: 2),
  });
  final ListeningSyncStore store;
  final OfficialListeningDayReader reader;
  final PlatformSession identity;
  final bool Function() isCurrent;
  final DateTime Function() now;
  final Duration minimumInterval;
  final Map<String, DateTime> _attempts = {};
  Future<void>? _pending;

  String get owner => 'kugou:${identity.userId}';

  /// UI refresh and a background drain share one read; neither can overwrite a
  /// newer observation with a slower request launched for the same day.
  Future<void> observe({bool force = false}) {
    if (_pending != null) return _pending!;
    final operation = _observe(force: force);
    final pending = operation.whenComplete(() => _pending = null);
    _pending = pending;
    return pending;
  }

  Future<void> _observe({required bool force}) async {
    if (!isCurrent()) return;
    final today = OfficialListeningDayStatus.dayStart(now());
    // Re-read yesterday only if this app has already observed that exact day.
    // This catches delayed official settlement without fabricating old data or
    // submitting any past segment again after midnight or an app restart.
    final yesterday = DateTime(today.year, today.month, today.day - 1);
    final prior = await store.entry(
      owner,
      OfficialListeningDayStatus.entryId(yesterday),
    );
    if (!isCurrent()) return;
    if (prior != null) await _observeDay(yesterday, force: force);
    if (isCurrent()) await _observeDay(today, force: force);
  }

  Future<void> _observeDay(DateTime day, {required bool force}) async {
    final key = OfficialListeningDayStatus.dayKey(day);
    final attemptedAt = now();
    final previousAttempt = _attempts[key];
    if (!force &&
        previousAttempt != null &&
        attemptedAt.difference(previousAttempt) < minimumInterval) {
      return;
    }
    _attempts[key] = attemptedAt;
    final id = OfficialListeningDayStatus.entryId(day);
    final previous = await store.entry(owner, id);
    if (!isCurrent()) return;
    Map<String, Object?> payload = {
      ...?previous?.payload,
      'day': key,
      'attemptedAt': attemptedAt.toIso8601String(),
    };
    try {
      final fact = await reader(identity, day);
      if (!isCurrent()) return;
      if (OfficialListeningDayStatus.dayKey(fact.day) != key ||
          fact.seconds < 0 ||
          (fact.totalSeconds != null && fact.totalSeconds! < 0)) {
        throw const FormatException('Invalid official daily observation');
      }
      payload = {
        ...payload,
        'seconds': fact.seconds,
        'readAt': fact.readAt.toIso8601String(),
        'readFailed': false,
        if (fact.totalSeconds != null) 'totalSeconds': fact.totalSeconds,
        if (OfficialListeningDayStatus.fromEntry(previous)?.seconds ==
            null) ...{
          'baselineSeconds': fact.seconds,
          'baselineReadAt': fact.readAt.toIso8601String(),
        },
      };
    } on Object {
      if (!isCurrent()) return;
      // Persist a categorical failure only, never raw transport errors which
      // could include credentials, private query values or upstream payloads.
      payload['readFailed'] = true;
    }
    if (!isCurrent()) return;
    if (previous == null) {
      await store.put(
        owner: owner,
        id: id,
        kind: 'official_day_readback',
        payload: payload,
        now: attemptedAt,
        state: ListeningSyncState.accepted,
      );
    } else {
      await store.change(
        previous,
        ListeningSyncState.accepted,
        attemptedAt,
        payload: payload,
      );
    }
  }
}
