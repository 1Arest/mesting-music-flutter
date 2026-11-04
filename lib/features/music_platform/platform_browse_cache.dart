import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'music_platform_providers.dart';
import 'platform_backend_providers.dart';
import '../../core/cache/browse_response_cache.dart';

/// An explicit refresh retains visible data and bypasses its recheck cooldown.
/// Cache storage itself has no dependency on platform providers or UI routing.
void revalidateBrowse(WidgetRef ref) {
  final (cache, scope) = _browseScope(ref);
  cache.revalidateScope(scope);
}

(BrowseResponseCache, String) _browseScope(WidgetRef ref) {
  final identity = ref.read(platformAccountProvider).value;
  final netease = ref.read(usesNeteaseProvider);
  final scope =
      '${netease ? "netease" : "kugou"}:${identity?.userId ?? "guest"}';
  final cache = netease
      ? ref.read(neteaseMusicRepositoryProvider).api.browseCache
      : ref.read(musicPlatformApiProvider).browseCache;
  return (cache, scope);
}

/// Refresh only the page's typed providers, keeping repositories, account
/// epochs and their current previews alive. Callbacks are started before the
/// first await, so an account switch cannot make an old completion invalidate
/// providers belonging to the newly selected account.
Future<void> refreshBrowse(
  WidgetRef ref,
  Iterable<Future<Object?> Function()> reloads,
) async {
  final (cache, scope) = _browseScope(ref);
  cache.revalidateScope(scope);
  await Future.wait([
    for (final reload in reloads)
      Future<Object?>.sync(reload).then<void>((_) {}, onError: (Object _) {}),
  ]);
  await cache.settleRefreshes(scope);
}
