/// Display tiers are official facts; local presentation never grants rights.
enum MembershipBadgeTier { vip, svip, supreme }

Map<String, dynamic> _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : {};

/// NetEase's membership response supplies rights per product. Historical
/// growth levels alone are not proof of a current subscription.
MembershipBadgeTier? neteaseMembershipTier(
  Map<String, dynamic> payload,
  DateTime now,
) {
  final data = _map(payload['data']);
  bool active(String key) {
    final row = _map(data[key]);
    if (row['rights'] != true && row['rights'] != 1) return false;
    final expiry = num.tryParse('${row['expireTime'] ?? ''}');
    return expiry == null || expiry > now.millisecondsSinceEpoch;
  }

  if (active('redplus')) return MembershipBadgeTier.svip;
  if (active('associator') || active('musicPackage')) {
    return MembershipBadgeTier.vip;
  }
  return null;
}

/// Only explicitly active, unexpired platform products receive a badge.
MembershipBadgeTier? kugouMembershipTier(
  Map<String, dynamic> payload,
  DateTime now,
) {
  final data = _map(payload['data']);
  final rows = data['busi_vip'];
  if (rows is! List) return null;
  var vip = false;
  for (final row in rows.whereType<Map>()) {
    if ('${row['is_vip']}' != '1') continue;
    final end = DateTime.tryParse(
      '${row['vip_end_time'] ?? ''}'.replaceFirst(' ', 'T'),
    );
    if (end != null && !end.isAfter(now)) continue;
    if ('${row['product_type']}' == 'svip') return MembershipBadgeTier.svip;
    if ({'vip', 'tvip'}.contains('${row['product_type']}')) vip = true;
  }
  return vip ? MembershipBadgeTier.vip : null;
}
