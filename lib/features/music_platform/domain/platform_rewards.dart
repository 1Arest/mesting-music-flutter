/// Daily membership contracts adapted from md3Music a69503b (AGPL-3.0).
/// Keep platform facts independent of widgets and local success animations.
class RewardOutcome {
  const RewardOutcome(
    this.success,
    this.message, {
    this.signed = false,
    this.quotaDone = false,
    this.needsVerification = false,
  });
  final bool success, signed, quotaDone, needsVerification;
  final String message;
}

class RewardVerification {
  const RewardVerification({required this.eventId, required this.appId});
  final String eventId, appId;
}

typedef RewardVerifier = Future<String?> Function(RewardVerification challenge);

class VipEntitlement {
  const VipEntitlement({
    required this.type,
    required this.active,
    this.expires,
  });
  final String type;
  final bool active;
  final DateTime? expires;
  String get label => type == 'tvip' ? '畅听会员' : '概念会员';

  /// Multiple purchases and daily rewards can coexist; show the latest expiry.
  static List<VipEntitlement> parse(Map<String, dynamic> payload) {
    final data = payload['data'] is Map ? payload['data'] as Map : payload;
    final rows = data['busi_vip'];
    return [
      for (final type in ['tvip', 'svip'])
        () {
          var active = false;
          DateTime? end;
          if (rows is List) {
            for (final row in rows.whereType<Map>()) {
              if ('${row['product_type']}' != type ||
                  '${row['is_vip']}' != '1') {
                continue;
              }
              active = true;
              final candidate = DateTime.tryParse(
                '${row['vip_end_time'] ?? ''}'.replaceFirst(' ', 'T'),
              );
              if (candidate != null &&
                  (end == null || candidate.isAfter(end))) {
                end = candidate;
              }
            }
          }
          return VipEntitlement(type: type, active: active, expires: end);
        }(),
    ];
  }
}

String rewardDateKey(DateTime day) =>
    '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

/// Invalid, non-concept and unconfirmed records cannot become checked days.
Set<String> parseRewardDates(Map<String, dynamic> payload) {
  final data = payload['data'] is Map ? payload['data'] as Map : payload;
  final rows = data['list'] ?? data['record_list'] ?? payload['list'];
  final dates = <String>{};
  if (rows is! List) return dates;
  for (final row in rows.whereType<Map>()) {
    if ('${row['vip_type']}' != 'svip' || '${row['receive_vip']}' != '1') {
      continue;
    }
    final value = '${row['day'] ?? ''}';
    final match = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2})(?:$|[ T])',
    ).firstMatch(value);
    if (match == null) continue;
    final year = int.parse(match[1]!),
        month = int.parse(match[2]!),
        day = int.parse(match[3]!);
    final parsed = DateTime(year, month, day);
    if (parsed.year == year && parsed.month == month && parsed.day == day) {
      dates.add(rewardDateKey(parsed));
    }
  }
  return dates;
}

class RewardSnapshot {
  const RewardSnapshot({
    required this.now,
    this.signedDates = const {},
    this.memberships = const [],
    this.recordsAvailable = true,
    this.membershipsAvailable = true,
  });
  final DateTime now;
  final Set<String> signedDates;
  final List<VipEntitlement> memberships;
  final bool recordsAvailable, membershipsAvailable;
}

enum RewardAction { signIn, listen, ad }
