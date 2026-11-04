import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesting_music/features/music_platform/netease/netease_api.dart';
import 'package:mesting_music/features/music_platform/netease/footprint/official_footprint.dart';
import 'package:mesting_music/features/music_platform/netease/footprint/official_footprint_reader.dart';
import 'package:mesting_music/features/music_platform/netease/footprint/official_footprint_repository.dart';
import 'netease_v112_listening_test.dart' show session;
import 'netease_v114_workflows_test.dart' show eapiBody;

Map<String, Object?> footprintResponse({
  String month = '2026-11',
  int seconds = 4680,
  Map<String, Object?>? day,
}) {
  final start = footprintMonthStart(month);
  final civil = footprintDate(start);
  return {
    'code': 200,
    'data': {
      'startTime': start.millisecondsSinceEpoch,
      'endTime': DateTime.utc(civil.year, civil.month + 1)
          .subtract(const Duration(hours: 8, milliseconds: 1))
          .millisecondsSinceEpoch,
      'listenTimeDistributionBlock': {
        'playDuration': seconds,
        'durationDetails': [?day],
      },
    },
  };
}

class FootprintFixture implements OfficialFootprintSource {
  int weekReads = 0, monthReads = 0, totalReads = 0, historyReads = 0;
  bool fail = false, failMonth = false;
  String day = '2026-11-02';
  int dailySeconds = 1020, monthlySeconds = 4680, totalValue = 20193360;
  Completer<OfficialListenPeriod>? weekPending;
  Completer<int>? totalPending;
  final Map<String, Completer<OfficialListenPeriod>> historyPending = {};
  OfficialListenPeriod period([String? month]) => OfficialListenPeriod.parse(
    footprintResponse(
      month: month ?? day.substring(0, 7),
      seconds: monthlySeconds,
      day: {'period': day, 'duration': dailySeconds},
    ),
  );
  @override
  Future<OfficialListenPeriod> currentWeek() async {
    weekReads++;
    if (fail) throw StateError('offline');
    return weekPending?.future ?? period();
  }

  @override
  Future<OfficialListenPeriod> currentMonth() async {
    monthReads++;
    if (fail || failMonth) throw StateError('offline');
    return period();
  }

  @override
  Future<int> totalSeconds() async {
    totalReads++;
    if (fail) throw StateError('offline');
    return totalPending?.future ?? totalValue;
  }

  @override
  Future<OfficialListenPeriod> history(String month) async {
    historyReads++;
    if (fail) throw StateError('offline');
    return historyPending[month]?.future ??
        OfficialListenPeriod.parse(
          footprintResponse(month: month, seconds: 36000),
        );
  }
}

