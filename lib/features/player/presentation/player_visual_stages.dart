import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../shared/models/track.dart';
import '../../../shared/layout/adaptive_layout.dart';
import '../../../shared/widgets/artwork_image.dart';
import '../../themes/mesting_palette.dart';
import '../player_visual_style.dart';
import 'vinyl_disc.dart';

const double alternativePlayerStageDefaultTopInset = 90;
const double alternativePlayerStageHeaderClearance = 68;

/// Geometric replacement for the outlined bitmap. Coordinates follow the
/// record width: the stylus stays on the outer grooves, outside its cover.
class _BetaTonearmPainter extends CustomPainter {
  const _BetaTonearmPainter(this.angle);
  final double angle;
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final pivot = Offset(w * .54, w * .005);
    canvas.save();
    canvas.translate(pivot.dx, pivot.dy);
    canvas.rotate(angle);
    canvas.translate(-pivot.dx, -pivot.dy);
    final path = Path()
      ..moveTo(pivot.dx, pivot.dy)
      ..quadraticBezierTo(w * .56, w * .14, w * .61, w * .24)
      ..quadraticBezierTo(w * .64, w * .28, w * .84, w * .37);
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFFF8F8F9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * .014
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(pivot, w * .024, Paint()..color = Colors.white);
    canvas.drawCircle(
      pivot,
      w * .009,
      Paint()..color = const Color(0xFFD5D7D9),
    );
    canvas.translate(w * .84, w * .37);
    canvas.rotate(.42);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(-w * .006, -w * .018, w * .064, w * .036),
        Radius.circular(w * .009),
      ),
      Paint()..color = Colors.white,
    );
    canvas.drawLine(
      Offset(w * .008, -w * .008),
      Offset(w * .04, -w * .008),
      Paint()
        ..color = const Color(0xFFC3C6C9)
        ..strokeWidth = w * .005,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BetaTonearmPainter oldDelegate) =>
      oldDelegate.angle != angle;
}

/// Artwork-only stage for Beta's shared transport shell. Reuses the production
/// motion surfaces continuously, without the preview's one-cycle animation.
class PlayerArtworkStage extends StatelessWidget {
  const PlayerArtworkStage({
    required this.style,
    required this.track,
    required this.playing,
    super.key,
  });
  final PlayerVisualStyle style;
  final Track track;
  final bool playing;
  @override
  Widget build(BuildContext context) {
    final motion = playing && !MediaQuery.disableAnimationsOf(context);
    final stage = switch (style) {
      PlayerVisualStyle.cover => ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: ArtworkImage(
          uri: track.coverAsset,
          width: 640,
          height: 640,
          fit: BoxFit.cover,
        ),
      ),
      PlayerVisualStyle.classic => LayoutBuilder(
        builder: (context, bounds) => Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.only(top: 28),
                child: VinylDisc(coverAsset: track.coverAsset, playing: motion),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: TweenAnimationBuilder<double>(
                  tween: Tween(end: playing ? 0 : -.38),
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 500),
                  builder: (context, angle, _) =>
                      CustomPaint(painter: _BetaTonearmPainter(angle)),
                ),
              ),
            ),
          ],
        ),
      ),
      PlayerVisualStyle.aurora => _AuroraRhythmOrbit(
        playing: motion,
        child: VinylDisc(
          coverAsset: track.coverAsset,
          playing: motion,
          labelSizeFactor: .64,
        ),
      ),
      PlayerVisualStyle.cassette => _ReactiveStageMotion(
        duration: const Duration(milliseconds: 1800),
        playing: motion,
        builder: (context, phase, energy, repaint, reduceMotion) =>
            _CosmicPulseSurface(
              track: track,
              phase: phase,
              energy: energy,
              repaint: repaint,
              reduceMotion: reduceMotion,
            ),
      ),
      PlayerVisualStyle.lyricStage => _ReactiveStageMotion(
        duration: const Duration(milliseconds: 1700),
        playing: motion,
        builder: (context, phase, energy, repaint, reduceMotion) =>
            _LiquidSpectrumSurface(
              track: track,
              phase: phase,
              energy: energy,
              repaint: repaint,
              reduceMotion: reduceMotion,
            ),
      ),
    };
    return Center(
      child: AspectRatio(aspectRatio: 1, child: RepaintBoundary(child: stage)),
    );
  }
}

double alternativePlayerStageTopInset(double safeTop) {
  return math.max(
    alternativePlayerStageDefaultTopInset,
    safeTop + alternativePlayerStageHeaderClearance,
  );
}

class PlayerStyleAtmosphere extends StatelessWidget {
  const PlayerStyleAtmosphere({required this.style, super.key});

  final PlayerVisualStyle style;

