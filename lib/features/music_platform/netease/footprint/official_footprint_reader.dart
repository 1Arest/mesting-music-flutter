import 'package:flutter/foundation.dart';
import 'official_footprint.dart';

/// A successful reading is immutable and retains its own calendar identity and
/// timestamp. Refresh errors never replace it with a fabricated zero.
class FootprintReading<T> {
  const FootprintReading({
    this.value,
    this.readAt,
    this.key = '',
    this.loading = false,
    this.failed = false,
  });
  final T? value;
  final DateTime? readAt;
  final String key;
  final bool loading, failed;
  FootprintReading<T> pending() =>
      FootprintReading(value: value, readAt: readAt, key: key, loading: true);
  FootprintReading<T> failure() =>
      FootprintReading(value: value, readAt: readAt, key: key, failed: true);
}

/// UI-independent read coordinator. Owner/token isolation is provided by the
/// provider lifetime and [current]; request generations also isolate fast month
/// changes, midnight rollover, and responses arriving after the page closes.
class OfficialFootprintReader extends ChangeNotifier {
  OfficialFootprintReader(
    this.source, {
    required this.current,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;
  final OfficialFootprintSource source;
  final bool Function() current;
  final DateTime Function() now;
  FootprintReading<int> today = const FootprintReading();
  FootprintReading<int> month = const FootprintReading();
  FootprintReading<int> total = const FootprintReading();
  FootprintReading<OfficialListenPeriod> history = const FootprintReading();
  String _day = '';
  int _generation = 0, _historyGeneration = 0;
  bool _alive = true;
  Future<void>? _currentWork;
  bool get calendarChanged => _day != footprintDay(now());
  bool get loading => today.loading || month.loading || total.loading;
  bool get _valid => _alive && current();

  Future<void> refresh() {
    if (!_valid) return Future.value();
    final day = footprintDay(now()), monthKey = day.substring(0, 7);
    if (_currentWork != null && _day == day) return _currentWork!;
    _day = day;
    final generation = ++_generation;
    today = today.pending();
    month = month.pending();
    total = total.pending();
    notifyListeners();
    bool valid() =>
        _valid && generation == _generation && footprintDay(now()) == day;
    Future<void> read(
      Future<int> Function() fetch,
      String key,
      void Function(FootprintReading<int>) set,
      FootprintReading<int> old,
    ) async {
      try {
        final value = await fetch();
        if (valid()) {
          set(FootprintReading(value: value, readAt: now(), key: key));
        }
      } catch (_) {
        if (valid()) set(old.failure());
      }
      if (valid()) notifyListeners();
    }

    final work = Future.wait([
      read(
        () async => (await source.currentWeek()).today(day),
        day,
        (v) => today = v,
        today,
      ),
      read(
        () async => (await source.currentMonth()).forMonth(monthKey).seconds,
        monthKey,
        (v) => month = v,
        month,
      ),
      read(source.totalSeconds, day, (v) => total = v, total),
    ]).then<void>((_) {});
    _currentWork = work;
    return work.whenComplete(() {
      if (generation == _generation) _currentWork = null;
    });
  }

  void selectMonth() {
    ++_historyGeneration;
    history = const FootprintReading();
    if (_valid) notifyListeners();
  }

  Future<void> readHistory(String selected) async {
    if (!_valid || (history.loading && history.key == selected)) return;
    footprintMonthStart(selected);
    final generation = ++_historyGeneration;
    final old = history.key == selected
        ? history
        : const FootprintReading<OfficialListenPeriod>();
    history = FootprintReading(
      value: old.value,
      readAt: old.readAt,
      key: selected,
      loading: true,
    );
    notifyListeners();
    bool valid() => _valid && generation == _historyGeneration;
    try {
      final value = (await source.history(selected)).forMonth(selected);
      if (valid()) {
        history = FootprintReading(value: value, readAt: now(), key: selected);
      }
    } catch (_) {
      if (valid()) {
        history = FootprintReading(
          value: old.value,
          readAt: old.readAt,
          key: selected,
          failed: true,
        );
      }
    }
    if (valid()) notifyListeners();
  }

  @override
  void dispose() {
    _alive = false;
    ++_generation;
    ++_historyGeneration;
    super.dispose();
  }
}
