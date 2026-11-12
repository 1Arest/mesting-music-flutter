import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesting_music/features/music_platform/netease/netease_api.dart';
import 'package:mesting_music/features/music_platform/netease/footprint/official_footprint.dart';
import 'package:mesting_music/features/music_platform/netease/footprint/official_footprint_reader.dart';
import 'package:mesting_music/features/music_platform/netease/footprint/official_footprint_repository.dart';
import 'package:mesting_music/features/music_platform/netease/footprint/listening_footprint_models.dart';
import 'package:mesting_music/features/music_platform/netease/footprint/listening_footprint_reader.dart';
import 'netease_v112_listening_test.dart' show session;
import 'netease_v114_workflows_test.dart' show eapiBody;
import 'release_137_footprint_test.dart' show FootprintFixture;

final footprint145Now = DateTime.utc(2026, 11, 3, 4);
const footprint145Covers = [
  'assets/images/playlists/13416469337261709.jpeg',
  'assets/images/playlists/13416469354055551.jpeg',
  'assets/images/playlists/13416469356600254.jpeg',
  'assets/images/playlists/13416469357886115.jpeg',
  'assets/images/playlists/13416469359090353.jpeg',
];

Map<String, Object?> footprint145Report(
  FootprintPeriod period, {
  int minutes = 195,
}) => {
  'code': 200,
  'data': {
    'startTime': period.start.millisecondsSinceEpoch,
    'endTime': period.end
        .subtract(const Duration(milliseconds: 1))
        .millisecondsSinceEpoch,
    'listenTimeDistributionBlock': {
      'playDuration': minutes,
      'listenDays': 3,
      'durationDetails': [
        for (var i = 0; i < 3; i++)
          {
            'period': period.dayKeys[i],
            'duration': 40 + i * 20,
            'podcastDuration': i == 1 ? 12 : 0,
            'audiobookDuration': i == 2 ? 3 : 0,
          },
      ],
    },
    'weekTodayListenBlock': {'songCount': 43, 'coverUrls': footprint145Covers},
  },
};

Map<String, Object?> footprint145Songs(String day, {int count = 8}) => {
  'code': 200,
  'data': {
    'songDTOs': [
      for (var i = 0; i < count; i++)
        {
          'songId': 1000 + i,
          'songName': ['月光下的钢琴', '雨后散步', '清晨的海'][i % 3],
          'aliasName': i == 0 ? 'Piano version' : '',
          'picUrl': footprint145Covers[i % 5],
          'artists': [
            {'artistName': i.isEven ? '陈奕迅' : '纯音乐合辑'},
          ],
          'lastPlayTime':
              DateTime.parse(
                '${day}T03:00:00Z',
              ).add(Duration(minutes: i)).millisecondsSinceEpoch ~/
              1000,
          'redStar': i.isEven,
        },
    ],
  },
};

Map<String, Object?> footprint145Years() => {
  'code': 200,
  'data': {
    'yearItems': [
      {'year': 2025, 'playNum': 1831, 'playDuration': 720061},
      {'year': 2024, 'playNum': 1102, 'playDuration': 360121},
      {'year': 2023, 'playNum': 934, 'playDuration': 190000},
    ],
  },
};

class Footprint145Fixture implements OfficialFootprintDetailSource {
  bool fail = false;
  int songReads = 0, yearReads = 0;
  final calls = <(String, bool)>[];
  final pending = <String, Completer<OfficialListeningReport>>{};
  Completer<OfficialTodaySongs>? pendingSongs;
  int minutes = 195;
  @override
  Future<OfficialListeningReport> report(
    FootprintPeriod selection, {
    required bool current,
  }) async {
    calls.add((selection.key, current));
    if (fail) throw StateError('controlled offline');
    return pending[selection.key]?.future ??
        OfficialListeningReport.parse(
          footprint145Report(selection, minutes: minutes),
        );
  }

  @override
  Future<OfficialTodaySongs> todaySongs(String day) async {
    songReads++;
    if (fail) throw StateError('controlled offline');
    return pendingSongs?.future ??
        OfficialTodaySongs.parse(footprint145Songs(day), day: day);
  }