  @override
  Widget build(BuildContext context) {
    final colors = switch (style) {
      PlayerVisualStyle.aurora => const [
        Color(0xD90A1029),
        Color(0xCC111B3C),
        Color(0xF2080B18),
      ],
      PlayerVisualStyle.cassette => const [
        Color(0xE80A1027),
        Color(0xD9131740),
        Color(0xF2070918),
      ],
      PlayerVisualStyle.lyricStage => const [
        Color(0xE8121834),
        Color(0xD919183F),
        Color(0xF2070918),
      ],
      PlayerVisualStyle.cover || PlayerVisualStyle.classic => const [
        Color(0x00000000),
        Color(0x00000000),
        Color(0x00000000),
      ],
    };
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: colors,
          ),
        ),
        child: style == PlayerVisualStyle.classic
            ? null
            : Align(
                alignment: const Alignment(.72, -.58),
                child: Container(
                  width: 210,
                  height: 210,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: switch (style) {
                      PlayerVisualStyle.aurora => const Color(0x183E9BFF),
                      PlayerVisualStyle.cassette => const Color(0x1F8B5CF6),
                      PlayerVisualStyle.lyricStage => const Color(0x1F2DD4BF),
                      PlayerVisualStyle.cover ||
                      PlayerVisualStyle.classic => Colors.transparent,
                    },
                    boxShadow: [
                      BoxShadow(
                        color: switch (style) {
                          PlayerVisualStyle.aurora => const Color(0x223E9BFF),
                          PlayerVisualStyle.cassette => const Color(0x2E8B5CF6),
                          PlayerVisualStyle.lyricStage => const Color(
                            0x2E2DD4BF,
                          ),
                          PlayerVisualStyle.cover ||
                          PlayerVisualStyle.classic => Colors.transparent,
                        },
                        blurRadius: 100,
                        spreadRadius: 30,
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}

class AlternativePlayerStage extends StatelessWidget {
  const AlternativePlayerStage({
    required this.style,
    required this.track,
    required this.vinylRotating,
    required this.routeAnimation,
    required this.favorite,
    required this.onToggleFavorite,
    required this.onShowLyrics,
    this.topInset = alternativePlayerStageDefaultTopInset,
    super.key,
  });

  final PlayerVisualStyle style;
  final Track track;
  final bool vinylRotating;
  final Animation<double> routeAnimation;
  final bool favorite;
  final VoidCallback onToggleFavorite;
  final VoidCallback onShowLyrics;
  final double topInset;

  @override
  Widget build(BuildContext context) {
    final entrance = CurvedAnimation(
      parent: routeAnimation,
      curve: const Interval(.08, 1, curve: Curves.easeOutCubic),
    );
    final stage = switch (style) {
      PlayerVisualStyle.aurora => _AuroraStage(
        track: track,
        vinylRotating: vinylRotating,
        favorite: favorite,
        onToggleFavorite: onToggleFavorite,
        onShowLyrics: onShowLyrics,
        topInset: topInset,
      ),
      PlayerVisualStyle.cassette => _CosmicPulseStage(
        track: track,
        playing: vinylRotating,
        favorite: favorite,
        onToggleFavorite: onToggleFavorite,
        onShowLyrics: onShowLyrics,
        topInset: topInset,
      ),
      PlayerVisualStyle.lyricStage => _LiquidSpectrumStage(
        track: track,
        playing: vinylRotating,
        favorite: favorite,
        onToggleFavorite: onToggleFavorite,
        onShowLyrics: onShowLyrics,
        topInset: topInset,
      ),
      PlayerVisualStyle.cover ||
      PlayerVisualStyle.classic => const SizedBox.shrink(),
    };
    return FadeTransition(
      opacity: entrance,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, .035),
          end: Offset.zero,
        ).animate(entrance),
        child: stage,
      ),
    );
  }
}

class PlayerVisualStagePreview extends StatelessWidget {
  const PlayerVisualStagePreview({
    required this.style,
    required this.active,
    required this.coverAsset,
    super.key,
  });

  final PlayerVisualStyle style;
  final bool active;
  final String coverAsset;

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final previewPlaying = active && !reduceMotion;
    final track = Track(
      id: 'player-style-preview-${style.id}',
      title: style.displayName,
      artist: 'Mesting Music',
      album: '播放器样式预览',
      duration: const Duration(minutes: 3, seconds: 48),
      audioAsset: '',
      coverAsset: coverAsset,
      lyricsAsset: '',
    );
    final preview = switch (style) {
      PlayerVisualStyle.aurora => _AuroraRhythmOrbit(
        playing: previewPlaying,
        duration: const Duration(milliseconds: 2400),
        cycleCount: 1,
        child: VinylDisc(
          coverAsset: coverAsset,
          playing: previewPlaying,
          rotationDuration: const Duration(milliseconds: 2400),
          rotationCount: 1,
          labelSizeFactor: .64,
        ),
      ),
      PlayerVisualStyle.cassette => _ReactiveStageMotion(
        playing: previewPlaying,
        duration: const Duration(milliseconds: 1800),
        cycleCount: 1,
        builder: (context, phase, energy, repaint, reduceMotion) {
          return _CosmicPulseSurface(
            track: track,
            phase: phase,
            energy: energy,
            repaint: repaint,
            reduceMotion: reduceMotion,
          );
        },
      ),
      PlayerVisualStyle.lyricStage => _ReactiveStageMotion(
        playing: previewPlaying,
        duration: const Duration(milliseconds: 1700),
        cycleCount: 1,
        builder: (context, phase, energy, repaint, reduceMotion) {
          return _LiquidSpectrumSurface(
            track: track,
            phase: phase,
            energy: energy,
            repaint: repaint,
            reduceMotion: reduceMotion,
          );
        },
      ),
      PlayerVisualStyle.cover || PlayerVisualStyle.classic => VinylDisc(
        coverAsset: coverAsset,
        playing: previewPlaying,
        rotationDuration: const Duration(milliseconds: 2400),
        rotationCount: 1,
      ),
    };
    final background = switch (style) {
      PlayerVisualStyle.cover ||
      PlayerVisualStyle.classic => const [Color(0xFFD8D2D4), Color(0xFFA8A1A4)],
      PlayerVisualStyle.aurora => const [Color(0xFF111D42), Color(0xFF090C1D)],
      PlayerVisualStyle.cassette => const [
        Color(0xFF151133),
        Color(0xFF080B1D),
      ],
      PlayerVisualStyle.lyricStage => const [
        Color(0xFF0D2934),
        Color(0xFF170C2A),
      ],
    };
    return DecoratedBox(
      key: ValueKey('player-style-real-preview-${style.id}'),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: background,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(9),
        child: Center(child: AspectRatio(aspectRatio: 1, child: preview)),
      ),
    );
  }
}

