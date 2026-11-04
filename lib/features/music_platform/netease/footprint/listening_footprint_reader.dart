import 'package:flutter/foundation.dart';
import 'official_footprint.dart';
import 'official_footprint_reader.dart';
import 'listening_footprint_models.dart';

/// Account-scoped exploration state. A selection owns its cached value and
/// timestamp, so failed refreshes and fast navigation never relabel other
/// periods' data. Provider lifetime and [current] guard owner/token changes.
class ListeningFootprintReader extends ChangeNotifier {
  ListeningFootprintReader(
    this.source, {
    required this.current,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now {
    for (final scale in FootprintScale.values) {
      _selections[scale] = FootprintPeriod.containing(this.now(), scale);
    }
    _day = footprintDay(this.now());
  }
  final OfficialFootprintDetailSource source;
  final bool Function() current;
  final DateTime Function() now;
  final _selections = <FootprintScale, FootprintPeriod>{};
  final _reports = <String, FootprintReading<OfficialListeningReport>>{};
  final _work = <String, Future<void>>{};
  final _generations = <String, int>{};
  FootprintReading<OfficialYearlyFootprint> yearly = const FootprintReading();
  FootprintReading<OfficialTodaySongs> todaySongs = const FootprintReading();
  FootprintScale scale = FootprintScale.week;
  String _day = '';
  bool _alive = true;
  bool get _valid => _alive && current();
  FootprintPeriod get selection => _selections[scale]!;
  FootprintReading<OfficialListeningReport> get report =>
      _reports[selection.key] ?? const FootprintReading();
  bool get loading =>
      (scale == FootprintScale.year ? yearly.loading : report.loading) ||
      todaySongs.loading;
  bool get calendarChanged => _day != footprintDay(now());
  OfficialTodayListening? get todayListening {
    final current =
        _reports[FootprintPeriod.containing(now(), FootprintScale.week).key];
    // A current-week cache can survive midnight. Its today block still belongs
    // to its read date, even though the week's calendar key remains unchanged.
    return current?.readAt != null &&
            footprintDay(current!.readAt!) == footprintDay(now())
        ? current.value?.todayListening
        : null;
  }

  void selectScale(FootprintScale value) {
    if (!_valid || scale == value) return;
    scale = value;
    notifyListeners();
  }

  List<int> get availableYears =>
      yearly.value?.years.map((y) => y.year).toList() ?? const [];
  bool canMove(int delta) {
    if (scale != FootprintScale.year) return selection.canMove(delta, now());
    final years = availableYears,
        index = years.indexOf(selection.civilStart.year);
    return index >= 0 && index + delta >= 0 && index + delta < years.length;
  }

  void move(int delta) {
    if (!_valid || !canMove(delta)) return;
    if (scale == FootprintScale.year) {
      final years = availableYears;
      selectYear(years[years.indexOf(selection.civilStart.year) + delta]);
    } else {
      _selections[scale] = selection.move(delta);
      notifyListeners();
    }
  }

  void selectYear(int year) {
    if (!_valid || !availableYears.contains(year)) return;
    _selections[FootprintScale.year] = FootprintPeriod.containing(
      DateTime.utc(year, 6),
      FootprintScale.year,
    );
    notifyListeners();
  }

  /// The clock only rolls visible *current* selections to a new calendar. It
  /// neither polls account data nor changes a deliberately selected old report.
  void updateCalendar() {
    final day = footprintDay(now());
    if (!_valid || day == _day) return;
    final oldInstant = DateTime.parse('${_day}T12:00:00Z');
    for (final scale in [FootprintScale.week, FootprintScale.month]) {
      if (_selections[scale]!.isCurrent(oldInstant)) {
        _selections[scale] = FootprintPeriod.containing(now(), scale);
      }
    }
    _day = day;
    notifyListeners();
  }

  Future<void> loadSelected({bool force = false}) {
    if (!_valid) return Future.value();
    updateCalendar();
    if (scale == FootprintScale.year) return _loadYears(force: force);
    return _loadReport(selection, force: force);
  }

  Future<void> _loadReport(FootprintPeriod selected, {required bool force}) {
    final key = selected.key, existing = _reports[selected.key];
    final requestedDay = footprintDay(now()),
        isCurrent = selected.isCurrent(now());
    final workKey = isCurrent ? '$key:$requestedDay' : key;
    if (_work[workKey] != null) return _work[workKey]!;
    if (!force && existing?.value != null && existing?.failed != true) {
      return Future.value();
    }
    final old = existing ?? const FootprintReading<OfficialListeningReport>();
    _reports[key] = FootprintReading(
      value: old.value,
      readAt: old.readAt,
      key: key,
      loading: true,
    );
    notifyListeners();
    return _run(
      workKey,
      () async {
        final value = (await source.report(
          selected,
          current: isCurrent,
        )).forSelection(selected, current: isCurrent);
        // A new midnight must not promote a previous day's realtime result.
        if (isCurrent && footprintDay(now()) != requestedDay) {
          throw const FormatException('日期已变化，请刷新官方报表');
        }
        if (_valid) {
          _reports[key] = FootprintReading(
            value: value,
            readAt: now(),
            key: key,
          );
        }
      },
      () {
        if (isCurrent && footprintDay(now()) != requestedDay) return;
        _reports[key] = FootprintReading(
          value: old.value,
          readAt: old.readAt,
          key: key,
          failed: true,
        );
      },
    );
  }

  Future<void> _loadYears({required bool force}) {
    const key = 'year-overview';
    if (_work[key] != null) return _work[key]!;
    if (!force && yearly.value != null && !yearly.failed) return Future.value();
    final old = yearly;
    yearly = yearly.pending();
    notifyListeners();
    return _run(key, () async {
      final value = await source.years();
      if (!_valid) return;
      yearly = FootprintReading(value: value, readAt: now(), key: key);
      final years = value.years.map((y) => y.year).toList();
      if (years.isNotEmpty &&
          !years.contains(_selections[FootprintScale.year]!.civilStart.year)) {
        // Many official annual reports contain only completed years. Selecting
        // their newest actual year is clearer than inventing a current-year 0.
        _selections[FootprintScale.year] = FootprintPeriod.containing(
          DateTime.utc(years.last, 6),
          FootprintScale.year,
        );
      }
    }, () => yearly = old.failure());
  }

  Future<void> loadToday({bool force = false}) {
    if (!_valid) return Future.value();
    final day = footprintDay(now()), key = 'today:$day';
    if (_work[key] != null) return _work[key]!;
    if (!force &&
        todaySongs.key == day &&
        todaySongs.value != null &&
        !todaySongs.failed) {
      return Future.value();
    }
    final old = todaySongs;
    todaySongs = old.pending();
    notifyListeners();
    return _run(
      key,
      () async {
        final value = await source.todaySongs(day);
        if (value.day != day || footprintDay(now()) != day) {
          throw const FormatException('日期已变化，请刷新今日歌曲');
        }
        if (_valid) {
          todaySongs = FootprintReading(value: value, readAt: now(), key: day);
        }
      },
      () {
        // A previous day's failed request cannot roll today's successful list back.
        if (footprintDay(now()) == day) todaySongs = old.failure();
      },
    );
  }

  Future<void> refresh() async {
    if (!_valid) return;
    updateCalendar();
    await Future.wait([loadSelected(force: true), loadToday(force: true)]);
  }

  Future<void> _run(
    String key,
    Future<void> Function() read,
    VoidCallback fail,
  ) {
    final generation = (_generations[key] ?? 0) + 1;
    _generations[key] = generation;
    final work = Future<void>.sync(read)
        .catchError((Object _) {
          if (_valid && _generations[key] == generation) fail();
        })
        .whenComplete(() {
          if (_generations[key] == generation) _work.remove(key);
          if (_valid) notifyListeners();
        });
    _work[key] = work;
    return work;
  }

  @override
  void dispose() {
    _alive = false;
    super.dispose();
  }
}
