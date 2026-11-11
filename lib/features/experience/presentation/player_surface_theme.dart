import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../themes/music_theme_tokens.dart';
import '../../themes/music_typography.dart';

/// Player overlays capture this theme. Changing only brightness/colorScheme
/// retains light-theme TextTheme/ListTileTheme ink on the dark glass surface.
ThemeData readablePlayerSurfaceTheme(ThemeData base) {
  final tokens = MusicThemeTokens.forBrightness(base.brightness);
  final scheme = base.colorScheme;
  return base.copyWith(
    textTheme: base.textTheme.merge(
      MusicTypography.textTheme(
        primary: tokens.textPrimary,
        secondary: tokens.textSecondary,
      ),
    ),
    primaryTextTheme: base.primaryTextTheme.apply(
      bodyColor: tokens.textPrimary,
      displayColor: tokens.textPrimary,
    ),
    iconTheme: base.iconTheme.copyWith(color: tokens.textSecondary),
    primaryIconTheme: base.primaryIconTheme.copyWith(color: tokens.textPrimary),
    listTileTheme: base.listTileTheme.copyWith(
      textColor: tokens.textPrimary,
      iconColor: tokens.textSecondary,
      titleTextStyle: base.listTileTheme.titleTextStyle?.copyWith(
        color: tokens.textPrimary,
      ),
      subtitleTextStyle: base.listTileTheme.subtitleTextStyle?.copyWith(
        color: tokens.textSecondary,
      ),
    ),
    dividerColor: tokens.border,
    cupertinoOverrideTheme: CupertinoThemeData(
      brightness: base.brightness,
      primaryColor: scheme.primary,
      textTheme: CupertinoTextThemeData(
        textStyle: MusicTypography.body.copyWith(color: tokens.textPrimary),
        actionTextStyle: MusicTypography.body.copyWith(color: scheme.primary),
        navTitleTextStyle: MusicTypography.headline.copyWith(
          color: tokens.textPrimary,
        ),
        navLargeTitleTextStyle: MusicTypography.largeTitle.copyWith(
          color: tokens.textPrimary,
        ),
      ),
    ),
  );
}
