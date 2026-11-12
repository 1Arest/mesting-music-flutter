import 'dart:convert';

/// Official report calendars use China civil dates. Keep them independent of
/// the device timezone and of retry time (including a user's travel timezone).
DateTime footprintDate(DateTime instant) =>
    instant.toUtc().add(const Duration(hours: 8));
String footprintDay(DateTime instant) {
  final d = footprintDate(instant);
  return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

String footprintMonth(DateTime instant) =>
    footprintDay(instant).substring(0, 7);

DateTime footprintMonthStart(String month) {
  if (!RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(month)) {
    throw const FormatException('月份格式无效');
  }
  final y = int.parse(month.substring(0, 4));
  if (y < 2015 || y > 2200) throw const FormatException('月份范围无效');
  return DateTime.utc(
    y,
    int.parse(month.substring(5)),
    1,
  ).subtract(const Duration(hours: 8));
}

/// Match the official month navigation's endOf(month)-one-hour request. The
/// response interval is validated too: a server fallback is never called the
/// requested historical month just because the HTTP request succeeded.
int footprintHistoryEnd(String month) {
  final start = footprintDate(footprintMonthStart(month));
  return DateTime.utc(
    start.year,
    start.month + 1,
  ).subtract(const Duration(hours: 9, milliseconds: 1)).millisecondsSinceEpoch;
}

Map<String, dynamic> _object(Object? value) {
  if (value is String) value = jsonDecode(value);
  if (value is! Map) throw const FormatException('官方报表结构暂不支持');
  return Map<String, dynamic>.from(value);
}

Map<String, dynamic> footprintData(Object? response) {
  final root = _object(response);
  if (root.containsKey('code') && '${root['code']}' != '200') {
    throw const FormatException('官方报表暂不可用');
  }
  return _object(root['data']);
}

int _number(Object? value, {int max = 1000000000000}) {
  final n = value is num ? value : num.tryParse('$value');
  if (n == null || !n.isFinite || n < 0 || n > max || n != n.round()) {
    throw const FormatException('官方时长字段暂不可用');
  }
  return n.toInt();
}

/// The official report's `dp` formatter consumes minutes, while the historical
/// total's `r8` formatter consumes seconds. Normalize report fields at their
/// parser boundary so every reader/page value below uses seconds exactly once.
int _reportSeconds(Object? minutes) => _number(minutes) * 60;

/// Formats the normalized internal seconds shared by reports and totalDuration.
String officialDuration(int seconds) {
  final h = seconds ~/ 3600, m = seconds % 3600 ~/ 60;
  return h > 0 ? '$h 小时 $m 分钟' : '$m 分钟';
}

class OfficialListenPeriod {
  const OfficialListenPeriod({
    required this.start,
    required this.end,
    required this.seconds,
    required this.days,
  });
  final DateTime start, end;
  final int seconds;
  final Map<String, int> days;

  static OfficialListenPeriod parse(Object? response) {
    final data = footprintData(response);
    final start = DateTime.fromMillisecondsSinceEpoch(
      _number(data['startTime'], max: 10000000000000),
      isUtc: true,
    );
    final end = DateTime.fromMillisecondsSinceEpoch(
      _number(data['endTime'], max: 10000000000000),
      isUtc: true,
    );
    if (start.year < 2015 || end.year > 2200 || !end.isAfter(start)) {
      throw const FormatException('官方报表日期范围无效');
    }
    final block = _object(data['listenTimeDistributionBlock']);
    final seconds = _reportSeconds(block['playDuration']);
    final days = <String, int>{};
    final details = block['durationDetails'];
    if (details != null && details is! List) {
      throw const FormatException('官方每日记录结构暂不支持');
    }
    for (final raw in (details as List? ?? const [])) {
      final d = _object(raw), key = '${d['period']}';
      final parsed = DateTime.tryParse(key);
      if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(key) ||
          parsed == null ||
          '${parsed.year.toString().padLeft(4, '0')}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')}' !=
              key ||
          days.containsKey(key) ||
          key.compareTo(footprintDay(start)) < 0 ||
          key.compareTo(footprintDay(end)) > 0) {
        throw const FormatException('官方每日记录日期无效');
      }
      // The official page sums three resource kinds for a day. Missing optional
      // podcast/audiobook categories mean zero; a missing song duration is not
      // silently interpreted as a confirmed zero-minute reading.
      days[key] =
          _reportSeconds(d['duration']) +
          _reportSeconds(d['podcastDuration'] ?? 0) +
          _reportSeconds(d['audiobookDuration'] ?? 0);
    }
    return OfficialListenPeriod(
      start: start,
      end: end,
      seconds: seconds,
      days: Map.unmodifiable(days),
    );
  }

  int today(String day) {
    final value = days[day];
    if (value == null) throw const FormatException('官方暂未返回今日记录');
    return value;
  }

  OfficialListenPeriod forMonth(String month) {
    if (footprintMonth(start) != month || footprintMonth(end) != month) {
      throw const FormatException('官方尚未返回所选月份报表');
    }
    return this;
  }
}

abstract interface class OfficialFootprintSource {
  Future<OfficialListenPeriod> currentWeek();
  Future<OfficialListenPeriod> currentMonth();
  Future<int> totalSeconds();
  Future<OfficialListenPeriod> history(String month);
}
