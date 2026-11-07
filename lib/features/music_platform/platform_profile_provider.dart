import 'qishui/qishui_providers.dart';
import 'qishui/qishui_profile_repository.dart';
import 'platform_backend_providers.dart';
import '../../core/cache/cached_browse_provider.dart';
import 'netease/netease_profile_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/platform_profile_repository.dart';
import 'domain/platform_session.dart';
import 'domain/platform_regions.dart';
import 'music_platform_providers.dart';
import 'domain/platform_profile.dart';
export 'domain/platform_profile.dart';

final platformProfileRepositoryProvider = Provider<PlatformProfileRepository>((
  ref,
) {
  final api = ref.watch(musicPlatformApiProvider);
  if (ref.watch(usesQishuiProvider)) {
    return QishuiProfileRepository(api, ref.watch(qishuiRepositoryProvider));
  }
  return ref.watch(usesNeteaseProvider)
      ? NeteaseProfileRepository(api, ref.watch(neteaseMusicRepositoryProvider))
      : PlatformProfileRepository(api);
});
final platformEditableProfileProvider = FutureProvider.autoDispose
    .family<PlatformProfileInfo, PlatformSession>(
      (ref, session) => cachedBrowse(
        ref,
        () => ref.watch(platformProfileRepositoryProvider).fetch(session),
      ),
    );
final musicRegionsProvider = FutureProvider<List<MusicRegion>>(
  (ref) => loadMusicRegions(),
);

/// Profile refresh is independent of credential restoration: an unavailable
/// avatar endpoint must never undo a working login or block music playback.
final platformProfileProvider = FutureProvider<PlatformProfileInfo?>((
  ref,
) async {
  final session = await ref.watch(platformAccountProvider.future);
  if (session == null) return null;
  final fallback = PlatformProfileInfo(session.nickname, session.avatarUrl);
  try {
    return await cachedBrowse(
      ref,
      () => ref.watch(platformProfileRepositoryProvider).fetch(session),
    );
  } catch (_) {
    return fallback;
  }
});