class _AuroraStage extends StatelessWidget {
  const _AuroraStage({
    required this.track,
    required this.vinylRotating,
    required this.favorite,
    required this.onToggleFavorite,
    required this.onShowLyrics,
    required this.topInset,
  });

  final Track track;
  final bool vinylRotating;
  final bool favorite;
  final VoidCallback onToggleFavorite;
  final VoidCallback onShowLyrics;
  final double topInset;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tabletLayout = mestingIsTabletWindow(MediaQuery.sizeOf(context));
        final discSize = math
            .min(
              constraints.maxWidth - 44,
              (constraints.maxHeight - 500).clamp(188.0, 340.0),
            )
            .toDouble();
        return Padding(
          padding: EdgeInsets.fromLTRB(22, topInset, 22, 154),
          child: Column(
            mainAxisAlignment: tabletLayout
                ? MainAxisAlignment.center
                : MainAxisAlignment.start,
            children: [
              const _StageEyebrow(
                icon: Icons.auto_awesome_rounded,
                label: 'AURORA ORBIT',
              ),
              const SizedBox(height: 14),
              Semantics(
                button: true,
                label: '查看歌词',
                child: GestureDetector(
                  key: const ValueKey('aurora-player-disc'),
                  onTap: onShowLyrics,
                  child: SizedBox.square(
                    dimension: discSize,
                    child: _AuroraRhythmOrbit(
                      playing: vinylRotating,
                      child: VinylDisc(
                        coverAsset: track.coverAsset,
                        playing: vinylRotating,
                        labelSizeFactor: .64,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              _TrackIdentity(
                track: track,
                centered: true,
                artistTrailing: _StageFavoriteButton(
                  style: PlayerVisualStyle.aurora,
                  favorite: favorite,
                  onToggleFavorite: onToggleFavorite,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CosmicPulseStage extends StatelessWidget {
  const _CosmicPulseStage({
    required this.track,
    required this.playing,
    required this.favorite,
    required this.onToggleFavorite,
    required this.onShowLyrics,
    required this.topInset,
  });

  final Track track;
  final bool playing;
  final bool favorite;
  final VoidCallback onToggleFavorite;
  final VoidCallback onShowLyrics;
  final double topInset;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tabletLayout = mestingIsTabletWindow(MediaQuery.sizeOf(context));
        final fieldHeight = (constraints.maxHeight - 500).clamp(188.0, 332.0);
        final fieldSize = math
            .min(constraints.maxWidth - 44, fieldHeight)
            .toDouble();
        return Padding(
          padding: EdgeInsets.fromLTRB(22, topInset, 22, 154),
          child: Column(
            mainAxisAlignment: tabletLayout
                ? MainAxisAlignment.center
                : MainAxisAlignment.start,
            children: [
              const _StageEyebrow(
                icon: Icons.blur_circular_rounded,
                label: 'COSMIC PULSE',
              ),
              const SizedBox(height: 14),
              Semantics(
                button: true,
                label: '查看歌词',
                child: GestureDetector(
                  key: const ValueKey('cosmic-pulse-stage'),
                  onTap: onShowLyrics,
                  child: SizedBox.square(
                    dimension: fieldSize,
                    child: _ReactiveStageMotion(
                      playing: playing,
                      duration: const Duration(milliseconds: 7200),
                      builder: (context, phase, energy, repaint, reduceMotion) {
                        return _CosmicPulseSurface(
                          track: track,
                          phase: phase,
                          energy: energy,
                          repaint: repaint,
                          reduceMotion: reduceMotion,
                        );
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              _TrackIdentity(
                track: track,
                centered: true,
                artistTrailing: _StageFavoriteButton(
                  style: PlayerVisualStyle.cassette,
                  favorite: favorite,
                  onToggleFavorite: onToggleFavorite,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LiquidSpectrumStage extends StatelessWidget {
  const _LiquidSpectrumStage({
    required this.track,
    required this.playing,
    required this.favorite,
    required this.onToggleFavorite,
    required this.onShowLyrics,
    required this.topInset,
  });

  final Track track;
  final bool playing;
  final bool favorite;
  final VoidCallback onToggleFavorite;
  final VoidCallback onShowLyrics;
  final double topInset;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tabletLayout = mestingIsTabletWindow(MediaQuery.sizeOf(context));
        final fieldHeight = (constraints.maxHeight - 500).clamp(188.0, 332.0);
        final fieldSize = math
            .min(constraints.maxWidth - 44, fieldHeight)
            .toDouble();
        return Padding(
          padding: EdgeInsets.fromLTRB(22, topInset, 22, 154),
          child: Column(
            mainAxisAlignment: tabletLayout
                ? MainAxisAlignment.center
                : MainAxisAlignment.start,
            children: [
              const _StageEyebrow(
                icon: Icons.water_rounded,
                label: 'LIQUID SPECTRUM',
              ),
              const SizedBox(height: 14),
              Semantics(
                button: true,
                label: '查看歌词',
                child: GestureDetector(
                  key: const ValueKey('liquid-spectrum-stage'),
                  onTap: onShowLyrics,
                  child: SizedBox.square(
                    dimension: fieldSize,
                    child: _ReactiveStageMotion(
                      playing: playing,
                      duration: const Duration(milliseconds: 6800),
                      builder: (context, phase, energy, repaint, reduceMotion) {
                        return _LiquidSpectrumSurface(
                          track: track,
                          phase: phase,
                          energy: energy,
                          repaint: repaint,
                          reduceMotion: reduceMotion,
                        );
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              _TrackIdentity(
                track: track,
                centered: true,
                artistTrailing: _StageFavoriteButton(
                  style: PlayerVisualStyle.lyricStage,
                  favorite: favorite,
                  onToggleFavorite: onToggleFavorite,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TrackIdentity extends StatelessWidget {
  const _TrackIdentity({
    required this.track,
    required this.centered,
    this.artistTrailing,
  });

  final Track track;
  final bool centered;
  final Widget? artistTrailing;

  @override
  Widget build(BuildContext context) {
    final alignment = centered
        ? CrossAxisAlignment.center
        : CrossAxisAlignment.start;
    return Column(
      crossAxisAlignment: alignment,
      children: [
        if (artistTrailing == null)
          Column(
            crossAxisAlignment: alignment,
            children: [
              _TrackTitle(track: track, centered: centered),
              const SizedBox(height: 8),
              _TrackArtist(track: track, centered: centered),
            ],
          )
        else
          SizedBox(
            key: const ValueKey('alternative-player-artist-actions'),
            width: double.infinity,
            height: 62,
            child: Stack(
              children: [
                Positioned.fill(
                  left: 50,
                  right: 50,
                  child: Column(
                    crossAxisAlignment: alignment,
                    children: [
                      _TrackTitle(track: track, centered: centered),
                      const SizedBox(height: 8),
                      _TrackArtist(track: track, centered: centered),
                    ],
                  ),
                ),
                Positioned(top: 0, right: 0, child: artistTrailing!),
              ],
            ),
          ),
      ],
    );
  }
}

class _TrackTitle extends StatelessWidget {
  const _TrackTitle({required this.track, required this.centered});

  final Track track;
  final bool centered;

  @override
  Widget build(BuildContext context) {
    return Text(
      track.title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: centered ? TextAlign.center : TextAlign.start,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 25,
        height: 1.1,
        fontWeight: FontWeight.w900,
        letterSpacing: -.5,
      ),
    );
  }
}

class _TrackArtist extends StatelessWidget {
  const _TrackArtist({required this.track, required this.centered});

  final Track track;
  final bool centered;

  @override
  Widget build(BuildContext context) {
    return Text(
      track.artist,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: centered ? TextAlign.center : TextAlign.start,
      style: TextStyle(
        color: Colors.white.withValues(alpha: .68),
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _StageEyebrow extends StatelessWidget {
  const _StageEyebrow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white70, size: 15),
        const SizedBox(width: 7),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xBFFFFFFF),
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 2,
          ),
        ),
      ],
    );
  }
}

class _StageFavoriteButton extends StatelessWidget {
  const _StageFavoriteButton({
    required this.style,
    required this.favorite,
    required this.onToggleFavorite,
  });

  final PlayerVisualStyle style;
  final bool favorite;
  final VoidCallback onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: favorite,
      label: favorite ? '已收藏' : '收藏歌曲',
      child: Tooltip(
        message: favorite ? '取消收藏' : '收藏歌曲',
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onToggleFavorite,
            customBorder: const CircleBorder(),
            child: AnimatedContainer(
              key: ValueKey('alternative-player-favorite-${style.id}'),
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: MestingPalette.favorite.withValues(
                  alpha: favorite ? .20 : .10,
                ),
                border: Border.all(
                  color: MestingPalette.favorite.withValues(
                    alpha: favorite ? .58 : .34,
                  ),
                ),
                boxShadow: favorite
                    ? [
                        BoxShadow(
                          color: MestingPalette.favorite.withValues(alpha: .18),
                          blurRadius: 12,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                switchInCurve: Curves.easeOutBack,
                switchOutCurve: Curves.easeInCubic,
                child: Icon(
                  favorite
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  key: ValueKey(favorite),
                  color: MestingPalette.favorite,
                  size: 22,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

typedef _ReactiveStageBuilder =
    Widget Function(
      BuildContext context,
      Animation<double> phase,
      Animation<double> energy,
      Listenable repaint,
      bool reduceMotion,
    );

@visibleForTesting
double reactiveStageRhythm(double progress) {
  final normalized = progress % 1;
  final bass = (math.sin((normalized * 7 - .08) * math.pi * 2) + 1) / 2;
  final texture = (math.sin((normalized * 14 + .24) * math.pi * 2) + 1) / 2;
  return (math.pow(bass, 4) * .72 + texture * .2 + .08).clamp(0, 1).toDouble();
}

@visibleForTesting
double reactiveStageCoreScale({
  required double progress,
  required double energy,
  required bool reduceMotion,
  bool liquid = false,
}) {
  if (reduceMotion) return 1;
  final activeEnergy = energy.clamp(0, 1);
  final range = liquid ? .012 : .018;
  return 1 + activeEnergy * (.003 + reactiveStageRhythm(progress) * range);
}

class _ReactiveStageMotion extends StatefulWidget {
  const _ReactiveStageMotion({
    required this.playing,
    required this.duration,
    required this.builder,
    this.cycleCount,
  });

  final bool playing;
  final Duration duration;
  final _ReactiveStageBuilder builder;
  final int? cycleCount;

  @override
  State<_ReactiveStageMotion> createState() => _ReactiveStageMotionState();
}

class _ReactiveStageMotionState extends State<_ReactiveStageMotion>
    with TickerProviderStateMixin {
  late final AnimationController _phaseController;
  late final AnimationController _energyController;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _phaseController = AnimationController(
      vsync: this,
      duration: widget.duration,
      value: .11,
    );
    _energyController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 460),
      reverseDuration: const Duration(milliseconds: 820),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    _syncAnimations();
  }

  @override
  void didUpdateWidget(covariant _ReactiveStageMotion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.duration != widget.duration) {
      _phaseController.duration = widget.duration;
    }
    if (oldWidget.playing != widget.playing ||
        oldWidget.cycleCount != widget.cycleCount) {
      _syncAnimations();
    }
  }

  void _syncAnimations() {
    if (_reduceMotion) {
      _phaseController
        ..stop()
        ..value = .11;
      _energyController
        ..stop()
        ..value = 0;
      return;
    }
    if (widget.playing) {
      if (!_phaseController.isAnimating) {
        _phaseController.repeat(count: widget.cycleCount);
      }
      _energyController.forward();
      return;
    }
    _energyController.reverse().whenComplete(() {
      if (!mounted ||
          widget.playing ||
          _reduceMotion ||
          !_energyController.isDismissed) {
        return;
      }
      _phaseController.stop();
    });
  }

  @override
  void dispose() {
    _phaseController.dispose();
    _energyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repaint = Listenable.merge([_phaseController, _energyController]);
    return widget.builder(
      context,
      _phaseController,
      _energyController,
      repaint,
      _reduceMotion,
    );
  }
}

class _CosmicPulseSurface extends StatelessWidget {
  const _CosmicPulseSurface({
    required this.track,
    required this.phase,
    required this.energy,
    required this.repaint,
    required this.reduceMotion,
  });

  final Track track;
  final Animation<double> phase;
  final Animation<double> energy;
  final Listenable repaint;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: const ValueKey('cosmic-pulse-repaint-boundary'),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final coreSize =
              math.min(constraints.maxWidth, constraints.maxHeight) * .48;
          return Container(
            key: const ValueKey('cosmic-pulse-visible-shape'),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0x558B5CF6)),
              gradient: const RadialGradient(
                center: Alignment(-.18, -.22),
                radius: .9,
                colors: [
                  Color(0xF021174E),
                  Color(0xF00B1635),
                  Color(0xF2070A1A),
                ],
                stops: [0, .58, 1],
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x553B1FA5),
                  blurRadius: 34,
                  offset: Offset(0, 16),
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      key: const ValueKey('cosmic-pulse-painter'),
                      painter: _CosmicPulsePainter(
                        phase: phase,
                        energy: energy,
                        reduceMotion: reduceMotion,
                        repaint: repaint,
                      ),
                    ),
                  ),
                ),
                AnimatedBuilder(
                  animation: repaint,
                  child: Container(
                    width: coreSize,
                    height: coreSize,
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF9B8AFB), Color(0xFF4CC9F0)],
                      ),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: .58),
                        width: 1.2,
                      ),
                      boxShadow: const [
                        BoxShadow(color: Color(0x888B5CF6), blurRadius: 30),
                      ],
                    ),
                    child: ClipOval(
                      child: ArtworkImage(
                        uri: track.coverAsset,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  builder: (context, child) {
                    final activeEnergy = Curves.easeOutCubic.transform(
                      energy.value,
                    );
                    return Transform.scale(
                      key: const ValueKey('cosmic-pulse-core-scale'),
                      scale: reactiveStageCoreScale(
                        progress: phase.value,
                        energy: activeEnergy,
                        reduceMotion: reduceMotion,
                      ),
                      child: child,
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _LiquidSpectrumSurface extends StatelessWidget {
  const _LiquidSpectrumSurface({
    required this.track,
    required this.phase,
    required this.energy,
    required this.repaint,
    required this.reduceMotion,
  });

  final Track track;
  final Animation<double> phase;
  final Animation<double> energy;
  final Listenable repaint;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: const ValueKey('liquid-spectrum-repaint-boundary'),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final coreSize =
              math.min(constraints.maxWidth, constraints.maxHeight) * .43;
          return Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    key: const ValueKey('liquid-spectrum-painter'),
                    painter: _LiquidSpectrumPainter(
                      phase: phase,
                      energy: energy,
                      reduceMotion: reduceMotion,
                      repaint: repaint,
                    ),
                  ),
                ),
              ),
              AnimatedBuilder(
                animation: repaint,
                child: Container(
                  key: const ValueKey('liquid-spectrum-visible-shape'),
                  width: coreSize,
                  height: coreSize,
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const SweepGradient(
                      colors: [
                        Color(0xFF5EEAD4),
                        Color(0xFF60A5FA),
                        Color(0xFF8B5CF6),
                        Color(0xFFC084FC),
                        Color(0xFF5EEAD4),
                      ],
                    ),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: .5),
                    ),
                    boxShadow: const [
                      BoxShadow(color: Color(0x6634D399), blurRadius: 28),
                      BoxShadow(color: Color(0x668B5CF6), blurRadius: 38),
                    ],
                  ),
                  child: ClipOval(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ArtworkImage(uri: track.coverAsset, fit: BoxFit.cover),
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Color(0x00131A36), Color(0x55131A36)],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                builder: (context, child) {
                  final activeEnergy = Curves.easeOutCubic.transform(
                    energy.value,
                  );
                  final floatY = reduceMotion
                      ? 0.0
                      : math.sin(phase.value * math.pi * 2) *
                            activeEnergy *
                            3.5;
                  return Transform.translate(
                    offset: Offset(0, floatY),
                    child: Transform.scale(
                      key: const ValueKey('liquid-spectrum-core-scale'),
                      scale: reactiveStageCoreScale(
                        progress: phase.value,
                        energy: activeEnergy,
                        reduceMotion: reduceMotion,
                        liquid: true,
                      ),
                      child: child,
                    ),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CosmicPulsePainter extends CustomPainter {
  _CosmicPulsePainter({
    required this.phase,
    required this.energy,
    required this.reduceMotion,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final Animation<double> phase;
  final Animation<double> energy;
  final bool reduceMotion;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final progress = reduceMotion ? .11 : phase.value;
    final activeEnergy = reduceMotion
        ? 0.0
        : Curves.easeOutCubic.transform(energy.value);
    final rhythm = reactiveStageRhythm(progress) * activeEnergy;
    final radius = math.min(size.width, size.height) * .43;

    final aura = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF8B5CF6).withValues(alpha: .18 + activeEnergy * .14),
          const Color(0x004CC9F0),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, aura);

    for (var index = 0; index < 3; index += 1) {
      final cycle = (progress * 3 + index / 3) % 1;
      final pulseRadius = radius * (.48 + cycle * .66);
      final opacity = (.25 * (1 - cycle) * activeEnergy) + .055;
      canvas.drawCircle(
        center,
        pulseRadius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1 + rhythm
          ..color = const Color(0xFFA78BFA).withValues(alpha: opacity),
      );
    }

    for (var index = 0; index < 34; index += 1) {
      final angle = index / 34 * math.pi * 2;
      final wave = (math.sin(index * .82 + progress * math.pi * 14) + 1) / 2;
      final length = 2.5 + activeEnergy * (4 + wave * 9 + rhythm * 4);
      final innerRadius = radius * .76;
      final paint = Paint()
        ..strokeCap = StrokeCap.round
        ..strokeWidth = index.isEven ? 1.2 : .8
        ..color = Color.lerp(
          const Color(0xFF8B5CF6),
          const Color(0xFF67E8F9),
          index / 34,
        )!.withValues(alpha: .18 + activeEnergy * (.18 + wave * .34));
      canvas.drawLine(
        Offset(
          center.dx + math.cos(angle) * innerRadius,
          center.dy + math.sin(angle) * innerRadius,
        ),
        Offset(
          center.dx + math.cos(angle) * (innerRadius + length),
          center.dy + math.sin(angle) * (innerRadius + length),
        ),
        paint,
      );
    }

    final orbitPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = const Color(
        0xFF67E8F9,
      ).withValues(alpha: .3 + activeEnergy * .28);
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(progress * math.pi * 2);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset.zero,
        width: radius * 2.15,
        height: radius * 1.18,
      ),
      orbitPaint,
    );
    for (var index = 0; index < 4; index += 1) {
      final angle = index / 4 * math.pi * 2;
      final node = Offset(
        math.cos(angle) * radius * 1.075,
        math.sin(angle) * radius * .59,
      );
      canvas.drawCircle(
        node,
        2.2 + rhythm * 1.8,
        Paint()
          ..color = index.isEven
              ? const Color(0xFFD8B4FE)
              : const Color(0xFFA5F3FC),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CosmicPulsePainter oldDelegate) {
    return oldDelegate.phase != phase ||
        oldDelegate.energy != energy ||
        oldDelegate.reduceMotion != reduceMotion;
  }
}

class _LiquidSpectrumPainter extends CustomPainter {
  _LiquidSpectrumPainter({
    required this.phase,
    required this.energy,
    required this.reduceMotion,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final Animation<double> phase;
  final Animation<double> energy;
  final bool reduceMotion;

  @override
  void paint(Canvas canvas, Size size) {
    final progress = reduceMotion ? .11 : phase.value;
    final activeEnergy = reduceMotion
        ? 0.0
        : Curves.easeOutCubic.transform(energy.value);
    final rhythm = reactiveStageRhythm(progress) * activeEnergy;
    final rect = Offset.zero & size;
    final center = size.center(Offset.zero);
    final blobRadius = size.shortestSide * (.43 + rhythm * .018);
    final blob = Path();
    const points = 48;
    for (var index = 0; index <= points; index += 1) {
      final angle = index / points * math.pi * 2;
      final currentRadius =
          blobRadius *
          (1 +
              math.sin(angle * 3 + progress * math.pi * 2) *
                  (.045 + activeEnergy * .025) +
              math.cos(angle * 5 - progress * math.pi * 3) *
                  (.026 + activeEnergy * .018));
      final point = Offset(
        center.dx + math.cos(angle) * currentRadius,
        center.dy + math.sin(angle) * currentRadius,
      );
      if (index == 0) {
        blob.moveTo(point.dx, point.dy);
      } else {
        blob.lineTo(point.dx, point.dy);
      }
    }
    blob.close();
    canvas.drawPath(
      blob,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-.22, -.28),
          radius: .92,
          colors: [Color(0xC62C817F), Color(0xCA24336D), Color(0xD31A102F)],
          stops: [0, .56, 1],
        ).createShader(rect)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2),
    );
    canvas.drawPath(
      blob,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2 + rhythm
        ..shader = const SweepGradient(
          colors: [
            Color(0x805EEAD4),
            Color(0x8060A5FA),
            Color(0x809E70FF),
            Color(0x805EEAD4),
          ],
        ).createShader(rect),
    );

    canvas.drawCircle(
      Offset(size.width * (.2 + progress * .55), size.height * .3),
      size.shortestSide * (.28 + rhythm * .025),
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0x4434D399), Color(0x0034D399)],
        ).createShader(rect),
    );
    canvas.drawCircle(
      Offset(size.width * (.78 - progress * .42), size.height * .62),
      size.shortestSide * (.32 + rhythm * .02),
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0x408B5CF6), Color(0x008B5CF6)],
        ).createShader(rect),
    );

    for (var band = 0; band < 3; band += 1) {
      final path = Path();
      final baseY = size.height * (.26 + band * .22);
      final amplitude = 5 + activeEnergy * (8 + band * 3 + rhythm * 5);
      for (var step = 0; step <= 32; step += 1) {
        final x = size.width * step / 32;
        final y =
            baseY +
            math.sin(
                  step * .42 + progress * math.pi * (4 + band) + band * 1.4,
                ) *
                amplitude;
        if (step == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      final color = switch (band) {
        0 => const Color(0xFF5EEAD4),
        1 => const Color(0xFF60A5FA),
        _ => const Color(0xFFC084FC),
      };
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 8 + band * 2
          ..color = color.withValues(alpha: .035 + activeEnergy * .045)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
      );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = .8 + rhythm * .7
          ..color = color.withValues(alpha: .22 + activeEnergy * .32),
      );
    }

    const barCount = 22;
    final barWidth = (size.width - 60) / barCount;
    for (var index = 0; index < barCount; index += 1) {
      final wave = (math.sin(index * .73 + progress * math.pi * 16) + 1) / 2;
      final height = 3 + activeEnergy * (4 + wave * 14 + rhythm * 3);
      final x = 30 + index * barWidth;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            x,
            size.height - 23 - height,
            math.max(1.5, barWidth * .38),
            height,
          ),
          const Radius.circular(99),
        ),
        Paint()
          ..color = Color.lerp(
            const Color(0xFF5EEAD4),
            const Color(0xFFC084FC),
            index / barCount,
          )!.withValues(alpha: .26 + activeEnergy * .48),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LiquidSpectrumPainter oldDelegate) {
    return oldDelegate.phase != phase ||
        oldDelegate.energy != energy ||
        oldDelegate.reduceMotion != reduceMotion;
  }
}

@visibleForTesting
double auroraOrbitRhythm(double progress) {
  final normalized = progress % 1;
  final primary = (math.sin((normalized * 8 - .08) * math.pi * 2) + 1) / 2;
  final secondary = (math.sin((normalized * 16 + .18) * math.pi * 2) + 1) / 2;
  final kick = math.pow(primary, 5).toDouble();
  return (kick * .74 + secondary * .18 + .08).clamp(0, 1).toDouble();
}

@visibleForTesting
double auroraOrbitDiscScale({
  required double progress,
  required double energy,
  required bool reduceMotion,
}) {
  if (reduceMotion) return 1;
  final safeEnergy = energy.clamp(0, 1);
  return 1 + safeEnergy * (.004 + auroraOrbitRhythm(progress) * .011);
}

class _AuroraRhythmOrbit extends StatefulWidget {
  const _AuroraRhythmOrbit({
    required this.playing,
    required this.child,
    this.duration = const Duration(milliseconds: 6400),
    this.cycleCount,
  });

  final bool playing;
  final Widget child;
  final Duration duration;
  final int? cycleCount;

  @override
  State<_AuroraRhythmOrbit> createState() => _AuroraRhythmOrbitState();
}

class _AuroraRhythmOrbitState extends State<_AuroraRhythmOrbit>
    with TickerProviderStateMixin {
  late final AnimationController _phaseController;
  late final AnimationController _energyController;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _phaseController = AnimationController(
      vsync: this,
      duration: widget.duration,
      value: .08,
    );
    _energyController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
      reverseDuration: const Duration(milliseconds: 760),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (_reduceMotion != reduceMotion) {
      _reduceMotion = reduceMotion;
    }
    _syncAnimations();
  }

  @override
  void didUpdateWidget(covariant _AuroraRhythmOrbit oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.duration != widget.duration) {
      _phaseController.duration = widget.duration;
    }
    if (oldWidget.playing != widget.playing ||
        oldWidget.cycleCount != widget.cycleCount) {
      _syncAnimations();
    }
  }

  void _syncAnimations() {
    if (_reduceMotion) {
      _phaseController
        ..stop()
        ..value = .08;
      _energyController
        ..stop()
        ..value = 0;
      return;
    }

    if (widget.playing) {
      if (!_phaseController.isAnimating) {
        _phaseController.repeat(count: widget.cycleCount);
      }
      _energyController.forward();
      return;
    }

    _energyController.reverse().whenComplete(() {
      if (!mounted ||
          widget.playing ||
          _reduceMotion ||
          !_energyController.isDismissed) {
        return;
      }
      _phaseController.stop();
    });
  }

  @override
  void dispose() {
    _phaseController.dispose();
    _energyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final orbitAnimation = Listenable.merge([
      _phaseController,
      _energyController,
    ]);
    return RepaintBoundary(
      key: const ValueKey('aurora-orbit-repaint-boundary'),
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.fromBorderSide(
                  BorderSide(color: Color(0x6673E0FF), width: 1.2),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x4D3B82F6),
                    blurRadius: 28,
                    spreadRadius: 2,
                  ),
                  BoxShadow(
                    color: Color(0x383B1FA5),
                    blurRadius: 48,
                    spreadRadius: 5,
                  ),
                ],
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                key: const ValueKey('aurora-rhythm-painter'),
                painter: _AuroraOrbitPainter(
                  phase: _phaseController,
                  energy: _energyController,
                  reduceMotion: _reduceMotion,
                  repaint: orbitAnimation,
                ),
              ),
            ),
          ),
          AnimatedBuilder(
            animation: orbitAnimation,
            child: Padding(
              padding: const EdgeInsets.all(21),
              child: widget.child,
            ),
            builder: (context, child) {
              return Transform.scale(
                key: const ValueKey('aurora-disc-rhythm-scale'),
                scale: auroraOrbitDiscScale(
                  progress: _phaseController.value,
                  energy: Curves.easeOutCubic.transform(
                    _energyController.value,
                  ),
                  reduceMotion: _reduceMotion,
                ),
                child: child,
              );
            },
          ),
        ],
      ),
    );
  }
}

class _AuroraOrbitPainter extends CustomPainter {
  _AuroraOrbitPainter({
    required this.phase,
    required this.energy,
    required this.reduceMotion,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final Animation<double> phase;
  final Animation<double> energy;
  final bool reduceMotion;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final shortestSide = size.shortestSide;
    final baseRadius = shortestSide / 2;
    final progress = reduceMotion ? .08 : phase.value;
    final activeEnergy = reduceMotion
        ? 0.0
        : Curves.easeOutCubic.transform(energy.value);
    final rhythm = auroraOrbitRhythm(progress) * activeEnergy;

    final haloRect = Rect.fromCircle(
      center: center,
      radius: baseRadius * (.91 + rhythm * .018),
    );
    final halo = Paint()
      ..shader = RadialGradient(
        stops: const [.58, .78, 1],
        colors: [
          const Color(0x003B82F6),
          const Color(0x303B82F6).withValues(alpha: .10 + activeEnergy * .12),
          const Color(0x0073E0FF),
        ],
      ).createShader(haloRect);
    canvas.drawCircle(center, haloRect.width / 2, halo);

    final baseRing = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = const Color(
        0xFF73E0FF,
      ).withValues(alpha: .34 + activeEnergy * .18);
    canvas.drawCircle(center, baseRadius - 5.5, baseRing);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(progress * math.pi * 2 - .42);
    canvas.translate(-center.dx, -center.dy);

    final primaryOrbit = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.8 + rhythm * 1.2
      ..shader = SweepGradient(
        colors: [
          const Color(0x0073E0FF),
          const Color(0xFF73E0FF).withValues(alpha: .78 + activeEnergy * .22),
          const Color(0xFF9E70FF).withValues(alpha: .66 + activeEnergy * .28),
          const Color(0x0073E0FF),
        ],
        stops: const [0, .28, .63, 1],
      ).createShader(Offset.zero & size);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: baseRadius - 5),
      -.28,
      4.85,
      false,
      primaryOrbit,
    );
    canvas.restore();

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-progress * math.pi * 1.35 + .72);
    canvas.translate(-center.dx, -center.dy);
    final secondaryOrbit = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1 + rhythm * .7
      ..shader = SweepGradient(
        colors: [
          const Color(0x0067E8F9),
          const Color(0xFF67E8F9).withValues(alpha: .26 + activeEnergy * .42),
          const Color(0x009E70FF),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: baseRadius - 12),
      .4,
      3.35,
      false,
      secondaryOrbit,
    );
    canvas.restore();

    _paintSpectrumTicks(
      canvas,
      center: center,
      radius: baseRadius - 17,
      progress: progress,
      energy: activeEnergy,
      rhythm: rhythm,
    );
    _paintOrbitParticles(
      canvas,
      center: center,
      radius: baseRadius - 6,
      progress: progress,
      energy: activeEnergy,
      rhythm: rhythm,
    );
  }

  void _paintSpectrumTicks(
    Canvas canvas, {
    required Offset center,
    required double radius,
    required double progress,
    required double energy,
    required double rhythm,
  }) {
    const tickCount = 40;
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1;
    for (var index = 0; index < tickCount; index += 1) {
      final angle = index / tickCount * math.pi * 2 - math.pi / 2;
      final wave = (math.sin(index * 1.73 + progress * math.pi * 16) + 1) / 2;
      final cluster = math.pow(wave, 2).toDouble();
      final length = 1.6 + energy * (1.4 + cluster * 4 + rhythm * 2.4);
      final inner = Offset(
        center.dx + math.cos(angle) * (radius - length),
        center.dy + math.sin(angle) * (radius - length),
      );
      final outer = Offset(
        center.dx + math.cos(angle) * radius,
        center.dy + math.sin(angle) * radius,
      );
      paint.color = Color.lerp(
        const Color(0xFF73E0FF),
        const Color(0xFF9E70FF),
        index / tickCount,
      )!.withValues(alpha: .12 + energy * (.18 + cluster * .34));
      canvas.drawLine(inner, outer, paint);
    }
  }

  void _paintOrbitParticles(
    Canvas canvas, {
    required Offset center,
    required double radius,
    required double progress,
    required double energy,
    required double rhythm,
  }) {
    const speeds = [1.0, -.68, 1.42];
    const offsets = [-.12, 2.34, 4.55];
    const radii = [1.0, .91, .965];
    for (var index = 0; index < speeds.length; index += 1) {
      final angle = progress * math.pi * 2 * speeds[index] + offsets[index];
      final particleCenter = Offset(
        center.dx + math.cos(angle) * radius * radii[index],
        center.dy + math.sin(angle) * radius * radii[index],
      );
      final particleRadius = 1.8 + index * .55 + energy * (1.2 + rhythm * 1.8);
      final color = index == 1
          ? const Color(0xFFB69CFF)
          : const Color(0xFFD9F7FF);
      canvas.drawCircle(
        particleCenter,
        particleRadius * 2.2,
        Paint()
          ..color = color.withValues(alpha: .08 + energy * .12)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
      canvas.drawCircle(
        particleCenter,
        particleRadius,
        Paint()..color = color.withValues(alpha: .72 + energy * .28),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AuroraOrbitPainter oldDelegate) {
    return oldDelegate.phase != phase ||
        oldDelegate.energy != energy ||
        oldDelegate.reduceMotion != reduceMotion;
  }
}
