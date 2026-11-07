import '../../shared/widgets/beta_page_motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

import '../../core/platform/distribution_channel.dart';
import 'beta_appearance.dart';
import 'mesting_palette.dart';
import 'music_theme_preset.dart';
import 'music_theme_tokens.dart';

ThemeData buildMestingTheme(MusicThemePreset preset) {
  final seed = DistributionChannel.isBeta ? BetaAppearance.blue : preset.accent;
  final generated = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: preset.dark ? Brightness.dark : Brightness.light,
    surface: preset.dark
        ? MestingPalette.darkSurface
        : MestingPalette.lightSurface,
  );
  final scheme = DistributionChannel.isBeta
      ? generated.copyWith(
          primary: BetaAppearance.accent(generated.brightness),
          // Keep functional surfaces neutral rather than inheriting a colored
          // Material seed wash. Cover art continues to own the player backdrop.
          onPrimary: preset.dark ? const Color(0xFF001B33) : Colors.white,
          primaryContainer: BetaAppearance.panel(generated.brightness),
          onPrimaryContainer: preset.dark
              ? Colors.white
              : const Color(0xFF1C1C1E),
          surfaceContainerLow: BetaAppearance.panel(generated.brightness),
          surface: preset.dark ? const Color(0xFF121316) : Colors.white,
          surfaceTint: Colors.transparent,
          onSurface: preset.dark
              ? const Color(0xFFF5F5F7)
              : const Color(0xFF1C1C1E),
          onSurfaceVariant: preset.dark
              ? const Color(0xFFAEAEB2)
              : const Color(0xFF636366),
          surfaceContainer: preset.dark
              ? const Color(0xFF242426)
              : const Color(0xFFF2F2F7),
          surfaceContainerHigh: preset.dark
              ? const Color(0xFF2C2C2E)
              : const Color(0xFFE8E8ED),
          surfaceContainerHighest: preset.dark
              ? const Color(0xFF3A3A3C)
              : const Color(0xFFE3E3E8),
        )
      : generated;
  final tokens = MusicThemeTokens.forBrightness(scheme.brightness);

  return ThemeData(
    useMaterial3: true,
    pageTransitionsTheme: DistributionChannel.isBeta
        ? const PageTransitionsTheme(
            builders: {
              TargetPlatform.android: BetaPageTransitionsBuilder(),
              TargetPlatform.iOS: BetaPageTransitionsBuilder(),
              TargetPlatform.windows: BetaPageTransitionsBuilder(),
            },
          )
        : const PageTransitionsTheme(),
    colorScheme: scheme,
    textSelectionTheme: DistributionChannel.isBeta
        ? TextSelectionThemeData(
            cursorColor: preset.dark
                ? const Color(0xFF0A84FF)
                : const Color(0xFF007AFF),
            selectionHandleColor: preset.dark
                ? const Color(0xFF0A84FF)
                : const Color(0xFF007AFF),
            selectionColor:
                (preset.dark
                        ? const Color(0xFF0A84FF)
                        : const Color(0xFF007AFF))
                    .withValues(alpha: .22),
          )
        : null,
    cupertinoOverrideTheme: DistributionChannel.isBeta
        ? CupertinoThemeData(
            primaryColor: preset.dark
                ? const Color(0xFF0A84FF)
                : const Color(0xFF007AFF),
            selectionHandleColor: preset.dark
                ? const Color(0xFF0A84FF)
                : const Color(0xFF007AFF),
          )
        : null,
    extensions: [tokens],
    scaffoldBackgroundColor: Colors.transparent,
    fontFamilyFallback: const ['Noto Sans SC', 'Microsoft YaHei', 'sans-serif'],
    textTheme: TextTheme(
      displaySmall: TextStyle(
        color: tokens.textPrimary,
        fontWeight: FontWeight.w900,
        letterSpacing: -1.4,
        height: 1.08,
      ),
      headlineMedium: TextStyle(
        color: tokens.textPrimary,
        fontWeight: FontWeight.w900,
      ),
      titleLarge: TextStyle(
        color: tokens.textPrimary,
        fontWeight: FontWeight.w800,
      ),
      titleMedium: TextStyle(
        color: tokens.textPrimary,
        fontWeight: FontWeight.w800,
      ),
      bodyLarge: TextStyle(color: tokens.textPrimary, height: 1.55),
      bodyMedium: TextStyle(color: tokens.textPrimary),
      bodySmall: TextStyle(color: tokens.textSecondary),
      labelLarge: TextStyle(color: tokens.textPrimary),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        backgroundColor: tokens.glassSubtle,
        foregroundColor: tokens.textPrimary,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: tokens.glassSubtle,
      hintStyle: TextStyle(color: tokens.textMuted),
      labelStyle: TextStyle(color: tokens.textSecondary),
      prefixIconColor: tokens.textSecondary,
      suffixIconColor: tokens.textSecondary,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: tokens.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: tokens.border),
      ),
    ),
    dividerColor: tokens.border,
    listTileTheme: ListTileThemeData(
      textColor: tokens.textPrimary,
      iconColor: tokens.textSecondary,
      subtitleTextStyle: TextStyle(color: tokens.textSecondary),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: tokens.glassSubtle,
      side: BorderSide(color: tokens.border),
      labelStyle: TextStyle(color: tokens.textPrimary),
      secondaryLabelStyle: TextStyle(color: tokens.textPrimary),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: seed,
      thumbColor: seed,
      overlayColor: seed.withValues(alpha: 0.14),
      trackHeight: 4,
    ),
  );
}
