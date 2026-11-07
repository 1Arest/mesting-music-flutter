import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mesting_music/app/router/beta_tab_shell.dart';
import 'package:mesting_music/core/diagnostics/diagnostic_run.dart';
import 'package:mesting_music/features/experience/presentation/beta_bottom_bar.dart';
import 'package:mesting_music/features/settings/presentation/production_diagnostic_driver.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/music_platform/netease/netease_features_page.dart';
import 'package:mesting_music/features/music_platform/netease/netease_features_repository.dart';
import 'package:mesting_music/shared/widgets/beta_music_chrome_scope.dart';
import 'package:mesting_music/shared/widgets/beta_tab_navigation.dart';
import 'support/personal_profile_fixture.dart';

/// Keep account switching inside the synthetic fixture; never touch a keystore.
class _DiagnosticAccount175 extends SyntheticProfileAccount {
  @override
  Future<PlatformSession?> retainedIdentity(MusicPlatform platform) async =>
      state.value;

  @override
  Future<void> switchPlatform(MusicPlatform platform) async {
    if (state.value?.platform != platform) throw StateError('fixture platform');
  }
}

void main() {
  setUpAll(LiquidGlassWidgets.initialize);
  testWidgets('user-playlist diagnostic opens the current real account ID', (
    tester,
  ) async {
    final fixture = await PersonalProfileFixture.create(
      accountFactory: _DiagnosticAccount175.new,
    );
    final navigator = GlobalKey<NavigatorState>();
    final router = GoRouter(
      navigatorKey: navigator,
      routes: [GoRoute(path: '/', builder: (_, _) => const Scaffold())],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: fixture.container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    final driver = ProductionDiagnosticDriver(
      container: fixture.container,
      router: router,
      navigator: navigator.currentState!,
      originalPlatform: MusicPlatform.netease,
    );
    Object? failure;
    var done = false;
    driver
        .open(
          const DiagnosticScenario(
            'netease/feed-userPlaylists',
            '用户歌单',
            'netease',
          ),
          DiagnosticTicket(),
        )
        .then<void>(
          (_) {
            done = true;
          },
          onError: (Object error, StackTrace _) {
            failure = error;
          },
        );
    for (var i = 0; i < 250 && !done && failure == null; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(failure, isNull);
    expect(done, isTrue);
    final page = tester.widget<NeteaseFeaturesPage>(
      find.byType(NeteaseFeaturesPage),
    );
    expect(page.feed, NeteaseFeed.userPlaylists);
    expect(
      page.id,
      fixture.container.read(platformAccountProvider).value!.userId,
    );
      final closing = driver.close();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 600));
      await closing;
    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
    await fixture.dispose();
  });
  for (final soda in [false, true]) {
    testWidgets(
      'rapid diagnostic reaches real ancestor chrome and paints final ${soda ? 'three' : 'four'}-tab destination',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final container = ProviderContainer();
        final navigator = GlobalKey<NavigatorState>();
        final chrome = BetaMusicChromeController();
        final text = TextEditingController();
        final focus = FocusNode();
        final requests = <int>[];
        final router = GoRouter(
          initialLocation: betaMusicRoutes.first,
          routes: [
            ShellRoute(
              navigatorKey: navigator,
              builder: (context, state, child) {
                final selected = betaMusicRoutes.indexOf(state.uri.path);
                return BetaMusicChromeScope(
                  controller: chrome,
                  child: Scaffold(
                    body: Stack(
                      children: [
                        Positioned.fill(child: child),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: BetaMusicBottomBar(
                            soda: soda,
                            selectedIndex: selected,
                            searchConfig: GlassSearchBarConfig(
                              controller: text,
                              focusNode: focus,
                              onSearchToggle: (_) {},
                            ),
                            onTabSelected: (index) {
                              requests.add(index);
                              container
                                  .read(betaTabNavigationProvider)
                                  .request(
                                    index: index,
                                    currentIndex: selected,
                                    navigate: (i) =>
                                        context.go(betaMusicRoutes[i]),
                                  );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
              routes: betaTabShellRoutes([
                for (var i = 0; i < betaMusicRoutes.length; i++)
                  GoRoute(
                    path: betaMusicRoutes[i],
                    builder: (_, _) => Center(child: Text('root$i')),
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
        final driver = ProductionDiagnosticDriver(
          container: container,
          router: router,
          navigator: navigator.currentState!,
          originalPlatform: null,
        );
        Map<String, Object>? result;
        Object? failure;
        driver
            .exercise(
              DiagnosticScenario(
                '${soda ? 'qishui' : 'netease'}/tabs',
                'tabs',
                soda ? 'qishui' : 'netease',
              ),
              DiagnosticPhase.pages,
              DiagnosticTicket(),
            )
            .then(
              (value) => result = value,
              onError: (Object error, StackTrace _) {
                failure = error;
              },
            );
        for (var i = 0; i < 250 && result == null && failure == null; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        expect(failure, isNull);
        expect(requests, hasLength(12));
        expect(result?['observedSelections'], 12);
        expect(result?['motionObserved'], isTrue);
        expect(result?['finalPaintedTabVerified'], isTrue);
        expect(find.text('root3').hitTestable(), findsOneWidget);
        expect(router.routeInformationProvider.value.uri.path, '/profile');
        await tester.pumpWidget(const SizedBox.shrink());
        router.dispose();
        chrome.dispose();
        text.dispose();
        focus.dispose();
        container.dispose();
      },
    );
  }
}
