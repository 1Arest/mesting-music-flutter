import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/features/player/presentation/shinchan_progress_walker.dart';

void main() {
  test('all Shinchan presets keep their original weather mapping', () {
    expect(
      shinchanWeatherForPreset('kasukabe-sky'),
      ShinchanProgressWeather.sun,
    );
    expect(
      shinchanWeatherForPreset('family-picnic'),
      ShinchanProgressWeather.breeze,
    );
    expect(
      shinchanWeatherForPreset('sunset-road'),
      ShinchanProgressWeather.sunset,
    );
    expect(
      shinchanWeatherForPreset('starry-radio'),
      ShinchanProgressWeather.night,
    );
    expect(
      shinchanWeatherForPreset('crayon-room'),
      ShinchanProgressWeather.breeze,
    );
    expect(
      shinchanWeatherForPreset('rainy-day'),
      ShinchanProgressWeather.drizzle,
    );
    expect(
      shinchanWeatherForPreset('midnight-cinema'),
      ShinchanProgressWeather.night,
    );
    expect(
      shinchanWeatherForPreset('motion-walk'),
      ShinchanProgressWeather.sun,
    );
    expect(
      shinchanWeatherForPreset('motion-rain'),
      ShinchanProgressWeather.storm,
    );
    expect(
      shinchanWeatherForPreset('motion-parade'),
      ShinchanProgressWeather.parade,
    );
  });

  test('Shinchan and Shiro walking frames are bundled', () {
    const frames = <String>[
      'assets/images/theme_gallery/progress-shinchan-walk-stride.png',
      'assets/images/theme_gallery/progress-shinchan-walk-mid.png',
      'assets/images/theme_gallery/progress-shinchan-walk-pass.png',
      'assets/images/theme_gallery/progress-shiro-walk-stride.png',
      'assets/images/theme_gallery/progress-shiro-walk-mid.png',
      'assets/images/theme_gallery/progress-shiro-walk-pass.png',
    ];

    for (final frame in frames) {
      final file = File(frame);
      expect(file.existsSync(), isTrue, reason: frame);
      expect(file.lengthSync(), greaterThan(0), reason: frame);
    }
  });

  testWidgets(
    'original storm animation paints through both lightning flashes',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Center(
            child: RepaintBoundary(
              child: ShinchanProgressWalker(
                presetId: 'motion-rain',
                playing: true,
              ),
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 3460));
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(milliseconds: 240));
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
