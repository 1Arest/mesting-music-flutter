import 'dart:async';
import 'dart:math' as math;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../shared/widgets/mesting_loading_indicator.dart';
import 'custom_background_controller.dart';
import 'music_theme_preset.dart';
import 'theme_controller.dart';

/// Configures a decorative video so it can never compete with music audio.
@visibleForTesting
Future<void> configureMutedThemeBackgroundVideo({
  required Future<void> Function(bool looping) setLooping,
  required Future<void> Function(double volume) setVolume,
  required Future<void> Function() play,
  required bool foreground,
}) async {
  await setLooping(true);
  await setVolume(0);
  if (foreground) await play();
}

class MusicThemeBackground extends ConsumerStatefulWidget {
  const MusicThemeBackground({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<MusicThemeBackground> createState() =>
      _MusicThemeBackgroundState();
}

class _MusicThemeBackgroundState extends ConsumerState<MusicThemeBackground>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _motionController;
  late MusicThemePreset _displayedPreset;
  bool _foreground = true;
  String? _preparingPresetId;
  int _preparationEpoch = 0;
  VideoPlayerController? _videoController;
  String? _configuredVideoPath;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _motionController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    )..repeat();
    _displayedPreset = ref.read(effectiveMusicThemeProvider);
    ref.listenManual(customBackgroundProvider, (previous, next) {
      _configureVideo(next);
    }, fireImmediately: true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      unawaited(_resumeMutedVideo());
    } else {
      unawaited(_pauseVideo());
    }
    _syncTicker();
  }

  Future<void> _resumeMutedVideo() async {
    final controller = _videoController;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      // Background videos never join the music audio session, including after
      // the app returns from the background.
      await controller.setVolume(0);
      if (_foreground && identical(controller, _videoController)) {
        await controller.play();
      }
    } on Object {
      // The selected file can be replaced while a lifecycle callback is busy.
    }
  }

  Future<void> _pauseVideo() async {
    final controller = _videoController;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      await controller.pause();
    } on Object {
      // A disposed controller no longer needs lifecycle handling.
    }
  }

  void _syncTicker() {
    if (!mounted) return;
    final preset = _displayedPreset;
    final mode = ref.read(themePerformanceProvider);
    final disabled = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final shouldAnimate =
        _foreground &&
        preset.isMotion &&
        mode != ThemePerformanceMode.reduced &&
        !disabled;
    if (shouldAnimate && !_motionController.isAnimating) {
      _motionController.repeat();
    } else if (!shouldAnimate && _motionController.isAnimating) {
      _motionController.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _motionController.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final requestedPreset = ref.watch(effectiveMusicThemeProvider);
    final preset = _displayedPreset;
    final pureClassic = preset.ip == MusicThemeIp.classic;
    final customBackground = ref.watch(customBackgroundProvider);
    final hasCustomBackground = customBackground.active;
    final mode = ref.watch(themePerformanceProvider);
    final visualSettings = ref.watch(themeVisualSettingsProvider);
    final media = MediaQuery.of(context);
    if (requestedPreset.id != preset.id &&
        _preparingPresetId != requestedPreset.id) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _preparePreset(requestedPreset, media.size.width < 600),
      );
    }
    final automaticReduction =
        mode == ThemePerformanceMode.automatic &&
        (media.size.shortestSide < 360 || media.devicePixelRatio > 3.5);
    final animate =
        _foreground &&
        preset.isMotion &&
        mode != ThemePerformanceMode.reduced &&
        !automaticReduction &&
        !media.disableAnimations;
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncTicker());

    return RepaintBoundary(
      child: DecoratedBox(
        decoration: pureClassic
            ? BoxDecoration(color: preset.colors.first)
            : BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: preset.colors,
                ),
              ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // A user-selected image or video is an explicit app-wide override,
            // including the classic light, dark and system appearances.
            if (hasCustomBackground)
              _buildCustomBackground(
                customBackground,
                cacheWidth: (media.size.width * media.devicePixelRatio)
                    .ceil()
                    .clamp(1, 2160),
              )
            else if (!pureClassic)
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 650),
                child: _ArtworkLayer(
                  key: ValueKey(preset.id),
                  preset: preset,
                  animation: _motionController,
                  animate: animate,
                  strength: visualSettings.backgroundStrength,
                ),
              ),
            if (!hasCustomBackground &&
                !pureClassic &&
                animate &&
                visualSettings.showIpDecoration)
              IgnorePointer(
                child: RepaintBoundary(
                  child: AnimatedBuilder(
                    animation: _motionController,
                    builder: (context, child) => CustomPaint(
                      painter: _AtmospherePainter(
                        progress: _motionController.value,
                        motion: preset.motion,
                        accent: preset.accent,
                      ),
                    ),
                  ),
                ),
              ),
            if (!hasCustomBackground && !pureClassic)
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: preset.dark
                        ? [
                            Colors.black.withValues(alpha: 0.08),
                            Colors.black.withValues(alpha: 0.34),
                          ]
                        : [
                            Colors.white.withValues(alpha: 0.07),
                            const Color(0xFFF9F5F0).withValues(alpha: 0.24),
                          ],
                  ),
                ),
              ),
            widget.child,
          ],
        ),
      ),
    );
  }

  Future<void> _preparePreset(MusicThemePreset preset, bool compact) async {
    if (!mounted || _preparingPresetId == preset.id) return;
    _preparingPresetId = preset.id;
    final epoch = ++_preparationEpoch;
    final asset = compact && preset.mobileBackgroundAsset != null
        ? preset.mobileBackgroundAsset
        : preset.backgroundAsset;
    if (asset != null) {
      try {
        await precacheImage(AssetImage(asset), context);
      } on Object {
        // The gradient remains visible if an optional theme asset cannot load.
      }
    }
    if (!mounted || epoch != _preparationEpoch) return;
    if (ref.read(effectiveMusicThemeProvider).id != preset.id) {
      _preparingPresetId = null;
      return;
    }
    setState(() {
      _displayedPreset = preset;
      _preparingPresetId = null;
    });
    _syncTicker();
  }

  Widget _buildCustomBackground(
    CustomBackgroundState custom, {
    required int cacheWidth,
  }) {
    if (!custom.isVideo) {
      return Image.file(
        File(custom.path!),
        fit: BoxFit.cover,
        cacheWidth: cacheWidth,
        filterQuality: FilterQuality.medium,
      );
    }
    final controller = _videoController;
    if (controller == null || !controller.value.isInitialized) {
      return const Center(
        child: MestingLoadingIndicator(
          key: ValueKey('theme-video-loading-animation'),
          size: 52,
          semanticLabel: '正在加载主题背景',
        ),
      );
    }
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: controller.value.size.width,
          height: controller.value.size.height,
          child: VideoPlayer(controller),
        ),
      ),
    );
  }

  Future<void> _configureVideo(CustomBackgroundState custom) async {
    final nextPath = custom.isVideo ? custom.path : null;
    if (_configuredVideoPath == nextPath) return;
    _configuredVideoPath = nextPath;
    final previous = _videoController;
    _videoController = null;
    await previous?.dispose();
    if (nextPath == null) {
      if (mounted) setState(() {});
      return;
    }
    final controller = VideoPlayerController.file(File(nextPath));
    _videoController = controller;
    try {
      await controller.initialize();
      await configureMutedThemeBackgroundVideo(
        setLooping: controller.setLooping,
        setVolume: controller.setVolume,
        play: controller.play,
        foreground: _foreground,
      );
    } catch (_) {
      await controller.dispose();
      if (_videoController == controller) _videoController = null;
    }
    if (mounted) setState(() {});
  }
}

