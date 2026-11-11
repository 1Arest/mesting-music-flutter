import '../features/music_platform/qishui/qishui_effects.dart';
import '../features/music_platform/qishui/qishui_history_providers.dart';
import '../features/music_platform/qishui/qishui_listening_binding.dart';
import '../features/music_platform/qishui/qishui_providers.dart';
import '../features/music_platform/qishui/qishui_download_playback.dart';
import '../features/music_platform/qishui/qishui_playback_recovery.dart';
import '../features/downloads/audio_downloads.dart';
import '../shared/widgets/beta_scroll_behavior.dart';
import '../features/music_platform/domain/platform_session.dart';
import '../features/music_platform/netease/netease_fallback.dart';
import '../features/downloads/download_source_coordinator.dart';
import '../features/music_platform/netease/netease_listening_reporter.dart';
import '../features/music_platform/netease/together/netease_together_controller.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import '../features/music_platform/presentation/song_list_tools_host.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/themes/app_theme.dart';
import '../features/themes/music_application_theme.dart';
import '../features/themes/theme_controller.dart';
import '../features/auth/presentation/first_launch_auth_coordinator.dart';
import '../features/auth/beta_entry_back_state.dart';
import '../features/legal/presentation/disclaimer_dialog.dart';
import '../features/lyrics/presentation/lyrics_overlay_coordinator.dart';
import '../features/app_update/presentation/app_update_coordinator.dart';
import '../core/audio/playback_providers.dart';
import '../core/audio/music_equalizer_providers.dart';
import '../core/platform/distribution_channel.dart';
import '../features/music_platform/data/embedded_kugou_music_source.dart';
import '../features/music_platform/data/music_platform_api.dart';
import '../features/music_platform/music_platform_providers.dart';
import '../features/music_platform/cross_platform_music_scope.dart';
import '../features/music_platform/platform_quality_providers.dart';
import '../features/music_platform/platform_recommendation_providers.dart';
import '../features/music_platform/listening_sync/listening_sync_providers.dart';
import '../features/audiobooks/audiobook_repository.dart';
import '../features/audiobooks/audiobook_models.dart';
import '../features/audiobooks/audiobook_playback.dart';
import '../features/kugou_together/together_controller.dart';
import '../shared/models/track.dart';
import '../core/persistence/playback_persistence_controller.dart';
import '../features/library/library_providers.dart';
import '../features/recommendation/recommendation_providers.dart';
import '../features/search/search_providers.dart';
import 'router/app_router.dart';
import 'system_back_coordinator.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

/// Fire on first mount as well as switches; a guest may never emit a login
/// change, but still needs a playback owner for durable daily listening data.
final playbackOwnerBindingProvider = Provider<void>((ref) {
  final persistence = ref.watch(playbackPersistenceControllerProvider);
  ref.listen(activeLibraryOwnerProvider, (previous, ownerId) {
    unawaited(persistence.activateOwner(ownerId));
  }, fireImmediately: true);
});

