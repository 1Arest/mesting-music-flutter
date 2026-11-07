import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/features/themes/music_theme_tokens.dart';
import 'package:mesting_music/shared/widgets/liquid_glass_sheet.dart';

void main() {
  testWidgets('liquid glass sheet adds blur, gradient and custom handle', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.pink),
          extensions: [MusicThemeTokens.forBrightness(Brightness.light)],
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => showLiquidGlassBottomSheet<void>(
                  context: context,
                  showDragHandle: true,
                  builder: (_) => const SizedBox(
                    height: 220,
                    child: Center(child: Text('液态玻璃抽屉')),
                  ),
                ),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    expect(find.byKey(liquidGlassSheetSurfaceKey), findsOneWidget);
    final blur = tester.widget<BackdropFilter>(
      find.descendant(
        of: find.byKey(liquidGlassSheetSurfaceKey),
        matching: find.byType(BackdropFilter),
      ),
    );
    expect(blur.filter, isA<ImageFilter>());
    expect(find.text('液态玻璃抽屉'), findsOneWidget);
  });

  testWidgets('dark liquid glass omits the bright top edge', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          brightness: Brightness.dark,
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.pink,
            brightness: Brightness.dark,
          ),
          extensions: [MusicThemeTokens.forBrightness(Brightness.dark)],
        ),
        home: const Scaffold(
          body: LiquidGlassSurface(child: SizedBox(height: 220)),
        ),
      ),
    );

    final surface = tester.widget<DecoratedBox>(
      find.byKey(liquidGlassSurfaceBodyKey),
    );
    final decoration = surface.decoration as BoxDecoration;
    final border = decoration.border! as Border;
    expect(border.top, BorderSide.none);
  });

  test('all modal bottom sheets use the shared liquid glass route', () {
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.path.endsWith('liquid_glass_sheet.dart')) continue;
      // These content sheets deliberately remain opaque. Beta.10 login-method
      // buttons own independent premium glass layers inside their stable sheet,
      // so the sheet itself must not add a second nested glass surface.
      if (entity.path.endsWith('playlist_editor_dialog.dart')) continue;
      if (entity.path.endsWith('beta_welcome_page.dart')) continue;
      // The update route selects the channel's existing material: Beta owns
      // one premium BetaGlassMenuSurface; stable retains the shared route.
      // Its rendered states and navigation are exercised by release_101_ui_test.
      if (entity.path.endsWith('app_update_sheet.dart')) continue;
      if (entity.readAsStringSync().contains('showModalBottomSheet')) {
        offenders.add(entity.path);
      }
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  test('the left navigation panel uses the liquid glass surface', () {
    final source = File(
      'lib/features/player/presentation/music_hub_top_bar.dart',
    ).readAsStringSync();
    expect(source, contains('liquidGlassSidePanelSurfaceKey'));
    expect(source, contains('LiquidGlassSurface('));
  });

  test(
    'the playback queue does not cover the shared glass with an old panel',
    () {
      final source = File(
        'lib/features/queue/presentation/queue_page.dart',
      ).readAsStringSync();
      expect(source, contains('liquidGlassQueuePageSurfaceKey'));
      expect(source, contains('LiquidGlassSurface('));
      expect(source, isNot(contains('ImageFilter.blur')));
      expect(
        source,
        isNot(contains('tokens.glassStrong.withValues(alpha: .95)')),
      );
    },
  );
}