class _ArtworkLayer extends StatelessWidget {
  const _ArtworkLayer({
    required this.preset,
    required this.animation,
    required this.animate,
    required this.strength,
    super.key,
  });

  final MusicThemePreset preset;
  final Animation<double> animation;
  final bool animate;
  final double strength;

  @override
  Widget build(BuildContext context) {
    if (preset.backgroundAsset == null) return const SizedBox.expand();
    final compact = MediaQuery.sizeOf(context).width < 600;
    final asset = compact && preset.mobileBackgroundAsset != null
        ? preset.mobileBackgroundAsset!
        : preset.backgroundAsset!;
    final opacity = (strength + (preset.dark ? .10 : 0)).clamp(.18, .92);
    final image = compact
        ? _MobileArtworkComposition(
            preset: preset,
            asset: asset,
            opacity: opacity,
          )
        : _SmoothThemeImage(
            asset: asset,
            fit: BoxFit.cover,
            alignment: preset.alignment,
            filterQuality: FilterQuality.medium,
            opacity: opacity,
          );
    if (!animate) return image;
    return AnimatedBuilder(
      animation: animation,
      child: image,
      builder: (context, child) {
        final wave = math.sin(animation.value * math.pi * 2);
        final scale = preset.motion == ThemeMotion.carousel
            ? 1.05 + wave.abs() * 0.012
            : 1.06;
        return Transform.translate(
          offset: Offset(wave * 8, math.cos(animation.value * math.pi * 2) * 4),
          child: Transform.scale(scale: scale, child: child),
        );
      },
    );
  }
}