class MestingMusicApp extends ConsumerWidget {
  const MestingMusicApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final musicTheme = ref.watch(effectiveMusicThemeProvider);
    final audioHandler = ref.read(audioHandlerProvider);
    if (DistributionChannel.isBeta) {
      ref.read(platformAccountProvider.notifier).preparePlatformSwitch = ref
          .read(playbackPersistenceControllerProvider)
          .preparePlatformSwitch;
      final source = ref.watch(kugouMusicSourceProvider);
      audioHandler.configureTrackPlaybackResolver((track) async {
        // Soda's decoded temporary file belongs to a specific credential.
        // A restored media item must revalidate the active official account.
        if (track.hasLocalAudio && track.source != TrackSource.qishui) {
          return track;
        }
        if (track.source == TrackSource.netease ||
            track.source == TrackSource.kugou) {
          final identity = await ref.read(platformAccountProvider.future);
          if (identity?.platform != MusicPlatform.qishui &&
              (identity?.platform.name ?? 'kugou') != track.source.name) {
            final quality = ref.read(platformQualityProvider);
            return resolveSupplementaryMusic(
              ref,
              track,
              quality.preferred,
              requireQuality:
                  quality.switching && quality.switchingTrackId == track.id,
            );
          }
        }
        if (track.source == TrackSource.qishui) {
          final identity = await ref.read(platformAccountProvider.future);
          if (identity == null || identity.platform != MusicPlatform.qishui) {
            throw const MusicPlatformException('请先切换到汽水账号播放这首歌');
          }
          final quality = ref.read(platformQualityProvider);
          final intent = audioHandler.transportRevision;
          final downloads = track.hasLocalAudio
              ? ref.read(audioDownloadManagerProvider)
              : null;
          return resolveQishuiPlaybackSource(
            track: track,
            owner: identity.ownerId,
            downloads: downloads?.tasks ?? const [],
            restoringDownloads: downloads?.restoring ?? false,
            official: () => ref
                .read(qishuiRepositoryProvider)
                .resolve(
                  track,
                  quality: quality.preferred,
                  requireQuality:
                      quality.switching && quality.switchingTrackId == track.id,
                  stillCurrent: () => intent == audioHandler.transportRevision,
                ),
          );
        }
        if (track.source == TrackSource.netease) {
          final identity = await ref.read(platformAccountProvider.future);
          if (identity?.platform != MusicPlatform.netease) {
            throw const MusicPlatformException('请先切换到网易云账号播放这首歌');
          }
          return resolveNeteasePlayback(
            ref,
            track,
            ref.read(platformQualityProvider).preferred,
            requireQuality:
                ref.read(platformQualityProvider).switching &&
                ref.read(platformQualityProvider).switchingTrackId == track.id,
          );
        }
        if (source is! EmbeddedKugouMusicSource ||
            track.source != TrackSource.kugou) {
          return track;
        }
        final activeKugou = await ref.read(platformAccountProvider.future);
        if (activeKugou != null &&
            activeKugou.platform != MusicPlatform.kugou) {
          throw const MusicPlatformException('请先切换到酷狗账号播放这首歌');
        }
        // Playback restored from disk must use the current platform account,
        // rather than a signed URL left over from a previous login/session.
        if (bookIdentity(track) != null) {
          return ref.read(audiobookRepositoryProvider).resolve(track);
        }
        final roomTrack = await ref
            .read(togetherControllerProvider)
            .resolveRoomTrack(track);
        if (roomTrack != null) return roomTrack;
        final resolved = await source.resolveTrack(
          track,
          quality: ref.read(platformQualityProvider).preferred,
          requireRequestedQuality:
              ref.read(platformQualityProvider).switching &&
              ref.read(platformQualityProvider).switchingTrackId == track.id,
        );
        if (!resolved.isPlayable) {
          throw MusicPlatformException(resolved.availabilityMessage);
        }
        return resolved;
      }, skipUnplayableTrack: qishuiCanSkipPlaybackFailure);
    }
    if (DistributionChannel.isBeta) {
      ref.watch(qishuiEffectsProvider);
      ref.watch(qishuiHistorySyncProvider);
      ref.watch(qishuiListeningSyncProvider);
      ref.watch(musicEqualizerProvider);
      ref.watch(platformRecommendationBindingProvider);
      ref.watch(audiobookProgressBindingProvider);
      ref.watch(platformListeningSyncProvider);
      ref.watch(neteaseListeningReporterProvider);
      ref.watch(neteaseTogetherControllerProvider);
    }
    final radioController = DistributionChannel.isBeta
        ? null
        : ref.watch(endlessRadioControllerProvider);
    final playbackPersistence = ref.read(playbackPersistenceControllerProvider);
    playbackPersistence.configureLibrarySynchronizer((ownerId) {
      final repository = ref.read(libraryRepositoryProvider);
      if (repository.ownerId != ownerId) return Future.value(false);
      return repository.synchronize();
    });
    if (radioController != null) {
      audioHandler.configureRadioTrackLoader(radioController.loadMore);
    }
    // Start secure local account restoration with the app rather than waiting
    // until the user opens the profile tab or side panel.
    ref.watch(playbackOwnerBindingProvider);
    if (!DistributionChannel.isBeta) {
      ref.listen(hotMusicControllerProvider, (previous, next) {
        next.whenData((snapshot) {
          audioHandler.updateOnlineFallbackTracks(
            snapshot.recommendationTracks,
          );
          unawaited(audioHandler.prefetchRadioTracks());
        });
      });
    }
    if (!DistributionChannel.isBeta) {
      ref.listen(favoriteTracksProvider, (previous, next) {
        if (next.hasValue && previous?.value != next.value) {
          audioHandler.invalidateRadioRecommendations();
          unawaited(audioHandler.prefetchRadioTracks());
        }
      });
    }
    final application = MaterialApp.router(
      // Native Cupertino pickers use these delegates too; the product is
      // Chinese even when Android's current system language is English.
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      title: DistributionChannel.isBeta ? 'Mesting Music' : 'Mesting 音乐',
      debugShowCheckedModeBanner: false,
      scrollBehavior: DistributionChannel.isBeta
          ? const BetaScrollBehavior()
          : null,
      theme: buildMestingTheme(musicTheme),
      routerConfig: appRouter,
      builder: (context, child) => MusicApplicationTheme(
        data: Theme.of(context),
        child: SystemBackCoordinator(
          // Entry is above Router and owns Back while its overlay is visible.
          canPop: () =>
              ref.read(betaEntryBackStateProvider).canHandlePop ??
              appRouter.canPop(),
          navigationChanges: appRouter.routerDelegate,
          child: FirstLaunchDisclaimerCoordinator(
            child: FirstLaunchAuthCoordinator(
              betaBackDispatcher: appRouter.backButtonDispatcher,
              onBetaLogout: () => appRouter.go('/music/recommend'),
              child: AppUpdateCoordinator(
                navigatorKey: appRootNavigatorKey,
                child: DownloadSourceCoordinator(
                  navigatorKey: appRootNavigatorKey,
                  enabled: DistributionChannel.isBeta,
                  child: LyricsOverlayCoordinator(
                    child: SongListToolsHost(
                      child: child ?? const SizedBox.shrink(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return DistributionChannel.isBeta
        ? LiquidGlassWidgets.wrap(
            brightnessResolver: Theme.maybeBrightnessOf,
            // The app's brief requires full optical quality even while music
            // and scrolling are active. The adaptive ceiling overrides an
            // explicit premium setting, so keep it disabled; optimize rebuilds.
            adaptiveQuality: false,
            child: application,
          )
        : application;
  }
}
