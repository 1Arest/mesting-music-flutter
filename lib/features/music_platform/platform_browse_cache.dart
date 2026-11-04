import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'music_platform_providers.dart';
import 'platform_backend_providers.dart';

/// An explicit refresh retains visible data and bypasses its recheck cooldown.
/// Cache storage itself has no dependency on platform providers or UI routing.
void revalidateBrowse(WidgetRef ref) {
  final identity = ref.read(platformAccountProvider).value;
  final netease = ref.read(usesNeteaseProvider);
  final scope =
      '${netease ? "netease" : "kugou"}:${identity?.userId ?? "guest"}';
  final cache = netease
      ? ref.read(neteaseMusicRepositoryProvider).api.browseCache
      : ref.read(musicPlatformApiProvider).browseCache;
  cache.revalidateScope(scope);
}
