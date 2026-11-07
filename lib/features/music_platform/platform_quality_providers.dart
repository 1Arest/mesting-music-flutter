import 'qishui/qishui_providers.dart';
import 'platform_backend_providers.dart';
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/playback_providers.dart';
import '../../core/persistence/app_preferences.dart';
import 'domain/platform_audio_quality.dart';
import 'data/platform_quality_catalog.dart';
import 'music_platform_providers.dart';
import 'data/music_platform_api.dart';
import 'netease/netease_fallback.dart';
import 'data/platform_playback_resolver.dart';
import 'data/playback_quality_catalog.dart';
import '../../shared/models/track.dart';
import 'retained_kugou_scope.dart';

/// Only successful provider states are retained. Each state still watches the
/// account future, so logout/login/token replacement invalidates its catalog.
/// A small FIFO bounds memory without persisting stale server capabilities.
final _qualityRetentionsProvider = Provider((ref) {
  final retentions = _QualityRetentions();
  ref.onDispose(retentions.clear);
  return retentions;
});

class _QualityRetentions {
  final _releases = <String, void Function()>{};
  void retain(String id, void Function() release) {
    _releases.remove(id)?.call();
    _releases[id] = release;
    while (_releases.length > 64) {
      _releases.remove(_releases.keys.first)?.call();
    }
  }

  void forget(String id, void Function() release) {
    if (identical(_releases[id], release)) _releases.remove(id);
  }

  void clear() {
    final releases = _releases.values.toList();
    _releases.clear();
    for (final release in releases) {
      release();
    }
  }
}

final platformSongQualitiesProvider = FutureProvider.autoDispose
    .family<Set<PlatformAudioQuality>, String>((ref, id) async {
      final session = await ref.watch(platformAccountProvider.future);
      if (id.startsWith('qishui_')) {
        return ref.watch(qishuiRepositoryProvider).qualities(id);
      }
      if (id.startsWith('netease_')) {
        return ref.watch(neteaseMusicRepositoryProvider).qualities(id);
      }
      final payload = await ref
          .watch(musicPlatformApiProvider)
          .get(
            '/audio',
            query: {'hash': id.substring('kugou_'.length)},
            expectedSession: session,
          );
      final result = PlatformQualityCatalog.parse(payload);
      if (ref.mounted) {
        final retained = ref.read(_qualityRetentionsProvider);
        final release = ref.keepAlive().close;
        retained.retain(id, release);
        ref.onDispose(() => retained.forget(id, release));
      }
      return result;
    }, retry: (_, _) => null);

/// The active recording and transport are part of this provider's key. Login,
/// retained-account replacement and source changes invalidate all pending work.
final platformPlaybackQualitiesProvider = FutureProvider.autoDispose
    .family<VerifiedPlaybackQualities, Track>((ref, track) async {
      final owner = await ref.watch(platformAccountProvider.future);
      final origin = playbackAudioOrigin(track);
      // Only the retained Concept adapter depends on the other saved login.
      // Official/direct playback must not initiate unrelated secure-store IO.
      final usesRetained = origin?.adapter == '酷狗概念版账号';
      final retained = usesRetained
          ? ref.watch(retainedKugouSessionProvider)
          : null;
      var cancelled = false;
      final abort = Completer<void>();
      void cancel() {
        cancelled = true;
        if (!abort.isCompleted) abort.complete();
      }

      ref.onDispose(cancel);
      bool current() =>
          !cancelled &&
          ref.mounted &&
          ref.read(platformAccountProvider).value?.ownerId == owner?.ownerId &&
          ref.read(platformAccountProvider).value?.token == owner?.token &&
          (!usesRetained ||
              ref.read(retainedKugouSessionProvider)?.token == retained?.token);
      final fallback =
          track.source == TrackSource.netease &&
              origin != null &&
              !origin.isNetease &&
              origin.recordingId.isNotEmpty
          ? ref.watch(neteaseFallbackResolverProvider)
          : null;
      final music = ref.watch(neteaseMusicRepositoryProvider);
      final api = ref.watch(musicPlatformApiProvider);
      final timer = Timer(const Duration(seconds: 35), () {
        if (!abort.isCompleted) abort.complete();
      });
      try {
        Iterable<PlatformAudioQuality> candidates = const [];
        if (origin?.isNetease == true ||
            origin?.adapter == AudioOrigin.kugou ||
            origin?.adapter == AudioOrigin.qishui) {
          candidates = await ref.watch(
            platformSongQualitiesProvider(track.id).future,
          );
        } else if (origin != null &&
            origin.recordingId.isNotEmpty &&
            fallback != null) {
          candidates = PlatformAudioQuality.values.where(
            (tier) => !tier.neteaseOnly,
          );
        }
        final values = await verifyPlaybackQualities(
          track: track,
          candidates: candidates,
          current: current,
          resolve: (tier) async {
            if (abort.isCompleted || !current()) return null;
            if (origin?.adapter == AudioOrigin.qishui) {
              return ref
                  .read(qishuiRepositoryProvider)
                  .resolve(track, quality: tier, abortTrigger: abort.future);
            }
            if (origin!.isNetease) {
              return music.resolve(
                track,
                tier,
                requireQuality: true,
                abortTrigger: abort.future,
              );
            }
            if (origin.adapter == AudioOrigin.kugou) {
              return PlatformPlaybackResolver(api).resolve(
                track,
                quality: tier,
                requireRequestedQuality: true,
                abortTrigger: abort.future,
              );
            }
            return fallback?.resolve(
              track.copyWith(playbackQuality: tier.code),
              current: current,
              requiredQuality: tier.code,
              onlySource: origin.adapter,
              requiredRecordingId: origin.recordingId,
              abortTrigger: abort.future,
            );
          },
        );
        // The selection returns after the dialog route is removed. Keep its
        // verified URLs briefly alive; account/source dependencies still revoke
        // this lease immediately when their identity changes.
        final lease = ref.keepAlive();
        final expiry = Timer(const Duration(seconds: 45), lease.close);
        ref.onDispose(expiry.cancel);
        return VerifiedPlaybackQualities(track, values, current: current);
      } finally {
        timer.cancel();
        if (!abort.isCompleted) abort.complete();
      }
    }, retry: (_, _) => null);

