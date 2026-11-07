import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../features/experience/presentation/beta_bottom_bar.dart';
import '../../core/haptics/app_haptics.dart';

/// Neutral controls use clear-body optics. Adaptive body normalization can
/// turn the lens into a grey fill as the sampled scroll background changes.
/// Only body compositing differs from the navigation/player material; blur,
/// refraction, lighting and the touch spring retain their existing settings.
LiquidGlassSettings betaNeutralActionGlass(BuildContext context) =>
    betaMusicPillGlass(context).copyWith(bodyMode: GlassBodyMode.clear);

/// Stable blue action glass. Adaptive body tint preserves background luminance,
/// which turns this blue almost cyan over light scrolling content. Clear body
/// uses alpha tint while retaining the renderer's specular, lens and refraction.
const betaBlueActionGlass = LiquidGlassSettings(
  glassColor: Color(0xF20063D8),
  bodyMode: GlassBodyMode.clear,
  thickness: 32,
  blur: 2,
  lightIntensity: .3,
  ambientStrength: .15,
  refractiveIndex: 1.25,
  chromaticAberration: .01,
  fresnelStrength: .12,
  saturation: 1.2,
);

/// Material owns optics and feedback; callers retain validation, saving and
/// navigation. Sibling surfaces must each own a layer to preserve refraction.
class BetaGlassAction extends StatelessWidget {
  const BetaGlassAction({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.loading = false,
    this.blue = true,
    this.compact = false,
    super.key,
  });
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool loading;
  final bool blue;

  /// Search uses an inset 36dp lens inside a stable 48dp touch target.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final interactive = onPressed != null && !loading;
    final emphasized = blue && (onPressed != null || loading);
    final foreground = onPressed == null && !loading
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : emphasized
        ? Colors.white
        : Theme.of(context).colorScheme.onSurface;
    void activate() {
      if (loading || onPressed == null) return;
      appHaptic(context, AppHapticEvent.impact);
      onPressed!();
    }

    return Semantics(
      button: true,
      enabled: onPressed != null && !loading,
      label: label,
      child: Tooltip(
        message: label,
        triggerMode: compact
            ? TooltipTriggerMode.manual
            : TooltipTriggerMode.longPress,
        child: RepaintBoundary(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: compact && onPressed != null && !loading ? activate : null,
            child: SizedBox.square(
              dimension: 48,
              child: Center(
                child: IgnorePointer(
                  ignoring: compact,
                  child: IgnorePointer(
                    ignoring: !interactive,
                    child: GlassButton.custom(
                      onTap: activate,
                      // Match BetaGlassButton: disabled is a neutral material,
                      // not a translucent blue lens carrying a white icon.
                      enabled: interactive,
                      fadeWhenDisabled: false,
                      excludeFromSemantics: true,
                      canRequestFocus: interactive,
                      width: compact ? 36 : 48,
                      height: compact ? 36 : 48,
                      useOwnLayer: true,
                      quality: GlassQuality.premium,
                      interactionScale: compact ? 1 : null,
                      stretch: compact ? 0 : .15,
                      shape: const LiquidRoundedRectangle(borderRadius: 24),
                      settings: emphasized
                          ? betaBlueActionGlass
                          : betaNeutralActionGlass(context),
                      child: loading
                          ? CupertinoActivityIndicator(color: foreground)
                          : Icon(
                              icon,
                              color: foreground,
                              size: compact
                                  ? 23
                                  : blue
                                  ? 25
                                  : 27,
                            ),
                    ),
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
