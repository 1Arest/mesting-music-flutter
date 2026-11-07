import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mesting_music/features/experience/presentation/player_more_menu.dart';
import 'package:mesting_music/shared/widgets/beta_glass_popover.dart';

const _surface = ValueKey('beta13-glass-menu-surface');

void main() {
  setUpAll(LiquidGlassWidgets.initialize);

  testWidgets(
    'tall player menu starts dismissing promptly and dispatches after closing',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final selected = <String>[];
      await tester.pumpWidget(
        LiquidGlassWidgets.wrap(
          adaptiveQuality: false,
          child: MaterialApp(
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.only(top: 36, right: 16),
                child: Align(
                  alignment: Alignment.topRight,
                  child: PlayerMoreMenu(
                    trigger: const Text('更多'),
                    groups: [
                      for (var group = 0; group < 3; group++)
                        [
                          for (var item = 0; item < 3; item++)
                            PlayerMenuAction(
                              '$group-$item',
                              '歌曲操作 $group-$item',
                              CupertinoIcons.music_note,
                            ),
                        ],
                    ],
                    onSelected: selected.add,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('更多'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 96));
      final early = tester.getRect(find.byKey(_surface));
      await tester.pump(BetaMenuMotion.player.openDuration);
      final complete = tester.getRect(find.byKey(_surface));
      expect(early.height, greaterThan(complete.height * .55));
      expect(
        tester.widget<BetaLiquidMenu>(find.byType(BetaLiquidMenu)).motion,
        same(BetaMenuMotion.player),
      );
      final glass = tester.widget<GlassContainer>(find.byKey(_surface));
      expect(glass.quality, GlassQuality.premium);

      await tester.tap(find.text('歌曲操作 0-0'));
      await tester.pump();
      final atDismiss = tester.getRect(find.byKey(_surface));
      expect(atDismiss.height, closeTo(complete.height, .01));
      expect(selected, isEmpty);
      await tester.pump(const Duration(milliseconds: 55));
      final closing = tester.getRect(find.byKey(_surface));
      expect(
        closing.height,
        lessThan(complete.height * .7),
        reason:
            'Closing must not wait at the near-static end of the opening curve.',
      );
      expect(selected, isEmpty);
      for (final ancestor
          in find
              .ancestor(
                of: find.byKey(_surface),
                matching: find.byType(FadeTransition),
              )
              .evaluate()) {
        expect((ancestor.widget as FadeTransition).opacity.value, 1);
      }
      await tester.pump(BetaMenuMotion.player.closeDuration);
      await tester.pump();
      expect(selected, ['0-0']);
      expect(find.byKey(_surface), findsNothing);
      // A quick subsequent opening gets one fresh route, without a leftover
      // closing menu or stale selection callback.
      await tester.tap(find.text('更多'));
      await tester.pump();
      await tester.pump(BetaMenuMotion.player.openDuration);
      expect(find.byType(BetaLiquidMenu), findsOneWidget);
      expect(selected, ['0-0']);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'player menu can reverse during opening without moving or rebuilding its rows',
    (tester) async {
      final motion = AnimationController(
        vsync: tester,
        duration: BetaMenuMotion.player.openDuration,
        reverseDuration: BetaMenuMotion.player.closeDuration,
      );
      var builds = 0;
      try {
        await tester.pumpWidget(
          LiquidGlassWidgets.wrap(
            adaptiveQuality: false,
            child: MaterialApp(
              home: Scaffold(
                body: Builder(
                  builder: (context) => BetaLiquidMenu(
                    animation: motion,
                    motion: BetaMenuMotion.player,
                    layout: BetaMenuLayout(
                      anchor: const Rect.fromLTWH(720, 40, 48, 48),
                      media: MediaQuery.of(context),
                      width: 280,
                      fromInnerEdge: true,
                    ),
                    child: Builder(
                      builder: (_) {
                        builds++;
                        return const SizedBox(width: 280, height: 440);
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        for (final elapsed in [40, 90, 180]) {
          motion.value = 0;
          motion.forward();
          await tester.pump();
          await tester.pump(Duration(milliseconds: elapsed));
          final before = tester.getRect(find.byKey(_surface));
          motion.reverse();
          await tester.pump();
          final after = tester.getRect(find.byKey(_surface));
          expect((after.topLeft - before.topLeft).distance, lessThan(.01));
          expect(after.size.width, closeTo(before.width, .01));
          expect(after.size.height, closeTo(before.height, .01));
          await tester.pump(const Duration(milliseconds: 15));
          expect(
            tester.getRect(find.byKey(_surface)).height,
            lessThan(before.height),
          );
        }
        expect(builds, 1);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        motion.dispose();
      }
    },
  );
}
