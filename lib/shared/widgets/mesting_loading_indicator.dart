import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:math_curve_loaders/math_curve_loaders.dart';
import '../../core/platform/distribution_channel.dart';
import 'artwork_reveal_boundary.dart';
import 'music_loading_scope.dart';

/// The shared, text-free loading animation used by content and page states.
///
/// Visible loading copy intentionally lives outside this widget. Callers should
/// normally provide only a Chinese semantic label so screen readers still
/// receive useful progress context without adding visual noise.
class MestingLoadingIndicator extends StatelessWidget {
  const MestingLoadingIndicator({
    this.size = 60,
    this.color,
    this.secondaryColor,
    this.semanticLabel = '内容正在加载',
    this.duration = const Duration(milliseconds: 2800),
    super.key,
  });

  final double size;
  final Color? color;
  final Color? secondaryColor;
  final String semanticLabel;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    if (DistributionChannel.isBeta) {
      if (MusicLoadingScope.coveredOf(context)) {
        return SizedBox.square(dimension: size);
      }
      return ArtworkPendingContent(
        child: Semantics(
          label: semanticLabel,
          liveRegion: true,
          child: SizedBox.square(
            dimension: size,
            child: Center(
              child: CupertinoActivityIndicator(
                radius: (size * .18).clamp(8.0, 14.0),
                color: color,
              ),
            ),
          ),
        ),
      );
    }
    final scheme = Theme.of(context).colorScheme;
    final primary = color ?? scheme.primary;
    final secondary = secondaryColor ?? scheme.secondary;

    return RepaintBoundary(
      child: ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (bounds) => LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [primary, secondary, primary],
          stops: const [0, .52, 1],
        ).createShader(bounds),
        child: MathCurveLoader.lissajous(
          size: size,
          color: Colors.white,
          duration: duration,
          semanticLabel: semanticLabel,
          respectReducedMotion: true,
          xFrequency: 3,
          yFrequency: 2,
          radius: size * .28,
          style: const MathCurveLoaderStyle(
            particleCount: 62,
            trailSpan: .34,
            strokeWidth: 3.2,
            guideOpacity: .1,
            minParticleOpacity: .04,
            maxParticleOpacity: .94,
            minParticleRadius: .7,
            maxParticleRadius: 2.9,
          ),
        ),
      ),
    );
  }
}
