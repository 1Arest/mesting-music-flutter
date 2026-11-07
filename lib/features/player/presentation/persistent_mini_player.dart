import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/audio/playback_providers.dart';
import '../../../shared/widgets/artwork_image.dart';
import '../../queue/presentation/queue_page.dart';
import '../../themes/music_theme_tokens.dart';
import 'now_playing_transition.dart';
import '../../../core/platform/distribution_channel.dart';
import '../../experience/presentation/floating_playback_pill.dart';

const double miniPlayerHeight = 64;
const double miniPlayerVinylDiameter = 64;
const double miniPlayerPlayControlDiameter = 40;
const double miniPlayerPlaySurfaceDiameter = 34;
const double miniPlayerSwipeDistanceThreshold = 42;
const double miniPlayerSwipeVelocityThreshold = 520;
const double miniPlayerTrackTransitionHorizontalOffset = .26;
const double miniPlayerTrackTransitionStartScale = .965;
const Duration miniPlayerTrackTransitionDuration = Duration(milliseconds: 380);
const double miniPlayerDragTravelFraction = .055;
const double miniPlayerDragScaleReduction = .018;
const double miniPlayerDragOpacityReduction = .08;
const Duration miniPlayerDragResetDuration = Duration(milliseconds: 210);
const Duration miniPlayerTrackTransitionDirectionTimeout = Duration(seconds: 2);
const List<BoxShadow> miniPlayerVinylShadows = <BoxShadow>[];

enum MiniPlayerSwipeAction { previous, next }

typedef MiniPlayerDragProgressChanged =
    void Function(double progress, bool dragging);

Offset miniPlayerTrackTransitionOffset({
  required MiniPlayerSwipeAction action,
  required bool incoming,
}) {
  final entersFromRight = action == MiniPlayerSwipeAction.next;
  final dx = entersFromRight
      ? (incoming
            ? miniPlayerTrackTransitionHorizontalOffset
            : -miniPlayerTrackTransitionHorizontalOffset)
      : (incoming
            ? -miniPlayerTrackTransitionHorizontalOffset
            : miniPlayerTrackTransitionHorizontalOffset);
  return Offset(dx, 0);
}

MiniPlayerSwipeAction? resolveMiniPlayerSwipeAction({
  required double dragDistance,
  required double primaryVelocity,
}) {
  final direction = dragDistance.abs() >= miniPlayerSwipeDistanceThreshold
      ? dragDistance
      : primaryVelocity.abs() >= miniPlayerSwipeVelocityThreshold
      ? primaryVelocity
      : 0;
  if (direction == 0) return null;
  return direction < 0
      ? MiniPlayerSwipeAction.next
      : MiniPlayerSwipeAction.previous;
}

List<BoxShadow> miniPlayerOuterShadowsFor(Brightness brightness, Color accent) {
  return const <BoxShadow>[];
}

List<Color> miniPlayerDepthGradientColorsFor({
  required Brightness brightness,
  required Color accent,
  required Color base,
}) {
  final dark = brightness == Brightness.dark;
  return [
    Color.alphaBlend(
      Colors.white.withValues(alpha: dark ? .11 : .58),
      base.withValues(alpha: dark ? .84 : .9),
    ),
    base.withValues(alpha: dark ? .8 : .84),
    Color.alphaBlend(
      accent.withValues(alpha: dark ? .09 : .055),
      base.withValues(alpha: dark ? .82 : .86),
    ),
  ];
}

@immutable
class MiniPlayerPlayControlPalette {
  const MiniPlayerPlayControlPalette({
    required this.surface,
    required this.progressTrack,
    required this.icon,
  });

  final Color surface;
  final Color progressTrack;
  final Color icon;
}

MiniPlayerPlayControlPalette miniPlayerPlayControlPaletteFor(
  Brightness brightness,
) {
  return brightness == Brightness.dark
      ? const MiniPlayerPlayControlPalette(
          surface: Color(0xB324202B),
          progressTrack: Color(0x57FFFFFF),
          icon: Color(0xFFF7F3FA),
        )
      : const MiniPlayerPlayControlPalette(
          surface: Color(0xEFFFFFFF),
          progressTrack: Color(0x3D5D626C),
          icon: Color(0xFF27242C),
        );
}

