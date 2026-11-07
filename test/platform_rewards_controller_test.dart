import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/features/music_platform/data/platform_rewards_repository.dart';
import 'package:mesting_music/features/music_platform/domain/platform_rewards.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/music_platform/platform_rewards_provider.dart';
import 'package:mesting_music/features/music_platform/retained_kugou_scope.dart';

const _a = PlatformSession(userId: 'A', token: 'fixture-A');
const _b = PlatformSession(userId: 'B', token: 'fixture-B');

class _Account extends PlatformAccountController {
  @override
  Future<PlatformSession?> build() async => _a;
  void select(PlatformSession? next) {
    state = AsyncData(next);
  }
}

class _Service implements PlatformRewardService {
  RewardSnapshot snapshot = RewardSnapshot(now: DateTime(2026, 10, 26, 18));
  int signs = 0, listens = 0, ads = 0;
  DateTime? signedDay;
  Completer<RewardOutcome>? signPending, listenPending;
  List<RewardOutcome> adResults = [];
  @override
  Future<RewardSnapshot> load(PlatformSession owner) async => snapshot;
  @override
  Future<RewardOutcome> signIn(
    PlatformSession owner,
    DateTime day, {
    RewardVerifier? verify,
  }) async {
    signs++;
    signedDay = day;
    return await (signPending?.future ??
        Future.value(const RewardOutcome(true, '签到成功', signed: true)));
  }

  @override
  Future<RewardOutcome> listen(PlatformSession owner) async {
    listens++;
    return await (listenPending?.future ??
        Future.value(const RewardOutcome(true, '听歌领取成功')));
  }

  @override
  Future<RewardOutcome> ad(PlatformSession owner) async {
    ads++;
    return adResults.isEmpty
        ? const RewardOutcome(true, '已领取')
        : adResults.removeAt(0);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ProviderContainer container;
  late SharedPreferences preferences;
  late _Service service;
  final waits = <Duration>[];
  Future<void> flush() async {
    for (var i = 0; i < 15; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<PlatformRewardsController> prepare({
    bool automatic = false,
    RewardDelay? delay,
  }) async {
    SharedPreferences.setMockInitialValues({
      PlatformRewardsController.autoSignInKey: automatic,
    });
    preferences = await SharedPreferences.getInstance();
    service = _Service();
    waits.clear();
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        platformAccountProvider.overrideWith(_Account.new),
        savedKugouSessionProvider.overrideWith((ref) async => null),
        platformRewardServiceProvider.overrideWithValue(service),
        platformRewardDelayProvider.overrideWithValue(
          delay ??
              (duration, cancelled) async {
                waits.add(duration);
              },
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(platformAccountProvider.future);
    container.listen(platformRewardsProvider, (_, _) {});
    await flush();
    return container.read(platformRewardsProvider.notifier);
  }

  test('disabled automation reads records without sending a sign-in', () async {
    await prepare();
    expect(service.signs, 0);
    expect(container.read(platformRewardsProvider).ownerId, 'A');
  });
  test(
    'automatic sign-in persists only the confirmed owner/day and skips a repeated login',
    () async {
      await prepare(automatic: true);
      expect(service.signs, 1);
      expect(
        preferences.getStringList(PlatformRewardsController.datesKey('A')),
        ['2026-10-26'],
      );
      (container.read(platformAccountProvider.notifier) as _Account).select(
        const PlatformSession(userId: 'A', token: 'rotated-fixture'),
      );
      await flush();
      expect(service.signs, 1);
    },
  );
  test(
    'a late old-account sign-in cannot mark the new account or its cache',
    () async {
      final controller = await prepare();
      service.signPending = Completer();
      final operation = controller.signIn();
      await flush();
      (container.read(platformAccountProvider.notifier) as _Account).select(_b);
      await flush();
      service.signPending!.complete(
        const RewardOutcome(true, '签到成功', signed: true),
      );
      expect((await operation).success, false);
      expect(container.read(platformRewardsProvider).ownerId, 'B');
      expect(container.read(platformRewardsProvider).localDates, isEmpty);
      expect(
        preferences.getStringList(PlatformRewardsController.datesKey('B')),
        isNull,
      );
    },
  );
  test(
    'an unfinished request prevents a second concurrent reward write',
    () async {
      final controller = await prepare();
      service.listenPending = Completer();
      final pending = controller.listen();
      await flush();
      expect((await controller.signIn()).success, false);
      expect(service.signs, 0);
      service.listenPending!.complete(const RewardOutcome(true, '已领取'));
      await pending;
    },
  );
  test(
    'ad claims stop at eight with seven 30-second successful-claim intervals',
    () async {
      final controller = await prepare();
      final result = await controller.ads();
      expect(result.success, true);
      expect(service.ads, 8);
      expect(waits, List.filled(7, const Duration(seconds: 30)));
      expect(container.read(platformRewardsProvider).adCount, 8);
    },
  );
  test(
    'quota terminates the ad batch without pretending there were eight successes',
    () async {
      final controller = await prepare();
      service.adResults = [
        const RewardOutcome(true, '成功'),
        const RewardOutcome(true, '次数用完', quotaDone: true),
      ];
      final result = await controller.ads();
      expect(result.quotaDone, true);
      expect(service.ads, 2);
      expect(container.read(platformRewardsProvider).adCount, 1);
      expect(result.message, contains('1 次'));
    },
  );
  test('stop during the interval prevents all further ad requests', () async {
    final controller = await prepare(delay: (_, cancelled) => cancelled);
    final operation = controller.ads();
    await flush();
    expect(service.ads, 1);
    controller.stopAds();
    final result = await operation;
    expect(result.message, contains('已停止'));
    expect(service.ads, 1);
  });
  test(
    'logout cancels the pending ad interval and cannot resume a request',
    () async {
      final controller = await prepare(delay: (_, cancelled) => cancelled);
      final operation = controller.ads();
      await flush();
      (container.read(platformAccountProvider.notifier) as _Account).select(
        null,
      );
      await flush();
      expect((await operation).success, false);
      expect(service.ads, 1);
      expect(container.read(platformRewardsProvider).ownerId, isNull);
    },
  );
  test('failed record refresh retains confirmed platform dates', () async {
    final controller = await prepare();
    service.snapshot = RewardSnapshot(
      now: DateTime(2026, 10, 26),
      signedDates: {'2026-10-25'},
    );
    await controller.refresh();
    service.snapshot = RewardSnapshot(
      now: DateTime(2026, 10, 26),
      recordsAvailable: false,
    );
    await controller.refresh();
    expect(container.read(platformRewardsProvider).signedDates, {'2026-10-25'});
    expect(
      container.read(platformRewardsProvider).snapshot!.recordsAvailable,
      false,
    );
  });
  test('manual sign-in refreshes the server day across midnight', () async {
    final controller = await prepare();
    service.snapshot = RewardSnapshot(now: DateTime(2026, 10, 27));
    await controller.signIn();
    expect(service.signedDay, DateTime(2026, 10, 27));
    expect(container.read(platformRewardsProvider).localDates, {'2026-10-27'});
  });
}
