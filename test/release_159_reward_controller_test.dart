import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesting_music/core/diagnostics/diagnostic_activity.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/features/music_platform/netease/netease_rewards.dart';
import 'package:mesting_music/features/music_platform/netease/netease_rewards_provider.dart';

final _selection = NotifierProvider<_Selection, NeteaseRewardService?>(
  _Selection.new,
);

class _Selection extends Notifier<NeteaseRewardService?> {
  @override
  NeteaseRewardService? build() => null;
  void select(NeteaseRewardService? service) => state = service;
}

class _Service implements NeteaseRewardService {
  _Service(this.ownerId);
  @override
  final String ownerId;
  NeteaseRewardSnapshot snapshot = NeteaseRewardSnapshot(
    now: DateTime(2026, 11, 5),
  );
  int signs = 0, ads = 0, reads = 0;
  bool loadFails = false;
  Completer<NeteaseRewardResult>? signPending, adPending;
  NeteaseRewardResult signResult = const NeteaseRewardResult(
    success: true,
    signed: true,
    message: '已确认',
  );
  final List<NeteaseRewardResult> adResults = [];
  @override
  Future<NeteaseRewardSnapshot> load() async {
    reads++;
    if (loadFails) throw StateError('synthetic offline');
    return snapshot;
  }

  @override
  Future<NeteaseRewardResult> signIn() async {
    signs++;
    return signPending?.future ?? Future.value(signResult);
  }

