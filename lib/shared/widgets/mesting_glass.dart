import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

/// A small integration boundary: product widgets never configure shaders.
/// Content remains ordinary Flutter UI; only floating controls use this layer.
class MestingGlass extends StatelessWidget {
  const MestingGlass({required this.child, this.radius = 32, super.key});
  final Widget child;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final reduceTransparency = MediaQuery.highContrastOf(context);
    if (reduceTransparency) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: theme.colorScheme.outline),
        ),
        child: child,
      );
    }
    return GlassContainer(
      useOwnLayer: true,
      // Standard uses the portable shader path on Android. Premium refraction
      // is deliberately bounded to the navigation layer by the package.
      quality: GlassQuality.standard,
      shape: LiquidRoundedSuperellipse(borderRadius: radius),
      settings: LiquidGlassSettings(
        glassColor: theme.colorScheme.surface.withValues(
          alpha: dark ? .84 : .78,
        ),
        blur: 12,
        thickness: 22,
        lightIntensity: .22,
        chromaticAberration: .005,
        saturation: 1.12,
      ),
      child: child,
    );
  }
}
