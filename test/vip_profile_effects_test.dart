import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mesting_music/features/music_platform/netease/netease_playback_options.dart';
import 'package:mesting_music/features/music_platform/presentation/beta_personal_profile.dart';
import 'package:mesting_music/features/profile/presentation/vip_profile_effects.dart';
import 'support/personal_profile_fixture.dart';

void main() {
  setUpAll(LiquidGlassWidgets.initialize);

  Widget host(
    VipEffectAnchorHandle anchor, {
    bool reduced = false,
    bool enabled = true,
    bool tickers = true,
    VoidCallback? onTap,
  }) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
        size: const Size(390, 844),
        disableAnimations: reduced,
      ),
      child: TickerMode(
        enabled: tickers,
        child: Scaffold(
          body: VipProfileEffects(
            enabled: enabled,
            avatarKey: anchor,
            child: ListView(
              children: [
                const SizedBox(height: 120),
                Center(
                  child: GestureDetector(
                    onTap: onTap,
                    behavior: HitTestBehavior.opaque,
                    child: VipEffectAnchor(
                      handle: anchor,
                      child: const SizedBox(
                        key: ValueKey('avatar'),
                        width: 104,
                        height: 104,
                      ),
                    ),
                  ),
                ),
                const VipGoldText(child: Text('VIP 昵称')),
                const SizedBox(height: 1600),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets(
    'continuous effects preserve avatar taps and pause for reduced motion',
    (tester) async {
      final key = VipEffectAnchorHandle();
      var taps = 0;
      await tester.pumpWidget(host(key, onTap: () => taps++));
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.binding.hasScheduledFrame, isTrue);
      await tester.tap(
        find
            .ancestor(
              of: find.byKey(const ValueKey('avatar')),
              matching: find.byType(GestureDetector),
            )
            .first,
      );
      expect(taps, 1);
      await tester.pumpWidget(host(key, reduced: true));
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(find.byType(VipGoldText), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('offscreen headers and covered routes stop animation work', (
    tester,
  ) async {
    final key = VipEffectAnchorHandle();
    await tester.pumpWidget(host(key));
    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.drag(find.byType(ListView), const Offset(0, 700));
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pumpWidget(host(key, tickers: false));
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'background pauses and foreground resumes the same effect clock',
    (tester) async {
      final key = VipEffectAnchorHandle();
      await tester.pumpWidget(host(key));
      await tester.pump(const Duration(milliseconds: 200));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('local SVIP gates gold identity and UID and handles large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fixture = await PersonalProfileFixture.create();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await fixture.dispose();
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: fixture.container,
        child: MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 800),
              textScaler: TextScaler.linear(2),
              disableAnimations: true,
            ),
            child: const Scaffold(body: BetaPersonalProfile()),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('至尊SVIP'), findsOneWidget);
    expect(find.text('ID 7001'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await fixture.container
        .read(neteaseLocalMembershipSettingsProvider.notifier)
        .setEnabled('7001', false);
    await tester.pumpAndSettle();
    expect(find.byType(VipGoldText), findsNothing);
    expect(find.text('ID 7001'), findsNothing);
    expect(find.text('固定测试账号'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
