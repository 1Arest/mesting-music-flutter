import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import '../../features/experience/presentation/beta_bottom_bar.dart';
import '../../features/themes/beta_appearance.dart';
import 'beta_glass_action.dart';
import '../../core/haptics/app_haptics.dart';
import 'music_activity_indicator.dart';
import '../../features/themes/music_typography.dart';

/// Floating controls share the navigation's optical material. Each surface
/// owns its layer: nesting glass would disable the child's refraction.
class BetaGlassButton extends StatelessWidget {
  const BetaGlassButton({
    required this.child,
    required this.onPressed,
    this.loading = false,
    this.interactionEnabled = true,
    this.hapticFeedback = true,
    this.label,
    this.height = 52,
    this.width,
    this.accent = false,
    this.blue = false,
    this.red = false,
    this.fontSize = MusicTypography.subheadlineSize,
    this.horizontalPadding = 18,
    this.embeddedInPill = false,
    this.borderRadius,
    super.key,
  });
  final Widget child;
  final VoidCallback? onPressed;
  final bool loading, accent, blue, interactionEnabled, hapticFeedback;
  final bool red;
  final String? label;
  final double height;
  final double fontSize;
  final double horizontalPadding;
  final double? width;
  final double? borderRadius;

  /// A segmented action capsule provides one optical layer for its children.
  /// Standalone buttons retain their own layer and all existing press behavior.
  final bool embeddedInPill;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final available = onPressed != null;
    final interactive = interactionEnabled && available && !loading;
    // Disabled controls own a complete foreground/material pair. The library's
    // generic 50% opacity fades the *whole* blue lens against the page, while
    // our white label used to stay white. Keep premium optics and render an
    // explicit neutral state instead; semantics, focus and hit testing below
    // remain genuinely disabled. A pending request keeps its original tint.
    final emphasized = (blue || red) && (available || loading);
    final foreground = !available && !loading
        ? scheme.onSurfaceVariant
        : emphasized
        ? Colors.white
        : accent
        ? BetaAppearance.accent(Theme.of(context).brightness)
        : scheme.onSurface;
    return Semantics(
      button: true,
      label: label,
      enabled: interactive,
      // Blocking a sibling request is an interaction state, not a new optical
      // material. Keep the same glass layer instead of inserting disabled opacity.
      child: ExcludeFocus(
        excluding: !interactive,
        child: IgnorePointer(
          ignoring: !interactive,
          child: RepaintBoundary(
            child: GlassButton.custom(
              onTap: () {
                if (!interactionEnabled || loading || onPressed == null) return;
                if (hapticFeedback) {
                  appHaptic(
                    context,
                    blue || red
                        ? AppHapticEvent.impact
                        : AppHapticEvent.selection,
                  );
                }
                onPressed!();
              },
              enabled: interactive,
              fadeWhenDisabled: false,
              excludeFromSemantics: true,
              canRequestFocus: interactive,
              height: height,
              width: width,
              useOwnLayer: !embeddedInPill,
              // A shared capsule owns the visible lens. Keep per-action
              // highlight, focus and spring without painting three inner pills.
              style: embeddedInPill
                  ? GlassButtonStyle.transparent
                  : GlassButtonStyle.filled,
              quality: GlassQuality.premium,
              stretch: .12,
              // A ListView winning the gesture must cancel every button's press
              // sheen. Raw-pointer tracking would leave neutral glass darkened
              // (and blue glass washed out) for the remainder of a page drag.
              // Tap/keyboard inflation, refraction and highlight remain intact.
              persistPressOnDrag: false,
              ambientBaseLight: emphasized ? .06 : null,
              glowColor: emphasized
                  ? red
                        ? BetaAppearance.playbackAction(
                            Theme.of(context).brightness,
                          )
                        : const Color(0xFF6CA7FF)
                  : null,
              glowOpacity: emphasized ? .12 : null,
              settings: emphasized
                  ? red
                        ? betaBlueActionGlass.copyWith(
                            glassColor: BetaAppearance.playbackAction(
                              Theme.of(context).brightness,
                            ).withAlpha(242),
                          )
                        : betaBlueActionGlass
                  : betaNeutralActionGlass(context),
              shape: LiquidRoundedRectangle(
                borderRadius: borderRadius ?? height / 2,
              ),
              child: Padding(
                padding: width == height
                    ? EdgeInsets.zero
                    : EdgeInsets.symmetric(horizontal: horizontalPadding),
                child: loading
                    ? BetaActivityIndicator(
                        color: foreground,
                        independent: true,
                      )
                    : IconTheme.merge(
                        data: IconThemeData(color: foreground),
                        child: DefaultTextStyle.merge(
                          style: TextStyle(
                            fontSize: fontSize,
                            fontWeight: MusicTypography.bodyWeight,
                            color: foreground,
                          ),
                          child: child,
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

class BetaGlassBackButton extends StatelessWidget {
  const BetaGlassBackButton({this.onPressed, super.key});
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => Tooltip(
    message: '返回',
    child: BetaGlassButton(
      label: '返回',
      width: 48,
      height: 48,
      onPressed: onPressed ?? () => Navigator.of(context).maybePop(),
      child: const Icon(CupertinoIcons.chevron_back, size: 22),
    ),
  );
}

/// The segmented Cupertino spinner is also used by comment sending. Keeping
/// one wrapper makes sizing/semantics consistent across every waiting state.
class BetaActivityIndicator extends StatelessWidget {
  const BetaActivityIndicator({
    this.color,
    this.radius = 10,
    this.label = '正在加载',
    this.independent = false,
    super.key,
  });
  final Color? color;
  final double radius;
  final String label;
  final bool independent;
  @override
  Widget build(BuildContext context) => MusicActivityIndicator(
    label: label,
    color: color,
    radius: radius,
    independent: independent,
  );
}

class BetaGlassField extends StatelessWidget {
  const BetaGlassField({required this.child, super.key});
  final Widget child;
  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: GlassContainer(
      useOwnLayer: true,
      quality: GlassQuality.premium,
      settings: betaMusicPillGlass(context),
      shape: const LiquidRoundedRectangle(borderRadius: 24),
      child: Theme(
        data: Theme.of(context).copyWith(
          inputDecorationTheme: const InputDecorationTheme(
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            disabledBorder: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 17),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: child,
        ),
      ),
    ),
  );
}
