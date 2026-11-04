import 'package:flutter/material.dart';
import '../../core/platform/distribution_channel.dart';

/// Destination meaning, independent of translated labels and platform routes.
enum BetaFeatureTone { action, music, together, downloads, insights }

/// Beta semantic colors. Functional tint, favorites and completion have separate
/// owners so changing navigation never recolors artwork or selected hearts.
/// Light tints are deepened for small text on grouped neutral surfaces.
abstract final class BetaAppearance {
  static const blue = Color(0xFF0066D9);
  static const blueOnDark = Color(0xFF0091FF);
  static const artworkCoral = Color(0xFFDE3A3D);
  static Color accent(Brightness brightness) =>
      brightness == Brightness.dark ? blueOnDark : blue;

  /// Music navigation uses the reference's rose red. Small light-mode labels
  /// use a deeper shade for contrast on the retained neutral glass material.
  static Color navigation(Brightness brightness) =>
      brightness == Brightness.dark
      ? const Color(0xFFFF375F)
      : const Color(0xFFD60035);

  /// Small navigation captions need their own lightness on selected glass.
  static Color navigationLabel(Brightness brightness) =>
      brightness == Brightness.dark
      ? const Color(0xFFFF829B)
      : const Color(0xFFBC0032);

  /// Color belongs to the feature's role, never its grid position. Formal
  /// builds retain their selected theme rather than inheriting Beta colors.
  static Color feature(BuildContext context, BetaFeatureTone tone) {
    final theme = Theme.of(context);
    if (!DistributionChannel.isBeta) return theme.colorScheme.primary;
    final dark = theme.brightness == Brightness.dark;
    return switch (tone) {
      BetaFeatureTone.action => accent(theme.brightness),
      BetaFeatureTone.music => navigation(theme.brightness),
      BetaFeatureTone.together =>
        dark ? const Color(0xFFBF8CFF) : const Color(0xFF7639C7),
      BetaFeatureTone.downloads => success(theme.brightness),
      BetaFeatureTone.insights =>
        dark ? const Color(0xFFFFAA3D) : const Color(0xFFA85B00),
    };
  }

  static Color favorite(Brightness brightness) => brightness == Brightness.dark
      ? const Color(0xFFFF375F)
      : const Color(0xFFFF2D55);

  /// Filled playback actions keep white labels readable in both themes;
  /// favorite glyphs retain their independent, brighter selection color.
  static Color playbackAction(Brightness brightness) =>
      brightness == Brightness.dark
      ? const Color(0xFFD92D4D)
      : const Color(0xFFD70040);

  static Color success(Brightness brightness) => brightness == Brightness.dark
      ? const Color(0xFF30D158)
      : const Color(0xFF007A2B);

  static Color successSurface(Brightness brightness) =>
      brightness == Brightness.dark
      ? const Color(0xFF153523)
      : const Color(0xFFE9F6ED);

  static Color panel(Brightness brightness) => brightness == Brightness.dark
      ? const Color(0xFF1C1C1E)
      : const Color(0xFFF2F2F7);
}