class _MobileArtworkComposition extends StatelessWidget {
  const _MobileArtworkComposition({
    required this.preset,
    required this.asset,
    required this.opacity,
  });

  final MusicThemePreset preset;
  final String asset;
  final double opacity;

  bool get _characterComposition => const {
    'hello-kitty-garden',
    'hello-kitty-dream',
    'kuromi-neon',
    'kuromi-night-flight',
  }.contains(preset.id);

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    if (preset.id == 'hello-kitty-candy-carousel') {
      return _SmoothThemeImage(
        asset: asset,
        fit: BoxFit.cover,
        alignment: Alignment.center,
        opacity: opacity,
      );
    }
    final character = _characterComposition;
    if (!character) {
      return _MobileLandscapeArtwork(
        preset: preset,
        asset: asset,
        opacity: opacity,
      );
    }
    final subjectWidth = size.width * (character ? .90 : 1.42);
    final subjectHeight = size.height * (character ? .55 : .52);
    final subjectX = switch (preset.id) {
      'hello-kitty-garden' => .72,
      'hello-kitty-dream' => .30,
      'kuromi-neon' => .27,
      'kuromi-night-flight' => .69,
      _ => .50,
    };
    return Stack(
      fit: StackFit.expand,
      children: [
        _SmoothThemeImage(
          asset: asset,
          fit: BoxFit.cover,
          alignment: preset.alignment,
          filterQuality: FilterQuality.low,
          opacity: opacity * .78,
        ),
        Positioned(
          left: size.width * subjectX - subjectWidth / 2,
          bottom: -size.height * .02,
          width: subjectWidth,
          height: subjectHeight,
          child: _FadedThemeSubject(
            child: _SmoothThemeImage(
              asset: asset,
              fit: BoxFit.contain,
              alignment: Alignment.bottomCenter,
              filterQuality: FilterQuality.medium,
              opacity: opacity,
            ),
          ),
        ),
      ],
    );
  }
}

class _MobileLandscapeArtwork extends StatelessWidget {
  const _MobileLandscapeArtwork({
    required this.preset,
    required this.asset,
    required this.opacity,
  });

  final MusicThemePreset preset;
  final String asset;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final sceneHeight = (size.width * .64).clamp(220.0, 390.0);
    final bottom = math.max(size.height * .07, 58.0);
    return Stack(
      fit: StackFit.expand,
      children: [
        // One full-height atmosphere layer keeps the same hue and brightness
        // above and below the fold. This replaces the former 32%-opacity top
        // crop that made the upper half look grey.
        _SmoothThemeImage(
          asset: asset,
          fit: BoxFit.cover,
          alignment: preset.alignment,
          filterQuality: FilterQuality.medium,
          opacity: opacity * .88,
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: bottom,
          height: sceneHeight,
          child: _FadedThemeSubject(
            child: _SmoothThemeImage(
              asset: asset,
              fit: BoxFit.contain,
              alignment: Alignment.bottomCenter,
              filterQuality: FilterQuality.medium,
              opacity: (opacity * 1.05).clamp(.18, .94),
            ),
          ),
        ),
      ],
    );
  }
}