  @override
  Future<NeteaseRewardResult> claimAd({bool Function()? stillCurrent}) async {
    ads++;
    return adPending?.future ??
        Future.value(
          adResults.isEmpty
              ? const NeteaseRewardResult(success: true, message: '已确认')
              : adResults.removeAt(0),
        );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ProviderContainer container;
  late SharedPreferences preferences;
  late _Service a;
  late NeteaseRewardsController controller;
  final waits = <Duration>[];
  Future<void> flush() async {
    for (var i = 0; i < 25; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<void> prepare({
    bool automatic = false,
    NeteaseRewardDelay? delay,
  }) async {
    SharedPreferences.setMockInitialValues({
      NeteaseRewardsController.autoKey('A'): automatic,
      NeteaseRewardsController.autoKey('B'): false,
    });
    preferences = await SharedPreferences.getInstance();
    waits.clear();
    a = _Service('A');
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        neteaseRewardClockProvider.overrideWithValue(
          () => DateTime(2026, 11, 5, 12),
        ),
        neteaseRewardServiceProvider.overrideWith(
          (ref) async => ref.watch(_selection),
        ),
        neteaseRewardDelayProvider.overrideWithValue(
          delay ??
              (duration, cancelled) async {
                waits.add(duration);
              },
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(_selection.notifier).select(a);
    container.listen(neteaseRewardsProvider, (_, _) {});
    await flush();
    controller = container.read(neteaseRewardsProvider.notifier);
  }

  test('saved disabled automation only reads and does not sign', () async {
    await prepare();
    expect(a.signs, 0);
    expect(container.read(neteaseRewardsProvider).ownerId, 'A');
    expect(container.read(neteaseRewardsProvider).localDates, isEmpty);
  });

  test(
    'automatic sign persists one explicit receipt and skips another resume',
    () async {
      await prepare(automatic: true);
      expect(a.signs, 1);
      expect(
        preferences.getStringList(NeteaseRewardsController.datesKey('A')),
        ['2026-11-05'],
      );
      await controller.resume();
      expect(a.signs, 1);
    },
  );

  test(
    'unknown automatic result is attempted once per owner and day',
    () async {
      await prepare();
      a.signResult = const NeteaseRewardResult(
        success: false,
        uncertain: true,
        message: '回复丢失',
      );
      await controller.setAutoSignIn(true);
      await flush();
      await controller.resume();
      expect(a.signs, 1);
      expect(
        preferences.getString(NeteaseRewardsController.attemptKey('A')),
        '2026-11-05',
      );
      expect(container.read(neteaseRewardsProvider).signedDates, isEmpty);
    },
  );

  test(
    'authority confirming today prevents an unnecessary sign write',
    () async {
      await prepare();
      a.snapshot = NeteaseRewardSnapshot(
        now: DateTime(2026, 11, 5),
        signedToday: true,
      );
      final result = await controller.signIn();
      expect(result.signed, isTrue);
      expect(a.signs, 0);
      expect(container.read(neteaseRewardsProvider).signedDates, {
        '2026-11-05',
      });
    },
  );

  test('late first A reply cannot mark B or the new A generation', () async {
    await prepare();
    a.signPending = Completer();
    final pending = controller.signIn();
    await flush();
    expect(a.signs, 1);
    container.read(_selection.notifier).select(_Service('B'));
    await flush();
    final newA = _Service('A');
    container.read(_selection.notifier).select(newA);
    await flush();
    a.signPending!.complete(
      const NeteaseRewardResult(success: true, signed: true, message: '旧回复'),
    );
    expect((await pending).success, isFalse);
    expect(container.read(neteaseRewardsProvider).ownerId, 'A');
    expect(container.read(neteaseRewardsProvider).localDates, isEmpty);
    expect(
      preferences.getStringList(NeteaseRewardsController.datesKey('A')),
      isNull,
    );
    expect(
      preferences.getStringList(NeteaseRewardsController.datesKey('B')),
      isNull,
    );
  });

  test('only one reward write can own the account at a time', () async {
    await prepare();
    a.signPending = Completer();
    final pending = controller.signIn();
    await flush();
    expect((await controller.ads()).success, isFalse);
    expect(a.ads, 0);
    a.signPending!.complete(
      const NeteaseRewardResult(success: true, signed: true, message: '已确认'),
    );
    await pending;
  });

  test(
    'unknown official limit uses bounded batch without claiming a daily quota',
    () async {
      await prepare();
      final result = await controller.ads();
      expect(result.success, isTrue);
      expect(a.ads, 8);
      expect(waits, List.filled(7, const Duration(seconds: 30)));
      expect(container.read(neteaseRewardsProvider).confirmedAds, 8);
      expect(result.message, contains('本批'));
      expect(
        container.read(neteaseRewardsProvider).snapshot?.freeListen?.adLimit,
        isNull,
      );
    },
  );

  test(
    'server quota and interval are used without counting quota as success',
    () async {
      await prepare();
      a.adResults.addAll([
        const NeteaseRewardResult(
          success: true,
          message: '成功',
          nextClaimAfter: Duration(seconds: 42),
        ),
        const NeteaseRewardResult(
          success: true,
          quotaDone: true,
          message: '次数已用完',
        ),
      ]);
      final result = await controller.ads();
      expect(result.quotaDone, isTrue);
      expect(a.ads, 2);
      expect(waits, [const Duration(seconds: 42)]);
      expect(container.read(neteaseRewardsProvider).confirmedAds, 1);
    },
  );

  test('stop interrupts a pending interval before any next request', () async {
    await prepare(delay: (_, cancelled) => cancelled);
    final pending = controller.ads();
    await flush();
    expect(a.ads, 1);
    controller.stopAds();
    final result = await pending;
    expect(result.message, contains('已停止'));
    expect(a.ads, 1);
  });

  test(
    'stop during a sent claim keeps its confirmed receipt without continuing',
    () async {
      await prepare();
      a.adPending = Completer();
      final pending = controller.ads();
      await flush();
      controller.stopAds();
      a.adPending!.complete(
        const NeteaseRewardResult(success: true, message: '已确认'),
      );
      await pending;
      expect(a.ads, 1);
      expect(container.read(neteaseRewardsProvider).confirmedAds, 1);
      expect(waits, isEmpty);
    },
  );

  test(
    'unknown write terminates the batch without an automatic retry',
    () async {
      await prepare();
      a.adResults.add(
        const NeteaseRewardResult(
          success: false,
          uncertain: true,
          message: '结果未确认',
        ),
      );
      final result = await controller.ads();
      expect(result.uncertain, isTrue);
      expect(a.ads, 1);
      expect(container.read(neteaseRewardsProvider).confirmedAds, 0);
      expect(waits, isEmpty);
    },
  );

  test('account logout cancels the batch interval', () async {
    await prepare(delay: (_, cancelled) => cancelled);
    final pending = controller.ads();
    await flush();
    container.read(_selection.notifier).select(null);
    await flush();
    expect((await pending).success, isFalse);
    expect(a.ads, 1);
    expect(container.read(neteaseRewardsProvider).ownerId, isNull);
  });

  test('diagnostic start cancels any subsequent ad mutation', () async {
    await prepare(delay: (_, cancelled) => cancelled);
    final pending = controller.ads();
    await flush();
    container.read(diagnosticActivityProvider.notifier).setRunning(true);
    await pending;
    expect(a.ads, 1);
    expect((await controller.signIn()).success, isFalse);
    expect(a.signs, 0);
  });

  test(
    'unavailable refresh retains same-day balance with a stale label',
    () async {
      await prepare();
      a.snapshot = NeteaseRewardSnapshot(
        now: DateTime(2026, 11, 5),
        freeListen: const NeteaseFreeListenSnapshot(
          remainingSeconds: 1234,
          adCount: 1,
          adTarget: 2,
        ),
      );
      await controller.refresh();
      a.snapshot = NeteaseRewardSnapshot(now: DateTime(2026, 11, 5));
      await controller.refresh();
      final state = container.read(neteaseRewardsProvider);
      expect(state.snapshot?.freeListen?.remainingSeconds, 1234);
      expect(state.freeListenStale, isTrue);
    },
  );

  test(
    'next server day cannot inherit yesterday daily free-listen progress',
    () async {
      await prepare();
      a.snapshot = NeteaseRewardSnapshot(
        now: DateTime(2026, 11, 5),
        signedToday: true,
        freeListen: const NeteaseFreeListenSnapshot(
          todayFree: true,
          adCount: 2,
          adTarget: 2,
        ),
      );
      await controller.refresh();
      a.snapshot = NeteaseRewardSnapshot(now: DateTime(2026, 11, 6));
      await controller.refresh();
      final state = container.read(neteaseRewardsProvider);
      expect(state.snapshot?.signedToday, isNull);
      expect(state.snapshot?.freeListen, isNull);
      expect(state.signedDates.contains('2026-11-06'), isFalse);
    },
  );

  test(
    'cross-midnight receipt records the platform-confirmed day only',
    () async {
      await prepare();
      a.signResult = const NeteaseRewardResult(
        success: true,
        signed: true,
        signedDate: '2026-11-06',
        message: '跨日已确认',
      );
      await controller.signIn();
      expect(container.read(neteaseRewardsProvider).localDates, {'2026-11-06'});
      expect(
        preferences.getStringList(NeteaseRewardsController.datesKey('A')),
        ['2026-11-06'],
      );
      expect(
        container
            .read(neteaseRewardsProvider)
            .localDates
            .contains('2026-11-05'),
        isFalse,
      );
    },
  );

  test(
    'a partial balance read retains known seconds and marks stale',
    () async {
      await prepare();
      a.snapshot = NeteaseRewardSnapshot(
        now: DateTime(2026, 11, 5),
        freeListen: const NeteaseFreeListenSnapshot(
          remainingSeconds: 1234,
          adCount: 1,
          adTarget: 2,
        ),
      );
      await controller.refresh();
      a.snapshot = NeteaseRewardSnapshot(
        now: DateTime(2026, 11, 5),
        freeListen: const NeteaseFreeListenSnapshot(adCount: 2, adTarget: 2),
      );
      await controller.refresh();
      final state = container.read(neteaseRewardsProvider);
      expect(state.snapshot?.freeListen?.remainingSeconds, 1234);
      expect(state.snapshot?.freeListen?.adCount, 2);
      expect(state.freeListenStale, isTrue);
    },
  );

  test(
    'server milestones are retained on partial same-day reads and cleared next day',
    () async {
      await prepare();
      a.snapshot = NeteaseRewardSnapshot(
        now: DateTime(2026, 11, 5),
        freeListen: const NeteaseFreeListenSnapshot(
          remainingSeconds: 1800,
          progressTitle: '继续领取免费听',
          progressSubtitle: '今日任务',
          milestones: [
            NeteaseRewardMilestone(label: '30分钟免费听', done: true, count: 1),
          ],
        ),
      );
      await controller.refresh();
      a.snapshot = NeteaseRewardSnapshot(
        now: DateTime(2026, 11, 5),
        freeListen: const NeteaseFreeListenSnapshot(remainingSeconds: 1700),
      );
      await controller.refresh();
      final previous = container.read(neteaseRewardsProvider);
      expect(previous.snapshot?.freeListen?.progressTitle, '继续领取免费听');
      expect(previous.snapshot?.freeListen?.progressSubtitle, '今日任务');
      expect(previous.snapshot?.freeListen?.milestones.single.count, 1);
      expect(previous.snapshot?.freeListen?.adTarget, isNull);
      expect(previous.snapshot?.freeListen?.adLimit, isNull);
      expect(previous.freeListenStale, isTrue);
      a.snapshot = NeteaseRewardSnapshot(
        now: DateTime(2026, 11, 6),
        freeListen: const NeteaseFreeListenSnapshot(remainingSeconds: 1600),
      );
      await controller.refresh();
      final current = container
          .read(neteaseRewardsProvider)
          .snapshot
          ?.freeListen;
      expect(current?.progressTitle, isNull);
      expect(current?.progressSubtitle, isNull);
      expect(current?.milestones, isEmpty);
    },
  );
}
