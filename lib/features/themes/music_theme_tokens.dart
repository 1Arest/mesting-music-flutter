import 'package:flutter/material.dart';

@immutable
class MusicThemeTokens extends ThemeExtension<MusicThemeTokens> {
  const MusicThemeTokens({
    required this.glass,
    required this.glassStrong,
    required this.glassSubtle,
    required this.border,
    required this.borderStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.shadow,
  });

  factory MusicThemeTokens.forBrightness(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    return MusicThemeTokens(
      glass: dark ? const Color(0xD9141720) : const Color(0xD9FFFFFF),
      glassStrong: dark ? const Color(0xF212151C) : const Color(0xF2FFFFFF),
      glassSubtle: dark ? const Color(0xB3151821) : const Color(0xB8FFFFFF),
      border: dark ? const Color(0x29FFFFFF) : const Color(0xBFFFFFFF),
      borderStrong: dark ? const Color(0x42FFFFFF) : const Color(0xF2FFFFFF),
      textPrimary: dark ? const Color(0xFFF5F7FC) : const Color(0xFF20232B),
      textSecondary: dark ? const Color(0xBDC8D0DE) : const Color(0xFF5D6572),
      textMuted: dark ? const Color(0x9198A2B3) : const Color(0xFF7E8795),
      shadow: dark ? const Color(0x66000000) : const Color(0x24232A3D),
    );
  }

  final Color glass;
  final Color glassStrong;
  final Color glassSubtle;
  final Color border;
  final Color borderStrong;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color shadow;

  @override
  MusicThemeTokens copyWith({
    Color? glass,
    Color? glassStrong,
    Color? glassSubtle,
    Color? border,
    Color? borderStrong,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? shadow,
  }) {
    return MusicThemeTokens(
      glass: glass ?? this.glass,
      glassStrong: glassStrong ?? this.glassStrong,
      glassSubtle: glassSubtle ?? this.glassSubtle,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      shadow: shadow ?? this.shadow,
    );
  }

  @override
  MusicThemeTokens lerp(covariant MusicThemeTokens? other, double t) {
    if (other == null) return this;
    return MusicThemeTokens(
      glass: Color.lerp(glass, other.glass, t)!,
      glassStrong: Color.lerp(glassStrong, other.glassStrong, t)!,
      glassSubtle: Color.lerp(glassSubtle, other.glassSubtle, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
    );
  }
}

extension MusicThemeTokenContext on BuildContext {
  MusicThemeTokens get musicThemeTokens =>
      Theme.of(this).extension<MusicThemeTokens>() ??
      MusicThemeTokens.forBrightness(Theme.of(this).brightness);
}
