import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/features/themes/startup_style.dart';
import 'package:mesting_music/features/themes/startup_style_picker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('startup choice persists independently across containers', () async {
    SharedPreferences.setMockInitialValues({'music_app_brand_style': 'coral'});
    final prefs = await SharedPreferences.getInstance();
    expect(savedStartupStyle(prefs), StartupStyle.staticOne);
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    await container
        .read(startupStyleProvider.notifier)
        .select(StartupStyle.staticTwo);
    container.dispose();
    final second = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    expect(second.read(startupStyleProvider), StartupStyle.staticTwo);
    await second
        .read(startupStyleProvider.notifier)
        .select(StartupStyle.classic);
    expect(savedStartupStyle(prefs), StartupStyle.classic);
    expect(prefs.getString('music_app_brand_style'), 'coral');
    second.dispose();
  });

  for (final entry in {
    'video-one': StartupStyle.staticTwo,
    'video-two': StartupStyle.staticOne,
    'unknown': StartupStyle.staticOne,
  }.entries) {
    test(
      'saved ${entry.key} falls back to static artwork after upgrade',
      () async {
        SharedPreferences.setMockInitialValues({
          startupStylePreferenceKey: entry.key,
          beta19StartupMigrationKey: true,
        });
        final prefs = await SharedPreferences.getInstance();
        await migrateBeta19StartupStyle(prefs);
        expect(savedStartupStyle(prefs), entry.value);
        final container = ProviderContainer(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        );
        expect(container.read(startupStyleProvider), entry.value);
        container.dispose();
      },
    );
  }

  testWidgets('picker only offers two static styles and classic', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      startupStylePreferenceKey: 'video-one',
    });
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const MaterialApp(home: Scaffold(body: StartupStylePicker())),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('startup-style-static-one')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('startup-style-static-two')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('startup-style-classic')), findsOneWidget);
    expect(find.byKey(const ValueKey('startup-style-video-one')), findsNothing);
    expect(find.byKey(const ValueKey('startup-style-video-two')), findsNothing);
    expect(
      find.byKey(const ValueKey('startup-style-animated-one')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('startup-style-animated-two')),
      findsNothing,
    );
    expect(find.text('唱片派对'), findsNothing);
    expect(find.byType(IconButton), findsNWidgets(3));
  });
}
