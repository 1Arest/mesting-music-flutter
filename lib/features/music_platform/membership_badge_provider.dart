import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'domain/membership_badge.dart';
import 'domain/platform_session.dart';
import 'music_platform_providers.dart';
import 'platform_backend_providers.dart';

/// Read-only account-owned membership lookup. No reward controller is started
/// by the badge. Account/credential changes discard the preceding response.
final officialMembershipBadgeProvider = FutureProvider<MembershipBadgeTier?>((
  ref,
) async {
  final session = ref.watch(platformAccountProvider).value;
  if (session == null || session.platform == MusicPlatform.qishui) return null;
  final now = DateTime.now();
  if (session.platform == MusicPlatform.netease) {
    final result = await ref
        .watch(neteaseMusicRepositoryProvider)
        .call('/vip/info');
    return neteaseMembershipTier(result, now);
  }
  final result = await ref
      .watch(musicPlatformApiProvider)
      .get('/user/vip/detail', expectedSession: session);
  return kugouMembershipTier(result, now);
}, retry: (_, _) => null);
