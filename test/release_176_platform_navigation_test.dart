import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/features/auth/beta_account_choice.dart';
import 'package:mesting_music/app/router/beta_tab_shell.dart';
import 'package:mesting_music/features/music_platform/discovery_startup_cache.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/music_platform/presentation/platform_home_visit.dart';
import 'package:mesting_music/features/music_platform/presentation/platform_login_options_page.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_pages.dart';

class _Accounts extends PlatformAccountController {
  @override
  Future<PlatformSession?> build() async => const PlatformSession(
    userId: 'host',
    token: 'host',
    platform: MusicPlatform.netease,
  );
  @override
  Future<PlatformSession?> retainedIdentity(MusicPlatform platform) async =>
      PlatformSession(
        userId: 'host-${platform.name}',
        token: 'host',
        platform: platform,
      );
  @override
  Future<void> switchPlatform(MusicPlatform platform) async =>
      state = AsyncData(await retainedIdentity(platform));
}

void main() {
  setUpAll(LiquidGlassWidgets.initialize);
  testWidgets(
    'explicit platform selection leaves the switch route and enters its default home at the top',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        BetaAccountChoiceController.preferenceKey: 'netease',
      });
      final preferences = await SharedPreferences.getInstance();
      final preparation = Completer<DiscoveryStartupCache>();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          platformAccountProvider.overrideWith(_Accounts.new),
          platformHomePreparationProvider.overrideWithValue(
            (_) => preparation.future,
          ),
        ],
      );
      await container.read(platformAccountProvider.future);
      final router = GoRouter(
        initialLocation: '/music/recommend',
        routes: [
          ShellRoute(
            builder: (_, _, child) => Scaffold(body: child),
            routes: betaTabShellRoutes([
              GoRoute(
                path: '/music/recommend',
                builder: (_, _) => QishuiRootSwitch(
                  root: QishuiRoot.discover,
                  child: ListView.builder(
                    key: const ValueKey('home-scroll'),
                    itemExtent: 100,
                    itemCount: 30,
                    itemBuilder: (_, index) => Text('home row $index'),
                  ),
                ),
              ),
              GoRoute(path: '/music', builder: (_, _) => const Text('music')),
              GoRoute(
                path: '/music/library',
                builder: (_, _) => const Text('library'),
              ),
              GoRoute(
                path: '/profile',
                builder: (context, _) => Center(
                  child: TextButton(
                    onPressed: () => openMusicPlatformSwitch(context),
                    child: const Text('open platform selection'),
                  ),
                ),
              ),
            ]),
          ),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const ValueKey('home-scroll')),
        const Offset(0, -600),
      );
      await tester.pumpAndSettle();
      double scrollOffset() => tester
          .state<ScrollableState>(
            find
                .descendant(
                  of: find.byKey(const ValueKey('home-scroll')),
                  matching: find.byType(Scrollable),
                )
                .first,
          )
          .position
          .pixels;
      expect(scrollOffset(), greaterThan(100));
      router.go('/profile');
      await tester.pumpAndSettle();
      await tester.tap(find.text('open platform selection'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('酷狗音乐'));
      await tester.pump(const Duration(milliseconds: 80));
      expect(
        find.byType(MusicPlatformSwitchPage),
        findsOneWidget,
        reason:
            'The real selector must cover the destination until cached preparation completes',
      );
      preparation.complete(DiscoveryStartupCache());
      var observedHomeMotion = false;
      for (var i = 0; i < 70; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        final home = find.byKey(const ValueKey('home-scroll'));
        if (home.evaluate().isNotEmpty &&
            tester.getTopLeft(home).dx.abs() > 1) {
          observedHomeMotion = true;
        }
      }
      expect(
        router.routeInformationProvider.value.uri.path,
        '/music/recommend',
      );
      expect(find.byType(MusicPlatformSwitchPage), findsNothing);
      expect(scrollOffset(), closeTo(0, .01));
      expect(find.text('home row 0').hitTestable(), findsOneWidget);
      expect(observedHomeMotion, isTrue);
      expect(
        container.read(platformHomeVisitProvider.notifier).pending,
        isFalse,
      );
      // Returning to the old Tab must not resurrect the selection route that was
      // pushed with Navigator instead of GoRouter's declarative route graph.
      router.go('/profile');
      await tester.pumpAndSettle();
      expect(
        find.text('open platform selection').hitTestable(),
        findsOneWidget,
      );
      expect(find.byType(MusicPlatformSwitchPage), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      router.dispose();
      container.dispose();
    },
  );
}