class _FadedThemeSubject extends StatelessWidget {
  const _FadedThemeSubject({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (bounds) => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.transparent, Color(0xA6000000), Colors.black],
        stops: [0, .20, .42],
      ).createShader(bounds),
      child: child,
    );
  }
}

class _SmoothThemeImage extends StatelessWidget {
  const _SmoothThemeImage({
    required this.asset,
    required this.fit,
    required this.alignment,
    required this.opacity,
    this.filterQuality = FilterQuality.medium,
  });

  final String asset;
  final BoxFit fit;
  final AlignmentGeometry alignment;
  final double opacity;
  final FilterQuality filterQuality;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      asset,
      fit: fit,
      alignment: alignment,
      filterQuality: filterQuality,
      opacity: AlwaysStoppedAnimation(opacity),
      gaplessPlayback: true,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded) return child;
        return AnimatedOpacity(
          opacity: frame == null ? 0 : 1,
          duration: const Duration(milliseconds: 360),
          curve: Curves.easeOutCubic,
          child: child,
        );
      },
      errorBuilder: (_, _, _) => const SizedBox.expand(),
    );
  }
}

class _AtmospherePainter extends CustomPainter {
  const _AtmospherePainter({
    required this.progress,
    required this.motion,
    required this.accent,
  });

  final double progress;
  final ThemeMotion motion;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    if (motion == ThemeMotion.none || motion == ThemeMotion.drift) return;
    final paint = Paint()..style = PaintingStyle.fill;
    final count = motion == ThemeMotion.rain ? 26 : 14;
    for (var index = 0; index < count; index++) {
      final seed = index * 0.6180339887;
      final x =
          ((seed + progress * (motion == ThemeMotion.rain ? 0.22 : 0.06)) % 1) *
          size.width;
      final y =
          ((seed * 1.73 + progress * (0.22 + index % 3 * 0.05)) % 1) *
          size.height;
      paint.color = accent.withValues(alpha: 0.10 + (index % 4) * 0.025);
      switch (motion) {
        case ThemeMotion.rain:
          paint
            ..strokeWidth = 1.2 + index % 2
            ..strokeCap = StrokeCap.round
            ..style = PaintingStyle.stroke;
          canvas.drawLine(Offset(x, y), Offset(x - 7, y + 28), paint);
          paint.style = PaintingStyle.fill;
        case ThemeMotion.petals:
          canvas.save();
          canvas.translate(x, y);
          canvas.rotate(progress * math.pi * 2 + index);
          canvas.drawOval(const Rect.fromLTWH(-5, -2, 10, 5), paint);
          canvas.restore();
        case ThemeMotion.stickers:
          final path = Path();
          for (var point = 0; point < 10; point++) {
            final radius = point.isEven ? 6.0 : 2.8;
            final angle = -math.pi / 2 + point * math.pi / 5;
            final offset = Offset(
              x + math.cos(angle) * radius,
              y + math.sin(angle) * radius,
            );
            point == 0
                ? path.moveTo(offset.dx, offset.dy)
                : path.lineTo(offset.dx, offset.dy);
          }
          path.close();
          canvas.drawPath(path, paint);
        case ThemeMotion.vinyl:
          paint.style = PaintingStyle.stroke;
          paint.strokeWidth = 1.4;
          canvas.drawCircle(Offset(x, y), 6 + (index % 3) * 4, paint);
          paint.style = PaintingStyle.fill;
        case ThemeMotion.carousel:
        case ThemeMotion.parade:
          canvas.drawCircle(Offset(x, y), 3 + index % 4, paint);
        case ThemeMotion.dream:
          canvas.drawOval(
            Rect.fromCenter(center: Offset(x, y), width: 16, height: 8),
            paint,
          );
        case ThemeMotion.none:
        case ThemeMotion.drift:
          break;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _AtmospherePainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.motion != motion;
}
