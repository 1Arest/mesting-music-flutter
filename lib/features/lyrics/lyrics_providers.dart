import '../music_platform/platform_backend_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'data/lyrics_repository.dart';
import 'domain/lyrics_document.dart';
import '../search/data/online_music_config.dart';
import '../search/search_providers.dart';
import '../../core/platform/distribution_channel.dart';
import '../music_platform/music_platform_providers.dart';
import '../music_platform/qishui/qishui_providers.dart';
import '../music_platform/cross_platform_music_scope.dart';
import '../music_platform/domain/platform_session.dart';

final lyricsRepositoryProvider = Provider<LyricsRepository>((ref) {
  if (DistributionChannel.isBeta) ref.watch(platformAccountProvider);
  return LyricsRepository(
    client: ref.watch(musicSearchHttpClientProvider),
    kugouApiBaseUrl: OnlineMusicConfig.kugouApiBaseUrl,
    neteaseApiBaseUrl: OnlineMusicConfig.neteaseApiBaseUrl,
    qishuiRequest: DistributionChannel.isBeta
        ? (id) => ref.read(qishuiRepositoryProvider).lyrics(id)
        : null,
    neteaseRequest: DistributionChannel.isBeta
        ? (path, query) async {
            final owner = await ref.read(platformAccountProvider.future);
            final music = owner?.platform == MusicPlatform.netease
                ? ref.read(neteaseMusicRepositoryProvider)
                : await ref.read(supplementaryNeteaseMusicProvider.future);
            return music.call(path, query);
          }
        : null,
    kugouRequest: DistributionChannel.isBeta
        ? (path, query) async {
            final owner = await ref.read(platformAccountProvider.future);
            final api = owner?.platform == MusicPlatform.netease
                ? await ref.read(supplementaryKugouApiProvider.future)
                : ref.read(musicPlatformApiProvider);
            return api.get(path, query: query);
          }
        : null,
  );
});

final lyricsProvider = FutureProvider.family<LyricsDocument, String>((
  ref,
  path,
) {
  return ref.watch(lyricsRepositoryProvider).loadAsset(path);
});
