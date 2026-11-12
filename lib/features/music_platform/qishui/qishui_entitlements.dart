import 'qishui_models.dart';

/// A read-only receipt of this account's commerce response. These values
/// describe server-reported rights; only the returned audio can prove whether
/// an individual recording is full length. Never derive rights from song tags,
/// task counts, an activity's end date, or a locally entered number of days.
class QishuiEntitlements {
  QishuiEntitlements(Map<String, dynamic> payload, {DateTime? now})
    : observedAt =
          _epoch(sodaMap(payload['status_info'])['now_ts_ms']) ??
          now ??
          DateTime.now(),
      listeningUntil = _epoch(
        sodaMap(payload['play_entitlements'])['expire_at'],
      ),
      incentiveUntil = sodaMap(payload['incentive'])['available'] == false
          ? null
          : _epoch(sodaMap(payload['incentive'])['expire_time']),
      membershipUntil = _epoch(sodaMap(payload['membership'])['expire_time']),
      membershipReported =
          sodaMap(payload['membership'])['is_membership'] == true;

  final DateTime observedAt;
  final DateTime? listeningUntil, incentiveUntil, membershipUntil;
  final bool membershipReported;

  // Both historical seconds and explicit milliseconds occur in these DTOs.
  // Reject missing, fractional, implausible and overflowing timestamps rather
  // than making an expired/unknown entitlement look like a valid membership.
  static DateTime? _epoch(Object? value) {
    final number = num.tryParse('$value');
    if (number == null ||
        !number.isFinite ||
        number != number.truncateToDouble()) {
      return null;
    }
    final millis = number >= 100000000000 ? number : number * 1000;
    if (millis < 946684800000 || millis > 4102444800000) return null;
    return DateTime.fromMillisecondsSinceEpoch(millis.toInt(), isUtc: true);
  }

  DateTime? get freeListeningUntil {
    final candidates =
        [listeningUntil, incentiveUntil]
            .whereType<DateTime>()
            .where((date) => date.isAfter(observedAt))
            .toList()
          ..sort();
    return candidates.lastOrNull;
  }

  bool get freeListeningActive => freeListeningUntil != null;
  bool get membershipActive =>
      membershipReported &&
      (membershipUntil == null || membershipUntil!.isAfter(observedAt));

  String get listeningSummary => freeListeningUntil == null
      ? '当前接口未返回有效的免费听到期时间'
      : '已同步免费听权益，有效至 ${_date(freeListeningUntil!)}';
  String get membershipSummary => membershipActive
      ? membershipUntil == null
            ? '服务端确认会员有效，未返回到期时间'
            : '会员有效至 ${_date(membershipUntil!)}'
      : '当前未确认有效会员';

  static String _date(DateTime date) {
    final china = date.toUtc().add(const Duration(hours: 8));
    String two(int value) => '$value'.padLeft(2, '0');
    return '${china.year}-${two(china.month)}-${two(china.day)} '
        '${two(china.hour)}:${two(china.minute)}（北京时间）';
  }
}
