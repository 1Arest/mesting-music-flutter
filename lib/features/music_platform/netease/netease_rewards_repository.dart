import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/cache/browse_response_cache.dart';
import '../domain/platform_rewards.dart' show rewardDateKey;
import 'netease_music_repository.dart';
import 'netease_reward_journal.dart';
import 'netease_rewards.dart';

/// NetEase's daily task and direct free-listening rights are separate writes.
/// Native 9.6.15 still signs through point/dailyTask; direct rights use the
/// source issued by the platform, rather than fabricated ad exposure records.
/// Static protocol evidence and runtime acceptance are documented separately.
class NeteaseRewardsRepository implements NeteaseRewardService {
  NeteaseRewardsRepository(
    this.music, {
    SharedPreferences? preferences,
    bool Function()? allowMutation,
    DateTime Function()? clock,
  }) : _journal = NeteaseRewardJournal(preferences),
       _allowMutation = allowMutation ?? (() => true),
       _clock = clock ?? DateTime.now,
       ownerId = 'netease:${music.api.session?.userId ?? ''}';

  final NeteaseMusicRepository music;
  final NeteaseRewardJournal _journal;
  final bool Function() _allowMutation;
  final DateTime Function() _clock;
  @override
  final String ownerId;
  bool _writing = false;

  static const balancePath = '/api/ad/homepage/free/tab/asset';
  static const progressPath = '/api/ad/homepage/free/tab/continuous_rights';
  static const qualificationPath = '/api/ad/listening/rights/qualification';
  static const claimPath = '/api/ad/listening/rights/gain';

  bool get _current =>
      music.credential != null &&
      music.api.session?.credentialId == music.credential &&
      'netease:${music.api.session?.userId}' == ownerId;
  bool get _canWrite => _current && _allowMutation();
  static int? _integer(Object? value) => int.tryParse('$value');
  static int? _nonnegative(Object? value) {
    final number = _integer(value);
    return number != null && number >= 0 ? number : null;
  }

  static bool? _boolean(Object? value) => switch (value) {
    true || 1 || '1' || 'true' => true,
    false || 0 || '0' || 'false' => false,
    _ => null,
  };
  static Map<String, dynamic> _object(Object? value) =>
      NeteaseMusicRepository.object(value);
  static bool _ok(Map<String, dynamic> value) => _integer(value['code']) == 200;

  Future<Map<String, dynamic>> _request(
    String path, [
    Map<String, Object?> data = const {},
  ]) => BrowseResponseCache.live(
    () => music.api.request(
      path,
      data,
      expectedCredential: music.credential,
      allowBusinessError: true,
    ),
  );

  Future<Map<String, dynamic>?> _read(
    String path, [
    Map<String, Object?> data = const {},
  ]) async {
    if (!_current) return null;
    try {
      final result = await _request(path, data);
      return _current && _ok(result) ? result : null;
    } on Object {
      return null;
    }
  }

  Future<bool?> _signedToday() async {
    final id = music.api.session?.userId;
    if (id == null) return null;
    final requestedDay = rewardDateKey(_clock());
    final profile = await _read('/api/v1/user/detail/$id');
    // The official profile parser reads mobileSign from the root response.
    // A missing field stays unknown, even when the response has code 200.
    return profile == null || requestedDay != rewardDateKey(_clock())
        ? null
        : _boolean(profile['mobileSign']);
  }

  @override
  Future<NeteaseRewardSnapshot> load() async {
    final requestedDay = rewardDateKey(_clock());
    final values = await Future.wait<Object?>([
      _signedToday(),
      _read(balancePath),
      _read(progressPath, const {'entranceType': 'FREE_LISTEN'}),
    ]);
    final now = _clock();
    // The profile may finish before the balance. If another read spans
    // midnight, none of that previous day's daily facts belong to `now`.
    final sameDay = requestedDay == rewardDateKey(now);
    final signed = sameDay ? values[0] as bool? : null;
    return NeteaseRewardSnapshot(
      now: now,
      signedToday: signed,
      recordsAvailable: signed != null,
      signedDates: signed == true ? {rewardDateKey(now)} : const {},
      freeListen: sameDay
          ? parseFreeListen(
              values[1] as Map<String, dynamic>?,
              values[2] as Map<String, dynamic>?,
            )
          : null,
      message: sameDay ? null : '日期已变化，请重新刷新签到与免费听',
    );
  }

