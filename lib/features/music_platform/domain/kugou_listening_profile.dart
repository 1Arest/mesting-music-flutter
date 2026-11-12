/// 官版听歌报告的日期维度：0日、1周、2月、3年。
enum KugouListenPeriod {
  day('日'),
  week('周'),
  month('月'),
  year('年');

  const KugouListenPeriod(this.label);
  final String label;
  DateTime start(DateTime value) => switch (this) {
    day => DateTime(value.year, value.month, value.day),
    week => DateTime(value.year, value.month, value.day - value.weekday + 1),
    month => DateTime(value.year, value.month),
    year => DateTime(value.year),
  };
  DateTime shift(DateTime value, int offset) => switch (this) {
    day => DateTime(value.year, value.month, value.day + offset),
    week => DateTime(value.year, value.month, value.day + offset * 7),
    month => DateTime(value.year, value.month + offset),
    year => DateTime(value.year + offset),
  };
}

Map<String, dynamic> kugouObject(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : const {};
int? kugouNonnegative(Object? value) {
  final n = num.tryParse('$value');
  return n != null && n.isFinite && n >= 0 ? n.toInt() : null;
}

String kugouDuration(int? seconds) {
  if (seconds == null) {
    return '尚未读取';
  }
  if (seconds < 60) {
    return '$seconds秒';
  }
  if (seconds < 3600) {
    return '${seconds ~/ 60}分${seconds % 60}秒';
  }
  return '${seconds ~/ 3600}小时${seconds % 3600 ~/ 60}分';
}

class KugouListeningStatistics {
  const KugouListeningStatistics(this.raw, this.period, this.date, this.readAt);
  final Map<String, dynamic> raw;
  final KugouListenPeriod period;
  final DateTime date, readAt;
  // listen_duration 是秒；grade_info.duration 在官版头部按分钟换算小时。
  int? get seconds => kugouNonnegative(raw['listen_duration']);
  int? get days => kugouNonnegative(raw['accumulate_listen_days']);
  int? get totalSeconds {
    final minutes = kugouNonnegative(
      kugouObject(raw['grade_info'])['duration'],
    );
    return minutes == null ? null : minutes * 60;
  }

  List<Map<String, dynamic>> rows(String key) => raw[key] is List
      ? (raw[key] as List).whereType<Map>().map(kugouObject).toList()
      : const [];
  // 官版月视图使用 months（逐月趋势），不是把日期数组假定为逐日资料。
  List<Map<String, dynamic>> get series => rows(switch (period) {
    KugouListenPeriod.day => 'clocks',
    KugouListenPeriod.week => 'dates',
    KugouListenPeriod.month => 'months',
    KugouListenPeriod.year => '',
  });
  bool get annual => period == KugouListenPeriod.year;
  int? get songCount =>
      kugouNonnegative(raw[annual ? 'song_count' : 'listen_total']);
}

class KugouGrade {
  const KugouGrade(this.raw, this.readAt);
  final Map<String, dynamic> raw;
  final DateTime readAt;
  int? get level => kugouNonnegative(raw['p_grade']);
  int? get nextLevel => kugouNonnegative(raw['p_next_grade']);
  int? get points => kugouNonnegative(raw['p_current_point']);
  int? get minimum => kugouNonnegative(raw['p_grade_point']);
  int? get nextPoints => kugouNonnegative(raw['p_next_grade_point']);
  int? get seconds {
    final nativeSeconds = kugouNonnegative(raw['d_sec']);
    final officialMinutes = kugouNonnegative(raw['duration']);
    return nativeSeconds ??
        (officialMinutes == null ? null : officialMinutes * 60);
  }

  String? get musicAge => kugouLevelMusicAge(raw['reg_time'], raw['timestamp']);
  double? get speed {
    final value = num.tryParse('${raw['p_speed']}');
    return value != null && value.isFinite && value > 0
        ? value.toDouble()
        : null;
  }

  double? get progress {
    final p = points, low = minimum, next = nextPoints;
    return p == null || low == null || next == null || next <= low
        ? null
        : ((p - low) / (next - low)).clamp(0.0, 1.0);
  }
}

/// 新版等级页的真实榜单类型；与听歌报告的好友榜完全独立。
enum KugouGradeRank {
  global(2, '全球年榜'),
  province(3, '省月榜'),
  city(4, '市周榜');

  const KugouGradeRank(this.code, this.label);
  final int code;
  final String label;
}

class KugouGradeRanking {
  const KugouGradeRanking(this.raw, this.kind, this.page, this.readAt);
  final Map<String, dynamic> raw;
  final KugouGradeRank kind;
  final int page;
  final DateTime readAt;
  List<Map<String, dynamic>> get items => raw['list'] is List
      ? (raw['list'] as List).whereType<Map>().map(kugouObject).toList()
      : const [];
  Map<String, dynamic> get self => kugouObject(raw['self_info']);
  Map<String, dynamic> get area => kugouObject(raw['area']);
  int? get total => kugouNonnegative(raw['total']);
  int? get periodEndTime => kugouNonnegative(raw['period_end_time']);
  bool hasMore(int loaded) => total != null && loaded < total!;
}

class KugouRankingCities {
  const KugouRankingCities(this.raw, this.readAt);
  final Map<String, dynamic> raw;
  final DateTime readAt;
  List<Map<String, dynamic>> get provinces => raw['items'] is List
      ? (raw['items'] as List).whereType<Map>().map(kugouObject).toList()
      : const [];
  static List<Map<String, dynamic>> cities(Map<String, dynamic> province) =>
      province['items'] is List
      ? (province['items'] as List).whereType<Map>().map(kugouObject).toList()
      : const [];
}

/// 20.8.6新等级H5用服务器timestamp计算天数，按360天/年、30天/月呈现。
/// 这一合同与旧个人资料的自然年月算法分开，缺少官方时间便不计算。
String? kugouLevelMusicAge(Object? registered, Object? serverSeconds) {
  final text = '${registered ?? ''}'.trim();
  final match = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})(?:[ T](\d{2}):(\d{2}):(\d{2}))?$',
  ).firstMatch(text);
  final seconds = num.tryParse('$serverSeconds');
  if (match == null ||
      seconds == null ||
      !seconds.isFinite ||
      seconds <= 0 ||
      seconds > 8640000000000) {
    return null;
  }
  final year = int.parse(match[1]!),
      month = int.parse(match[2]!),
      day = int.parse(match[3]!);
  final hour = int.parse(match[4] ?? '0'),
      minute = int.parse(match[5] ?? '0'),
      second = int.parse(match[6] ?? '0');
  final registeredAt = DateTime.utc(year, month, day, hour, minute, second);
  if (registeredAt.year != year ||
      registeredAt.month != month ||
      registeredAt.day != day ||
      hour > 23 ||
      minute > 59 ||
      second > 59) {
    return null;
  }
  // 注册文字是中国时区；转UTC后与服务器Unix秒比较，不取本机系统时间。
  final elapsed =
      (seconds * 1000 -
              registeredAt
                  .subtract(const Duration(hours: 8))
                  .millisecondsSinceEpoch)
          .floor();
  if (elapsed < 0) {
    return null;
  }
  final days = elapsed ~/ Duration.millisecondsPerDay;
  if (days < 30) {
    return '$days天';
  }
  if (days < 360) {
    return '${days ~/ 30}个月';
  }
  final years = days ~/ 360, months = days % 360 ~/ 30;
  return '$years年${months > 0 ? '$months个月' : ''}';
}

