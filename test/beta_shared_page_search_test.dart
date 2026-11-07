import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mesting_music/core/audio/playback_providers.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mesting_music/shared/widgets/beta_bottom_search.dart';
import 'package:mesting_music/shared/widgets/beta_page_search_layout.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'support/no_music_account_fixture.dart';

void main() {
  setUpAll(LiquidGlassWidgets.initialize);
  late SharedPreferences preferences;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
  });
  testWidgets('standalone page has one official glass search at the bottom', (
    tester,
  ) async {
    String? submitted, changed;
    final controller = BetaPageSearchController(
      hintText: '筛选本地内容',
      onSubmitted: (v) => submitted = v,
      onCleared: () => changed = '',
      onChanged: (v) => changed = v,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        builder: (_, child) => ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(preferences),
            platformAccountProvider.overrideWith(NoMusicAccountFixture.new),
            currentMediaItemProvider.overrideWith((ref) => Stream.value(null)),
          ],
          child: child!,
        ),
        home: Scaffold(
          body: BetaPageSearchLayout(
            controller: controller,
            child: const Center(child: Text('内容')),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(GlassTabBar), findsOneWidget);
    expect(find.byType(EditableText), findsOneWidget);
    expect(tester.getCenter(find.byType(EditableText)).dy, greaterThan(450));
    controller.setActive(true);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText), '本地');
    await tester.pump();
    expect(changed, '本地');
    expect(controller.hasResults, isTrue);
    await tester.tap(find.byKey(const ValueKey('search-submit-action')));
    await tester.pump();
    expect(submitted, '本地');
    controller.clearResults();
    await tester.pump();
    expect(changed, '');
    expect(controller.text.text, '');
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('a shell registration reuses its field without making another', (
    tester,
  ) async {
    final host = BetaBottomSearchHost(
      location: '/music',
      openMusicSearch: () {},
    );
    final controller = BetaPageSearchController(
      hintText: '查找功能',
      onSubmitted: (_) {},
      onCleared: () {},
    );
    addTearDown(host.dispose);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        builder: (_, child) => ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(preferences),
            platformAccountProvider.overrideWith(NoMusicAccountFixture.new),
            currentMediaItemProvider.overrideWith((ref) => Stream.value(null)),
          ],
          child: child!,
        ),
        home: BetaBottomSearchScope(
          host: host,
          child: BetaPageSearchLayout(
            controller: controller,
            child: const Center(child: Text('内容')),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(host.current, same(controller));
    expect(find.byType(GlassTabBar), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(host.current, isNull);
  });
  testWidgets('keyboard lift is applied once when a scaffold already resizes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    final controller = BetaPageSearchController(
      hintText: '查找',
      onSubmitted: (_) {},
      onCleared: () {},
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        builder: (_, child) => ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(preferences),
            platformAccountProvider.overrideWith(NoMusicAccountFixture.new),
            currentMediaItemProvider.overrideWith((ref) => Stream.value(null)),
          ],
          child: child!,
        ),
        home: Scaffold(
          body: BetaPageSearchLayout(
            controller: controller,
            child: const Center(child: Text('内容')),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    await tester.pump(const Duration(milliseconds: 500));
    final field = tester.getRect(find.byType(EditableText));
    expect(field.bottom, lessThanOrEqualTo(564));
    expect(field.center.dy, greaterThan(430));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
