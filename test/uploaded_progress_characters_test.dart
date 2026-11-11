import 'dart:io';
import 'package:flutter/services.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/features/player/presentation/ip_progress_decoration.dart';
import 'package:mesting_music/features/player/presentation/uploaded_progress_portrait.dart';
import 'package:mesting_music/features/themes/music_theme_preset.dart';
import 'package:mesting_music/features/themes/theme_controller.dart';
import 'package:mesting_music/features/themes/theme_gallery_page.dart';
import 'package:mesting_music/features/themes/app_theme.dart';

const uploaded = [
  ProgressDecoration.myMelody,
  ProgressDecoration.usagi,
  ProgressDecoration.chiikawa,
  ProgressDecoration.hachiware,
  ProgressDecoration.puppyWhite,
  ProgressDecoration.puppyGray,
  ProgressDecoration.cinnamoroll,
  ProgressDecoration.sleepingKirby,
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'all uploaded styles and characters persist independently across containers',
    () async {
      for (final style in uploaded) {
        for (final character in uploaded) {
          SharedPreferences.setMockInitialValues({});
          final prefs = await SharedPreferences.getInstance();
          ProviderContainer create() => ProviderContainer(
            overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
          );
          final first = create();
          await first
              .read(themeVisualSettingsProvider.notifier)
              .setProgressStyle(style);
          await first
              .read(themeVisualSettingsProvider.notifier)
              .setProgressCharacter(character);
          first.dispose();
          final restored = create();
          final settings = restored.read(themeVisualSettingsProvider);
          expect(settings.progressStyle, style);
          expect(settings.progressCharacter, character);
          final ip = decorationIp(character, musicThemePresets.first);
          expect(isUploadedProgressIp(ip), true);
          expect(File(companionAssetForIp(ip)!).existsSync(), true);
          expect(
            progressCharacterAsset(character, musicThemePresets.first),
            companionAssetForIp(ip),
          );
          restored.dispose();
        }
      }
    },
  );

  test(
    'IP families include existing characters and do not create empty background categories',
    () {
      for (final item in [
        ProgressDecoration.helloKitty,
        ProgressDecoration.kuromi,
        ProgressDecoration.myMelody,
        ProgressDecoration.cinnamoroll,
      ]) {
        expect(progressDecorationSeries(item), '三丽鸥');
      }
      for (final item in [
        ProgressDecoration.usagi,
        ProgressDecoration.chiikawa,
        ProgressDecoration.hachiware,
      ]) {
        expect(progressDecorationSeries(item), '吉伊卡哇');
      }
      expect(
        progressDecorationSeries(ProgressDecoration.puppyWhite),
        progressDecorationSeries(ProgressDecoration.puppyGray),
      );
      for (final category in musicThemeCategories) {
        expect(musicThemePresets.where((p) => p.ip == category), isNotEmpty);
      }
      expect(musicThemeCategories.any(isUploadedProgressIp), false);
    },
  );

  for (final character in uploaded) {
    final ip = decorationIp(character, musicThemePresets.first);
    testWidgets(
      '${character.name} decodes and fits at slider size in light and dark themes',
      (tester) async {
        for (final brightness in Brightness.values) {
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(brightness: brightness),
              home: MediaQuery(
                data: const MediaQueryData(disableAnimations: true),
                child: Center(
                  child: IpProgressCompanion(ip: ip, playing: true),
                ),
              ),
            ),
          );
          await tester.runAsync(() async {
            final bytes = await rootBundle.load(companionAssetForIp(ip)!);
            expect(bytes.lengthInBytes, greaterThan(1000));
            await precacheImage(
              ResizeImage(AssetImage(companionAssetForIp(ip)!), width: 256),
              tester.element(find.byType(UploadedProgressPortrait)),
            );
          });
          await tester.pumpAndSettle();
          final portrait = find.byType(UploadedProgressPortrait);
          expect(portrait, findsOneWidget);
          final size = tester.getSize(portrait);
          expect(size.width, lessThanOrEqualTo(36));
          expect(size.height, lessThanOrEqualTo(28));
          expect(
            tester.widget<Image>(find.byType(Image)).image,
            isA<ResizeImage>(),
          );
          expect(tester.takeException(), isNull);
          expect(tester.binding.transientCallbackCount, 0);
        }
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'grouped role and rail choices have distinct previews and save independently',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildMestingTheme(musicThemePresets.first),
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) {
                  final settings = ref.watch(themeVisualSettingsProvider);
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: ProgressDecorationPicker(
                          selected: settings.progressStyle,
                          character: false,
                          onSelected: (v) => ref
                              .read(themeVisualSettingsProvider.notifier)
                              .setProgressStyle(v),
                        ),
                      ),
                      Expanded(
                        child: ProgressDecorationPicker(
                          selected: settings.progressCharacter,
                          character: true,
                          onSelected: (v) => ref
                              .read(themeVisualSettingsProvider.notifier)
                              .setProgressCharacter(v),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final value in uploaded) {
        expect(
          find.descendant(
            of: find.byType(InkWell),
            matching: find.text(progressDecorationLabel(value)),
          ),
          findsOneWidget,
        );
        expect(
          find.text('${progressDecorationLabel(value)}轨道'),
          findsOneWidget,
        );
      }
      expect(find.text('三丽鸥'), findsNWidgets(2));
      expect(find.text('线条小狗'), findsNWidgets(2));
      await tester.tap(find.byKey(const ValueKey('progress-track-myMelody')));
      await tester.pumpAndSettle();
      expect(
        container.read(themeVisualSettingsProvider).progressStyle,
        ProgressDecoration.myMelody,
      );
      expect(
        container.read(themeVisualSettingsProvider).progressCharacter,
        ProgressDecoration.classic,
      );
      await tester.tap(
        find.byKey(const ValueKey('progress-character-hachiware')),
      );
      await tester.pumpAndSettle();
      expect(
        container.read(themeVisualSettingsProvider).progressStyle,
        ProgressDecoration.myMelody,
      );
      expect(
        container.read(themeVisualSettingsProvider).progressCharacter,
        ProgressDecoration.hachiware,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      container.dispose();
    },
  );

  testWidgets('uploaded companion animation stops when playback pauses', (
    tester,
  ) async {
    Widget companion(bool playing) => MaterialApp(
      home: Center(
        child: IpProgressCompanion(
          ip: MusicThemeIp.sleepingKirby,
          playing: playing,
        ),
      ),
    );
    await tester.pumpWidget(companion(true));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    await tester.pumpWidget(companion(false));
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(const SizedBox());
  });
}
