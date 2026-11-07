import 'official_footprint.dart';

/// Public listen-home contracts, independently of local playback diagnostics.
/// Report durations are minutes on the wire; total and yearly durations are
/// seconds. Every public value in this file is normalized to seconds once.
enum FootprintScale { week, month, year }

/// A civil-calendar selection always uses the official China timezone. The
/// official page uses startOf('week'), whose week begins on Sunday.
class FootprintPeriod {
  const FootprintPeriod._(this.scale, this.civilStart);
  final FootprintScale scale;
  final DateTime civilStart;

  factory FootprintPeriod.containing(DateTime instant, FootprintScale scale) {
    final d = footprintDate(instant);
    final day = DateTime.utc(d.year, d.month, d.day);
    return FootprintPeriod._(scale, switch (scale) {
      FootprintScale.week => day.subtract(Duration(days: day.weekday % 7)),
      FootprintScale.month => DateTime.utc(day.year, day.month),
      FootprintScale.year => DateTime.utc(day.year),
    });
  }

  DateTime get start => civilStart.subtract(const Duration(hours: 8));
  DateTime get civilEnd => switch (scale) {
    FootprintScale.week => civilStart.add(const Duration(days: 7)),
    FootprintScale.month => DateTime.utc(civilStart.year, civilStart.month + 1),
    FootprintScale.year => DateTime.utc(civilStart.year + 1),
  };
  DateTime get end => civilEnd.subtract(const Duration(hours: 8));
  String get firstDay => footprintDay(start);
  String get lastDay =>
      footprintDay(end.subtract(const Duration(milliseconds: 1)));
  String get key => '${scale.name}:$firstDay';
  String get type => scale.name;
  bool isCurrent(DateTime now) =>
      key == FootprintPeriod.containing(now, scale).key;

  /// Official history navigation submits endOf(period) minus one hour. Never
  /// send the device's timezone or an arbitrary current timestamp as history.
  int get historyEnd => end
      .subtract(const Duration(hours: 1, milliseconds: 1))
      .millisecondsSinceEpoch;

  FootprintPeriod move(int amount) => FootprintPeriod._(scale, switch (scale) {
    FootprintScale.week => civilStart.add(Duration(days: 7 * amount)),
    FootprintScale.month => DateTime.utc(
      civilStart.year,
      civilStart.month + amount,
    ),
    FootprintScale.year => DateTime.utc(civilStart.year + amount),
  });

  bool canMove(int amount, DateTime now) {
    final candidate = move(amount);
    if (candidate.start.isAfter(now)) return false;
    // Match the public page's three-year history boundary. Entitlement and
    // report availability remain server decisions, never guessed VIP values.
    final civilNow = footprintDate(now);
    final oldest = DateTime.utc(
      civilNow.year - 3,
      civilNow.month,
      civilNow.day,
    );
    return !candidate.civilEnd.isBefore(oldest) &&
        candidate.civilEnd.isAfter(DateTime.utc(2020, 9, 18));
  }

  List<String> get dayKeys => [
    for (
      var day = start;
      day.isBefore(end);
      day = day.add(const Duration(days: 1))
    )
      footprintDay(day),
  ];
}

Map<String, dynamic> _object(Object? value) {
  if (value is! Map) throw const FormatException('官方足迹结构暂不支持');
  return Map<String, dynamic>.from(value);
}

int _integer(Object? value, {int max = 1000000000000}) {
  final n = value is num ? value : num.tryParse('$value');
  if (n == null || !n.isFinite || n < 0 || n > max || n != n.round()) {
    throw const FormatException('官方足迹字段暂不可用');
  }
  return n.toInt();
}

String _text(Object? value) => value is String ? value.trim() : '';

/// An optional category that is absent in an otherwise valid daily record is
/// zero, as on the official chart. An absent *day* stays absent, never zero.
class OfficialFootprintDay {
  const OfficialFootprintDay({
    required this.day,
    required this.songSeconds,
    required this.podcastSeconds,
    required this.audiobookSeconds,
  });
  final String day;
  final int songSeconds, podcastSeconds, audiobookSeconds;
  int get seconds => songSeconds + podcastSeconds + audiobookSeconds;
}

class OfficialTodayListening {
  const OfficialTodayListening({required this.songCount, required this.covers});
  final int? songCount;
  final List<String> covers;
}

class OfficialListeningReport {
  const OfficialListeningReport({
    required this.period,
    required this.days,
    this.listenDays,
    this.todayListening,
  });
  final OfficialListenPeriod period;
  final Map<String, OfficialFootprintDay> days;
  final int? listenDays;
  final OfficialTodayListening? todayListening;

