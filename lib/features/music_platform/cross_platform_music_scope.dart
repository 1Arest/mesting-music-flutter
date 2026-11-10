import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/system_music_io_client.dart';
import '../../shared/models/track.dart';
import 'data/music_platform_api.dart';
import 'data/platform_playback_resolver.dart';
import 'domain/platform_audio_quality.dart';
import 'domain/platform_session.dart';
import 'music_platform_providers.dart';
import 'retained_kugou_scope.dart';
import 'netease/netease_api.dart';
import 'netease/netease_music_repository.dart';
import 'netease/netease_providers.dart';

/// Separate source jars never reconfigure the selected account or the player
/// owner. Disposal revokes requests immediately; credentials never enter Track.
final supplementaryKugouApiProvider = FutureProvider<MusicPlatformApi>((
  ref,
) async {
  final mutation = ref.watch(retainedKugouMutationProvider);
  final active = ref.watch(platformAccountProvider).value;
  final store = ref.watch(platformSessionStoreProvider);
  final server = ref.watch(musicServerProvider);
  final session = mutation.known
      ? mutation.session
      : active?.platform == MusicPlatform.kugou
      ? active
      : await store.read().timeout(const Duration(seconds: 5));
  if (!ref.mounted) throw const MusicPlatformException('账号已变化');
  final client = SystemMusicIoClient();
  var alive = true;
  final api = MusicPlatformApi(
    server: server,
    client: client,
    sessionCurrent: () => alive,
  )..session = session;
  ref.onDispose(() {
    alive = false;
    api.session = null;
    client.close();
  });
  return api;
}, retry: (_, _) => null);

final supplementaryNeteaseMusicProvider =
    FutureProvider<NeteaseMusicRepository>((ref) async {
      ref.watch(retainedNeteaseEpochProvider);
      ref.watch(
        platformAccountProvider.select(
          (a) => (a.value?.ownerId, a.value?.token),
        ),
      );
      final session = await ref
          .watch(neteaseSessionStoreProvider)
          .read()
          .timeout(const Duration(seconds: 5));
      if (!ref.mounted) throw const MusicPlatformException('账号已变化');
      final client = SystemMusicIoClient();
      final api = NeteaseApi(client)..configure(session);
      ref.onDispose(() {
        api.configure(null);
        client.close();
      });
      return NeteaseMusicRepository(api);
    }, retry: (_, _) => null);

/// The active UI/library identity stays unchanged. The selected recording uses
/// only its own platform's normal resolver and entitlement/preview rules.
Future<Track> resolveSupplementaryMusic(
  WidgetRef ref,
  Track track,
  PlatformAudioQuality quality, {
  bool requireQuality = false,
}) async {
  final owner = ref.read(platformAccountProvider).value;
  final identity = (owner?.ownerId, owner?.token);
  bool current() {
    if (!ref.context.mounted) return false;
    final now = ref.read(platformAccountProvider).value;
    return (now?.ownerId, now?.token) == identity;
  }

  final Track resolved;
  if (track.source == TrackSource.kugou) {
    // NetEase-only tiers can remain selected while the UI stays on NetEase.
    // A normal supplementary play uses Kugou's standard tier in that case;
    // an explicit unsupported quality request must never claim success.
    if (quality.neteaseOnly && requireQuality) {
      throw const MusicPlatformException('酷狗音源不支持该音质，请选择此音源提供的音质');
    }
    final sourceQuality = quality.neteaseOnly
        ? PlatformAudioQuality.standard
        : quality;
    final api = await ref.read(supplementaryKugouApiProvider.future);
    if (!current()) throw const MusicPlatformException('账号已变化，请重新选择歌曲');
    if (api.session == null) {
      throw const MusicPlatformException(
        '请先登录酷狗账号，此资源可能需要会员权限',
        code: 'source_login_kugou',
      );
    }
    resolved = await PlatformPlaybackResolver(api).resolve(
      track,
      quality: sourceQuality,
      requireRequestedQuality: requireQuality,
    );
  } else if (track.source == TrackSource.netease) {
    final music = await ref.read(supplementaryNeteaseMusicProvider.future);
    if (!current()) throw const MusicPlatformException('账号已变化，请重新选择歌曲');
    if (music.api.session == null) {
      throw const MusicPlatformException(
        '请先登录网易云账号，此资源可能需要会员权限',
        code: 'source_login_netease',
      );
    }
    resolved = await music.resolve(
      track,
      quality,
      requireQuality: requireQuality,
    );
  } else {
    throw const MusicPlatformException('该歌曲来源不支持融合播放');
  }
  if (!current()) throw const MusicPlatformException('账号已变化，请重新选择歌曲');
  return resolved;
}
