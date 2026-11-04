import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../themes/beta_appearance.dart';

/// Composition and optical values from liquid_glass_widgets' official
/// example/lib/apple_music/apple_music_demo.dart (MIT). Keep these centralized:
/// the package owns the spring, press/drag physics and accessory morphing.
LiquidGlassSettings betaMusicPillGlass(BuildContext context) =>
    LiquidGlassSettings(
      glassColor: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xCC1C1C1E)
          : const Color(0x80F2F2F7),
      thickness: 30,
      blur: 2,
      lightIntensity: Theme.of(context).brightness == Brightness.dark
          ? .18
          : .28,
      chromaticAberration: .01,
      saturation: 1.2,
      fresnelStrength: Theme.of(context).brightness == Brightness.dark ? 0 : .2,
    );

const betaMusicRoutes = [
  '/music/recommend',
  '/music',
  '/music/library',
  '/profile',
];
const betaMusicTabs = [
  GlassTab(
    label: '发现',
    icon: Icon(CupertinoIcons.compass),
    activeIcon: Icon(CupertinoIcons.compass_fill),
  ),
  GlassTab(
    label: '功能',
    icon: Icon(CupertinoIcons.square_grid_2x2),
    activeIcon: Icon(CupertinoIcons.square_grid_2x2_fill),
  ),
  GlassTab(
    label: '音乐库',
    icon: Icon(CupertinoIcons.music_albums),
    activeIcon: Icon(CupertinoIcons.music_albums_fill),
  ),
  GlassTab(
    label: '我的',
    icon: Icon(CupertinoIcons.person),
    activeIcon: Icon(CupertinoIcons.person_fill),
  ),
];

class BetaMusicBottomBar extends StatelessWidget {
  const BetaMusicBottomBar({
    required this.selectedIndex,
    required this.onTabSelected,
    required this.searchConfig,
    this.isSearchActive = false,
    this.inline = false,
    this.accessory,
    this.accessoryEnabled = true,
    super.key,
  });
  final int selectedIndex;
  final ValueChanged<int> onTabSelected;
  final GlassSearchBarConfig searchConfig;
  final bool isSearchActive, inline, accessoryEnabled;
  final Widget? accessory;

  @override
  Widget build(BuildContext context) {
    final foreground = Theme.of(context).colorScheme.onSurface;
    final scaled = (MediaQuery.textScalerOf(context).scale(24) - 24).clamp(
      0.0,
      28.0,
    );
    return GlassTabBar.searchable(
      key: const ValueKey('beta6-official-music-bar'),
      tabs: betaMusicTabs,
      selectedIndex: selectedIndex,
      onTabSelected: onTabSelected,
      isSearchActive: isSearchActive,
      // At narrow widths the two transport buttons already consume most of
      // an inline accessory. Keep the shared glass capsule expanded so large
      // text never squeezes its controls out of the available row.
      bottomAccessoryPlacement:
          inline &&
              MediaQuery.sizeOf(context).width >= 360 &&
              MediaQuery.textScalerOf(context).scale(12) <= 18
          ? GlassTabBarAccessoryPlacement.inline
          : GlassTabBarAccessoryPlacement.expanded,
      bottomAccessory: accessory,
      bottomAccessoryEnabled: accessoryEnabled,
      bottomAccessoryHeight: 50 + scaled,
      barHeight: 64 + scaled,
      searchBarHeight: 50 + scaled,
      horizontalPadding: 20,
      verticalPadding: 16,
      spacing: 8,
      selectedIconColor: BetaAppearance.navigation(
        Theme.of(context).brightness,
      ),
      selectedLabelColor: BetaAppearance.navigationLabel(
        Theme.of(context).brightness,
      ),
      unselectedIconColor: foreground.withValues(alpha: .9),
      unselectedLabelColor: foreground.withValues(alpha: .9),
      // Keep the selected lens neutral and translucent; a heavy inverse tint
      // behind the caption erases red-on-glass contrast in both appearances.
      indicatorColor: Theme.of(context).brightness == Brightness.dark
          ? const Color(0x0DFFFFFF)
          : const Color(0x33FFFFFF),
      labelFontSize: 10,
      iconSize: 28,
      iconLabelSpacing: 0,
      quality: GlassQuality.premium,
      interactionBehavior: GlassInteractionBehavior.full,
      // Scroll-bottom whitening can flatten a compact pill's optical body.
      // Readability comes from the shared material, not a scroll-time white veil.
      whitenAtBottom: false,
      settings: LiquidGlassSettings(
        glassColor: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xAA1C1C1E)
            : const Color(0x80F2F2F7),
        thickness: 30,
        blur: 2,
        chromaticAberration: .01,
        lightAngle: GlassDefaults.lightAngle,
        lightIntensity: Theme.of(context).brightness == Brightness.dark
            ? .2
            : .28,
        ambientStrength: 0,
        refractiveIndex: 1.2,
        fresnelStrength: Theme.of(context).brightness == Brightness.dark
            ? 0
            : .2,
        saturation: 1.2,
        specularSharpness: GlassSpecularSharpness.medium,
      ),
      searchConfig: searchConfig,
    );
  }
}
