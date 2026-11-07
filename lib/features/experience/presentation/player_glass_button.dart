import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'beta_bottom_bar.dart';

/// Matching, stationary player lenses. Keeping the material in one component
/// prevents the dismiss and overflow controls from drifting between styles.
class PlayerGlassButton extends StatelessWidget {
  const PlayerGlassButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    super.key,
  });
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    button: true,
    child: Tooltip(
      message: label,
      child: RepaintBoundary(
        child: GlassButton.custom(
          onTap: onPressed,
          width: 48,
          height: 48,
          useOwnLayer: true,
          quality: GlassQuality.premium,
          shape: const LiquidOval(),
          settings: betaMusicPillGlass(
            context,
          ).copyWith(glassColor: const Color(0x602C2C2E)),
          child: Icon(icon, color: Colors.white, size: 24),
        ),
      ),
    ),
  );
}