  /// Only explicitly mapped server fields may become balances or progress.
  /// Unknown response layouts are kept unavailable instead of guessed as zero.
  static NeteaseFreeListenSnapshot? parseFreeListen(
    Map<String, dynamic>? balance,
    Map<String, dynamic>? progress,
  ) {
    final free = _object(_object(balance?['data'])['freeListen']);
    final remainingMs = _nonnegative(free['rightsRemainingTime']);
    final tasks = _object(progress?['data']);
    String? text(Object? value) =>
        value is String && value.trim().isNotEmpty ? value.trim() : null;
    final rows = tasks['tasks'];
    final milestones = <NeteaseRewardMilestone>[
      if (rows is List)
        for (final row in rows.whereType<Map>())
          if (text(row['label']) case final String label)
            NeteaseRewardMilestone(
              label: label,
              done: row['state'] == 'DONE' ? true : null,
              count: _nonnegative(row['doneCount']),
            ),
    ];
    final title = text(tasks['title']), subtitle = text(tasks['subTitle']);
    if (remainingMs == null &&
        milestones.isEmpty &&
        title == null &&
        subtitle == null) {
      return null;
    }
    return NeteaseFreeListenSnapshot(
      // Official native code calls this countDownTimeMills; the RN timer also
      // combines it with Date.now(). Durations cannot be treated as seconds.
      remainingSeconds: remainingMs == null ? null : remainingMs ~/ 1000,
      progressTitle: title,
      progressSubtitle: subtitle,
      milestones: milestones,
    );
  }

  static NeteaseRewardResult _refusal(Map<String, dynamic> value) {
    final code = _integer(value['code']);
    final verification = {405, 415, 460}.contains(code);
    return NeteaseRewardResult(
      success: false,
      needsVerification: verification,
      uncertain: code == null,
      message: switch (code) {
        301 || 302 => '网易云登录已失效，请重新登录后重试',
        405 || 415 || 460 => '网易云要求安全验证，本次领取已停止',
        null => '平台回执不完整，请刷新核对；不会自动重复提交',
        _ => '网易云暂未同意本次请求（$code），本次操作已停止',
      },
    );
  }

  Future<NeteaseRewardResult> _exclusive(
    Future<NeteaseRewardResult> Function() operation,
  ) async {
    if (!_canWrite) {
      return const NeteaseRewardResult(
        success: false,
        message: '账号已变化或诊断正在运行，本次操作已停止',
      );
    }
    if (_writing) {
      return const NeteaseRewardResult(success: false, message: '当前领取尚未完成，请稍候');
    }
    _writing = true;
    try {
      return await operation();
    } on Object {
      // The journal remains pending if transport or decoding failed after the
      // write. Neither this repository nor the HTTP layer retries that POST.
      return const NeteaseRewardResult(
        success: false,
        uncertain: true,
        message: '请求结果未确认，请刷新核对；不会自动重复提交',
      );
    } finally {
      _writing = false;
    }
  }

  @override
  Future<NeteaseRewardResult> signIn() => _exclusive(() async {
    final requestedDay = rewardDateKey(_clock());
    final observation = await _signedToday();
    final day = rewardDateKey(_clock());
    final signed = requestedDay == day ? observation : null;
    if (!_canWrite) {
      return const NeteaseRewardResult(success: false, message: '账号已变化或诊断已启动');
    }
    if (signed == true) {
      await _journal.clear(ownerId, 'sign');
      return NeteaseRewardResult(
        success: true,
        signed: true,
        signedDate: rewardDateKey(_clock()),
        message: '网易云今日签到已确认',
      );
    }
    final pending = _journal.read(ownerId, 'sign');
    if (pending != null &&
        (pending['unreadable'] == true || pending['day'] == day)) {
      return const NeteaseRewardResult(
        success: false,
        uncertain: true,
        message: '上次签到结果尚未核实，请刷新核对；本次不会重复提交',
      );
    }
    await _journal.begin(ownerId, 'sign', {'day': day});
    if (!_canWrite || day != rewardDateKey(_clock())) {
      await _journal.clear(ownerId, 'sign');
      return const NeteaseRewardResult(
        success: false,
        message: '签到已停止，请刷新当前账号与日期后重试',
      );
    }
    final result = await _request('/api/point/dailyTask', {'type': 0});
    final code = _integer(result['code']);
    if (code != 200 && code != -2) {
      if (code != null) await _journal.clear(ownerId, 'sign');
      return _refusal(result);
    }
    await _journal.clear(ownerId, 'sign');
    final receivedDay = rewardDateKey(_clock());
    // Across midnight, a receipt alone cannot identify which calendar date
    // was credited. Confirm today's independent state before marking a date.
    final confirmed = receivedDay == day || await _signedToday() == true;
    return NeteaseRewardResult(
      success: true,
      signed: confirmed,
      signedDate: confirmed ? receivedDay : null,
      message: !confirmed
          ? '签到请求已确认，日期已变化，请刷新签到记录'
          : code == -2
          ? '网易云今日已签到'
          : '网易云签到成功${_nonnegative(result['point']) == null ? '' : '，获得 ${_nonnegative(result['point'])} 积分'}',
    );
  });

