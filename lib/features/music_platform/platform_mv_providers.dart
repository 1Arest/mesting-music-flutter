import 'platform_backend_providers.dart';
import 'netease/netease_mv_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'data/platform_mv_repository.dart';
import 'music_platform_providers.dart';

final platformMvRepositoryProvider = Provider<PlatformMvRepository>((ref) {
  final api = ref.watch(musicPlatformApiProvider);
  return ref.watch(usesNeteaseProvider)
      ? NeteaseMvRepository(api, ref.watch(neteaseMusicRepositoryProvider))
      : PlatformMvRepository(api);
});
