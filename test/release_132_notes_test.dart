import 'package:mesting_music/features/experience/presentation/beta_bottom_bar.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/features/app_update/app_update_providers.dart';
import 'package:mesting_music/features/app_update/data/release_notes_receipt.dart';
import 'package:mesting_music/features/app_update/domain/app_update_models.dart';
import 'package:mesting_music/features/app_update/domain/release_history.dart';
import 'package:mesting_music/features/app_update/presentation/app_update_coordinator.dart';
import 'package:mesting_music/features/app_update/presentation/release_history_page.dart';
import 'package:mesting_music/features/auth/beta_entry_flow.dart';
import 'package:mesting_music/features/auth/presentation/first_launch_auth_coordinator.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/settings/presentation/settings_page.dart';
import 'support/release_132_qa.dart';

const current = AppVersionInfo(
  packageName: 'com.mesting.music.beta',
  versionName: '1.0.32',
  versionCode: 53,
);

class _OfflineUpdate extends AppUpdateController {
  int checks = 0;
  @override
  AppUpdateState build() => const AppUpdateState();
  @override
  Future<AppUpdateCheckResult?> check({bool manual = false}) async {
    checks++;
    state = const AppUpdateState(
      phase: AppUpdatePhase.failed,
      currentVersion: current,
      errorMessage: '模拟断网',
    );
    return null;
  }
}

class _Account extends PlatformAccountController {
  @override
  Future<PlatformSession?> build() async => null;
}

