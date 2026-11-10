import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mesting_music/core/diagnostics/diagnostic_run.dart';
import 'package:mesting_music/features/experience/presentation/player_more_menu.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/music_platform/presentation/beta_personal_profile.dart';
import 'package:mesting_music/features/settings/presentation/production_diagnostic_driver.dart';
import 'package:mesting_music/shared/widgets/beta_glass_popover.dart';
import 'package:mesting_music/shared/widgets/liquid_glass_sheet.dart';

import 'support/personal_profile_fixture.dart';

void main() {
  setUpAll(LiquidGlassWidgets.initialize);
  for (final nested in [false, true]) {
    for (final profile in [false, true]) {
      for (final phase in [
        DiagnosticPhase.normal,
        DiagnosticPhase.fastReverse,
      ]) {
        for (final cancelled in [
          false,
          if (nested && phase == DiagnosticPhase.fastReverse) true,
        ]) {
          testWidgets(
            'production ${nested ? 'nested' : 'single'} ${profile ? 'profile' : 'player'} menu sampler ${cancelled ? 'cleans cancellation' : 'observes open and close'} in $phase',
            (tester) async {
              tester.view.physicalSize = const Size(390, 844);
              tester.view.devicePixelRatio = 1;
              addTearDown(tester.view.reset);
              final fixture = (await tester.runAsync(
                PersonalProfileFixture.create,
              ))!;
              final navigator = GlobalKey<NavigatorState>();
              final rootNavigator = GlobalKey<NavigatorState>();
              var actions = 0;
              final page = GoRoute(
                path: '/',
                builder: (_, _) => Scaffold(
                  body: profile
                      ? const BetaPersonalProfile()
                      : Center(
                          child: PlayerMoreMenu(
                            trigger: const Text('more'),
                            onSelected: (_) => actions++,
                            groups: const [
                              [
                                PlayerMenuAction(
                                  'fixture-action',
                                  'fixture action',
                                  Icons.music_note,
                                ),
                              ],
                            ],
                          ),
                        ),
                ),
              );
              // Production settings/players live inside a retained branch, while
              // the player's popover deliberately uses the root Navigator. A
              // single-Navigator fixture cannot detect an orphan above that branch.
              final router = GoRouter(
                navigatorKey: nested ? rootNavigator : navigator,
                routes: nested
                    ? [
                        ShellRoute(
                          navigatorKey: navigator,
                          builder: (_, _, child) => child,
                          routes: [page],
                        ),
                      ]
                    : [page],
              );
              await tester.pumpWidget(
                UncontrolledProviderScope(
                  container: fixture.container,
                  child: MaterialApp.router(
                    routerConfig: router,
                    builder: (context, child) => MediaQuery(
                      data: MediaQuery.of(
                        context,
                      ).copyWith(disableAnimations: true),
                      child: child!,
                    ),
                  ),
                ),
              );
              for (var i = 0; i < 20; i++) {
                await tester.pump(const Duration(milliseconds: 16));
              }
              final driver = ProductionDiagnosticDriver(
                container: fixture.container,
                router: router,
                navigator: navigator.currentState!,
                originalPlatform: MusicPlatform.netease,
              );
              Map<String, Object>? report;
              Object? error;
              final ticket = DiagnosticTicket();
              final running = driver
                  .exercise(
                    DiagnosticScenario(
                      'netease/${profile ? 'profile-menu' : 'player-menu'}',
                      'synthetic host menu',
                      'netease',
                    ),
                    phase,
                    ticket,
                  )
                  .then<void>(
                    (value) => report = value,
                    onError: (Object failure) => error = failure,
                  );
              for (var i = 0; i < 600 && report == null && error == null; i++) {
                await tester.pump(const Duration(milliseconds: 16));
                if (cancelled && i == 1) ticket.cancelled = true;
              }
              if (cancelled) {
                expect(error, isA<DiagnosticCancelled>());
                expect(report, isNull);
              } else {
                expect(error, isNull);
                expect(
                  report?['menuCycles'],
                  phase == DiagnosticPhase.fastReverse ? 6 : 3,
                );
                expect(report?['observedOpenAndClose'], isTrue);
              }
              expect(actions, 0);
              await running;
              // The root must be clear even when cancellation arrives during
              // entry; later branch navigation must never paint under an orphan.
              expect(find.byType(BetaLiquidMenu), findsNothing);
              expect(find.byKey(liquidGlassSheetSurfaceKey), findsNothing);
              await driver.close();
              expect(tester.takeException(), isNull);
              await tester.pumpWidget(const SizedBox());
              router.dispose();
              await fixture.dispose();
            },
          );
        }
      }
    }
  }
}
