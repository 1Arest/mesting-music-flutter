import 'package:flutter/material.dart';
import 'music_activity_indicator.dart';

/// Compatibility entry for the existing blue-glass action buttons. All Beta
/// entry points now render the same native Cupertino animation.
class BetaActivityIndicator extends StatelessWidget {
  const BetaActivityIndicator({
    this.color = Colors.white,
    this.radius = 12,
    super.key,
  });
  final Color color;
  final double radius;
  @override
  Widget build(BuildContext context) =>
      MusicActivityIndicator(color: color, radius: radius, independent: true);
}