class PersistentMiniPlayer extends ConsumerStatefulWidget {
  const PersistentMiniPlayer({super.key});

  @override
  ConsumerState<PersistentMiniPlayer> createState() =>
      _PersistentMiniPlayerState();
}

class _PersistentMiniPlayerState extends ConsumerState<PersistentMiniPlayer> {
  final GlobalKey _vinylKey = GlobalKey();
  MiniPlayerSwipeAction _trackTransitionAction = MiniPlayerSwipeAction.next;
  MiniPlayerSwipeAction? _pendingSwipeAction;
  Timer? _pendingSwipeTimer;
  String? _displayedTrackId;
  double _swipeDragProgress = 0;
  bool _swipeDragging = false;

  @override
  void dispose() {
    _pendingSwipeTimer?.cancel();
    super.dispose();
  }

  void _rememberSwipeAction(MiniPlayerSwipeAction action) {
    _pendingSwipeTimer?.cancel();
    setState(() => _pendingSwipeAction = action);
    _pendingSwipeTimer = Timer(miniPlayerTrackTransitionDirectionTimeout, () {
      if (mounted && _pendingSwipeAction == action) {
        setState(() => _pendingSwipeAction = null);
      }
    });
  }

  void _syncTrackTransition(String trackId) {
    if (_displayedTrackId == null) {
      _displayedTrackId = trackId;
      return;
    }
    if (_displayedTrackId == trackId) return;
    _displayedTrackId = trackId;
    _trackTransitionAction = _pendingSwipeAction ?? MiniPlayerSwipeAction.next;
    _pendingSwipeAction = null;
    _pendingSwipeTimer?.cancel();
    _pendingSwipeTimer = null;
  }

  void _openNowPlaying() {
    final renderBox =
        _vinylKey.currentContext?.findRenderObject() as RenderBox?;
    final origin = renderBox == null || !renderBox.hasSize
        ? null
        : renderBox.localToGlobal(Offset.zero) & renderBox.size;
    context.push(
      '/player',
      extra: origin == null
          ? null
          : NowPlayingTransitionIntent(vinylOrigin: origin),
    );
  }

