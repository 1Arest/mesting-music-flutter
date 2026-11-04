import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/core/audio/mesting_audio_handler.dart';
import 'package:mesting_music/features/app_update/app_update_providers.dart';
import 'package:mesting_music/features/app_update/domain/app_update_models.dart';
import 'package:mesting_music/features/app_update/presentation/release_history_page.dart';
import 'package:mesting_music/features/experience/presentation/beta_bottom_bar.dart';
import 'package:mesting_music/features/experience/presentation/beta_music_shell.dart';
import 'package:mesting_music/features/music_platform/retained_kugou_scope.dart';
import 'package:mesting_music/features/music_platform/netease/netease_account_overview.dart';
import 'package:mesting_music/shared/widgets/beta_content_insets.dart';
import 'package:mesting_music/shared/widgets/beta_glass_scroll_body.dart';
import 'package:mesting_music/shared/widgets/music_feature_page.dart';
import 'support/deterministic_audio_player.dart';
import 'support/personal_profile_fixture.dart';
import 'support/test_tracks.dart';
import 'support/release_133_qa.dart';

void main() {
  setUpAll(initialize133QA);
  for (final large in [false, true]) {
    for (final secondary in [false, true]) {
      testWidgets(
        'history last tile clears real glass large=$large secondary=$secondary',
        (tester) async {
          final dependencies = (await tester.runAsync(() async {
            final handler = MestingAudioHandler(
              tracks: testTracks,
              player: DeterministicAudioPlayer(),
            );
            await handler.replaceQueue(testTracks, autoplay: false);
            final fixture = await PersonalProfileFixture.create(
              audioHandler: handler,
              extraOverrides: [
                savedKugouSessionProvider.overrideWith((_) async => null),
                appVersionProvider.overrideWith(
                  (_) async => const AppVersionInfo(
                    packageName: 'com.mesting.music.beta',
                    versionName: '1.0.33',
                    versionCode: 54,
                  ),
                ),
              ],
            );
            return (handler, fixture);
          }))!;
          final (handler, fixture) = dependencies;
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = large
              ? const Size(320, 720)
              : const Size(390, 844);
          tester.view.viewPadding = const FakeViewPadding(bottom: 34);
          tester.view.padding = const FakeViewPadding(bottom: 34);
          addTearDown(tester.view.reset);
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: fixture.container,
              child: RepaintBoundary(
                key: capture133Key,
                child: MaterialApp(
                  debugShowCheckedModeBanner: false,
                  theme: theme133(large),
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: TextScaler.linear(large ? 1.5 : 1)),
                    child: child!,
                  ),
                  home: secondary
                      ? const MusicReleaseHistoryPage()
                      : const BetaMusicShell(
                          location: '/music/settings',
                          child: MusicReleaseHistoryPage(),
                        ),
                ),
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 600));
          final scroll = tester
              .state<ScrollableState>(find.byType(Scrollable).first)
              .position;
          scroll.jumpTo(scroll.maxScrollExtent);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 700));
          final last = find.byKey(
            const PageStorageKey('release-history-1.0.1'),
          );
          expect(last, findsOneWidget);
          expect(find.byType(BetaMusicBottomBar), findsOneWidget);
          expect(
            tester.getRect(last).bottom,
            lessThan(tester.getRect(find.byType(BetaMusicBottomBar)).top),
            reason:
                'The entire final row, not just its centre, must be above the real accessory.',
          );
          await tester.tap(find.text('v1.0.1'));
          await tester.pump(const Duration(milliseconds: 500));
          scroll.jumpTo(scroll.maxScrollExtent);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          // Expansion changes a lazy viewport's estimated extent over more than
          // one layout. Finish at the actual end, as repeated user scrolling does.
          for (var i = 0; i < 3; i++) {
            scroll.jumpTo(scroll.maxScrollExtent);
            await tester.pump(const Duration(milliseconds: 100));
          }
          expect(
            tester.getRect(last).bottom,
            lessThan(tester.getRect(find.byType(BetaMusicBottomBar)).top),
          );
          await capture133UI(
            tester,
            'history-bottom-large-$large-secondary-$secondary',
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          await tester.runAsync(() async {
            await fixture.dispose();
            await handler.debugDispose();
          });
        },
      );
    }
  }
  testWidgets('shared form can scroll its final action above primary chrome', (
    tester,
  ) async {
    final fixture = await tester.runAsync(
      () => PersonalProfileFixture.create(
        extraOverrides: [
          savedKugouSessionProvider.overrideWith((_) async => null),
        ],
      ),
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: fixture!.container,
        child: MaterialApp(
          theme: theme133(false),
          home: BetaMusicShell(
            location: '/music/settings',
            child: MusicFeaturePage(
              title: '表单',
              child: BetaGlassScrollBody(
                children: [
                  for (var i = 0; i < 30; i++)
                    SizedBox(height: 50, child: Text('字段 $i')),
                  const Text('最后操作', key: ValueKey('last-form-action')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    position.jumpTo(position.maxScrollExtent);
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      tester.getRect(find.byKey(const ValueKey('last-form-action'))).bottom,
      lessThan(tester.getRect(find.byType(BetaMusicBottomBar)).top),
    );
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(fixture.dispose);
  });
  for (final secondary in [false, true]) {
    testWidgets(
      'real account overview final section is reachable secondary=$secondary',
      (tester) async {
        final fixture = (await tester.runAsync(
          () => PersonalProfileFixture.create(
            extraOverrides: [
              savedKugouSessionProvider.overrideWith((_) async => null),
            ],
          ),
        ))!;
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(320, 680);
        tester.view.viewPadding = const FakeViewPadding(bottom: 34);
        tester.view.padding = const FakeViewPadding(bottom: 34);
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: fixture.container,
            child: RepaintBoundary(
              key: capture133Key,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: theme133(true),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(1.5)),
                  child: child!,
                ),
                home: secondary
                    ? const NeteaseAccountOverviewPage()
                    : const BetaMusicShell(
                        location: '/profile',
                        child: NeteaseAccountOverviewPage(),
                      ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        final position = tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position;
        for (var i = 0; i < 3; i++) {
          position.jumpTo(position.maxScrollExtent);
          await tester.pump(const Duration(milliseconds: 300));
        }
        expect(
          tester.getRect(find.text('收藏概览')).bottom,
          lessThan(tester.getRect(find.byType(BetaMusicBottomBar)).top),
        );
        await capture133UI(tester, 'account-bottom-secondary-$secondary');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(fixture.dispose);
      },
    );
  }
  testWidgets(
    'music padding preserves stable authored spacing and explicit zero scope',
    (tester) async {
      double? bottom;
      await tester.pumpWidget(
        MaterialApp(
          home: BetaContentInsets(
            bottom: 0,
            child: Builder(
              builder: (context) {
                bottom = BetaContentInsets.musicPaddingOf(
                  context,
                  const EdgeInsets.all(24),
                ).bottom;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      expect(bottom, 24);
    },
  );
}