void main() {
  setUpAll(initialize132QA);
  late SharedPreferences preferences;
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      firstLaunchAuthCompletedPreferenceKey: true,
    });
    preferences = await SharedPreferences.getInstance();
  });
  Future<(ProviderContainer, _OfflineUpdate)> mount(
    WidgetTester tester, {
    Widget? page,
    bool narrow = false,
    bool startup = true,
    bool automaticChecks = true,
    Future<AppVersionInfo> Function()? version,
  }) async {
    tester.view.physicalSize = Size(narrow ? 320 : 390, narrow ? 650 : 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final update = _OfflineUpdate();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        appVersionProvider.overrideWith(
          (_) => version?.call() ?? Future.value(current),
        ),
        appUpdateControllerProvider.overrideWith(() => update),
        autoAppUpdateChecksEnabledProvider.overrideWithValue(automaticChecks),
        autoInstalledReleaseNotesEnabledProvider.overrideWithValue(startup),

        platformAccountProvider.overrideWith(_Account.new),
      ],
    );
    addTearDown(container.dispose);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        key: UniqueKey(),
        container: container,
        child: RepaintBoundary(
          key: capture132Key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            navigatorKey: navigator,
            theme: theme132(narrow),
            // Match the real app: the coordinator sits above its Navigator.
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                disableAnimations: true,
                textScaler: TextScaler.linear(narrow ? 1.5 : 1),
              ),
              child: AppUpdateCoordinator(
                navigatorKey: navigator,
                child: child!,
              ),
            ),
            home: Scaffold(body: page ?? const Text('音乐首页')),
          ),
        ),
      ),
    );
    await tester.pump();
    return (container, update);
  }

  Future<void> launch(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> closeNotes(WidgetTester tester) async {
    await tester.tap(find.bySemanticsLabel('关闭更新说明').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  test('receipt is isolated by package and exact installed build', () async {
    final receipt = ReleaseNotesReceipt(preferences);
    expect(receipt.hasSeen(current), isFalse);
    await receipt.acknowledge(current);
    expect(receipt.hasSeen(current), isTrue);
    expect(
      receipt.hasSeen(
        const AppVersionInfo(
          packageName: 'other',
          versionName: '1.0.32',
          versionCode: 53,
        ),
      ),
      isFalse,
    );
    expect(
      receipt.hasSeen(
        const AppVersionInfo(
          packageName: 'com.mesting.music.beta',
          versionName: '1.0.33',
          versionCode: 54,
        ),
      ),
      isFalse,
    );
  });
  testWidgets(
    'installed notes present above Router offline, acknowledge only after close and once per launch/build',
    (tester) async {
      final (_, update) = await mount(tester);
      await launch(tester);
      expect(find.text('此次更新'), findsOneWidget);
      expect(find.text('Mesting Music 1.0.32'), findsOneWidget);
      expect(
        update.checks,
        0,
        reason: 'remote check waits for the local sheet',
      );
      expect(ReleaseNotesReceipt(preferences).hasSeen(current), isFalse);
      await capture132UI(tester, 'installed-notes-light');
      await closeNotes(tester);
      expect(ReleaseNotesReceipt(preferences).hasSeen(current), isTrue);
      expect(update.checks, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await launch(tester);
      expect(find.text('此次更新'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await mount(tester);
      await launch(tester);
      expect(find.text('此次更新'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'entry and foreground gate notes; interrupted sheet is not consumed',
    (tester) async {
      await preferences.setBool(firstLaunchAuthCompletedPreferenceKey, false);
      final (container, _) = await mount(tester, narrow: true);
      await launch(tester);
      expect(find.text('此次更新'), findsNothing);
      await container.read(betaEntryFlowProvider.notifier).finish();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await launch(tester);
      expect(find.text('此次更新'), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await launch(tester);
      expect(find.text('此次更新'), findsOneWidget);
      await capture132UI(tester, 'installed-notes-narrow-dark-large-text');
      final notesScroll = find.descendant(
        of: find.byKey(const ValueKey('release-notes-sheet')),
        matching: find.byType(Scrollable),
      );
      await tester.drag(notesScroll, const Offset(0, -420));
      await tester.pump();
      expect(
        find.text(notesForMusicVersion('1.0.32').last).hitTestable(),
        findsOneWidget,
      );
      await capture132UI(tester, 'installed-notes-narrow-dark-bottom');
      await tester.pumpWidget(const SizedBox());
      expect(ReleaseNotesReceipt(preferences).hasSeen(current), isFalse);
      await mount(tester, narrow: true);
      await launch(tester);
      expect(find.text('此次更新'), findsOneWidget);
      await closeNotes(tester);
      expect(ReleaseNotesReceipt(preferences).hasSeen(current), isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('unknown installed versions never inherit bundled notes', (
    tester,
  ) async {
    await mount(
      tester,
      version: () async => const AppVersionInfo(
        packageName: 'com.mesting.music.beta',
        versionName: '99.9.9',
        versionCode: 999,
      ),
    );
    await launch(tester);
    expect(find.text('此次更新'), findsNothing);
    expect(ReleaseNotesReceipt(preferences).hasSeen(current), isFalse);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('slow version read cannot show notes while backgrounded', (
    tester,
  ) async {
    final version = Completer<AppVersionInfo>();
    await mount(tester, version: () => version.future);
    await launch(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    version.complete(current);
    await tester.pump();
    expect(find.text('此次更新'), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await launch(tester);
    expect(find.text('此次更新'), findsOneWidget);
    await closeNotes(tester);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'settings independent history entry reads current and both missing versions offline',
    (tester) async {
      final (_, update) = await mount(
        tester,
        page: const SettingsPage(),
        startup: false,
        automaticChecks: false,
      );
      await tester.pumpAndSettle();
      final entry = find.byKey(const ValueKey('settings-release-history'));
      await tester.scrollUntilVisible(
        entry,
        350,
        scrollable: find.byType(Scrollable).first,
      );
      await capture132UI(tester, 'settings-release-history-entry');
      await tester.tap(entry);
      await tester.pumpAndSettle();
      expect(find.byType(MusicReleaseHistoryPage), findsOneWidget);
      final historyList = find.byKey(
        const PageStorageKey('music-release-history'),
      );
      final historyScroll = find
          .descendant(of: historyList, matching: find.byType(Scrollable))
          .first;
      // The longer newest notes can keep this fixture's older installed
      // version outside the lazy list. Build its row before checking notes.
      await tester.scrollUntilVisible(
        find.text('v1.0.32'),
        250,
        scrollable: historyScroll,
      );
      await tester.pumpAndSettle();
      expect(find.text(notesForMusicVersion('1.0.32').first), findsOneWidget);
      await capture132UI(tester, 'release-history-current');
      // The fixture's installed version moves down as new releases are added.
      // Position its header clear of the floating player before collapsing it.
      await Scrollable.ensureVisible(
        tester.element(find.text('v1.0.32')),
        alignment: 0.25,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('v1.0.32'));
      await tester.pumpAndSettle();
      for (final version in ['1.0.31', '1.0.30']) {
        final header = find.text('v$version');
        await tester.scrollUntilVisible(header, 250, scrollable: historyScroll);
        // Newer releases move these historical rows. Bring the row into the
        // usable viewport before tapping, clear of the floating music controls.
        await Scrollable.ensureVisible(tester.element(header), alignment: 0.25);
        await tester.pumpAndSettle();
        await tester.tap(header);
        await tester.pumpAndSettle();
        expect(find.text(notesForMusicVersion(version).first), findsOneWidget);
        await capture132UI(tester, 'release-history-$version');
        await tester.tap(header);
        await tester.pumpAndSettle();
      }
      expect(
        update.checks,
        0,
        reason: 'manual history must not query the update service',
      );
      final history = tester.widget<ListView>(historyList);
      expect(
        (history.padding! as EdgeInsets).bottom,
        greaterThanOrEqualTo(
          tester.getSize(find.byType(BetaMusicBottomBar)).height,
        ),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