  void _updateSwipeDragProgress(double progress, bool dragging) {
    if ((_swipeDragProgress - progress).abs() < .001 &&
        _swipeDragging == dragging) {
      return;
    }
    setState(() {
      _swipeDragProgress = progress;
      _swipeDragging = dragging;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (DistributionChannel.isBeta) return const FloatingPlaybackPill();
    final mediaItem = ref.watch(currentMediaItemProvider).value;
    if (mediaItem == null) return const SizedBox.shrink();

    final handler = ref.watch(audioHandlerProvider);
    final track = ref.watch(currentTrackProvider);
    final state = ref.watch(playbackStateProvider).value;
    final playing = state?.playing ?? false;
    final vinylRotating = shouldAnimateVinyl(state);
    final tokens = context.musicThemeTokens;
    final accent = Theme.of(context).colorScheme.primary;
    final brightness = Theme.of(context).brightness;
    final dark = brightness == Brightness.dark;
    final depthColors = miniPlayerDepthGradientColorsFor(
      brightness: brightness,
      accent: accent,
      base: tokens.glassStrong,
    );
    _syncTrackTransition(track.id);
    final trackTransitionKey = ValueKey<String>(track.id);
    return Container(
      key: const ValueKey('mini-player-capsule'),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        boxShadow: miniPlayerOuterShadowsFor(
          Theme.of(context).brightness,
          accent,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: DecoratedBox(
          key: const ValueKey('mini-player-depth-surface'),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: depthColors,
              stops: const [0, .52, 1],
            ),
          ),
          child: Material(
            color: Colors.transparent,
            shape: StadiumBorder(
              side: BorderSide(
                color: dark ? tokens.borderStrong : const Color(0x33596375),
              ),
            ),
            elevation: 0,
            child: MiniPlayerSwipeRegion(
              onDragProgressChanged: _updateSwipeDragProgress,
              onPrevious: () {
                _rememberSwipeAction(MiniPlayerSwipeAction.previous);
                unawaited(handler.skipToPrevious());
              },
              onNext: () {
                _rememberSwipeAction(MiniPlayerSwipeAction.next);
                unawaited(handler.skipToNext());
              },
              child: InkWell(
                onTap: _openNowPlaying,
                child: SizedBox(
                  height: miniPlayerHeight,
                  child: Row(
                    children: [
                      SizedBox.square(
                        key: _vinylKey,
                        dimension: miniPlayerVinylDiameter,
                        child: ClipRect(
                          child: MiniPlayerDragMotion(
                            progress: _swipeDragProgress,
                            dragging: _swipeDragging,
                            child: MiniPlayerTrackSwitcher(
                              trackKey: trackTransitionKey,
                              action: _trackTransitionAction,
                              child: RepaintBoundary(
                                child: _MiniVinylRecord(
                                  coverAsset: track.coverAsset,
                                  playing: vinylRotating,
                                  accent: accent,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ClipRect(
                          child: MiniPlayerDragMotion(
                            progress: _swipeDragProgress,
                            dragging: _swipeDragging,
                            child: MiniPlayerTrackSwitcher(
                              trackKey: trackTransitionKey,
                              action: _trackTransitionAction,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  MiniPlayerOverflowMarquee(
                                    text: track.title,
                                    semanticLabel: '歌曲名称',
                                    animate: playing,
                                    style: TextStyle(
                                      color: tokens.textPrimary,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  MiniPlayerOverflowMarquee(
                                    text: track.artist,
                                    semanticLabel: '歌手名称',
                                    animate: playing,
                                    style: TextStyle(
                                      color: tokens.textSecondary,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      _MiniProgressPlayButtonConsumer(
                        playing: playing,
                        fallbackDuration: track.duration,
                        accent: accent,
                        onPressed: handler.togglePlayPause,
                      ),
                      const SizedBox(width: 9),
                      IconButton(
                        tooltip: '播放队列',
                        onPressed: () => showPlaybackQueueSheet(context),
                        icon: const Icon(Icons.queue_music_rounded),
                      ),
                      const SizedBox(width: 5),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MiniPlayerTrackSwitcher extends StatelessWidget {
  const MiniPlayerTrackSwitcher({
    required this.trackKey,
    required this.action,
    required this.child,
    super.key,
  });

  final Key trackKey;
  final MiniPlayerSwipeAction action;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final duration = MediaQuery.maybeOf(context)?.disableAnimations == true
        ? Duration.zero
        : miniPlayerTrackTransitionDuration;
    return AnimatedSwitcher(
      key: const ValueKey('mini-player-track-switcher'),
      duration: duration,
      reverseDuration: duration,
      switchInCurve: Curves.easeOutQuart,
      switchOutCurve: Curves.easeInQuart,
      layoutBuilder: (currentChild, previousChildren) => Stack(
        alignment: Alignment.centerLeft,
        children: [...previousChildren, ?currentChild],
      ),
      transitionBuilder: (transitionChild, animation) {
        final incoming = transitionChild.key == trackKey;
        final movement = Tween<Offset>(
          begin: miniPlayerTrackTransitionOffset(
            action: action,
            incoming: incoming,
          ),
          end: Offset.zero,
        ).animate(animation);
        final scale = Tween<double>(
          begin: miniPlayerTrackTransitionStartScale,
          end: 1,
        ).animate(animation);
        return ExcludeSemantics(
          excluding: !incoming,
          child: IgnorePointer(
            ignoring: !incoming,
            child: ScaleTransition(
              key: ValueKey<String>(
                'mini-player-track-${incoming ? 'incoming' : 'outgoing'}-scale',
              ),
              scale: scale,
              child: FadeTransition(
                key: ValueKey<String>(
                  'mini-player-track-${incoming ? 'incoming' : 'outgoing'}-fade',
                ),
                opacity: animation,
                child: SlideTransition(
                  key: ValueKey<String>(
                    'mini-player-track-${incoming ? 'incoming' : 'outgoing'}-slide',
                  ),
                  position: movement,
                  child: transitionChild,
                ),
              ),
            ),
          ),
        );
      },
      child: KeyedSubtree(key: trackKey, child: child),
    );
  }
}

class MiniPlayerDragMotion extends StatelessWidget {
  const MiniPlayerDragMotion({
    required this.progress,
    required this.dragging,
    required this.child,
    super.key,
  });

  final double progress;
  final bool dragging;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reducedMotion =
        MediaQuery.maybeOf(context)?.disableAnimations == true;
    final duration = reducedMotion || dragging
        ? Duration.zero
        : miniPlayerDragResetDuration;
    final scale = 1 - progress.abs() * miniPlayerDragScaleReduction;
    final opacity = 1 - progress.abs() * miniPlayerDragOpacityReduction;
    return AnimatedSlide(
      key: const ValueKey('mini-player-drag-slide'),
      offset: Offset(progress * miniPlayerDragTravelFraction, 0),
      duration: duration,
      curve: Curves.easeOutCubic,
      child: AnimatedScale(
        key: const ValueKey('mini-player-drag-scale'),
        scale: scale,
        duration: duration,
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          key: const ValueKey('mini-player-drag-opacity'),
          opacity: opacity,
          duration: duration,
          curve: Curves.easeOutCubic,
          child: child,
        ),
      ),
    );
  }
}

class MiniPlayerSwipeRegion extends StatefulWidget {
  const MiniPlayerSwipeRegion({
    required this.onPrevious,
    required this.onNext,
    required this.child,
    this.onDragProgressChanged,
    super.key,
  });

  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final Widget child;
  final MiniPlayerDragProgressChanged? onDragProgressChanged;

  @override
  State<MiniPlayerSwipeRegion> createState() => _MiniPlayerSwipeRegionState();
}

class _MiniPlayerSwipeRegionState extends State<MiniPlayerSwipeRegion> {
  double _horizontalDragDistance = 0;

  void _reportDragProgress({required bool dragging}) {
    final progress =
        (_horizontalDragDistance / (miniPlayerSwipeDistanceThreshold * 1.5))
            .clamp(-1.0, 1.0);
    widget.onDragProgressChanged?.call(progress, dragging);
  }

  void _resetDragProgress({required bool dragging}) {
    _horizontalDragDistance = 0;
    widget.onDragProgressChanged?.call(0, dragging);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const ValueKey('mini-player-swipe-area'),
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: (_) => _resetDragProgress(dragging: true),
      onHorizontalDragUpdate: (details) {
        _horizontalDragDistance += details.primaryDelta ?? 0;
        _reportDragProgress(dragging: true);
      },
      onHorizontalDragCancel: () => _resetDragProgress(dragging: false),
      onHorizontalDragEnd: (details) {
        final action = resolveMiniPlayerSwipeAction(
          dragDistance: _horizontalDragDistance,
          primaryVelocity: details.primaryVelocity ?? 0,
        );
        switch (action) {
          case MiniPlayerSwipeAction.previous:
            widget.onPrevious();
          case MiniPlayerSwipeAction.next:
            widget.onNext();
          case null:
            break;
        }
        _resetDragProgress(dragging: false);
      },
      child: widget.child,
    );
  }
}

class MiniPlayerOverflowMarquee extends StatelessWidget {
  const MiniPlayerOverflowMarquee({
    required this.text,
    required this.semanticLabel,
    required this.style,
    this.marqueeEnabled = true,
    this.animate = true,
    this.keyPrefix,
    super.key,
  });

  final String text;
  final String semanticLabel;
  final TextStyle style;
  final bool marqueeEnabled;
  final bool animate;
  final String? keyPrefix;

  String get _staticKey => keyPrefix == null
      ? 'mini-player-static-$semanticLabel'
      : '$keyPrefix-static';

  String get _marqueeKey => keyPrefix == null
      ? 'mini-player-marquee-$semanticLabel'
      : '$keyPrefix-marquee';

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: style),
          maxLines: 1,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();
        final availableWidth = constraints.maxWidth;
        final overflows =
            availableWidth.isFinite && painter.width > availableWidth;
        final animationsDisabled =
            MediaQuery.maybeOf(context)?.disableAnimations ?? false;

        if (!overflows || animationsDisabled || !marqueeEnabled) {
          return Text(
            text,
            key: ValueKey(_staticKey),
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: style,
          );
        }

        return Semantics(
          label: '$semanticLabel：$text',
          child: ExcludeSemantics(
            child: SizedBox(
              height: painter.height,
              child: ClipRect(
                child: OverflowBox(
                  alignment: Alignment.centerLeft,
                  minWidth: 0,
                  maxWidth: double.infinity,
                  minHeight: painter.height,
                  maxHeight: painter.height,
                  child: _MiniPlayerMarqueeTrack(
                    key: ValueKey(_marqueeKey),
                    text: text,
                    style: style,
                    textWidth: painter.width,
                    animate: animate,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MiniPlayerMarqueeTrack extends StatefulWidget {
  const _MiniPlayerMarqueeTrack({
    required this.text,
    required this.style,
    required this.textWidth,
    required this.animate,
    super.key,
  });

  static const double gap = 32;
  static const double pixelsPerSecond = 30;

  final String text;
  final TextStyle style;
  final double textWidth;
  final bool animate;

  @override
  State<_MiniPlayerMarqueeTrack> createState() =>
      _MiniPlayerMarqueeTrackState();
}

class _MiniPlayerMarqueeTrackState extends State<_MiniPlayerMarqueeTrack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  double get _travelDistance => widget.textWidth + _MiniPlayerMarqueeTrack.gap;

  Duration get _duration {
    final scrollMilliseconds =
        (_travelDistance / _MiniPlayerMarqueeTrack.pixelsPerSecond * 1000)
            .round();
    return Duration(milliseconds: scrollMilliseconds);
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _duration);
    if (widget.animate) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant _MiniPlayerMarqueeTrack oldWidget) {
    super.didUpdateWidget(oldWidget);
    final contentChanged =
        oldWidget.text != widget.text ||
        oldWidget.style != widget.style ||
        oldWidget.textWidth != widget.textWidth;
    if (contentChanged) {
      _controller
        ..stop()
        ..duration = _duration
        ..value = 0;
      if (widget.animate) {
        _controller.repeat();
      }
      return;
    }
    if (oldWidget.animate == widget.animate) return;
    if (widget.animate) {
      _controller.repeat();
    } else {
      _controller.stop(canceled: false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.text, maxLines: 1, softWrap: false, style: widget.style),
          const SizedBox(width: _MiniPlayerMarqueeTrack.gap),
          Text(widget.text, maxLines: 1, softWrap: false, style: widget.style),
        ],
      ),
      builder: (context, child) {
        return Transform.translate(
          // The duplicate copy lands exactly where the first copy started, so
          // repeating stays seamless without a stationary pause.
          offset: Offset(-_travelDistance * _controller.value, 0),
          child: child,
        );
      },
    );
  }
}

class _MiniProgressPlayButtonConsumer extends ConsumerWidget {
  const _MiniProgressPlayButtonConsumer({
    required this.playing,
    required this.fallbackDuration,
    required this.accent,
    required this.onPressed,
  });

  final bool playing;
  final Duration fallbackDuration;
  final Color accent;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final position = ref.watch(positionProvider).value ?? Duration.zero;
    final duration = ref.watch(durationProvider).value ?? fallbackDuration;
    final progress = duration.inMilliseconds <= 0
        ? 0.0
        : (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
    return RepaintBoundary(
      child: _MiniProgressPlayButton(
        playing: playing,
        progress: progress,
        accent: accent,
        onPressed: onPressed,
      ),
    );
  }
}

class _MiniProgressPlayButton extends StatelessWidget {
  const _MiniProgressPlayButton({
    required this.playing,
    required this.progress,
    required this.accent,
    required this.onPressed,
  });

  final bool playing;
  final double progress;
  final Color accent;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = miniPlayerPlayControlPaletteFor(
      Theme.of(context).brightness,
    );
    return SizedBox.square(
      dimension: miniPlayerPlayControlDiameter,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            key: const ValueKey('mini-player-play-surface'),
            width: miniPlayerPlaySurfaceDiameter,
            height: miniPlayerPlaySurfaceDiameter,
            decoration: BoxDecoration(
              color: palette.surface,
              shape: BoxShape.circle,
            ),
          ),
          TweenAnimationBuilder<double>(
            tween: Tween(end: progress.clamp(0.0, 1.0)),
            duration: const Duration(milliseconds: 200),
            curve: Curves.linear,
            builder: (context, value, child) => SizedBox.square(
              dimension: miniPlayerPlaySurfaceDiameter,
              child: CircularProgressIndicator(
                value: value,
                strokeWidth: 1.7,
                strokeCap: StrokeCap.round,
                color: accent,
                backgroundColor: palette.progressTrack,
                semanticsLabel: '歌曲播放进度',
                semanticsValue: '${(value * 100).round()}%',
              ),
            ),
          ),
          IconButton(
            key: const ValueKey('mini-player-play-toggle'),
            tooltip: playing ? '暂停' : '播放',
            onPressed: onPressed,
            padding: EdgeInsets.zero,
            style: IconButton.styleFrom(
              minimumSize: const Size.square(miniPlayerPlayControlDiameter),
              maximumSize: const Size.square(miniPlayerPlayControlDiameter),
              foregroundColor: palette.icon,
              overlayColor: accent.withValues(alpha: .10),
            ),
            icon: AnimatedSwitcher(
              duration: const Duration(milliseconds: 160),
              switchInCurve: Curves.easeOutBack,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: ScaleTransition(scale: animation, child: child),
              ),
              child: Icon(
                playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                key: ValueKey(playing),
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniVinylRecord extends StatefulWidget {
  const _MiniVinylRecord({
    required this.coverAsset,
    required this.playing,
    required this.accent,
  });

  final String coverAsset;
  final bool playing;
  final Color accent;

  @override
  State<_MiniVinylRecord> createState() => _MiniVinylRecordState();
}

class _MiniVinylRecordState extends State<_MiniVinylRecord>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rotation;

  @override
  void initState() {
    super.initState();
    _rotation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5600),
    );
    if (widget.playing) _rotation.repeat();
  }

  @override
  void didUpdateWidget(covariant _MiniVinylRecord oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playing == widget.playing) return;
    widget.playing ? _rotation.repeat() : _rotation.stop();
  }

  @override
  void dispose() {
    _rotation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: miniPlayerVinylDiameter,
      child: RotationTransition(
        turns: _rotation,
        child: Stack(
          alignment: Alignment.center,
          children: [
            const DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  stops: [0, .18, .20, .38, .40, 1],
                  colors: [
                    Color(0xFF46414C),
                    Color(0xFF17151A),
                    Color(0xFF3A3640),
                    Color(0xFF121116),
                    Color(0xFF29262E),
                    Color(0xFF07070A),
                  ],
                ),
                boxShadow: miniPlayerVinylShadows,
              ),
              child: SizedBox.expand(),
            ),
            Positioned.fill(
              child: CustomPaint(painter: _MiniVinylGrooves(widget.accent)),
            ),
            ClipOval(
              child: ArtworkImage(
                uri: widget.coverAsset,
                width: 38,
                height: 38,
              ),
            ),
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: const Color(0xFF17151A),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0x8AFFFFFF)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniVinylGrooves extends CustomPainter {
  const _MiniVinylGrooves(this.accent);

  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .65;
    for (var index = 0; index < 5; index++) {
      paint.color = index.isEven
          ? accent.withValues(alpha: .12)
          : Colors.white.withValues(alpha: .08);
      canvas.drawCircle(center, size.shortestSide * (.36 + index * .03), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _MiniVinylGrooves oldDelegate) =>
      oldDelegate.accent != accent;
}
