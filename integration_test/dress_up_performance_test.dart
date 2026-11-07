import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/features/themes/theme_gallery_page.dart';
import 'package:mesting_music/shared/widgets/liquid_glass_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('dress-up drawer opens without a full-screen live blur layer', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF221923), Color(0xFF4B2835)],
                  ),
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FilledButton(
                        key: const ValueKey('open-dress-up'),
                        onPressed: () => showDressUpCenterSheet(context),
                        child: const Text('打开装扮'),
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton(
                        key: const ValueKey('open-baseline'),
                        onPressed: () => showModalBottomSheet<void>(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: Colors.transparent,
                          elevation: 0,
                          builder: (context) => FractionallySizedBox(
                            heightFactor: .965,
                            child: ColoredBox(
                              color: const Color(0xFF2B222E),
                              child: Align(
                                alignment: Alignment.topRight,
                                child: IconButton(
                                  key: const ValueKey('close-baseline'),
                                  onPressed: Navigator.of(context).pop,
                                  icon: const Icon(Icons.close_rounded),
                                ),
                              ),
                            ),
                          ),
                        ),
                        child: const Text('打开基线抽屉'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final warmup = warmUpDressUpAssets(
      tester.element(find.byKey(const ValueKey('open-dress-up'))),
    );
    for (var frame = 0; frame < 8; frame += 1) {
      await tester.pump(const Duration(milliseconds: 16));
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
    await warmup;

    await binding.watchPerformance(() async {
      await tester.tap(find.byKey(const ValueKey('open-baseline')));
      await _pumpTransition(tester);
    }, reportKey: 'plain_sheet_open');
    await tester.tap(find.byKey(const ValueKey('close-baseline')));
    await tester.pumpAndSettle();

    await binding.watchPerformance(() async {
      await tester.tap(find.byKey(const ValueKey('open-dress-up')));
      await _pumpTransition(tester);
    }, reportKey: 'dress_up_open');

    final surface = find.byKey(liquidGlassSheetSurfaceKey);
    expect(surface, findsOneWidget);
    final surfaceWidget = tester.widget<LiquidGlassSurface>(surface);
    expect(surfaceWidget.blurSigma, 0);
    expect(surfaceWidget.showShadow, isFalse);
    expect(surfaceWidget.showDecorativeGlow, isFalse);
    expect(
      find.byKey(const ValueKey('theme-gallery-sheet-content')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('theme-gallery-glass-panel')),
      findsNothing,
    );
    expect(find.byType(BackdropFilter), findsNothing);

    // Printed into the device test log and written by the integration driver.
    // ignore: avoid_print
    print('[DressUpPerformance] ${binding.reportData?['dress_up_open']}');
  });
}

Future<void> _pumpTransition(WidgetTester tester) async {
  for (var frame = 0; frame < 24; frame += 1) {
    await tester.pump(const Duration(milliseconds: 16));
    await Future<void>.delayed(const Duration(milliseconds: 16));
  }
  await tester.pumpAndSettle();
}
