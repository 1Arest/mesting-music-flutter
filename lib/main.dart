import 'dart:async';
import 'shared/media/persistent_network_image_cache.dart';
import 'shared/media/artwork_refresh_coordinator.dart';
import 'core/cache/browse_response_cache.dart';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'app/branded_launch_screen.dart';
import 'app/mesting_music_app.dart';
import 'app/startup_image_surface.dart';
import 'app/startup_visibility_gate.dart';
import 'core/audio/mesting_audio_handler.dart';
import 'core/audio/playback_providers.dart';
import 'core/platform/distribution_channel.dart';
import 'features/music_platform/platform_credits.dart';
import 'features/music_platform/discovery_startup_cache.dart';
import 'core/database/app_database.dart';
import 'core/persistence/app_preferences.dart';
import 'core/persistence/playback_persistence_controller.dart';
import 'core/performance/frame_timing_probe.dart';
import 'core/performance/startup_timing_probe.dart';
import 'features/app_update/app_update_providers.dart';
import 'features/library/library_providers.dart';
import 'features/themes/app_brand_style.dart';
import 'features/themes/theme_controller.dart';
import 'features/themes/startup_style.dart';
import 'shared/models/track.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  StartupTimingProbe.start();
  if (DistributionChannel.isBeta) PlatformCredits.register();
  final preferences = await SharedPreferences.getInstance();
  await migrateBeta7Appearance(preferences);
  await migrateBeta6Appearance(preferences);
  await migrateBeta19StartupStyle(preferences);
  final currentBrand = await AppBrandStyleBridge.current();
  if (DistributionChannel.isBeta && currentBrand != AppBrandStyle.coral) {
    await AppBrandStyleBridge.select(AppBrandStyle.coral);
    await AppBrandStyleBridge.applyQueuedStyle();
  }
  final brandStyle = DistributionChannel.isBeta
      ? AppBrandStyle.coral
      : currentBrand;
  final launchThemeMode = savedMusicThemeMode(preferences);
  await AppBrandStyleBridge.syncLaunchTheme(
    launchThemeMode,
    updateLauncher: false,
  );
  FrameTimingProbe.start();
  runApp(
    _MestingBootstrap(
      brandStyle: brandStyle,
      launchThemeMode: launchThemeMode,
      preferences: preferences,
    ),
  );
}

class _MestingBootstrap extends StatefulWidget {
  const _MestingBootstrap({
    required this.brandStyle,
    required this.launchThemeMode,
    required this.preferences,
  });

  final AppBrandStyle brandStyle;
  final ThemeMode launchThemeMode;
  final SharedPreferences preferences;

  @override
  State<_MestingBootstrap> createState() => _MestingBootstrapState();
}

class _MestingBootstrapState extends State<_MestingBootstrap> {
  late Future<_MestingDependencies> _dependencies;
  late final StartupStyle _startupStyle;
  bool _startupFinished = false;
  bool _persistenceStarted = false;
  bool _imageAborted = false;
  late final _staticVisibility = StartupVisibilityGate(
    onElapsed: () {
      if (mounted) setState(() => _startupFinished = true);
    },
  );