/// 只保存官方明确返回的个人资料；注册时间缺失时不借本机日期补齐。
class KugouMusicProfile {
  const KugouMusicProfile(this.raw, this.readAt);
  final Map<String, dynamic> raw;
  final DateTime readAt;
  String? get musicAge => kugouMusicAge(raw['reg_time'], raw['servertime']);
}

/// 原生首页的已获勋章摘要。完整分类、详情和佩戴管理归属官方返回的页面。
class KugouMedalCollection {
  const KugouMedalCollection(this.raw, this.readAt);
  final Map<String, dynamic> raw;
  final DateTime readAt;
  int? get total => kugouNonnegative(raw['total']);
  List<Map<String, dynamic>> get medals => raw['list'] is List
      ? (raw['list'] as List).whereType<Map>().map(kugouObject).toList()
      : const [];
  Uri? get officialPage => kugouOfficialMedalUri(raw['h5_url_index']);
}

/// 后端下发的勋章地址仍须约束为官方HTTPS域名，凭据不能跟随任意外链。
Uri? kugouOfficialMedalUri(Object? value) {
  final uri = Uri.tryParse('${value ?? ''}'.trim());
  return uri != null &&
          uri.scheme == 'https' &&
          uri.userInfo.isEmpty &&
          !uri.hasPort &&
          (uri.host == 'kugou.com' || uri.host.endsWith('.kugou.com'))
      ? uri
      : null;
}

