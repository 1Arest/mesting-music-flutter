import 'package:audio_service/audio_service.dart';
import '../../themes/personal_decorations.dart';
import '../../../shared/widgets/beta_glass_controls.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../player/presentation/open_now_playing.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../../core/audio/playback_providers.dart';
import '../../../core/haptics/app_haptics.dart';
import '../../../shared/widgets/track_artwork.dart';
import '../../../shared/models/track.dart';
import '../../music_platform/presentation/platform_feedback.dart';
import '../../music_platform/qishui/qishui_providers.dart';
import '../../music_platform/qishui/qishui_player_navigation.dart';
import '../../player/presentation/persistent_mini_player.dart'
    show MiniPlayerSwipeRegion, miniPlayerSwipeDistanceThreshold;
import 'beta_bottom_bar.dart';
import 'playback_pill_menu.dart';
import 'playback_pill_track_motion.dart';
import 'playback_pill_artwork.dart';
import '../../themes/music_typography.dart';

/// Official Apple Music example's GlassButton.custom play pill (MIT), with live
/// Mesting media/actions. The package owns press/spring/refraction, while the
/// existing audio service and swipe contract own playback. No second player.
class FloatingPlaybackPill extends ConsumerStatefulWidget {
  const FloatingPlaybackPill({this.compact = false, super.key});
  final bool compact;
  @override
  ConsumerState<FloatingPlaybackPill> createState() =>
      _FloatingPlaybackPillState();
}

class _FloatingPlaybackPillState extends ConsumerState<FloatingPlaybackPill> {
  final _anchor = GlobalKey();
  bool _menuOpen = false;
  final _drag = ValueNotifier((progress: 0.0, dragging: false));
  ({String from, bool forward, DateTime at})? _pendingSkip;
  String? _shownTrack;
  bool _forward = true;

  @override
  void dispose() {
    _drag.dispose();
    super.dispose();
  }

  Future<void> _openMenu() async {
    if (_menuOpen) return;
    final box = _anchor.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    _menuOpen = true;
    try {
      await showPlaybackPillMenu(
        context,
        ref,
        box.localToGlobal(Offset.zero) & box.size,
      );
    } finally {
      _menuOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(currentMediaItemProvider).value == null) {
      return const SizedBox.shrink();
    }
    final track = ref.watch(currentTrackProvider);
    if (_shownTrack != track.id) {
      final requested = _pendingSkip;
      _forward =
          requested != null &&
              requested.from == _shownTrack &&
              DateTime.now().difference(requested.at) <
                  const Duration(seconds: 2)
          ? requested.forward
          : true;
      _shownTrack = track.id;
      _pendingSkip = null;
    }
    final playing = ref.watch(
      playbackStateProvider.select((value) => value.value?.playing ?? false),
    );
    final busy = ref.watch(
      playbackStateProvider.select(
        (value) => value.value?.processingState == AudioProcessingState.loading,
      ),
    );
    final handler = ref.watch(audioHandlerProvider);
    final foreground = Theme.of(context).colorScheme.onSurface;
    Future<void> action(Future<void> Function() operation) async {
      appHaptic(context, AppHapticEvent.selection);
      try {
        await operation();
      } catch (error) {
        _pendingSkip = null;
        if (context.mounted) showPlatformFailure(context, error);
      }
    }

    Future<void> skip(bool forward) async {
      _pendingSkip = (from: track.id, forward: forward, at: DateTime.now());
      await action(forward ? handler.skipToNext : handler.skipToPrevious);
    }

    Widget control({
      required String label,
      required IconData icon,
      required VoidCallback onTap,
    }) => Semantics(
      label: label,
      button: true,
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: const Size(44, 44),
        onPressed: onTap,
        child: Icon(icon, size: 23, color: foreground),
      ),
    );

    // Placement is known by the shell. Measuring every intermediate width used
    // to rebuild this entire premium surface and flip layout at exactly 300dp.
    final compact = widget.compact;
    final narrowCompact = compact && MediaQuery.sizeOf(context).width < 360;
    return MiniPlayerSwipeRegion(
      onPrevious: () => skip(false),
      onNext: () => skip(true),
      onDragProgressChanged: (progress, dragging) =>
          _drag.value = (progress: progress, dragging: dragging),
      child: GestureDetector(
        key: _anchor,
        onLongPress: _openMenu,
        child: RepaintBoundary(
          child: PersonalMiniPlayer(
            child: GlassButton.custom(
              key: const ValueKey('beta6-official-play-pill'),
              onTap: () {
                appHaptic(context, AppHapticEvent.impact);
                if (ref.read(qishuiNavigationProvider)) {
                  openQishuiMusicTab(context, ref);
                } else {
                  openNowPlaying(context, ref);
                }
              },
              quality: GlassQuality.premium,
              useOwnLayer: true,
              width: double.infinity,
              height: 64,
              shape: const LiquidRoundedRectangle(borderRadius: 32),
              settings: betaMusicPillGlass(context),
              child: AnimatedPadding(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                padding: EdgeInsets.symmetric(
                  horizontal: narrowCompact
                      ? 6
                      : compact
                      ? 10
                      : 16,
                ),
                child: Row(
                  children: [
                    // Retain both 44dp transport targets on narrow inline bars.
                    // Only cover geometry adapts; its original image stays cached.
                    Expanded(
                      child: ValueListenableBuilder(
                        valueListenable: _drag,
                        builder: (context, drag, child) =>
                            PlaybackPillTrackMotion(
                              trackId: track.id,
                              forward: _forward,
                              dragOffset:
                                  drag.progress *
                                  miniPlayerSwipeDistanceThreshold *
                                  1.5,
                              dragging: drag.dragging,
                              child: child!,
                            ),
                        child: Row(
                          children: [
                            if (track.source == TrackSource.netease)
                              PlaybackPillArtwork(
                                track: track,
                                dimension: narrowCompact ? 24 : 32,
                              )
                            else
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeOutCubic,
                                width: narrowCompact ? 24 : 32,
                                height: narrowCompact ? 24 : 32,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: TrackArtwork(
                                    track: track,
                                    width: 32,
                                    height: 32,
                                  ),
                                ),
                              ),
                            SizedBox(width: narrowCompact ? 6 : 10),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    track.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: foreground,
                                      fontWeight: MusicTypography.bodyWeight,
                                      fontSize: MusicTypography.subheadlineSize,
                                    ),
                                  ),
                                  if (!compact ||
                                      MediaQuery.textScalerOf(
                                            context,
                                          ).scale(12) <=
                                          16)
                                    Text(
                                      track.artist,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: foreground.withValues(alpha: .7),
                                        fontSize: MusicTypography.captionSize,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (busy)
                      const SizedBox(
                        width: 44,
                        height: 44,
                        child: Center(
                          child: BetaActivityIndicator(label: '正在加载所选歌曲'),
                        ),
                      )
                    else
                      control(
                        label: playing ? '暂停' : '播放',
                        icon: playing
                            ? CupertinoIcons.pause_fill
                            : CupertinoIcons.play_fill,
                        // Consult the live fade state so another tap can cancel
                        // Pause before the shared transport finishes its fade.
                        onTap: () => action(handler.togglePlayPause),
                      ),
                    control(
                      label: '下一首',
                      icon: CupertinoIcons.forward_end_fill,
                      onTap: () => skip(true),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
