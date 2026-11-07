import '../domain/platform_rewards.dart';
import '../domain/platform_session.dart';
import 'music_platform_api.dart';

/// Protocol surface for deterministic controller tests and future API changes.
abstract interface class PlatformRewardService {
  Future<RewardSnapshot> load(PlatformSession owner);
  Future<RewardOutcome> signIn(
    PlatformSession owner,
    DateTime day, {
    RewardVerifier? verify,
  });
  Future<RewardOutcome> listen(PlatformSession owner);
  Future<RewardOutcome> ad(PlatformSession owner);
}

/// The existing embedded server already owns signing and all youth/verify
/// routes. Never log credentials, replay a timed-out write, or invent a reward.
/// Source: md3Music a69503b, kugou_provider.dart and kugou_api_client.dart.
class PlatformRewardsRepository implements PlatformRewardService {
  PlatformRewardsRepository(
    this.api, {
    DateTime Function()? clock,
    bool Function()? allowMutation,
  }) : _clock = clock ?? DateTime.now,
       _allowMutation = allowMutation ?? (() => true);
  final MusicPlatformApi api;
  final DateTime Function() _clock;
  final bool Function() _allowMutation;

  static int? code(Map<String, dynamic> value) =>
      int.tryParse('${value['error_code']}');
  static bool ok(Map<String, dynamic> value) =>
      '${value['status']}' == '1' ||
      (value['status'] == null && code(value) == 0);

  @override
  Future<RewardSnapshot> load(PlatformSession owner) async {
    Future<Map<String, dynamic>?> read(String path) async {
      try {
        return await api.get(path, expectedSession: owner);
      } on Object {
        return null;
      }
    }

    final results = await Future.wait([
      read('/youth/month/vip/record'),
      read('/user/vip/detail'),
      read('/server/now'),
    ]);
    final server = results[2];
    final timeData = MusicPlatformApi.objectMap(server?['data'] ?? server);
    final timestamp = num.tryParse('${timeData['timestamp']}');
    final now = timestamp == null || timestamp <= 0
        ? _clock()
        : DateTime.fromMillisecondsSinceEpoch(
            (timestamp > 100000000000 ? timestamp : timestamp * 1000).round(),
          );
    return RewardSnapshot(
      now: now,
      signedDates: results[0] == null
          ? const {}
          : parseRewardDates(results[0]!),
      memberships: results[1] == null
          ? const []
          : VipEntitlement.parse(results[1]!),
      recordsAvailable: results[0] != null,
      membershipsAvailable: results[1] != null,
    );
  }

  Future<Map<String, dynamic>> _post(
    String path,
    PlatformSession owner, {
    Map<String, String> query = const {},
  }) {
    // An already-started request cannot be recalled, but diagnostics starting
    // between reward steps must prevent the next upgrade/verification write.
    if (!_allowMutation()) {
      throw const MusicPlatformException('流畅度诊断期间暂停奖励领取');
    }
    return api.post(path, query: query, expectedSession: owner);
  }

  @override
  Future<RewardOutcome> signIn(
    PlatformSession owner,
    DateTime day, {
    RewardVerifier? verify,
  }) async {
    // A verified challenge permits one retry. Ordinary transport failures do
    // not: the platform might already have processed a timed-out POST.
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final claim = await _post(
          '/youth/day/vip',
          owner,
          query: {'receive_day': rewardDateKey(day)},
        );
        _challenge(claim);
        if (!ok(claim) && code(claim) != 131001) {
          return RewardOutcome(false, _error(claim));
        }
        final upgrade = await _post('/youth/day/vip/upgrade', owner);
        _challenge(upgrade);
        if (!ok(upgrade) && !{20030, 20033, 131001}.contains(code(upgrade))) {
          return RewardOutcome(false, '畅听会员已领取，概念会员升级失败：${_error(upgrade)}');
        }
        return const RewardOutcome(true, '签到成功，概念会员已确认', signed: true);
      } on _VerificationRequired catch (request) {
        if (verify == null || attempt != 0) {
          return const RewardOutcome(
            false,
            '签到需要安全验证，请在签到日历中重试',
            needsVerification: true,
          );
        }
        final info = await api.get(
          '/get/verify/info',
          query: {'eventid': request.eventId},
          expectedSession: owner,
          allowBusinessError: true,
        );
        final data = MusicPlatformApi.objectMap(info['data']);
        final type = int.tryParse('${data['v_type'] ?? 23}');
        final appId = '${data['txappid'] ?? ''}';
        if (type != 23 || !RegExp(r'^\d{1,32}$').hasMatch(appId)) {
          return const RewardOutcome(false, '平台要求其他安全验证，请先在酷狗完成后重试');
        }
        final proof = await verify(
          RewardVerification(eventId: request.eventId, appId: appId),
        );
        if (proof == null || proof.isEmpty) {
          return const RewardOutcome(false, '安全验证未完成，签到已停止');
        }
        if (!_allowMutation()) {
          return const RewardOutcome(false, '流畅度诊断期间暂停安全验证与签到');
        }
        final result = await api.get(
          '/verify/user/info',
          query: {
            'eventid': request.eventId,
            'v_type': '23',
            'verifycode': proof,
          },
          expectedSession: owner,
          allowBusinessError: true,
        );
        if (!ok(result)) {
          return RewardOutcome(false, '安全验证失败：${_error(result)}');
        }
      }
    }
    return const RewardOutcome(false, '验证后平台仍拒绝签到，请稍后重试');
  }

  void _challenge(Map<String, dynamic> response) {
    final data = MusicPlatformApi.objectMap(response['data']);
    final event =
        '${response['ssaCode'] ?? data['ssaCode'] ?? response['eventid'] ?? ''}';
    if (code(response) == 20028 && event.isNotEmpty) {
      throw _VerificationRequired(event);
    }
  }

  @override
  Future<RewardOutcome> listen(PlatformSession owner) async {
    final result = await _post('/youth/listen/song', owner);
    if (ok(result)) return const RewardOutcome(true, '听歌领取成功');
    if (code(result) == 130012) return const RewardOutcome(true, '今日听歌奖励已领取');
    return RewardOutcome(false, '听歌领取失败：${_error(result)}');
  }

  @override
  Future<RewardOutcome> ad(PlatformSession owner) async {
    final result = await _post('/youth/vip', owner);
    if (ok(result)) return const RewardOutcome(true, '广告领取成功');
    if (code(result) == 30002) {
      return const RewardOutcome(true, '今日广告次数已用完', quotaDone: true);
    }
    return RewardOutcome(false, '广告领取失败：${_error(result)}');
  }

  String _error(Map<String, dynamic> value) => switch (code(value)) {
    130012 || 131001 || 20033 => '今日已领取',
    30002 || 20034 => '今日领取次数已用完',
    20006 => '签名失效，请重新登录后重试',
    20018 => '登录已过期，请重新登录',
    20010 => '平台拒绝了请求参数，请稍后重试',
    20028 => '平台要求安全验证或账号暂不符合领取条件',
    20030 => '概念会员已升级',
    final error => '平台暂未确认成功（${error ?? '未知错误'}），请稍后重试',
  };
}

class _VerificationRequired implements Exception {
  const _VerificationRequired(this.eventId);
  final String eventId;
}
