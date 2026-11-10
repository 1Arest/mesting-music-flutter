import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/music_http_client.dart';
import '../../shared/models/track.dart';
import 'cross_platform_music_scope.dart';
import 'data/music_platform_api.dart';
import 'domain/platform_session.dart';
import 'music_platform_providers.dart';
import 'platform_backend_providers.dart';
import 'netease/netease_music_repository.dart';

/// One source's credential and request jar, independent of the selected UI.
/// Anonymous reads stay anonymous. Writes and playback check [session] first.
class SourceMediaScope {
  SourceMediaScope({
    required this.source,
    required this.api,
    this.music,
    required this.isCurrent,
  });
  final TrackSource source;
  final MusicPlatformApi api;
  final NeteaseMusicRepository? music;
  final bool Function() isCurrent;
  PlatformSession? get session =>
      music != null ? music!.api.session?.identity : api.session;
  void requireLogin() {
    if (!isCurrent()) throw const MusicPlatformException('来源账号已变化，请重新打开');
    if (session == null) {
      throw MusicPlatformException(
        '请先登录${source == TrackSource.kugou ? '酷狗' : '网易云'}账号，此资源可能需要会员权限',
        code: 'source_login_${source.name}',
      );
    }
  }
}

final sourceMediaScopeProvider =
    FutureProvider.family<SourceMediaScope, TrackSource>((ref, source) async {
      // UI account changes revoke an open page too; source authentication itself
      // never publishes a different active account or changes the player owner.
      final active = ref.watch(platformAccountProvider.select((s) => s.value));
      var alive = true;
      ref.onDispose(() => alive = false);
      // Reuse the already-owned current platform jar. Supplementary scopes are
      // only needed for a foreign source; this also avoids redundant cold reads.
      if (active?.platform.name == source.name ||
          active == null && source == TrackSource.kugou) {
        final api = ref.watch(musicPlatformApiProvider);
        final music = source == TrackSource.netease
            ? ref.watch(neteaseMusicRepositoryProvider)
            : null;
        final identity = (active?.ownerId, active?.token);
        return SourceMediaScope(
          source: source,
          api: api,
          music: music,
          isCurrent: () =>
              alive &&
              (
                    ref.read(platformAccountProvider).value?.ownerId,
                    ref.read(platformAccountProvider).value?.token,
                  ) ==
                  identity,
        );
      }
      if (source == TrackSource.kugou) {
        final api = await ref.watch(supplementaryKugouApiProvider.future);
        if (!ref.mounted) throw const MusicPlatformException('账号已变化');
        final owner = api.session;
        return SourceMediaScope(
          source: source,
          api: api,
          isCurrent: () =>
              alive &&
              api.session?.ownerId == owner?.ownerId &&
              api.session?.token == owner?.token,
        );
      }
      if (source != TrackSource.netease) {
        throw const MusicPlatformException('该来源暂不支持双平台资源');
      }
      final music = await ref.watch(supplementaryNeteaseMusicProvider.future);
      if (!ref.mounted) throw const MusicPlatformException('账号已变化');
      final client = MusicHttpClient();
      final api = MusicPlatformApi(
        server: ref.read(musicServerProvider),
        client: client,
      )..session = music.api.session?.identity;
      ref.onDispose(client.close);
      final owner = music.api.session?.credentialId;
      return SourceMediaScope(
        source: source,
        api: api,
        music: music,
        isCurrent: () => alive && music.api.session?.credentialId == owner,
      );
    }, retry: (_, _) => null);
