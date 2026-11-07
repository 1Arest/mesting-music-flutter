import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/features/themes/app_theme.dart';
import 'package:mesting_music/features/themes/music_theme_preset.dart';

void main() {
  for (final dark in [false, true]) {
    test('application typography has consistent roles dark=$dark', () {
      final preset = musicThemePresets.firstWhere(
        (value) => value.dark == dark,
      );
      final theme = buildMestingTheme(preset);
      final text = theme.textTheme;

      expect(text.displayLarge!.fontSize, 34);
      expect(text.displaySmall!.fontSize, 28);
      expect(text.headlineMedium!.fontSize, 22);
      expect(text.headlineSmall!.fontSize, 20);
      expect(text.titleMedium!.fontSize, 17);
      expect(text.bodyMedium!.fontSize, 17);
      expect(text.bodySmall!.fontSize, 13);
      expect(text.labelSmall!.fontSize, 11);
      for (final style in [
        text.displayLarge,
        text.displaySmall,
        text.headlineMedium,
        text.headlineSmall,
        text.titleMedium,
      ]) {
        expect(style!.fontWeight, FontWeight.w500);
      }
      for (final style in [text.bodyLarge, text.bodyMedium, text.bodySmall]) {
        expect(style!.fontWeight, FontWeight.w400);
      }
      expect(theme.listTileTheme.subtitleTextStyle!.fontSize, 15);
      expect(
        theme.listTileTheme.subtitleTextStyle!.fontWeight,
        FontWeight.w400,
      );
      expect(text.bodyMedium!.height, closeTo(22 / 17, .001));
      expect(text.bodyMedium!.color, isNot(text.bodySmall!.color));
    });
  }

  test('application text avoids heavy weight overrides', () {
    final heavyWeight = RegExp(r'FontWeight\.(?:w[6789]00|bold)\b');
    final violations = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .where((file) => heavyWeight.hasMatch(file.readAsStringSync()))
        .map((file) => file.path)
        .toList();
    expect(
      violations,
      isEmpty,
      reason: 'Application text uses Regular/Medium.',
    );
  });
}
