import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../themes/app_theme.dart';
import '../../themes/music_theme_preset.dart';
import '../../themes/music_theme_tokens.dart';

/// Artwork is darkened by the retained lyrics backdrop. Use the application's
/// complete dark scheme, including component themes, rather than changing only
/// brightness/onSurface on a light theme (which leaves light filled buttons).
/// Font choices and unrelated extensions stay with the caller.
ThemeData qishuiArtworkTheme(ThemeData base) {
  final dark = buildMestingTheme(musicThemePresetById('classic-dark'));
  final scheme = dark.colorScheme;
  final cupertino = dark.cupertinoOverrideTheme;
  final cupertinoText = cupertino?.textTheme;
  return dark.copyWith(
    platform: base.platform,
    visualDensity: base.visualDensity,
    pageTransitionsTheme: base.pageTransitionsTheme,
    cupertinoOverrideTheme: cupertino?.copyWith(
      textTheme: cupertinoText?.copyWith(
        textStyle: cupertinoText.textStyle.copyWith(
          fontFamily: base.textTheme.bodyMedium?.fontFamily,
          fontFamilyFallback: base.textTheme.bodyMedium?.fontFamilyFallback,
        ),
        actionTextStyle: cupertinoText.actionTextStyle.copyWith(
          fontFamily: base.textTheme.bodyMedium?.fontFamily,
          fontFamilyFallback: base.textTheme.bodyMedium?.fontFamilyFallback,
        ),
      ),
    ),
    textTheme: base.textTheme.apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    ),
    primaryTextTheme: base.primaryTextTheme.apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    ),
    // ListTile supplies explicit text styles, so it does not inherit textTheme
    // font changes automatically. Retain typography while taking dark colors.
    listTileTheme: dark.listTileTheme.copyWith(
      titleTextStyle: dark.listTileTheme.titleTextStyle?.copyWith(
        fontFamily: base.textTheme.titleMedium?.fontFamily,
        fontFamilyFallback: base.textTheme.titleMedium?.fontFamilyFallback,
      ),
      subtitleTextStyle: dark.listTileTheme.subtitleTextStyle?.copyWith(
        fontFamily: base.textTheme.bodyMedium?.fontFamily,
        fontFamilyFallback: base.textTheme.bodyMedium?.fontFamilyFallback,
      ),
    ),
    extensions: [
      for (final extension in base.extensions.values)
        if (extension is! MusicThemeTokens) extension,
      MusicThemeTokens.forBrightness(Brightness.dark),
    ],
  );
}

/// Keep the same wrapper in both states so retained navigation/page state is
/// never discarded when the lyrics view opens or closes. No saved/global
/// appearance preference is written. The caller's Builder resolves glass
/// settings and bottom controls inside this same effective theme.
class QishuiArtworkAppearance extends StatelessWidget {
  const QishuiArtworkAppearance({
    required this.active,
    required this.child,
    super.key,
  });
  final bool active;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    final effective = active ? qishuiArtworkTheme(base) : base;
    final overlay = effective.brightness == Brightness.dark
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark;
    // Status/gesture icons share the temporary appearance and restore with the
    // wrapper. A child AppBar can still supply its normal route-specific style.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarContrastEnforced: false,
      ),
      child: Theme(data: effective, child: child),
    );
  }
}

/// A retained lyrics flag is not enough: an inactive tab, secondary page,
/// search, another platform or another source must keep the normal app theme.
bool qishuiLyricsAppearanceActive({
  required bool musicRootVisible,
  required bool lyricsVisible,
  required bool qishuiTrack,
  required bool searching,
  required bool chromeVisible,
}) =>
    musicRootVisible &&
    lyricsVisible &&
    qishuiTrack &&
    !searching &&
    chromeVisible;
