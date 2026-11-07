import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/router/app_router.dart';
import '../../../core/audio/mesting_audio_handler.dart';
import '../../../core/audio/playback_providers.dart';
import '../../../core/platform/lyrics_overlay_bridge.dart';
import '../../auth/account_capabilities.dart';
import '../../music_platform/presentation/platform_feedback.dart';
import '../../../core/platform/distribution_channel.dart';
import '../../library/presentation/library_access.dart';
import '../../library/library_providers.dart';
import '../lyrics_providers.dart';

class LyricsOverlayCoordinator extends ConsumerStatefulWidget {
  const LyricsOverlayCoordinator({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<LyricsOverlayCoordinator> createState() =>
      _LyricsOverlayCoordinatorState();
}

class _LyricsOverlayCoordinatorState
    extends ConsumerState<LyricsOverlayCoordinator>
    with WidgetsBindingObserver {
  String _lastSignature = '';
  String _lastNotificationSignature = '';
  bool _overlaySyncInFlight = false;
  bool _overlaySyncPending = false;
  StreamSubscription<dynamic>? _notificationActionSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _notificationActionSubscription = ref
        .read(audioHandlerProvider)
        .customEvent
        .listen(_handleNotificationAction);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(lyricsOverlayProvider.notifier).refreshPermissions();
    }
  }

  @override
  void dispose() {
    _notificationActionSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _handleNotificationAction(dynamic event) async {
    final action = event is Map ? event['action'] as String? : event as String?;
    final permissionRequestLaunched =
        event is Map && event['permissionRequestLaunched'] == true;
    if (!mounted || action == null) return;

    switch (action) {
      case MestingAudioHandler.notificationToggleFavoriteAction:
        if (!ref.read(canUseCurrentLibraryProvider)) {
          final redirect = Uri.encodeComponent('/music?view=favorites');
          appRouter.go('/auth?mode=register&redirect=$redirect');
          await ref.read(lyricsOverlayBridgeProvider).bringAppToFront();
          return;
        }
        if (DistributionChannel.isBeta &&
            !await ensureLibraryAccess(
              context,
              ref,
              reason: '收藏音乐',
              redirect: '/music?view=favorites',
            )) {
          return;
        }
        if (!mounted) return;
        final track = ref.read(currentTrackProvider);
        final repository = ref.read(libraryRepositoryProvider);
        bool nextFavorite;
        try {
          nextFavorite = await repository.toggleFavorite(track);
        } catch (error) {
          if (mounted) showPlatformFailure(context, error);
          return;
        }
        await ref
            .read(audioHandlerProvider)
            .updateNotificationExtras(
              favorite: nextFavorite,
              lyricsOverlayVisible: ref.read(lyricsOverlayProvider).visible,
              lyricsOverlayLocked: ref.read(lyricsOverlayProvider).locked,
            );
      case MestingAudioHandler.notificationToggleLyricsAction:
        if (permissionRequestLaunched) {
          final snapshot = await _lyricsSnapshot();
          ref
              .read(lyricsOverlayProvider.notifier)
              .prepareShowAfterPermission(
                current: snapshot.current,
                next: snapshot.next,
                playing: snapshot.playing,
                favorite: snapshot.favorite,
              );
          return;
        }
        await _toggleLyricsOverlay();
    }
  }

  Future<void> _toggleLyricsOverlay() async {
    final controller = ref.read(lyricsOverlayProvider.notifier);
    final overlay = ref.read(lyricsOverlayProvider);
    if (overlay.visible && overlay.locked) {
      await controller.setLocked(false);
      return;
    }
    if (overlay.visible) {
      await controller.hide();
      return;
    }
    final snapshot = await _lyricsSnapshot();
    await controller.show(
      current: snapshot.current,
      next: snapshot.next,
      playing: snapshot.playing,
      favorite: snapshot.favorite,
    );
  }

  Future<({String current, String next, bool playing, bool favorite})>
  _lyricsSnapshot() async {
    final track = ref.read(currentTrackProvider);
    final position = ref.read(positionProvider).value ?? Duration.zero;
    final playing = ref.read(playbackStateProvider).value?.playing ?? false;
    final favorite =
        ref.read(canUseCurrentLibraryProvider) &&
        ref.read(favoriteTrackIdsProvider).contains(track.id);
    var current = track.title;
    var next = track.artist;
    try {
      final lyrics = await ref.read(
        lyricsProvider(track.resolvedLyricsAsset).future,
      );
      if (lyrics.lines.isNotEmpty) {
        final index = lyrics.activeIndexAt(position);
        if (index >= 0) current = lyrics.lines[index].text;
        if (index + 1 >= 0 && index + 1 < lyrics.lines.length) {
          next = lyrics.lines[index + 1].text;
        }
      }
    } on Object {
      // 本地歌词暂不可用时仍显示歌曲信息，避免悬浮窗停留在“准备中”。
    }
    return (current: current, next: next, playing: playing, favorite: favorite);
  }

  Future<void> _syncOverlayLyrics() async {
    if (!mounted || !ref.read(lyricsOverlayProvider).visible) return;
    if (_overlaySyncInFlight) {
      _overlaySyncPending = true;
      return;
    }
    _overlaySyncInFlight = true;
    try {
      do {
        _overlaySyncPending = false;
        final snapshot = await _lyricsSnapshot();
        final overlay = ref.read(lyricsOverlayProvider);
        if (!mounted || !overlay.visible) break;
        final signature =
            '${snapshot.current}\n${snapshot.next}\n${snapshot.playing}\n'
            '${snapshot.favorite}\n'
            '${overlay.locked}\n${overlay.fontSize}\n${overlay.textColor}';
        if (signature != _lastSignature) {
          _lastSignature = signature;
          await ref
              .read(lyricsOverlayProvider.notifier)
              .update(
                current: snapshot.current,
                next: snapshot.next,
                playing: snapshot.playing,
                favorite: snapshot.favorite,
              );
        }
      } while (_overlaySyncPending);
    } finally {
      _overlaySyncInFlight = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final overlay = ref.watch(lyricsOverlayProvider);
    final track = ref.watch(currentTrackProvider);
    final authenticated = ref.watch(canUseCurrentLibraryProvider);
    final favorite =
        authenticated && ref.watch(favoriteTrackIdsProvider).contains(track.id);

    final notificationSignature =
        '${track.id}\n$favorite\n${overlay.visible}\n${overlay.locked}';
    if (notificationSignature != _lastNotificationSignature) {
      _lastNotificationSignature = notificationSignature;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref
            .read(audioHandlerProvider)
            .updateNotificationExtras(
              favorite: favorite,
              lyricsOverlayVisible: overlay.visible,
              lyricsOverlayLocked: overlay.locked,
            );
      });
    }

    ref.listen(positionProvider, (_, _) => unawaited(_syncOverlayLyrics()));
    ref.listen(
      currentMediaItemProvider,
      (_, _) => unawaited(_syncOverlayLyrics()),
    );
    ref.listen(
      playbackStateProvider,
      (_, _) => unawaited(_syncOverlayLyrics()),
    );
    ref.listen(
      favoriteTrackIdsProvider,
      (_, _) => unawaited(_syncOverlayLyrics()),
    );
    ref.listen(lyricsOverlayProvider, (previous, next) {
      if (next.visible) unawaited(_syncOverlayLyrics());
    });
    return widget.child;
  }
}