  @override
  void initState() {
    super.initState();
    _startupStyle = savedStartupStyle(widget.preferences);
    _startupFinished =
        !DistributionChannel.isBeta || !_startupStyle.staticImage;
    _dependencies = _initializeDependencies();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => StartupTimingProbe.mark('startup_frame'),
    );
  }

  Future<_MestingDependencies> _initializeDependencies() async {
    final stopwatch = Stopwatch()..start();
    final database = AppDatabase();
    try {
      // Show the inexpensive startup surface first. Optics and native audio
      // initialize concurrently, and both must finish before the real app mounts.
      final visualReady = DistributionChannel.isBeta
          ? LiquidGlassWidgets.initialize()
          : Future<void>.value();
      final brandReady =
          !DistributionChannel.isBeta ||
              widget.preferences.getString(appBrandStylePreferenceKey) !=
                  widget.brandStyle.id
          ? widget.preferences.setString(
              appBrandStylePreferenceKey,
              widget.brandStyle.id,
            )
          : Future<bool>.value(true);
      final audioReady = AudioService.init<MestingAudioHandler>(
        builder: () => MestingAudioHandler(tracks: const <Track>[]),
        config: AudioServiceConfig(
          androidNotificationIcon: 'drawable/ic_stat_mesting',
          androidNotificationChannelId: 'com.mesting.music.playback',
          androidNotificationChannelName: DistributionChannel.isBeta
              ? 'Mesting Music'
              : 'Mesting 音乐播放',
          androidNotificationChannelDescription: '显示正在播放的歌曲与媒体控制',
          androidStopForegroundOnPause: false,
        ),
      );
      final initialized = await Future.wait<dynamic>([
        audioReady,
        visualReady,
        brandReady,
        if (DistributionChannel.isBeta)
          persistentNetworkImageCache.initialize(),
        if (DistributionChannel.isBeta) browseResponseCache.initialize(),
      ]);
      if (DistributionChannel.isBeta) {
        browseResponseCache.prepareRefresh =
            artworkRefreshCoordinator.prepareRefresh;
        browseResponseCache.prepareCached =
            artworkRefreshCoordinator.prepareCached;
      }
      final audioHandler = initialized.first as MestingAudioHandler;
      final playbackPersistence = PlaybackPersistenceController(
        database: database,
        audioHandler: audioHandler,
      );
      final minimumLaunchDuration = DistributionChannel.isBeta
          ? Duration.zero
          : Duration(milliseconds: 720);
      final remaining = minimumLaunchDuration - stopwatch.elapsed;
      if (remaining > Duration.zero) {
        await Future<void>.delayed(remaining);
      }
      final dependencies = _MestingDependencies(
        database: database,
        preferences: widget.preferences,
        audioHandler: audioHandler,
        playbackPersistence: playbackPersistence,
      );
      // Hydrate into the container that the app will actually mount. Restoring
      // only a directory index leaves every FutureProvider in AsyncLoading on
      // the first routed frame, even when its response already exists on disk.
      if (DistributionChannel.isBeta) {
        dependencies.discoveryCache = await DiscoveryStartupCache.prepare(
          dependencies.container,
        );
      }
      StartupTimingProbe.mark('dependencies_ready');

      // Start persistence after the real app has rendered its first frame.
      // Account restoration in MestingMusicApp selects the isolated snapshot.
      // Launcher aliases are only changed by an explicit brand selection.
      // Retrying a pending alias update during cold start can make OEM
      // launchers briefly surface both the old and new icons.
      return dependencies;
    } on Object {
      await database.close();
      rethrow;
    }
  }

  void _retry() {
    _staticVisibility.dispose();
    setState(() {
      // Retry dependency initialization, not the already presented startup artwork.
      _startupFinished = true;
      _dependencies = _initializeDependencies();
    });
  }

  @override
  void dispose() {
    _staticVisibility.dispose();
    unawaited(
      _dependencies.then((d) {
        d.discoveryCache?.dispose();
        d.container.dispose();
      }, onError: (Object _) {}),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_MestingDependencies>(
      future: _dependencies,
      builder: (context, snapshot) {
        final dependencies = snapshot.data;
        final Widget child;
        if (dependencies == null || !_startupFinished) {
          child =
              DistributionChannel.isBeta &&
                  _startupStyle.staticImage &&
                  !_imageAborted &&
                  !snapshot.hasError
              ? MaterialApp(
                  key: const ValueKey('startup-image-app'),
                  debugShowCheckedModeBanner: false,
                  home: StartupImageSurface(
                    style: _startupStyle,
                    onPresented: _staticVisibility.presented,
                    onFailed: () {
                      _staticVisibility.dispose();
                      if (mounted) {
                        setState(() {
                          _imageAborted = true;
                          _startupFinished = true;
                        });
                      }
                    },
                  ),
                )
              : MestingBrandedLaunchApp(
                  key: const ValueKey('branded-launch-app'),
                  brandStyle: widget.brandStyle,
                  themeMode: widget.launchThemeMode,
                  forceCoral: DistributionChannel.isBeta,
                  failed: snapshot.hasError,
                  onRetry: snapshot.hasError ? _retry : null,
                );
        } else {
          if (!_persistenceStarted) {
            _persistenceStarted = true;
            // Only the real app's first frame starts persistence/restoration.
            // In particular the startup artwork cannot race a restored track.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              StartupTimingProbe.mark('bootstrap_app_frame');
              dependencies.playbackPersistence.start();
              dependencies.discoveryCache?.resume();
            });
          }
          child = UncontrolledProviderScope(
            key: const ValueKey('mesting-music-app'),
            container: dependencies.container,
            child: const MestingMusicApp(),
          );
        }
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) =>
              FadeTransition(opacity: animation, child: child),
          child: child,
        );
      },
    );
  }
}

class _MestingDependencies {
  _MestingDependencies({
    required this.database,
    required this.preferences,
    required this.audioHandler,
    required this.playbackPersistence,
  });

  late final container = ProviderContainer(
    overrides: [
      audioHandlerProvider.overrideWithValue(audioHandler),
      appDatabaseProvider.overrideWithValue(database),
      sharedPreferencesProvider.overrideWithValue(preferences),
      playbackPersistenceControllerProvider.overrideWithValue(
        playbackPersistence,
      ),
      beforeAppUpdateInstallProvider.overrideWithValue(
        playbackPersistence.saveBeforeUpdate,
      ),
    ],
  );
  DiscoveryStartupCache? discoveryCache;

  final AppDatabase database;
  final SharedPreferences preferences;
  final MestingAudioHandler audioHandler;
  final PlaybackPersistenceController playbackPersistence;
}
