import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/features/themes/mesting_palette.dart';
import 'package:mesting_music/features/themes/music_theme_preset.dart';

void main() {
  test('classic themes use the cobalt family instead of rose', () {
    expect(musicThemePresets[0].accent, MestingPalette.primary);
    expect(musicThemePresets[1].accent, MestingPalette.primaryBright);
    expect(musicThemePresets[2].accent, MestingPalette.primary);

    for (final preset in musicThemePresets) {
      final hsl = _hsl(preset.accent);
      expect(
        hsl.hue >= 330 && hsl.saturation >= .10,
        isFalse,
        reason: '${preset.id} still uses a rose-family accent',
      );
    }
  });

  test('functional colors retain readable contrast', () {
    expect(
      _contrast(Colors.white, MestingPalette.primary),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      _contrast(Colors.white, MestingPalette.danger),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      _contrast(Colors.white, MestingPalette.heart),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      _contrast(MestingPalette.primaryBright, MestingPalette.darkSurface),
      greaterThanOrEqualTo(4.5),
    );
  });

  test('rose colors are limited to declared brand and heart roles', () {
    final files = <File>[
      ...Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart')),
      File(
        'android/app/src/main/kotlin/com/mesting/mesting_music/MainActivity.kt',
      ),
      File('android/app/src/main/res/values/colors.xml'),
      File('android/app/src/main/res/values-night/colors.xml'),
    ];
    final violations = <String>[];
    final dartColor = RegExp(r'0x([0-9A-Fa-f]{8})');
    final androidColor = RegExp(
      r'#([0-9A-Fa-f]{8}|[0-9A-Fa-f]{6})(?![0-9A-Fa-f])',
    );
    const removedBrandColors = {'D95046', 'CF5368', 'E8758D'};

    for (final file in files) {
      final source = file.readAsStringSync();
      final normalizedPath = file.path.replaceAll(Platform.pathSeparator, '/');
      final expressions = file.path.endsWith('.dart')
          ? dartColor.allMatches(source).map((match) => match.group(1)!)
          : androidColor.allMatches(source).map((match) => match.group(1)!);
      for (final expression in expressions) {
        final normalized = expression.toUpperCase();
        final rgb = normalized.length == 8
            ? normalized.substring(2)
            : normalized;
        final value = int.parse(rgb, radix: 16);
        final hsl = _hsl(Color(0xFF000000 | value));
        final isRoseFamily =
            removedBrandColors.contains(rgb) ||
            (hsl.hue >= 330 && hsl.saturation >= .10);
        final isAllowedCoralBrandColor =
            (normalizedPath.endsWith('lib/app/branded_launch_screen.dart') &&
                rgb == 'D95046') ||
            (normalizedPath.endsWith(
                  'lib/features/themes/theme_gallery_page.dart',
                ) &&
                const {'D95046', 'E8758D'}.contains(rgb)) ||
            (normalizedPath.endsWith(
                  'android/app/src/main/res/values/colors.xml',
                ) &&
                rgb == 'D95046');
        final isAllowedHeartColor =
            (normalizedPath.endsWith(
                  'lib/features/themes/mesting_palette.dart',
                ) &&
                const {'CC3F56', 'FF7C8A', 'FFE9ED'}.contains(rgb)) ||
            (rgb == 'CC3F56' &&
                (normalizedPath.endsWith(
                      'lib/features/player/presentation/music_hub_top_bar.dart',
                    ) ||
                    normalizedPath.endsWith(
                      'lib/features/profile/presentation/profile_page.dart',
                    ) ||
                    normalizedPath.endsWith(
                      'android/app/src/main/kotlin/com/mesting/mesting_music/MainActivity.kt',
                    )));
        final isPinnedBetaArtOrFavorite =
            normalizedPath.endsWith(
              'lib/features/themes/beta_appearance.dart',
            ) &&
            const {'DE3A3D', 'FF2D55', 'FF375F'}.contains(rgb);
        // User-approved Beta.10 entry artwork keeps its coral/porcelain world
        // scoped to these new surfaces. Exact roles are listed, rather than
        // allowing arbitrary rose colors throughout the application.
        final isPinnedBetaEntryColor =
            (normalizedPath.endsWith(
                  'lib/features/auth/presentation/beta_welcome_page.dart',
                ) &&
                rgb == '291B20') ||
            (normalizedPath.endsWith(
                  'lib/features/auth/presentation/beta_onboarding_page.dart',
                ) &&
                rgb == '22181D') ||
            (normalizedPath.endsWith(
                  'lib/features/auth/presentation/beta_player_style_previews.dart',
                ) &&
                const {'D75E63', '784344'}.contains(rgb));
        if (isRoseFamily &&
            !isAllowedCoralBrandColor &&
            !isAllowedHeartColor &&
            !isPinnedBetaArtOrFavorite &&
            !isPinnedBetaEntryColor) {
          violations.add(
            '${file.path}: #$rgb '
            '(h=${hsl.hue.toStringAsFixed(1)}, '
            's=${hsl.saturation.toStringAsFixed(2)})',
          );
        }
      }
    }

    expect(violations, isEmpty, reason: violations.take(20).join('\n'));
  });

  test('brand compatibility id keeps the restored coral display name', () {
    final sources = [
      File('lib/features/themes/app_brand_style.dart').readAsStringSync(),
      File(
        'lib/features/profile/presentation/profile_background_visual.dart',
      ).readAsStringSync(),
    ].join('\n');

    expect(sources, contains('珊瑚原声'));
    expect(sources, contains('温暖珊瑚红'));
    expect(sources, isNot(contains('玫瑰云')));
    expect(sources, isNot(contains('钴蓝原声')));
    expect(sources, contains('雾蓝星云'));
  });
}

({double hue, double saturation}) _hsl(Color color) {
  final argb = color.toARGB32();
  final red = ((argb >> 16) & 0xFF) / 255;
  final green = ((argb >> 8) & 0xFF) / 255;
  final blue = (argb & 0xFF) / 255;
  final maximum = math.max(red, math.max(green, blue));
  final minimum = math.min(red, math.min(green, blue));
  final delta = maximum - minimum;
  final lightness = (maximum + minimum) / 2;
  final saturation = delta == 0 ? 0.0 : delta / (1 - (2 * lightness - 1).abs());
  var hue = 0.0;
  if (delta != 0) {
    if (maximum == red) {
      hue = 60 * (((green - blue) / delta) % 6);
    } else if (maximum == green) {
      hue = 60 * (((blue - red) / delta) + 2);
    } else {
      hue = 60 * (((red - green) / delta) + 4);
    }
  }
  if (hue < 0) hue += 360;
  return (hue: hue, saturation: saturation);
}

double _contrast(Color first, Color second) {
  final firstLuminance = first.computeLuminance();
  final secondLuminance = second.computeLuminance();
  return (math.max(firstLuminance, secondLuminance) + .05) /
      (math.min(firstLuminance, secondLuminance) + .05);
}