  @override
  Future<NeteaseRewardResult> claimAd({
    bool Function()? stillCurrent,
  }) => _exclusive(() async {
    bool current() => _canWrite && (stillCurrent?.call() ?? true);
    if (!current()) {
      return const NeteaseRewardResult(success: false, message: '领取已停止');
    }
    final day = rewardDateKey(_clock());
    final pending = _journal.read(ownerId, 'ad');
    // There is no independently proven per-claim receipt lookup in this
    // protocol. An ambiguous ad write stays blocked for this day; merely
    // seeing a higher balance cannot attribute it to this exact request.
    if (pending != null &&
        (pending['unreadable'] == true || pending['day'] == day)) {
      return const NeteaseRewardResult(
        success: false,
        uncertain: true,
        message: '上次领取结果尚未核实，本次不会重复提交，请核对平台记录',
      );
    }
    final userId = _integer(music.api.session?.userId);
    if (userId == null || userId <= 0) {
      return const NeteaseRewardResult(
        success: false,
        message: '网易云账号资料不完整，请重新登录',
      );
    }
    // Qualification is read with the real account only. The server supplies
    // the entry/source and right type; no ad completion or identity is forged.
    final qualification = await _request(qualificationPath, {
      // The native qualification caller supplies an object, unlike the gain
      // form's JSON string. A minimum real-account query is attempted here;
      // whether a current account needs further entry parameters is unverified.
      'reqParam': {'userId': userId},
    });
    if (!current()) {
      return const NeteaseRewardResult(success: false, message: '领取已停止');
    }
    if (!_ok(qualification)) return _refusal(qualification);
    final hint = _object(qualification['data']);
    if (day != rewardDateKey(_clock())) {
      return const NeteaseRewardResult(
        success: false,
        message: '日期已变化，请刷新领取资格后重试',
      );
    }
    if (_boolean(hint['qualified']) != true) {
      return const NeteaseRewardResult(
        success: false,
        message: '网易云暂未提供直接领取资格，已停止本次领取',
      );
    }
    final params = <String, Object?>{'userId': userId};
    // These are descriptive entitlement values from the qualification result.
    // Ad reqUid, exposure/click times, appInfo and video proof are excluded.
    for (final key in const [
      'source',
      'creativeType',
      'rightsGainMethod',
      'rightsGainType',
      'rightsGainDuration',
      'nextRightsGainDuration',
      'extraRightsType',
      'extraRightsGainMethod',
      'extraRightsGainDuration',
      'gainMethodStep',
    ]) {
      final value = hint[key];
      if (value is String || value is num || value is bool) params[key] = value;
    }
    if (params['source'] == null || '${params['source']}'.isEmpty) {
      return const NeteaseRewardResult(
        success: false,
        message: '网易云未返回领取来源，无法直接申请本次奖励',
      );
    }
    await _journal.begin(ownerId, 'ad', {'day': day});
    if (!current() || day != rewardDateKey(_clock())) {
      await _journal.clear(ownerId, 'ad');
      return const NeteaseRewardResult(success: false, message: '领取已停止');
    }
    final result = await _request(claimPath, {'reqParam': jsonEncode(params)});
    if (!_ok(result)) {
      if (_integer(result['code']) != null) await _journal.clear(ownerId, 'ad');
      return _refusal(result);
    }
    final data = _object(result['data']);
    final gained = _boolean(data['gainFlag']);
    if (gained == null) {
      return const NeteaseRewardResult(
        success: false,
        uncertain: true,
        message: '网易云未返回明确领取结果，请刷新核对；不会自动重试',
      );
    }
    await _journal.clear(ownerId, 'ad');
    final quota = !gained && _boolean(data['rightsUpperLimit']) == true;
    return NeteaseRewardResult(
      success: gained,
      quotaDone: quota,
      message: gained
          ? '网易云广告奖励已确认，正在刷新实际时长'
          : quota
          ? '网易云提示本次权益已达上限，已停止领取'
          : '网易云未同意直接领取，可能需要广告凭证或暂不符合条件，已停止',
    );
  });
}
