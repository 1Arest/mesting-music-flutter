import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/features/player/presentation/nailong_progress.dart';
import 'package:mesting_music/features/player/presentation/ip_progress_decoration.dart';
import 'package:mesting_music/features/themes/music_theme_preset.dart';
import 'package:mesting_music/features/themes/theme_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Nailong matches the visible Shinchan body in both control layouts', () {
    for (final width in [56.0, 104.0]) {
      final size = progressCompanionSize(
        MusicThemeIp.nailong,
        shinchanWidth: width,
      );
      expect(size.height * 282 / 301, closeTo(width * 236 / 502, .01));
      expect(size.height, lessThan(59));
      final top = progressCompanionTop(
        MusicThemeIp.nailong,
        companionSize: size,
      );
      expect(top + size.height, 24 - ipProgressTrackHeight / 2);
    }
    expect(progressDecorationSeries(ProgressDecoration.nailong), '奶龙');
    expect(
      decorationIp(ProgressDecoration.nailong, musicThemePresets.first),
      MusicThemeIp.nailong,
    );
  });

  testWidgets('the packaged clip is animated and transparent', (tester) async {
    await tester.runAsync(() async {
      final data = await rootBundle.load(
        'assets/images/theme_gallery/nailong-laugh.webp',
      );
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      expect(codec.frameCount, 72);
      final frame = await codec.getNextFrame();
      final bytes = (await frame.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();
      expect(bytes[3], 0);
      expect(frame.duration.inMilliseconds, greaterThan(0));
      frame.image.dispose();
      codec.dispose();
    });
  });

  testWidgets(
    'Nailong shows a frame while paused and freezes when playback pauses',
    (tester) async {
      Widget host(bool playing) => MaterialApp(
        home: SizedBox(
          width: 40,
          height: 60,
          child: NailongProgressCompanion(playing: playing),
        ),
      );
      await tester.pumpWidget(host(false));
      for (var i = 0; i < 40; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pump(const Duration(milliseconds: 16));
        if (tester.widget<RawImage>(find.byType(RawImage)).image != null) break;
      }
      final before = tester.widget<RawImage>(find.byType(RawImage)).image;
      expect(before, isNotNull);
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        tester.widget<RawImage>(find.byType(RawImage)).image,
        same(before),
      );
      await tester.pumpWidget(host(true));
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpWidget(host(false));
      await tester.pump();
      final paused = tester.widget<RawImage>(find.byType(RawImage)).image;
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        tester.widget<RawImage>(find.byType(RawImage)).image,
        same(paused),
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('rail motion stops for paused playback and reduced motion', (
    tester,
  ) async {
    Widget host(bool playing, {bool reduced = false}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduced),
        child: IpProgressSliderTheme(
          ip: MusicThemeIp.nailong,
          playing: playing,
          data: const SliderThemeData(trackHeight: 6),
          child: Builder(
            builder: (context) =>
                Material(child: Slider(value: .6, onChanged: (_) {})),
          ),
        ),
      ),
    );
    await tester.pumpWidget(host(true));
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    await tester.pumpWidget(host(false));
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(host(true, reduced: true));
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(const SizedBox());
  });
}
