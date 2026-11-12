import '../domain/kugou_listening_profile.dart';
import '../domain/platform_session.dart';
import 'kugou_official_api.dart';
import 'music_platform_api.dart';

/// 页面只接触已核实的读取合同；网络签名、设备注册和账号归属集中在传输层。
/// 此仓库没有任何伪造累计时长或回补历史记录的写入入口。
class KugouListeningProfileRepository {
  KugouListeningProfileRepository({
    required this.api,
    required this.official,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;

  final MusicPlatformApi api;
  final KugouOfficialApi official;
  final DateTime Function() clock;

  static const firstAnnualYear = 2019;
  static const lastAnnualYear = 2025;

  void _check(PlatformSession owner) {
    if (owner.platform != MusicPlatform.kugou || !official.isCurrent(owner)) {
      throw const KugouOfficialException('账号已变化，请返回后重新打开页面');
    }
  }

  Map<String, dynamic> _data(Map<String, dynamic> payload) {
    if (payload['data'] is! Map) {
      throw const KugouOfficialException('酷狗未返回这项资料，请稍后重试');
    }
    return kugouObject(payload['data']);
  }

  /// 日/周/月按官版实时或历史查询。年报有独立协议和单位，不能假定为同一接口。
  Future<KugouListeningStatistics> statistics(
    PlatformSession owner,
    KugouListenPeriod period,
    DateTime date,
  ) async {
    _check(owner);
    final normalized = period.start(date);
    if (period == KugouListenPeriod.year) {
      return _annual(owner, normalized);
    }
    final current = normalized == period.start(clock());
    final data = _data(
      await official.request(
        KugouOfficialRoute.statistics,
        owner,
        query: {
          'date_type': '${period.index}',
          'is_real_time': '$current',
          'is_entrance': 'false',
          'date': current ? '0' : _date(normalized),
        },
      ),
    );
    _check(owner);
    return KugouListeningStatistics(data, period, normalized, clock());
  }

  Future<KugouListeningStatistics> _annual(
    PlatformSession owner,
    DateTime date,
  ) async {
    final route = switch (date.year) {
      2019 => KugouOfficialRoute.annual2019,
      2020 => KugouOfficialRoute.annual2020,
      2021 => KugouOfficialRoute.annual2021,
      2022 => KugouOfficialRoute.annual2022,
      2023 => KugouOfficialRoute.annual2023,
      2024 || 2025 => KugouOfficialRoute.annual,
      _ => null,
    };
    if (route == null) {
      throw const KugouOfficialException('该年度的官方听歌报告尚未取得，可在官方报告页查看');
    }
    final raw = _data(
      await official.request(
        route,
        owner,
        query: {
          'field_list':
              'top10_scid,top3_singer,style_like,play_scids,play_days,play_times,top1_singer,play_count,top10_singer',
          if (date.year >= 2024) 'biz': 'v${date.year}',
        },
      ),
    );
    _check(owner);
    return KugouListeningStatistics(
      kugouAnnualStatistics(date.year, raw),
      KugouListenPeriod.year,
      date,
      clock(),
    );
  }

  Future<KugouGrade> grade(PlatformSession owner) async {
    _check(owner);
    // 新版官版等级页自己的 my_info 同时返回等级、乐龄基准和累计听歌分钟。
    // 不把Lite v2的读取改标成标准版v4，也不猜测v4加密参数。
    final data = _data(
      await official.request(KugouOfficialRoute.levelInfo, owner),
    );
    _check(owner);
    return KugouGrade({
      ...kugouObject(data['grade']),
      'timestamp': data['timestamp'],
    }, clock());
  }

  Future<KugouGradeRanking> ranking(
    PlatformSession owner,
    KugouGradeRank kind, {
    int page = 1,
  }) async {
    _check(owner);
    if (page < 1) {
      throw ArgumentError.value(page, 'page');
    }
    final data = _data(
      await official.request(
        KugouOfficialRoute.levelRank,
        owner,
        query: {'rank_type': '${kind.code}', 'page': '$page', 'pagesize': '50'},
      ),
    );
    _check(owner);
    return KugouGradeRanking(data, kind, page, clock());
  }

  Future<void> setRankLiked(
    PlatformSession owner,
    KugouGradeRank kind,
    String target, {
    required bool liked,
  }) async {
    _check(owner);
    final uid = int.tryParse(target);
    if (uid == null || uid <= 0) {
      throw const KugouOfficialException('这位用户的酷狗资料不完整，请刷新榜单');
    }
    await official.request(
      liked ? KugouOfficialRoute.levelLike : KugouOfficialRoute.levelUnlike,
      owner,
      body: {'target_userid': uid, 'rank_type': kind.code},
    );
    _check(owner);
  }

  Future<KugouRankingCities> rankingCities(PlatformSession owner) async {
    _check(owner);
    final data = _data(
      await official.request(
        KugouOfficialRoute.rankCities,
        owner,
        body: {
          'userid': int.parse(owner.userId),
          'token': owner.kugouOfficialToken,
        },
      ),
    );
    _check(owner);
    return KugouRankingCities(data, clock());
  }

  Future<void> setRankingCity(PlatformSession owner, String cityId) async {
    _check(owner);
    if (!RegExp(r'^\d{6}$').hasMatch(cityId)) {
      throw const KugouOfficialException('请选择官方地区列表中的有效城市');
    }
    await official.request(
      KugouOfficialRoute.setRankCity,
      owner,
      body: {
        'userid': int.parse(owner.userId),
        'token': owner.kugouOfficialToken,
        'city_id': cityId,
      },
    );
    _check(owner);
  }

  Future<KugouMusicProfile> profile(PlatformSession owner) async {
    _check(owner);
    final result = await api.get('/user/detail', expectedSession: owner);
    _check(owner);
    final data = _data(result);
    // servertime可在外层返回；只合并官方服务器时间，绝不回退为本机时间。
    if (!data.containsKey('servertime') && result.containsKey('servertime')) {
      data['servertime'] = result['servertime'];
    }
    return KugouMusicProfile(data, clock());
  }

  Future<KugouMedalCollection> medals(PlatformSession owner) async {
    _check(owner);
    final uid = int.tryParse(owner.userId);
    if (uid == null || uid <= 0) {
      throw const KugouOfficialException('酷狗账号信息不完整，请重新登录');
    }
    final result = await official.request(
      KugouOfficialRoute.medals,
      owner,
      body: {'target_userid': uid, 'req_ver': 4},
    );
    _check(owner);
    return KugouMedalCollection(_data(result), clock());
  }

  static String _date(DateTime value) =>
      '${value.year}'
      '${value.month.toString().padLeft(2, '0')}'
      '${value.day.toString().padLeft(2, '0')}';
}
