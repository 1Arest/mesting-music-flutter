import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mesting_music/features/music_platform/presentation/beta_personal_profile.dart';
import 'package:mesting_music/features/music_platform/presentation/platform_avatar.dart';
import 'package:mesting_music/features/themes/app_theme.dart';
import 'package:mesting_music/features/themes/music_theme_preset.dart';
import 'package:mesting_music/shared/widgets/artwork_image.dart';
import 'package:mesting_music/shared/widgets/beta_glass_controls.dart';
import 'package:mesting_music/shared/widgets/beta_page_motion.dart';
import 'package:mesting_music/shared/widgets/beta_scroll_behavior.dart';
import 'support/personal_profile_fixture.dart';
import 'support/pump_artwork_ready.dart';

/// The membership plate intentionally runs while visible. Sample a bounded
/// settling window so scroll/route tests retain that real motion rather than
/// waiting forever for an animation that is designed to keep running.
Future<void> settle188(WidgetTester tester) async {
  for (var frame = 0; frame < 12; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(() => LiquidGlassWidgets.initialize());

  Future<(PersonalProfileFixture, GoRouter)> mount(
    WidgetTester tester, {
    bool dark = false,
    bool narrow = false,
  }) async {
    final fixture = await PersonalProfileFixture.create();
    final router = GoRouter(
      initialLocation: '/music/library',
      routes: [
        GoRoute(
          path: '/music/library',
          builder: (_, _) =>
              const Scaffold(body: Center(child: Text('固定音乐库入口'))),
        ),
        GoRoute(
          path: '/profile',
          pageBuilder: (context, state) => CustomTransitionPage<void>(
            key: state.pageKey,
            child: const Scaffold(body: BetaPersonalProfile()),
            transitionDuration: const Duration(milliseconds: 360),
            transitionsBuilder: (_, a, _, child) =>
                BetaPageMotion(animation: a, child: child),
          ),
        ),
      ],
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      router.dispose();
      await fixture.dispose();
    });
    tester.view.devicePixelRatio = 2.625;
    tester.view.physicalSize = Size(narrow ? 840 : 1080, 2400);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: fixture.container,
        child: MaterialApp.router(
          routerConfig: router,
          theme: buildMestingTheme(
            musicThemePresetById(dark ? 'classic-dark' : 'classic'),
          ),
          scrollBehavior: const BetaScrollBehavior(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(narrow ? 1.3 : 1)),
            child: child!,
          ),
        ),
      ),
    );
    router.go('/profile');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await pumpArtworkReady(tester);
    await settle188(tester);
    return (fixture, router);
  }

  for (final dark in [false, true]) {
    for (final narrow in [false, true]) {
      testWidgets(
        'complete NetEase My page normal/fast/reverse scrolling dark=$dark narrow=$narrow',
        (tester) async {
          final (_, router) = await mount(tester, dark: dark, narrow: narrow);
          expect(find.text('674 首喜欢  ·  5 个歌单'), findsNothing);
          expect(
            find.byKey(const ValueKey('netease-personal-statistics')),
            findsOneWidget,
          );
          expect(find.text('创建的歌单 · 2'), findsOneWidget);
          expect(find.text('收藏的歌单 · 2', skipOffstage: false), findsOneWidget);
          expect(find.text('Lv.9'), findsOneWidget);
          expect(find.byType(BetaGlassButton), findsNWidgets(6));
          final scroll = find.byType(CustomScrollView);
          for (final duration in [
            const Duration(milliseconds: 360),
            const Duration(milliseconds: 80),
          ]) {
            for (var i = 0; i < 6; i++) {
              await tester.timedDrag(scroll, const Offset(0, -520), duration);
              await tester.pump(const Duration(milliseconds: 180));
              await tester.timedDrag(scroll, const Offset(0, 520), duration);
              await tester.pump(const Duration(milliseconds: 180));
            }
          }
          await settle188(tester);
          expect(router.routeInformationProvider.value.uri.path, '/profile');
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'offscreen heading and quick controls have no viewport paint extent',
    (tester) async {
      await mount(tester);
      final position = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;
      position.jumpTo(760);
      await tester.pump();
      for (final key in ['profile-heading-sliver', 'profile-quick-sliver']) {
        final sliver = tester.renderObject<RenderSliverToBoxAdapter>(
          find.byKey(ValueKey(key), skipOffstage: false),
        );
        expect(sliver.geometry!.paintExtent, 0);
        expect(sliver.geometry!.visible, isFalse);
      }
      position.jumpTo(0);
      await tester.pump();
      expect(
        tester
            .renderObject<RenderSliverToBoxAdapter>(
              find.byKey(const ValueKey('profile-quick-sliver')),
            )
            .geometry!
            .visible,
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'unrelated favorite metadata does not rebuild identity or glass controls',
    (tester) async {
      final (fixture, _) = await mount(tester);
      var avatarBuilds = 0, buttonBuilds = 0;
      final previous = debugOnRebuildDirtyWidget;
      debugOnRebuildDirtyWidget = (element, builtOnce) {
        if (element.widget is PlatformAvatar) avatarBuilds++;
        if (element.widget is BetaGlassButton) buttonBuilds++;
      };
      try {
        final next = [...fixture.tracks];
        next[600] = next[600].copyWith(availabilityMessage: '仅修改另一首歌曲的状态');
        fixture.favorites.add(next);
        await tester.pump();
        await tester.pump();
        expect(avatarBuilds, 0);
        expect(buttonBuilds, 0);
        fixture.favorites.add(next.take(673).toList());
        await tester.pump();
        await tester.pump();
        expect(find.text('673 首歌曲'), findsOneWidget);
        expect(avatarBuilds, 0);
        expect(buttonBuilds, 0);
      } finally {
        debugOnRebuildDirtyWidget = previous;
      }
    },
  );

  testWidgets('liked cover uses its 64 logical pixel decode budget', (
    tester,
  ) async {
    await mount(tester);
    final artwork = tester.widget<ArtworkImage>(
      find.descendant(
        of: find.widgetWithText(ListTile, '我喜欢的音乐'),
        matching: find.byType(ArtworkImage),
      ),
    );
    expect(artwork.width, 64);
    expect(artwork.height, 64);
    expect(artwork.decodeWidth, 64);
    expect(artwork.decodeHeight, 64);
  });

  testWidgets(
    'repeated library/My entries preserve responsive full account content',
    (tester) async {
      final (_, router) = await mount(tester);
      for (var i = 0; i < 12; i++) {
        await tester.timedDrag(
          find.byType(CustomScrollView),
          const Offset(0, -400),
          const Duration(milliseconds: 90),
        );
        await tester.pump(const Duration(milliseconds: 120));
        router.go('/music/library');
        await settle188(tester);
        router.go('/profile');
        await settle188(tester);
        expect(
          find.byKey(const ValueKey('netease-personal-statistics')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'starting a scroll on a quick glass button cancels its action before lift',
    (tester) async {
      final (_, router) = await mount(tester);
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('最近')),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.moveBy(const Offset(0, -120));
      await tester.pump(const Duration(milliseconds: 200));
      expect(router.routeInformationProvider.value.uri.path, '/profile');
      await gesture.up();
      await settle188(tester);
      expect(router.routeInformationProvider.value.uri.path, '/profile');
      expect(tester.takeException(), isNull);
    },
  );
}
