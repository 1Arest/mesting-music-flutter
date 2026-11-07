import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/features/themes/music_theme_preset.dart';
import 'package:mesting_music/features/themes/music_theme_tokens.dart';

void main() {
  test('27 套主题的玻璃表面和文字都满足可读对比度', () {
    for (final preset in musicThemePresets) {
      final brightness = preset.dark ? Brightness.dark : Brightness.light;
      final tokens = MusicThemeTokens.forBrightness(brightness);
      final surface = Color.alphaBlend(tokens.glassStrong, preset.colors.first);

      expect(
        _contrast(tokens.textPrimary, surface),
        greaterThanOrEqualTo(7),
        reason: '${preset.id} 主文字对比度不足',
      );
      expect(
        _contrast(tokens.textSecondary, surface),
        greaterThanOrEqualTo(4.5),
        reason: '${preset.id} 次文字对比度不足',
      );
      expect(
        _contrast(tokens.textMuted, surface),
        greaterThanOrEqualTo(3),
        reason: '${preset.id} 弱提示文字对比度不足',
      );
    }
  });

  test('每个角色分类只包含自己的静态与动态主题', () {
    for (final ip in MusicThemeIp.values) {
      final presets = musicThemePresets.where((preset) => preset.ip == ip);
      expect(presets, isNotEmpty, reason: '$ip 分类不能为空');
      expect(
        presets.every((preset) => preset.ip == ip),
        isTrue,
        reason: '$ip 分类混入了其他角色主题',
      );
      if (ip != MusicThemeIp.classic) {
        expect(presets.any((preset) => preset.isMotion), isTrue);
        expect(presets.any((preset) => !preset.isMotion), isTrue);
      }
    }
  });
}

double _contrast(Color foreground, Color background) {
  final opaqueBackground = Color.alphaBlend(background, Colors.white);
  final opaqueForeground = Color.alphaBlend(foreground, opaqueBackground);
  final lighter =
      opaqueForeground.computeLuminance() >= opaqueBackground.computeLuminance()
      ? opaqueForeground
      : opaqueBackground;
  final darker = identical(lighter, opaqueForeground)
      ? opaqueBackground
      : opaqueForeground;
  return (lighter.computeLuminance() + .05) / (darker.computeLuminance() + .05);
}