void main() {
  test(
    'month boundary refresh replaces the previous month without adding local or yesterday values',
    () async {
      final source = FootprintFixture()..day = '2026-11-30';
      var now = DateTime.utc(2026, 11, 30, 15, 59);
      final reader = OfficialFootprintReader(
        source,
        current: () => true,
        now: () => now,
      );
      addTearDown(reader.dispose);
      await reader.refresh();
      expect(reader.month.key, '2026-11');
      now = now.add(const Duration(minutes: 2));
      source.day = '2026-12-01';
      source.monthlySeconds = 60;
      source.dailySeconds = 60;
      await reader.refresh();
      expect(reader.month.key, '2026-12');
      expect(reader.month.value, 60);
      expect(reader.today.key, '2026-12-01');
      expect(reader.today.value, 60);
      expect(reader.total.value, 20193360);
    },
  );
  test(
    'official seconds and three daily categories do not reuse widget units',
    () {
      final p = OfficialListenPeriod.parse(
        footprintResponse(
          day: {
            'period': '2026-11-02',
            'duration': 900,
            'podcastDuration': 60,
            'audiobookDuration': 60,
          },
        ),
      );
      expect(p.today('2026-11-02'), 1020);
      expect(p.seconds, 4680);
      expect(officialDuration(20193360), '5609 小时 16 分钟');
      expect(officialDuration(p.seconds), '1 小时 18 分钟');
      expect(officialDuration(0), '0 分钟');
      expect(() => p.today('2026-11-03'), throwsFormatException);
    },
  );
  test(
    'China dates and historical endTime stay in the requested month across UTC midnight',
    () {
      expect(footprintDay(DateTime.utc(2026, 11, 1, 15, 59)), '2026-11-01');
      expect(footprintDay(DateTime.utc(2026, 11, 1, 16)), '2026-11-02');
      final end = DateTime.fromMillisecondsSinceEpoch(
        footprintHistoryEnd('2026-10'),
        isUtc: true,
      );
      expect(footprintDay(end), '2026-10-31');
      expect(footprintDate(end).hour, 22);
      expect(footprintDate(end).minute, 59);
      expect(
        footprintDay(
          DateTime.fromMillisecondsSinceEpoch(
            footprintHistoryEnd('2028-02'),
            isUtc: true,
          ),
        ),
        '2028-02-29',
      );
      expect(() => footprintHistoryEnd('2026-13'), throwsFormatException);
    },
  );
  test(
    'missing, malformed, duplicate and wrong-month official data are never confirmed zeroes',
    () {
      expect(
        () => OfficialListenPeriod.parse({'data': {}}),
        throwsFormatException,
      );
      expect(
        () => OfficialListenPeriod.parse(
          footprintResponse(day: {'period': '2026-11-02'}),
        ),
        throwsFormatException,
      );
      expect(
        () => OfficialListenPeriod.parse(
          footprintResponse(day: {'period': '2026-11-31', 'duration': 0}),
        ),
        throwsFormatException,
      );
      final wrong = OfficialListenPeriod.parse(footprintResponse());
      expect(() => wrong.forMonth('2026-10'), throwsFormatException);
      final zero = OfficialListenPeriod.parse(
        footprintResponse(
          seconds: 0,
          day: {'period': '2026-11-02', 'duration': 0},
        ),
      );
      expect(zero.today('2026-11-02'), 0);
      expect(
        () => OfficialListenPeriod.parse(footprintResponse(seconds: -1)),
        throwsFormatException,
      );
      final duplicate = footprintResponse(
        day: {'period': '2026-11-02', 'duration': 0},
      );
      (((duplicate['data'] as Map)['listenTimeDistributionBlock']
                  as Map)['durationDetails']
              as List)
          .add({'period': '2026-11-02', 'duration': 1});
      expect(
        () => OfficialListenPeriod.parse(duplicate),
        throwsFormatException,
      );
    },
  );
  test(
    'report reader uses exact official types/endTime and no playback-write route',
    () async {
      final requests = <String, Map<String, dynamic>>{};
      final api = NeteaseApi(
        MockClient((r) async {
          expect(r.url.host, 'interface.music.163.com');
          final body = eapiBody(r);
          requests['${r.url.path}:${body['type']}'] = body;
          final response = r.url.path.endsWith('/total')
              ? {
                  'code': 200,
                  'data': {'totalDuration': '20193360'},
                }
              : footprintResponse(
                  month: body.containsKey('endTime') ? '2026-10' : '2026-11',
                );
          return http.Response(jsonEncode(response), 200);
        }),
      )..configure(session);
      final source = OfficialFootprintRepository(api);
      await source.currentWeek();
      await source.currentMonth();
      expect(await source.totalSeconds(), 20193360);
      expect((await source.history('2026-10')).seconds, 4680);
      expect(
        requests.keys,
        containsAll([
          '/eapi/content/activity/listen/data/realtime/report:week',
          '/eapi/content/activity/listen/data/realtime/report:month',
          '/eapi/content/activity/listen/data/total:null',
          '/eapi/content/activity/listen/data/report:month',
        ]),
      );
      final history =
          requests['/eapi/content/activity/listen/data/report:month']!;
      expect(history['endTime'], footprintHistoryEnd('2026-10'));
      expect(
        requests.values.every(
          (q) => !q.containsKey('logs') && !q.containsKey('realtime'),
        ),
        isTrue,
      );
    },
  );
  test(
    'reader coalesces clicks, handles independent failures and retains success timestamps',
    () async {
      final source = FootprintFixture()..weekPending = Completer();
      var now = DateTime.utc(2026, 11, 2);
      final reader = OfficialFootprintReader(
        source,
        current: () => true,
        now: () => now,
      );
      addTearDown(reader.dispose);
      final first = reader.refresh();
      reader.refresh();
      await Future<void>.delayed(Duration.zero);
      expect(reader.month.value, 4680);
      expect(reader.total.value, 20193360);
      expect(reader.today.loading, isTrue);
      expect(source.weekReads, 1);
      source.weekPending!.complete(source.period());
      await first;
      expect(reader.today.value, 1020);
      final at = reader.today.readAt;
      source.weekPending = null;
      source.fail = true;
      now = now.add(const Duration(minutes: 5));
      await reader.refresh();
      expect(reader.today.value, 1020);
      expect(reader.today.failed, isTrue);
      expect(reader.today.readAt, at);
      expect(reader.total.readAt, at);
      source.fail = false;
      source.failMonth = true;
      await reader.refresh();
      expect(reader.today.failed, isFalse);
      expect(reader.month.failed, isTrue);
      expect(reader.month.readAt, at);
      expect(reader.today.readAt, now);
    },
  );
  test(
    'new date refresh wins over late previous-day requests and does not relabel old data',
    () async {
      final source = FootprintFixture()..weekPending = Completer();
      var now = DateTime.utc(2026, 11, 2, 15, 59);
      final reader = OfficialFootprintReader(
        source,
        current: () => true,
        now: () => now,
      );
      addTearDown(reader.dispose);
      final old = reader.refresh(), pending = source.weekPending!;
      now = now.add(const Duration(minutes: 2));
      source.day = '2026-11-03';
      source.weekPending = null;
      expect(reader.calendarChanged, isTrue);
      await reader.refresh();
      expect(reader.today.key, '2026-11-03');
      pending.complete(
        OfficialListenPeriod.parse(
          footprintResponse(day: {'period': '2026-11-02', 'duration': 9999}),
        ),
      );
      await old;
      expect(reader.today.key, '2026-11-03');
      expect(reader.today.value, 1020);
    },
  );
  test(
    'account/dispose invalidation prevents old responses and later requests',
    () async {
      final source = FootprintFixture()..totalPending = Completer();
      var current = true;
      final reader = OfficialFootprintReader(
        source,
        current: () => current,
        now: () => DateTime.utc(2026, 11, 2),
      );
      final work = reader.refresh();
      current = false;
      source.totalPending!.complete(999999);
      await work;
      expect(reader.total.value, isNull);
      await reader.refresh();
      expect(source.totalReads, 1);
      reader.dispose();
      await reader.refresh();
      expect(source.weekReads, 1);
    },
  );
  test(
    'fast historical month changes discard earlier completion and failed refresh keeps same-month result',
    () async {
      final source = FootprintFixture();
      final reader = OfficialFootprintReader(source, current: () => true);
      addTearDown(reader.dispose);
      source.historyPending['2026-10'] = Completer();
      final old = reader.readHistory('2026-10');
      reader.selectMonth();
      await reader.readHistory('2026-09');
      source.historyPending['2026-10']!.complete(
        OfficialListenPeriod.parse(
          footprintResponse(month: '2026-10', seconds: 9999),
        ),
      );
      await old;
      expect(reader.history.key, '2026-09');
      expect(reader.history.value!.seconds, 36000);
      final at = reader.history.readAt;
      source.fail = true;
      await reader.readHistory('2026-09');
      expect(reader.history.value!.seconds, 36000);
      expect(reader.history.failed, isTrue);
      expect(reader.history.readAt, at);
      reader.selectMonth();
      expect(reader.history.value, isNull);
    },
  );
}