  factory OfficialListeningReport.parse(Object? response) {
    // The established parser owns date validity, duplicate-day rejection and
    // duration validation. Keep diagnostics and this presentation in agreement.
    final period = OfficialListenPeriod.parse(response);
    final data = footprintData(response);
    final block = _object(data['listenTimeDistributionBlock']);
    final rawDays = block['durationDetails'] as List? ?? const [];
    final days = <String, OfficialFootprintDay>{};
    for (final raw in rawDays) {
      final d = _object(raw), day = '${d['period']}';
      days[day] = OfficialFootprintDay(
        day: day,
        songSeconds: _integer(d['duration']) * 60,
        podcastSeconds: _integer(d['podcastDuration'] ?? 0) * 60,
        audiobookSeconds: _integer(d['audiobookDuration'] ?? 0) * 60,
      );
    }
    OfficialTodayListening? today;
    final rawToday = data['weekTodayListenBlock'];
    if (rawToday != null) {
      final b = _object(rawToday), covers = b['coverUrls'];
      if (covers != null && covers is! List) {
        throw const FormatException('官方今日封面暂不可用');
      }
      today = OfficialTodayListening(
        songCount: b['songCount'] == null ? null : _integer(b['songCount']),
        covers: List.unmodifiable(
          (covers as List? ?? const [])
              .map(_text)
              .where((url) => url.isNotEmpty),
        ),
      );
    }
    return OfficialListeningReport(
      period: period,
      days: Map.unmodifiable(days),
      listenDays: block['listenDays'] == null
          ? null
          : _integer(block['listenDays'], max: 366),
      todayListening: today,
    );
  }

  OfficialListeningReport forSelection(
    FootprintPeriod selected, {
    required bool current,
  }) {
    if (selected.scale == FootprintScale.year ||
        footprintDay(period.start) != selected.firstDay ||
        footprintDay(period.end).compareTo(selected.lastDay) > 0 ||
        (!current && footprintDay(period.end) != selected.lastDay)) {
      throw const FormatException('官方尚未返回所选区间报表');
    }
    return this;
  }
}

/// The official annual lazy module renders yearItems, not monthly series. Keep
/// annual totals as annual totals; no monthly estimate is manufactured here.
class OfficialFootprintYear {
  const OfficialFootprintYear({
    required this.year,
    required this.seconds,
    required this.songCount,
  });
  final int year, seconds, songCount;
}

class OfficialYearlyFootprint {
  const OfficialYearlyFootprint(this.years);
  final List<OfficialFootprintYear> years;
  factory OfficialYearlyFootprint.parse(Object? response) {
    final values = footprintData(response)['yearItems'];
    if (values is! List) throw const FormatException('官方年度足迹暂不可用');
    final years = <OfficialFootprintYear>[], seen = <int>{};
    for (final raw in values) {
      final r = _object(raw), year = _integer(r['year'], max: 2200);
      if (year < 2015 || !seen.add(year)) {
        throw const FormatException('官方年度日期暂不支持');
      }
      years.add(
        OfficialFootprintYear(
          year: year,
          seconds: _integer(r['playDuration']),
          songCount: _integer(r['playNum']),
        ),
      );
    }
    years.sort((a, b) => a.year.compareTo(b.year));
    return OfficialYearlyFootprint(List.unmodifiable(years));
  }
}

class OfficialFootprintSong {
  const OfficialFootprintSong({
    required this.id,
    required this.title,
    required this.alias,
    required this.cover,
    required this.artists,
    required this.lastPlayedAt,
    required this.redStar,
  });
  final String id, title, alias, cover;
  final List<String> artists;
  final DateTime lastPlayedAt;
  final bool redStar;
}

class OfficialTodaySongs {
  const OfficialTodaySongs({required this.day, required this.songs});
  final String day;
  final List<OfficialFootprintSong> songs;

  factory OfficialTodaySongs.parse(Object? response, {required String day}) {
    final values = footprintData(response)['songDTOs'];
    if (values is! List) throw const FormatException('官方今日歌曲暂不可用');
    final songs = <OfficialFootprintSong>[];
    for (final raw in values.take(100)) {
      final r = _object(raw);
      final id = _integer(r['songId']).toString(), title = _text(r['songName']);
      if (id == '0' || title.isEmpty || r['artists'] is! List) {
        throw const FormatException('官方歌曲信息暂不完整');
      }
      // Public todayList multiplies lastPlayTime by 1000: this is seconds,
      // unlike the report interval's startTime/endTime millisecond fields.
      final time = DateTime.fromMillisecondsSinceEpoch(
        _integer(r['lastPlayTime'], max: 10000000000) * 1000,
        isUtc: true,
      );
      if (footprintDay(time) != day) {
        throw const FormatException('官方尚未返回今日歌曲');
      }
      songs.add(
        OfficialFootprintSong(
          id: id,
          title: title,
          alias: _text(r['aliasName']),
          cover: _text(r['picUrl']),
          artists: List.unmodifiable(
            (r['artists'] as List)
                .map((a) => _text(_object(a)['artistName']))
                .where((a) => a.isNotEmpty),
          ),
          lastPlayedAt: time,
          redStar: r['redStar'] == true || r['redStar'] == 1,
        ),
      );
    }
    return OfficialTodaySongs(day: day, songs: List.unmodifiable(songs));
  }
}

/// Separate capability interface keeps old official-summary/diagnostic sources
/// and fixtures compatible. All these endpoints are read-only report reads.
abstract interface class OfficialFootprintDetailSource {
  Future<OfficialListeningReport> report(
    FootprintPeriod selection, {
    required bool current,
  });
  Future<OfficialYearlyFootprint> years();
  Future<OfficialTodaySongs> todaySongs(String day);
}
