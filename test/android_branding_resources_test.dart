import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

void main() {
  const resRoot = 'android/app/src/main/res';

  test(
    'Beta native warm-start windows do not reuse the coral startup canvas',
    () {
      const betaRes = 'android/app/src/beta/res';
      for (final folder in ['values', 'values-night']) {
        final colors = File('$betaRes/$folder/colors.xml').readAsStringSync();
        final runtimeColor = folder == 'values' ? '#FFFFFF' : '#11141B';
        expect(
          colors,
          contains(
            '<color name="mesting_splash_background">$runtimeColor</color>',
          ),
        );
        expect(
          colors,
          contains(
            '<color name="mesting_runtime_background">$runtimeColor</color>',
          ),
        );
        expect(
          colors,
          contains('<color name="mesting_coral_launch_light">#FFFFFF</color>'),
        );
        expect(
          colors,
          contains('<color name="mesting_coral_launch_dark">#11141B</color>'),
        );
        final styles = File('$betaRes/$folder/styles.xml').readAsStringSync();
        expect(
          styles,
          contains(
            '<item name="android:windowBackground">@color/mesting_runtime_background</item>',
          ),
        );
      }
    },
  );

  test('launcher icons exist at every Android density', () {
    const expectedSizes = <String, int>{
      'mipmap-mdpi': 48,
      'mipmap-hdpi': 72,
      'mipmap-xhdpi': 96,
      'mipmap-xxhdpi': 144,
      'mipmap-xxxhdpi': 192,
    };

    for (final entry in expectedSizes.entries) {
      for (final name in <String>[
        'ic_launcher',
        'ic_launcher_morning',
        'ic_launcher_midnight',
      ]) {
        final file = File('$resRoot/${entry.key}/$name.png');
        expect(file.existsSync(), isTrue, reason: file.path);
        expect(_pngSize(file), (entry.value, entry.value), reason: file.path);
      }
    }
  });

  test('legacy primary launcher uses the coral canvas', () async {
    final file = File('$resRoot/mipmap-xxxhdpi/ic_launcher.png');
    final decoded = await _decodeRgba(file);
    final offset = (96 * decoded.width + 24) * 4;
    expect(
      decoded.bytes.sublist(offset, offset + 4),
      orderedEquals(<int>[217, 80, 70, 255]),
    );
    expect(
      decoded.bytes.sublist(offset, offset + 3),
      isNot(orderedEquals(<int>[70, 92, 199])),
    );
  });

  test('dress-up launcher components and adaptive icons are bundled', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    expect(manifest, contains('.MorningMistLauncher'));
    expect(manifest, contains('.MidnightVinylLauncher'));
    expect(manifest, contains('@mipmap/ic_launcher_morning'));
    expect(manifest, contains('@mipmap/ic_launcher_midnight'));
    expect(manifest, contains('.CoralLightLauncher'));
    expect(manifest, contains('.CoralDarkLauncher'));
    expect(manifest, contains('@style/LaunchThemeCoralLight'));
    expect(manifest, contains('@style/LaunchThemeCoralDark'));

    for (final version in <String>['mipmap-anydpi-v26', 'mipmap-anydpi-v33']) {
      final morning = File(
        '$resRoot/$version/ic_launcher_morning.xml',
      ).readAsStringSync();
      final midnight = File(
        '$resRoot/$version/ic_launcher_midnight.xml',
      ).readAsStringSync();
      expect(
        morning,
        contains('@drawable/mesting_morning_adaptive_background'),
      );
      expect(morning, contains('@drawable/mesting_morning_adaptive'));
      expect(
        midnight,
        contains('@drawable/mesting_midnight_adaptive_background'),
      );
      expect(midnight, contains('@drawable/mesting_midnight_adaptive'));
      expect(morning, isNot(contains('<monochrome')));
      expect(midnight, isNot(contains('<monochrome')));
    }

    for (final name in <String>['morning', 'midnight']) {
      expect(
        _pngSize(
          File('$resRoot/drawable-xxxhdpi/mesting_${name}_foreground.png'),
        ),
        (432, 432),
      );
      expect(
        _pngSize(
          File(
            '$resRoot/drawable-xxxhdpi/'
            'mesting_${name}_adaptive_background.png',
          ),
        ),
        (432, 432),
      );
      final inset = File(
        '$resRoot/drawable/mesting_${name}_adaptive.xml',
      ).readAsStringSync();
      expect(inset, contains('android:insetLeft="16dp"'));
      expect(inset, contains('android:insetTop="16dp"'));
      expect(inset, contains('android:insetRight="16dp"'));
      expect(inset, contains('android:insetBottom="16dp"'));
      expect(inset, contains('@drawable/mesting_${name}_foreground'));
    }
    expect(_pngSize(File('assets/branding/dress-morning-icon-v2.png')), (
      1024,
      1024,
    ));
    expect(_pngSize(File('assets/branding/dress-midnight-icon-v2.png')), (
      1024,
      1024,
    ));
  });

  test('chat voice recording declares the microphone permission', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    expect(
      manifest,
      contains(
        '<uses-permission android:name="android.permission.RECORD_AUDIO" />',
      ),
    );
  });

  test(
    'alternate launch artwork uses matching phone-native canvases',
    () async {
      for (final name in <String>['morning', 'midnight']) {
        final file = File(
          name == 'morning'
              ? 'assets/branding/dress-morning-launch.webp'
              : 'assets/branding/dress-midnight-launch-v2.webp',
        );
        final decoded = await _decodeRgba(file);
        final size = (decoded.width, decoded.height);
        expect(size, (900, 2000), reason: file.path);
        expect(size.$1 / size.$2, closeTo(9 / 20, .001), reason: file.path);
      }
    },
  );

  test('alternate brand palettes match their native launch canvases', () {
    final colors = File('$resRoot/values/colors.xml').readAsStringSync();
    final nightColors = File(
      '$resRoot/values-night/colors.xml',
    ).readAsStringSync();

    for (final source in <String>[colors, nightColors]) {
      expect(
        source,
        contains('<color name="mesting_morning_background">#FFF7E5</color>'),
      );
      expect(
        source,
        contains('<color name="mesting_midnight_background">#081824</color>'),
      );
      expect(source, isNot(contains('#EDF2F7')));
      expect(source, isNot(contains('#090B1D')));
    }
  });

  test('adaptive launcher preserves the selected full-color brand', () {
    final adaptive = File(
      '$resRoot/mipmap-anydpi-v26/ic_launcher.xml',
    ).readAsStringSync();
    final themed = File(
      '$resRoot/mipmap-anydpi-v33/ic_launcher.xml',
    ).readAsStringSync();

    expect(adaptive, contains('@color/mesting_brand_coral'));
    expect(adaptive, contains('@drawable/mesting_mark_adaptive'));
    expect(themed, contains('@color/mesting_brand_coral'));
    expect(themed, contains('@drawable/mesting_mark_adaptive'));
    expect(themed, isNot(contains('<monochrome')));

    expect(
      _pngSize(File('$resRoot/drawable-xxxhdpi/mesting_mark_foreground.png')),
      (432, 432),
    );
    final inset = File(
      '$resRoot/drawable/mesting_mark_adaptive.xml',
    ).readAsStringSync();
    expect(inset, contains('android:insetLeft="16dp"'));
    expect(inset, contains('@drawable/mesting_mark_foreground'));
  });

  test('alternate launcher layers match the primary safe zone', () async {
    final primaryForeground = File(
      '$resRoot/drawable-xxxhdpi/mesting_mark_foreground.png',
    );
    final primaryBounds = await _alphaBounds(primaryForeground);

    for (final name in <String>['morning', 'midnight']) {
      final foreground = File(
        '$resRoot/drawable-xxxhdpi/mesting_${name}_foreground.png',
      );
      final background = File(
        '$resRoot/drawable-xxxhdpi/'
        'mesting_${name}_adaptive_background.png',
      );
      expect(
        await _alphaBounds(foreground),
        primaryBounds,
        reason: '$name foreground must use the primary visual safe zone',
      );
      expect(
        await _alphaAt(background, 0, 0),
        255,
        reason: '$name adaptive background must fill the system mask',
      );
      expect(
        await _alphaAt(background, 431, 431),
        255,
        reason: '$name adaptive background must fill the system mask',
      );
    }
  });

  test('legacy launcher variants share the rounded canvas', () async {
    for (final directory in <String>[
      'mipmap-mdpi',
      'mipmap-hdpi',
      'mipmap-xhdpi',
      'mipmap-xxhdpi',
      'mipmap-xxxhdpi',
    ]) {
      for (final name in <String>[
        'ic_launcher',
        'ic_launcher_morning',
        'ic_launcher_midnight',
      ]) {
        final file = File('$resRoot/$directory/$name.png');
        final size = _pngSize(file).$1;
        expect(
          await _alphaAt(file, 0, 0),
          0,
          reason: '${file.path} must not bake an opaque square corner',
        );
        expect(
          await _alphaAt(file, size ~/ 2, size ~/ 2),
          255,
          reason: '${file.path} must fill the rounded icon center',
        );
      }
    }
  });

  test('Android 12 system splash does not duplicate the Flutter lockup', () {
    for (final directory in <String>['values-v31', 'values-night-v31']) {
      final styles = File('$resRoot/$directory/styles.xml').readAsStringSync();
      expect(styles, contains('windowSplashScreenBackground'));
      expect(styles, contains('@color/mesting_splash_background'));
      expect(
        styles,
        contains(
          '<item name="android:windowSplashScreenAnimatedIcon">'
          '@android:color/transparent</item>',
        ),
      );
      expect(
        styles,
        contains(
          '<item name="android:windowSplashScreenAnimationDuration">0</item>',
        ),
      );
      expect(styles, isNot(contains('@drawable/mesting_mark_splash')));
      expect(styles, isNot(contains('@drawable/mesting_launch_lockup')));
    }

    final lightColors = File('$resRoot/values/colors.xml').readAsStringSync();
    final darkColors = File(
      '$resRoot/values-night/colors.xml',
    ).readAsStringSync();
    expect(lightColors, contains('#D95046'));
    expect(darkColors, contains('#17131B'));

    expect(
      _pngSize(File('$resRoot/drawable-xxxhdpi/mesting_launch_lockup.png')),
      (912, 912),
    );
  });

  test('classic launch aliases preserve the saved light or dark mode', () {
    final baseStyles = File('$resRoot/values/styles.xml').readAsStringSync();
    final android12Styles = File(
      '$resRoot/values-v31/styles.xml',
    ).readAsStringSync();
    final colors = File('$resRoot/values/colors.xml').readAsStringSync();
    final activity = File(
      'android/app/src/main/kotlin/com/mesting/mesting_music/MainActivity.kt',
    ).readAsStringSync();

    for (final styles in <String>[baseStyles, android12Styles]) {
      expect(styles, contains('LaunchThemeCoralLight'));
      expect(styles, contains('LaunchThemeCoralDark'));
      expect(styles, contains('@color/mesting_coral_launch_light'));
      expect(styles, contains('@color/mesting_coral_launch_dark'));
    }
    expect(
      android12Styles,
      contains(
        '<item name="android:windowSplashScreenBackground">'
        '@color/mesting_coral_launch_light</item>',
      ),
    );
    expect(
      android12Styles,
      contains(
        '<item name="android:windowSplashScreenBackground">'
        '@color/mesting_coral_launch_dark</item>',
      ),
    );
    expect(
      colors,
      contains('<color name="mesting_coral_launch_light">#D95046'),
    );
    expect(colors, contains('<color name="mesting_coral_launch_dark">#17131B'));
    expect(activity, contains('"setLaunchThemeMode"'));
    expect(activity, contains('launcherAlias("CoralLightLauncher")'));
    expect(activity, contains('launcherAlias("CoralDarkLauncher")'));
    expect(activity, contains('PackageManager.DONT_KILL_APP'));
  });

  test(
    'launcher aliases switch atomically without disabling running activities',
    () {
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      final activity = File(
        'android/app/src/main/kotlin/com/mesting/mesting_music/MainActivity.kt',
      ).readAsStringSync();
      final bootstrap = File('lib/main.dart').readAsStringSync();

      expect(
        RegExp(
          r'<category android:name="android\.intent\.category\.LAUNCHER" />',
        ).allMatches(manifest),
        hasLength(5),
      );
      for (final entry in const <String, String>{
        'CoralLauncher': 'CoralBrandActivity',
        'CoralLightLauncher': 'CoralLightBrandActivity',
        'CoralDarkLauncher': 'CoralDarkBrandActivity',
        'MorningMistLauncher': 'MorningMistBrandActivity',
        'MidnightVinylLauncher': 'MidnightVinylBrandActivity',
      }.entries) {
        final alias = RegExp(
          '<activity-alias\\s+android:name="\\.${entry.key}"'
          '[\\s\\S]*?</activity-alias>',
        ).firstMatch(manifest);
        expect(alias, isNotNull, reason: entry.key);
        expect(
          alias!.group(0),
          contains('android:targetActivity=".${entry.value}"'),
          reason: entry.key,
        );

        final target = RegExp(
          '<activity\\s+android:name="\\.${entry.value}"'
          '[\\s\\S]*?</activity>',
        ).firstMatch(manifest);
        expect(target, isNotNull, reason: entry.value);
        expect(target!.group(0), contains('android:exported="false"'));
        expect(
          target.group(0),
          isNot(contains('android.intent.category.LAUNCHER')),
        );
      }

      final launcherComponents = activity.substring(
        activity.indexOf('private fun brandStyleComponents()'),
        activity.indexOf('private fun legacyBrandStyleComponents()'),
      );
      expect(launcherComponents, contains('launcherAlias("CoralLauncher")'));
      expect(
        launcherComponents,
        contains('launcherAlias("MorningMistLauncher")'),
      );
      expect(
        launcherComponents,
        contains('launcherAlias("MidnightVinylLauncher")'),
      );
      expect(launcherComponents, isNot(contains('Activity::class.java')));
      expect(activity, contains('setComponentEnabledSettings('));
      expect(activity, contains('PackageManager.ComponentEnabledSetting('));
      expect(activity, contains('Build.VERSION_CODES.TIRAMISU'));
      expect(activity, contains('PackageManager.SYNCHRONOUS'));
      expect(activity, contains('"brand-style-apply"'));
      expect(activity, contains('catch (_: RuntimeException)'));
      expect(activity, contains('.putString(PENDING_BRAND_STYLE, style)'));
      expect(activity, contains('.commit()'));
      final onCreate = activity.substring(
        activity.indexOf('override fun onCreate'),
        activity.indexOf('override fun onResume'),
      );
      expect(onCreate, isNot(contains('applyPendingBrandStyle()')));
      expect(activity, contains('"applyQueuedBrandStyle"'));
      expect(bootstrap, contains('updateLauncher: false'));
      // Persistence now starts after the startup film and the real app's first
      // frame. Check the callback contract independently of its old position
      // before `return dependencies`, which no longer owns that frame.
      final firstFrameCallbacks = RegExp(
        r'WidgetsBinding\.instance\.addPostFrameCallback\(\(_\)\s*\{([\s\S]*?)\}\);',
      ).allMatches(bootstrap);
      expect(firstFrameCallbacks, isNotEmpty);
      for (final callback in firstFrameCallbacks) {
        expect(
          callback.group(1),
          isNot(contains('AppBrandStyleBridge.applyQueuedStyle()')),
        );
      }
      final currentBrandStyle = activity.substring(
        activity.indexOf('private fun currentBrandStyle()'),
        activity.indexOf('private fun queueBrandStyle('),
      );
      expect(
        currentBrandStyle,
        contains('.remove(PENDING_BRAND_STYLE).commit()'),
      );
      expect(
        currentBrandStyle,
        isNot(contains('getString(PENDING_BRAND_STYLE')),
      );
    },
  );

  test('in-app updater uses a private FileProvider and install permission', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    expect(manifest, contains('android.permission.REQUEST_INSTALL_PACKAGES'));
    expect(manifest, contains('androidx.core.content.FileProvider'));
    expect(manifest, contains(r'${applicationId}.update_files'));
    expect(manifest, contains('android:exported="false"'));
    expect(manifest, contains('@xml/update_file_paths'));

    final paths = File('$resRoot/xml/update_file_paths.xml').readAsStringSync();
    expect(paths, contains('<cache-path'));
    expect(paths, contains('<files-path'));
    expect(paths, contains('path="app_updates/"'));
    expect(paths, isNot(contains('<root-path')));
    expect(paths, isNot(contains('path="."')));
    final activity = File(
      'android/app/src/main/kotlin/com/mesting/mesting_music/MainActivity.kt',
    ).readAsStringSync();
    expect(activity, contains('listOf(cacheDir, filesDir)'));
  });
}

