import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/features/music_platform/netease/netease_rewards.dart';
import 'package:mesting_music/features/music_platform/netease/netease_rewards_provider.dart';
import 'package:mesting_music/features/music_platform/presentation/netease_reward_calendar.dart';
import 'support/release_152_qa.dart';

class _Rewards implements NeteaseRewardService {
  @override
  String get ownerId => 'reward-fixture';
  int ads = 0;
  @override
  Future<NeteaseRewardSnapshot> load() async => NeteaseRewardSnapshot(
    now: DateTime(2026, 11, 5, 12),
    signedToday: true,
    signedDates: {'2026-11-02', '2026-11-04'},
    recordsAvailable: true,
    freeListen: const NeteaseFreeListenSnapshot(
      remainingSeconds: 1834,
      progressTitle: '再领一次，继续免费听',
      progressSubtitle: '奖励以平台返回为准',
      milestones: [
        NeteaseRewardMilestone(label: '30分钟免费听', done: true, count: 1),
        NeteaseRewardMilestone(label: '今日免费听', done: false, count: 0),
      ],
    ),
  );
  @override
  Future<NeteaseRewardResult> signIn() async =>
      const NeteaseRewardResult(success: true, signed: true, message: '已确认');
  @override
  Future<NeteaseRewardResult> claimAd({bool Function()? stillCurrent}) async {
    ads++;
    return const NeteaseRewardResult(success: true, message: '已确认');
  }
}

void main() {
  setUpAll(initialize151QA);
  for (final dark in [false, true]) {
    for (final large in [false, true]) {
      testWidgets(
        'NetEase calendar and welfare retain accessible layout dark=$dark large=$large',
        (tester) async {
          final semantics = tester.ensureSemantics();
          var semanticsDisposed = false;
          addTearDown(() {
            if (!semanticsDisposed) semantics.dispose();
          });
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(large ? 320 : 390, 844);
          addTearDown(tester.view.reset);
          SharedPreferences.setMockInitialValues({
            NeteaseRewardsController.autoKey('reward-fixture'): false,
          });
          final prefs = await SharedPreferences.getInstance();
          final service = _Rewards();
          final container = ProviderContainer(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(prefs),
              neteaseRewardServiceProvider.overrideWith((ref) async => service),
              neteaseRewardClockProvider.overrideWithValue(
                () => DateTime(2026, 11, 5, 12),
              ),
              neteaseRewardDelayProvider.overrideWithValue(
                (_, cancelled) => cancelled,
              ),
            ],
          );
          var disposed = false;
          addTearDown(() {
            if (!disposed) container.dispose();
          });
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: theme152(dark),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(large ? 2 : 1)),
                  child: capture151Builder(child!),
                ),
                home: const NeteaseRewardCalendar(),
              ),
            ),
          );
          for (var n = 0; n < 18; n++) {
            await tester.pump(const Duration(milliseconds: 50));
          }
          expect(
            find.byKey(const ValueKey('netease-reward-days')),
            findsOneWidget,
          );
          expect(find.text('本月已确认 3 天'), findsOneWidget);
          // A successful profile read confirms today's flag, not the whole
          // month. An unrecorded past day must remain explicitly unknown.
          expect(find.bySemanticsLabel('11月1日，暂无确认记录'), findsOneWidget);
          expect(find.bySemanticsLabel('11月1日，未签到'), findsNothing);
          expect(tester.takeException(), isNull);
          await shot151(
            tester,
            '159-netease-calendar-${dark ? 'dark' : 'light'}-${large ? 'large' : 'normal'}',
          );
          await tester.ensureVisible(
            find.byKey(const ValueKey('netease-free-listen-card')),
          );
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.text('30分34秒'), findsOneWidget);
          expect(find.text('再领一次，继续免费听'), findsOneWidget);
          expect(find.text('奖励以平台返回为准'), findsOneWidget);
          expect(find.text('30分钟免费听 · 已确认 1 次'), findsOneWidget);
          expect(find.text('今日免费听 · 已确认 0 次'), findsOneWidget);
          expect(find.text('今日领取进度 1/2'), findsNothing);
          expect(find.text('云贝收益'), findsNothing);
          expect(find.text('领现金'), findsNothing);
          expect(tester.takeException(), isNull);
          await shot151(
            tester,
            '159-netease-welfare-${dark ? 'dark' : 'light'}-${large ? 'large' : 'normal'}',
          );
          final button = find.byKey(const ValueKey('netease-reward-claim-ad'));
          await tester.ensureVisible(button);
          await tester.pump(const Duration(milliseconds: 300));
          await tester.tap(button);
          for (var n = 0; n < 10; n++) {
            await tester.pump(const Duration(milliseconds: 50));
          }
          expect(service.ads, 1);
          expect(find.text('停止领取'), findsOneWidget);
          expect(container.read(neteaseRewardsProvider).confirmedAds, 1);
          await tester.tap(button);
          for (var n = 0; n < 8; n++) {
            await tester.pump(const Duration(milliseconds: 50));
          }
          expect(service.ads, 1);
          expect(container.read(neteaseRewardsProvider).action, isNull);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          // WidgetsBinding checks pending timers before addTearDown callbacks.
          // Dispose the kept-alive reward scope here to exercise and verify the
          // production midnight timer's onDispose cleanup before that check.
          container.dispose();
          disposed = true;
          semantics.dispose();
          semanticsDisposed = true;
          await tester.pump();
        },
      );
    }
  }
}