/// 只有官版确实发布的年度协议可以转换为秒；未发布年份不可套用旧版字段。
Map<String, dynamic> kugouAnnualStatistics(int year, Map<String, dynamic> raw) {
  final data = year >= 2022 ? kugouObject(raw['year_data']) : raw;
  final all = kugouObject(data['play_all']);
  final yearAll = kugouObject(data['year_all']);
  final duration = switch (year) {
    2025 => kugouNonnegative(all['total_play_duration']),
    2024 => kugouNonnegative(yearAll['play_min']),
    2023 || 2022 || 2021 => kugouNonnegative(all['play_time']),
    2020 || 2019 => kugouNonnegative(data['play_times']),
    _ => null,
  };
  final durationIsMinutes = {2019, 2020, 2021, 2022, 2024}.contains(year);
  final songSource = switch (year) {
    2025 => kugouObject(data['year_play_list'])['list'],
    2024 => kugouObject(data['year_play_detail'])['song_list'],
    _ => data['top10_scid'],
  };
  final songs = <Map<String, dynamic>>[];
  for (final source
      in songSource is List ? songSource.whereType<Map>() : const <Map>[]) {
    final item = kugouObject(source);
    final audio = kugouObject(item['audio_info']);
    var title =
        '${item['songname'] ?? item['ori_audio_name'] ?? item['name'] ?? audio['songname'] ?? ''}';
    var singer = '${item['author_name'] ?? audio['author_name'] ?? ''}';
    if (year <= 2020 && item['name'] is String) {
      final parts = (item['name'] as String).split(' - ');
      if (parts.length > 1) {
        singer = parts.first;
        title = parts.skip(1).join(' - ');
      }
    }
    songs.add({
      'song_info': {
        'name': title,
        'singer_name': singer,
        'mixsongid': item['mixsongid'] ?? audio['mixsongid'],
        'cover': item['pic'] ?? audio['pic'],
      },
      'count':
          item['play_cnt'] ??
          item['num'] ??
          item['times'] ??
          item['play_times'],
    });
  }
  return {
    if (duration != null)
      'listen_duration': duration * (durationIsMinutes ? 60 : 1),
    'accumulate_listen_days': switch (year) {
      2025 => kugouObject(data['login_days'])['days'],
      2024 => yearAll['open_day'],
      2023 => data['active_days_year'],
      2022 => kugouObject(data['active_cnt'])['day_cnt'],
      _ => null,
    },
    'song_count': switch (year) {
      2025 => all['total_play_count'],
      2024 => yearAll['song_count'],
      2023 || 2022 || 2021 => all['play_song_num'],
      _ => data['play_count'],
    },
    'rank_song': songs,
  };
}

/// 乐龄依据官方注册时间和服务器时间计算自然年月，不使用本机累计时长。
String? kugouMusicAge(Object? registered, Object? server) {
  DateTime? timestamp(Object? value) {
    final text = '${value ?? ''}'.trim();
    // GuestUserInfoEntity 的注册/服务器时间可为中国时区日历文字。
    final calendar = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2})(?:[ T](\d{2}):(\d{2}):(\d{2}))?$',
    ).firstMatch(text);
    if (calendar != null) {
      final year = int.parse(calendar[1]!);
      final month = int.parse(calendar[2]!);
      final day = int.parse(calendar[3]!);
      if (calendar[4] != null &&
          (int.parse(calendar[4]!) > 23 ||
              int.parse(calendar[5]!) > 59 ||
              int.parse(calendar[6]!) > 59)) {
        return null;
      }
      final parsed = DateTime.utc(year, month, day);
      return parsed.year == year && parsed.month == month && parsed.day == day
          ? parsed
          : null;
    }
    final n = num.tryParse('$value');
    if (n == null || !n.isFinite || n <= 0 || n > 8640000000000000) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(
      (n < 100000000000 ? n * 1000 : n).toInt(),
      isUtc: true,
    ).add(const Duration(hours: 8));
  }

  final from = timestamp(registered), to = timestamp(server);
  if (from == null || to == null || to.isBefore(from)) {
    return null;
  }
  var months = (to.year - from.year) * 12 + to.month - from.month;
  if (to.day < from.day) {
    months--;
  }
  if (months < 1) {
    return '不足1个月';
  }
  return '${months ~/ 12 > 0 ? '${months ~/ 12}年' : ''}${months % 12 > 0 ? '${months % 12}个月' : ''}';
}