class PlatformQualityState {
  const PlatformQualityState(
    this.preferred, {
    this.switching = false,
    this.switchingTrackId,
  });
  final PlatformAudioQuality preferred;
  final bool switching;
  final String? switchingTrackId;
}

/// Preferences and operation state are shared across every player appearance.
/// The audio handler owns source replacement and stale-command protection.
class PlatformQualityController extends Notifier<PlatformQualityState> {
  static const preferenceKey = 'beta_platform_audio_quality';
  String get _key => ref.read(usesQishuiProvider)
      ? '${preferenceKey}_qishui'
      : ref.read(usesNeteaseProvider)
      ? '${preferenceKey}_netease'
      : preferenceKey;
  @override
  PlatformQualityState build() {
    // Rebuild even when switching between two users of the same platform, so
    // an old in-flight quality change cannot leave the new account busy.
    ref.watch(platformAccountProvider.select((a) => a.value?.ownerId));
    final netease = ref.watch(usesNeteaseProvider);
    final prefs = ref.watch(sharedPreferencesProvider);
    final saved = PlatformAudioQuality.fromCode(
      prefs.getString(
            ref.watch(usesQishuiProvider)
                ? '${preferenceKey}_qishui'
                : netease
                ? '${preferenceKey}_netease'
                : preferenceKey,
          ) ??
          prefs.getString(preferenceKey),
    );
    return PlatformQualityState(
      saved == null || (!netease && saved.neteaseOnly)
          ? PlatformAudioQuality.standard
          : saved,
    );
  }

  Future<bool> select(
    PlatformAudioQuality quality, {
    VerifiedPlaybackQualities? catalog,
  }) async {
    if (state.switching) return false;
    final handler = ref.read(audioHandlerProvider);
    final currentTrack = handler.trackForId(handler.mediaItem.value?.id ?? '');
    if (catalog != null &&
        (!catalog.current() ||
            currentTrack == null ||
            currentTrack.id != catalog.track.id ||
            currentTrack.audioAsset != catalog.track.audioAsset ||
            !catalog.values.containsKey(quality))) {
      return false;
    }
    if (catalog != null && currentTrack?.playbackQuality == quality.code) {
      return true;
    }
    final owner = ref.read(platformAccountProvider).value?.ownerId;
    final preference = _key;
    final previous = state.preferred;
    var saved = previous;
    state = PlatformQualityState(
      quality,
      switching: true,
      switchingTrackId: ref.read(currentTrackProvider).id,
    );
    try {
      final applied = catalog == null
          ? await handler.refreshCurrentSource()
          : await handler.refreshVerifiedSource((original) async {
              if (!catalog.current() ||
                  original.id != catalog.track.id ||
                  playbackAudioOrigin(original) != catalog.origin) {
                throw const MusicPlatformException('歌曲、音源或账号已变化，请重新打开音质选择');
              }
              return catalog.values[quality]!;
            });
      // A cancelled/stale request is not an applied choice. Read the audio owner
      // synchronously: the StreamProvider may still hold the previous item.
      if (!applied ||
          !ref.mounted ||
          (catalog != null && !catalog.current()) ||
          ref.read(platformAccountProvider).value?.ownerId != owner) {
        return false;
      }
      final activeHandler = ref.read(audioHandlerProvider);
      final actual = activeHandler.trackForId(
        activeHandler.mediaItem.value?.id ?? '',
      );
      if (actual?.playbackQuality != quality.code) {
        throw const MusicPlatformException('未能切换到所选音质，已保留原音源');
      }
      await ref
          .read(sharedPreferencesProvider)
          .setString(preference, quality.code);
      saved = quality;
      return true;
    } finally {
      if (ref.mounted &&
          ref.read(platformAccountProvider).value?.ownerId == owner) {
        state = PlatformQualityState(saved);
      }
    }
  }
}

final platformQualityProvider =
    NotifierProvider<PlatformQualityController, PlatformQualityState>(
      PlatformQualityController.new,
    );