  @override
  Future<OfficialYearlyFootprint> years() async {
    yearReads++;
    if (fail) throw StateError('controlled offline');
    return OfficialYearlyFootprint.parse(footprint145Years());
  }
}

void main() {
  test(
    'China Sunday weeks and leap-month navigation match official end-minus-hour history',
    () {
      final week = FootprintPeriod.containing(
        DateTime.utc(2026, 10, 31, 16),
        FootprintScale.week,
      );
      expect(week.firstDay, '2026-11-01');
      expect(week.lastDay, '2026-11-07');
      expect(week.move(-1).firstDay, '2026-10-25');
      expect(
        FootprintPeriod.containing(
          DateTime.utc(2024, 2, 12),
          FootprintScale.month,
        ).dayKeys.length,
        29,
      );
      final month = FootprintPeriod.containing(
        footprint145Now,
        FootprintScale.month,
      );
      expect(month.move(-1).historyEnd, footprintHistoryEnd('2026-10'));
      expect(month.move(-11).firstDay, '2025-12-01');
      expect(month.canMove(1, footprint145Now), isFalse);
      expect(month.canMove(-37, footprint145Now), isFalse);
    },
  );

  test(
    'report parser preserves category seconds, reported day count, covers and absent buckets',
    () {
      final selection = FootprintPeriod.containing(
        footprint145Now,
        FootprintScale.week,
      );
      final report = OfficialListeningReport.parse(
        footprint145Report(selection),
      );
      expect(report.period.seconds, 195 * 60);
      expect(report.listenDays, 3);
      expect(report.days['2026-11-02']!.seconds, 72 * 60);
      expect(report.days['2026-11-02']!.podcastSeconds, 12 * 60);
      expect(report.days['2026-11-03']!.audiobookSeconds, 3 * 60);
      expect(report.days['2026-11-04'], isNull);
      expect(report.todayListening!.songCount, 43);
      expect(report.todayListening!.covers, hasLength(5));
      expect(report.forSelection(selection, current: true), same(report));
      expect(
        () => report.forSelection(selection.move(-1), current: false),
        throwsFormatException,
      );
    },
  );

  test(
    'valid zero remains zero while malformed and fallback calendar reports fail',
    () {
      final selection = FootprintPeriod.containing(
        footprint145Now,
        FootprintScale.month,
      );
      final response = footprint145Report(selection, minutes: 0);
      final data = response['data'] as Map;
      final block = data['listenTimeDistributionBlock'] as Map;
      (block['durationDetails'] as List).first['duration'] = 0;
      final zero = OfficialListeningReport.parse(response);
      expect(zero.period.seconds, 0);
      expect(zero.days[selection.firstDay]!.seconds, 0);
      (block['durationDetails'] as List).first.remove('duration');
      expect(
        () => OfficialListeningReport.parse(response),
        throwsFormatException,
      );
    },
  );

  test(
    'annual playDuration is seconds for every year including 2024, never invented months',
    () {
      final annual = OfficialYearlyFootprint.parse(footprint145Years());
      expect(annual.years.map((y) => y.year), [2023, 2024, 2025]);
      expect(annual.years[1].seconds, 360121);
      expect(annual.years.last.songCount, 1831);
      final response = footprint145Years(),
          rows = (response['data'] as Map)['yearItems'] as List;
      rows.add(rows.first);
      expect(
        () => OfficialYearlyFootprint.parse(response),
        throwsFormatException,
      );
      expect(
        () => OfficialYearlyFootprint.parse({'code': 200, 'data': {}}),
        throwsFormatException,
      );
    },
  );

  test(
    'today songs use second timestamps, preserve aliases/artists, cap100 and reject other days',
    () {
      final today = OfficialTodaySongs.parse(
        footprint145Songs('2026-11-03', count: 105),
        day: '2026-11-03',
      );
      expect(today.songs, hasLength(100));
      expect(today.songs.first.alias, 'Piano version');
      expect(today.songs.first.artists, ['陈奕迅']);
      expect(today.songs.first.redStar, isTrue);
      expect(today.songs.first.lastPlayedAt, DateTime.utc(2026, 11, 3, 3));
      expect(
        () => OfficialTodaySongs.parse(
          footprint145Songs('2026-11-02'),
          day: '2026-11-03',
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'repository sends exact read-only report/year/today requests and rejects server interval fallback',
    () async {
      final requests = <(String, Map<String, dynamic>)>[];
      var fallback = false;
      final week = FootprintPeriod.containing(
        footprint145Now,
        FootprintScale.week,
      );
      final month = FootprintPeriod.containing(
        footprint145Now,
        FootprintScale.month,
      );
      final client = MockClient((request) async {
        final payload = eapiBody(request), path = request.url.path;
        requests.add((path, payload));
        final Object response;
        if (path.endsWith('/year/report')) {
          response = footprint145Years();
        } else if (path.endsWith('/today/song/play/rank')) {
          response = footprint145Songs('2026-11-03');
        } else {
          final isWeek = payload['type'] == 'week';
          final period = isWeek ? week : month;
          response = footprint145Report(
            path.endsWith('/realtime/report') || fallback
                ? period
                : period.move(-1),
          );
        }
        return http.Response(
          jsonEncode(response),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      addTearDown(client.close);
      final api = NeteaseApi(client)..configure(session);
      final repository = OfficialFootprintRepository(api);
      await repository.report(week, current: true);
      await repository.report(week.move(-1), current: false);
      await repository.report(month.move(-1), current: false);
      await repository.years();
      await repository.todaySongs('2026-11-03');
      expect(
        requests[0].$1,
        '/eapi/content/activity/listen/data/realtime/report',
      );
      expect(requests[0].$2['type'], 'week');
      expect(requests[0].$2.containsKey('endTime'), isFalse);
      expect(requests[1].$2['endTime'], week.move(-1).historyEnd);
      expect(requests[2].$2['endTime'], month.move(-1).historyEnd);
      for (final (_, payload) in requests) {
        expect(payload.keys, isNot(contains('logs')));
        expect(payload.keys, isNot(contains('realtime')));
      }
      expect(requests[3].$2.containsKey('year'), isFalse);
      expect(requests[4].$2.containsKey('day'), isFalse);
      fallback = true;
      await expectLater(
        repository.report(week.move(-1), current: false),
        throwsFormatException,
      );
    },
  );

  test(
    'total-only summary coalesces with full refresh and retains failed official success',
    () async {
      final source = FootprintFixture()..totalPending = Completer();
      final reader = OfficialFootprintReader(
        source,
        current: () => true,
        now: () => footprint145Now,
      );
      addTearDown(reader.dispose);
      final first = reader.refreshTotalOnly();
      reader.refreshTotalOnly();
      expect(source.weekReads, 0);
      expect(source.monthReads, 0);
      final full = reader.refresh();
      expect(source.totalReads, 1);
      source.totalPending!.complete(99900);
      await Future.wait([first, full]);
      expect(reader.total.value, 99900);
      final readAt = reader.total.readAt;
      source.totalPending = null;
      source.fail = true;
      await reader.refreshTotalOnly();
      expect(reader.total.failed, isTrue);
      expect(reader.total.value, 99900);
      expect(reader.total.readAt, readAt);
    },
  );

  test(
    'period switching isolates late responses and navigation retains successful per-period cache',
    () async {
      final source = Footprint145Fixture(),
          week = FootprintPeriod.containing(
            footprint145Now,
            FootprintScale.week,
          );
      source.pending[week.key] = Completer();
      final reader = ListeningFootprintReader(
        source,
        current: () => true,
        now: () => footprint145Now,
      );
      addTearDown(reader.dispose);
      final lateWeek = reader.loadSelected();
      reader.loadSelected();
      reader.selectScale(FootprintScale.month);
      await reader.loadSelected();
      final month = reader.report.value;
      expect(source.calls.where((c) => c.$1 == week.key), hasLength(1));
      source.pending[week.key]!.complete(
        OfficialListeningReport.parse(footprint145Report(week, minutes: 99)),
      );
      await lateWeek;
      expect(reader.report.value, same(month));
      reader.selectScale(FootprintScale.week);
      expect(reader.report.value!.period.seconds, 99 * 60);
      reader.move(-1);
      expect(reader.report.value, isNull);
      await reader.loadSelected();
      reader.move(1);
      expect(reader.report.value!.period.seconds, 99 * 60);
    },
  );

  test(
    'failed period and today refresh retain only their own prior official value and timestamp',
    () async {
      final source = Footprint145Fixture();
      final reader = ListeningFootprintReader(
        source,
        current: () => true,
        now: () => footprint145Now,
      );
      addTearDown(reader.dispose);
      await reader.refresh();
      final report = reader.report.value,
          at = reader.report.readAt,
          songs = reader.todaySongs.value;
      source.fail = true;
      await reader.refresh();
      expect(reader.report.value, same(report));
      expect(reader.report.readAt, at);
      expect(reader.report.failed, isTrue);
      expect(reader.todaySongs.value, same(songs));
      expect(reader.todaySongs.failed, isTrue);
      reader.move(-1);
      await reader.loadSelected();
      expect(reader.report.value, isNull);
      expect(reader.report.failed, isTrue);
    },
  );

  test(
    'year navigation uses actual returned years and does not fabricate missing current year',
    () async {
      final reader = ListeningFootprintReader(
        Footprint145Fixture(),
        current: () => true,
        now: () => footprint145Now,
      );
      addTearDown(reader.dispose);
      reader.selectScale(FootprintScale.year);
      await reader.loadSelected();
      expect(reader.selection.civilStart.year, 2025);
      expect(reader.canMove(1), isFalse);
      reader.move(-1);
      expect(reader.selection.civilStart.year, 2024);
      reader.selectYear(2026);
      expect(reader.selection.civilStart.year, 2024);
      reader.move(-1);
      expect(reader.canMove(-1), isFalse);
    },
  );

  test(
    'account invalidation and dispose prevent late data and subsequent reads',
    () async {
      final source = Footprint145Fixture()..pendingSongs = Completer();
      var current = true;
      final reader = ListeningFootprintReader(
        source,
        current: () => current,
        now: () => footprint145Now,
      );
      final pending = reader.loadToday();
      current = false;
      source.pendingSongs!.complete(
        OfficialTodaySongs.parse(
          footprint145Songs('2026-11-03'),
          day: '2026-11-03',
        ),
      );
      await pending;
      expect(reader.todaySongs.value, isNull);
      await reader.refresh();
      expect(source.calls, isEmpty);
      reader.dispose();
      current = true;
      await reader.loadSelected();
      expect(source.calls, isEmpty);
    },
  );

  test(
    'midnight cannot relabel old today list and realtime response cannot overwrite new-day report',
    () async {
      var now = DateTime.utc(2026, 11, 3, 15, 59);
      final source = Footprint145Fixture();
      final reader = ListeningFootprintReader(
        source,
        current: () => true,
        now: () => now,
      );
      addTearDown(reader.dispose);
      await reader.loadToday();
      await reader.loadSelected();
      expect(reader.todayListening!.songCount, 43);
      final key = reader.selection.key;
      final completer = Completer<OfficialListeningReport>();
      source.pending[key] = completer;
      final old = reader.loadSelected(force: true);
      now = now.add(const Duration(minutes: 2));
      expect(reader.todayListening, isNull);
      source.pending.clear();
      source.minutes = 210;
      await reader.refresh();
      expect(reader.todaySongs.value!.day, '2026-11-04');
      expect(reader.report.value!.period.seconds, 210 * 60);
      completer.complete(
        OfficialListeningReport.parse(
          footprint145Report(reader.selection, minutes: 9),
        ),
      );
      await old;
      expect(reader.report.value!.period.seconds, 210 * 60);
      expect(reader.report.failed, isFalse);
    },
  );
}