(int, int) _pngSize(File file) {
  final bytes = file.readAsBytesSync();
  expect(
    bytes.take(8),
    orderedEquals(<int>[137, 80, 78, 71, 13, 10, 26, 10]),
    reason: file.path,
  );
  final data = ByteData.sublistView(Uint8List.fromList(bytes));
  return (data.getUint32(16), data.getUint32(20));
}

Future<({int bottom, int left, int right, int top})> _alphaBounds(
  File file,
) async {
  final decoded = await _decodeRgba(file);
  var left = decoded.width;
  var top = decoded.height;
  var right = -1;
  var bottom = -1;
  for (var y = 0; y < decoded.height; y += 1) {
    for (var x = 0; x < decoded.width; x += 1) {
      final alpha = decoded.bytes[(y * decoded.width + x) * 4 + 3];
      if (alpha == 0) {
        continue;
      }
      if (x < left) left = x;
      if (y < top) top = y;
      if (x > right) right = x;
      if (y > bottom) bottom = y;
    }
  }
  expect(right, greaterThanOrEqualTo(left), reason: file.path);
  expect(bottom, greaterThanOrEqualTo(top), reason: file.path);
  return (left: left, top: top, right: right + 1, bottom: bottom + 1);
}

Future<int> _alphaAt(File file, int x, int y) async {
  final decoded = await _decodeRgba(file);
  expect(x, inInclusiveRange(0, decoded.width - 1), reason: file.path);
  expect(y, inInclusiveRange(0, decoded.height - 1), reason: file.path);
  return decoded.bytes[(y * decoded.width + x) * 4 + 3];
}

Future<({Uint8List bytes, int height, int width})> _decodeRgba(
  File file,
) async {
  final codec = await ui.instantiateImageCodec(file.readAsBytesSync());
  try {
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    expect(data, isNotNull, reason: file.path);
    return (
      bytes: data!.buffer.asUint8List(),
      width: frame.image.width,
      height: frame.image.height,
    );
  } finally {
    codec.dispose();
  }
}
