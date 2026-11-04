import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../core/platform/distribution_channel.dart';
import 'music_loading_scope.dart';
import 'artwork_reveal_boundary.dart';

/// All Beta indeterminate progress uses the actual Cupertino tick animation.
/// Stable keeps its Material style; determinate byte/progress bars are separate.
class MusicActivityIndicator extends StatelessWidget {
  const MusicActivityIndicator({
    this.color,
    this.radius = 10,
    this.label = '正在加载',
    this.independent = false,
    this.strokeWidth = 2,
    super.key,
  });
  final Color? color;
  final double radius, strokeWidth;
  final String label;
  final bool independent;
  @override
  Widget build(BuildContext context) {
    if (!independent && MusicLoadingScope.coveredOf(context)) {
      return SizedBox.square(dimension: radius * 2);
    }
    final indicator = Semantics(
      label: label,
      liveRegion: true,
      child: DistributionChannel.isBeta
          ? CupertinoActivityIndicator(
              color: color,
              radius: radius,
              animating: !MediaQuery.disableAnimationsOf(context),
            )
          : CircularProgressIndicator(color: color, strokeWidth: strokeWidth),
    );
    return DistributionChannel.isBeta && !independent
        ? ArtworkPendingContent(child: indicator)
        : indicator;
  }
}
