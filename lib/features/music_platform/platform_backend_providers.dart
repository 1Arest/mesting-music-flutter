import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'domain/platform_session.dart';
import 'music_platform_providers.dart';
import 'netease/netease_music_repository.dart';
import 'netease/netease_providers.dart';

/// Presentation keeps its existing models/widgets. Only repository creation
/// chooses a backend, and every authenticated epoch gets fresh caches.
final usesNeteaseProvider = Provider<bool>(
  (ref) =>
      ref.watch(platformAccountProvider).value?.platform ==
      MusicPlatform.netease,
);

final neteaseMusicRepositoryProvider = Provider<NeteaseMusicRepository>((ref) {
  ref.watch(
    platformAccountProvider.select((a) => (a.value?.ownerId, a.value?.token)),
  );
  return NeteaseMusicRepository(ref.watch(neteaseApiProvider));
});
