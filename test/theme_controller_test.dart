import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/features/player/player_visual_style.dart';
import 'package:mesting_music/features/themes/theme_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('已保存主题决定下一次品牌启动页明暗', () async {
    for (final entry in <String, ThemeMode>{
      'classic': ThemeMode.light,
      'classic-dark': ThemeMode.dark,
      'classic-system': ThemeMode.system,
      'kasukabe-sky': ThemeMode.light,
      'starry-radio': ThemeMode.dark,
    }.entries) {
      SharedPreferences.setMockInitialValues({
        musicThemePreferenceKey: entry.key,
      });
      final preferences = await SharedPreferences.getInstance();
      expect(savedMusicThemeMode(preferences), entry.value, reason: entry.key);
    }
  });

  test('首次安装默认使用经典体系并跟随系统深浅模式', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final lightContainer = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        systemBrightnessProvider.overrideWithValue(Brightness.light),
      ],
    );
    addTearDown(lightContainer.dispose);

    expect(lightContainer.read(musicThemeProvider).id, 'classic-system');
    expect(lightContainer.read(effectiveMusicThemeProvider).id, 'classic');
    expect(
      lightContainer.read(themeVisualSettingsProvider).progressStyle,
      ProgressDecoration.classic,
    );
    expect(
      lightContainer.read(themeVisualSettingsProvider).progressCharacter,
      ProgressDecoration.classic,
    );
    expect(
      lightContainer.read(themeVisualSettingsProvider).showIpDecoration,
      isFalse,
    );
    expect(
      lightContainer.read(playerVisualStyleProvider),
      PlayerVisualStyle.classic,
    );

    final darkContainer = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        systemBrightnessProvider.overrideWithValue(Brightness.dark),
      ],
    );
    addTearDown(darkContainer.dispose);
    expect(darkContainer.read(musicThemeProvider).id, 'classic-system');
    expect(darkContainer.read(effectiveMusicThemeProvider).id, 'classic-dark');
  });

  test('已有用户保存的主题样式不会被首次安装默认值覆盖', () async {
    SharedPreferences.setMockInitialValues({
      'music_theme_preset': 'kasukabe-sky',
      'music_ip_decoration': true,
      'music_progress_style': 'kuromi',
      'music_progress_character': 'helloKitty',
      'player_visual_style': 'lyricStage',
    });
    final preferences = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
    );
    addTearDown(container.dispose);

    expect(container.read(musicThemeProvider).id, 'kasukabe-sky');
    expect(
      container.read(themeVisualSettingsProvider).progressStyle,
      ProgressDecoration.kuromi,
    );
    expect(
      container.read(themeVisualSettingsProvider).progressCharacter,
      ProgressDecoration.helloKitty,
    );
    expect(
      container.read(themeVisualSettingsProvider).showIpDecoration,
      isTrue,
    );
    expect(
      container.read(playerVisualStyleProvider),
      PlayerVisualStyle.lyricStage,
    );
  });

  test('跟随系统主题会解析为当前系统深浅模式', () async {
    SharedPreferences.setMockInitialValues({
      'music_theme_preset': 'classic-system',
    });
    final preferences = await SharedPreferences.getInstance();

    final lightContainer = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        systemBrightnessProvider.overrideWithValue(Brightness.light),
      ],
    );
    addTearDown(lightContainer.dispose);
    expect(lightContainer.read(musicThemeProvider).id, 'classic-system');
    expect(lightContainer.read(effectiveMusicThemeProvider).id, 'classic');

    final darkContainer = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        systemBrightnessProvider.overrideWithValue(Brightness.dark),
      ],
    );
    addTearDown(darkContainer.dispose);
    expect(darkContainer.read(musicThemeProvider).id, 'classic-system');
    expect(darkContainer.read(effectiveMusicThemeProvider).id, 'classic-dark');
  });

  test('跟随系统选择会持久化', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        systemBrightnessProvider.overrideWithValue(Brightness.light),
      ],
    );
    addTearDown(container.dispose);

    await container.read(musicThemeProvider.notifier).select('classic-system');

    expect(container.read(musicThemeProvider).followsSystem, isTrue);
    expect(preferences.getString('music_theme_preset'), 'classic-system');
  });

  testWidgets('系统深浅模式变化会立即更新生效主题', (tester) async {
    SharedPreferences.setMockInitialValues({
      'music_theme_preset': 'classic-system',
    });
    final preferences = await SharedPreferences.getInstance();
    tester.binding.platformDispatcher.platformBrightnessTestValue =
        Brightness.light;
    addTearDown(
      tester.binding.platformDispatcher.clearPlatformBrightnessTestValue,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
        child: Consumer(
          builder: (context, ref, _) => MaterialApp(
            home: Text(ref.watch(effectiveMusicThemeProvider).id),
          ),
        ),
      ),
    );
    expect(find.text('classic'), findsOneWidget);

    tester.binding.platformDispatcher.platformBrightnessTestValue =
        Brightness.dark;
    await tester.pump();

    expect(find.text('classic-dark'), findsOneWidget);
    expect(find.text('classic'), findsNothing);
  });
}
