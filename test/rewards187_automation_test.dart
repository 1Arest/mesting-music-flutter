import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/core/diagnostics/diagnostic_activity.dart';
import 'package:mesting_music/features/music_platform/data/platform_ad_progress_store.dart';
import 'package:mesting_music/features/music_platform/data/platform_rewards_repository.dart';
import 'package:mesting_music/features/music_platform/domain/platform_rewards.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/music_platform/platform_rewards_provider.dart';
import 'package:mesting_music/features/music_platform/retained_kugou_scope.dart';

const kg = PlatformSession(userId: 'kg', token: 'fake-source');

class _UI extends PlatformAccountController {
  @override
  Future<PlatformSession?> build() async => const PlatformSession(
    userId: 'net',
    token: 'fake-ui',
    platform: MusicPlatform.netease,
  );
}

class _Service implements PlatformRewardService {
  int ads = 0, signs = 0;
  final outcomes = <RewardOutcome>[];
  Completer<RewardOutcome>? pending;
  @override
  Future<RewardSnapshot> load(PlatformSession owner) async =>
      RewardSnapshot(now: DateTime(2026, 11, 10, 10));
  @override
  Future<RewardOutcome> signIn(
    PlatformSession owner,
    DateTime day, {
    RewardVerifier? verify,
  }) async {
    signs++;
    return const RewardOutcome(true, 'ok', signed: true);
  }

  @override
  Future<RewardOutcome> listen(PlatformSession owner) async =>
      const RewardOutcome(true, 'ok');
  @override
  Future<RewardOutcome> ad(PlatformSession owner) async {
    ads++;
    return pending?.future ??
        Future.value(
          outcomes.isEmpty
              ? const RewardOutcome(true, 'confirmed')
              : outcomes.removeAt(0),
        );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;
  late _Service service;
  late ProviderContainer container;
  late DateTime now;
  final waits = <Duration>[];
  Future<void> flush() async {
    for (var i = 0; i < 120; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<PlatformRewardsController> start({
    Map<String, Object> extra = const {},
    RewardDelay? delay,
    bool reuse = false,
    List<RewardOutcome> outcomes = const [],
    Completer<RewardOutcome>? pending,
  }) async {
    if (!reuse) {
      SharedPreferences.setMockInitialValues({
        PlatformRewardsController.autoSignInKey: false,
        ...extra,
      });
    }
    prefs = await SharedPreferences.getInstance();
    service = _Service()
      ..outcomes.addAll(outcomes)
      ..pending = pending;
    now = DateTime(2026, 11, 10, 10);
    waits.clear();
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        platformAccountProvider.overrideWith(_UI.new),
        savedKugouSessionProvider.overrideWith((ref) async => kg),
        platformRewardServiceProvider.overrideWithValue(service),
        platformRewardClockProvider.overrideWithValue(() => now),
        platformRewardDelayProvider.overrideWithValue(
          delay ??
              (interval, cancelled) async {
                waits.add(interval);
                now = now.add(interval);
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

  test(
    'default startup claims under NetEase UI and stops at eight confirmed daily claims',
    () async {
      final controller = await start();
      expect(service.ads, 8);
      expect(service.signs, 0);
      expect(waits, List.filled(7, const Duration(seconds: 30)));
      expect(
        container.read(platformAccountProvider).value!.platform,
        MusicPlatform.netease,
      );
      expect(PlatformAdProgress.read(prefs, 'kg', '2026-11-10').count, 8);
      expect((await controller.ads()).quotaDone, isTrue);
      expect(service.ads, 8);
    },
  );
  test(
    'independent off switch and explicit enabling preserve sign-in setting',
    () async {
      final controller = await start(
        extra: {PlatformRewardsController.autoAdsKey('kg'): false},
      );
      expect(service.ads, 0);
      await controller.setAutoAds(true);
      await flush();
      expect(service.ads, 8);
      expect(service.signs, 0);
      expect(prefs.getBool(PlatformRewardsController.autoSignInKey), false);
    },
  );
  test('restart resumes confirmed count and remaining 30 second gap', () async {
    final time = DateTime(2026, 11, 10, 10).millisecondsSinceEpoch;
    await start(
      extra: {
        PlatformAdProgress.key('kg', '2026-11-10'): [
          '3',
          '${time - 5000}',
          'pending',
        ],
      },
    );
    expect(service.ads, 5);
    expect(waits.first, const Duration(seconds: 25));
    expect(waits.skip(1), List.filled(4, const Duration(seconds: 30)));
    expect(PlatformAdProgress.read(prefs, 'kg', '2026-11-10').count, 8);
  });
  test('turning off during the interval cancels the next request', () async {
    final entered = Completer<void>();
    final controller = await start(
      delay: (interval, cancelled) async {
        if (!entered.isCompleted) entered.complete();
        await cancelled;
      },
    );
    expect(entered.isCompleted, true);
    expect(service.ads, 1);
    await controller.setAutoAds(false);
    await flush();
    expect(service.ads, 1);
    expect(container.read(platformRewardsProvider).action, isNull);
  });
  test(
    'diagnostics stop an automatic batch and never restart it in that process',
    () async {
      await start(delay: (interval, cancelled) async => cancelled);
      expect(service.ads, 1);
      container.read(diagnosticActivityProvider.notifier).state = true;
      await flush();
      expect(service.ads, 1);
      container.read(diagnosticActivityProvider.notifier).state = false;
      await flush();
      expect(service.ads, 1);
    },
  );
  test(
    'a failed automatic claim stops and token refresh cannot start a retry storm',
    () async {
      final controller = await start(
        outcomes: [const RewardOutcome(false, 'fixture failure')],
      );
      expect(service.ads, 1);
      container
          .read(retainedKugouMutationProvider.notifier)
          .publish(const PlatformSession(userId: 'kg', token: 'rotated-fake'));
      await flush();
      expect(service.ads, 1);
      await controller.ads();
      expect(service.ads, 9);
    },
  );
  test(
    'confirmed server quota persists across restart without claiming eight rewards locally',
    () async {
      await start(
        outcomes: [
          const RewardOutcome(true, 'confirmed'),
          const RewardOutcome(true, 'quota', quotaDone: true),
        ],
      );
      expect(service.ads, 2);
      final progress = PlatformAdProgress.read(prefs, 'kg', '2026-11-10');
      expect(progress.count, 1);
      expect(progress.done, true);
      container.dispose();
      await start(reuse: true);
      expect(service.ads, 0);
    },
  );
  test(
    'logout cancels a late claim response instead of marking another owner',
    () async {
      final pending = Completer<RewardOutcome>();
      await start(pending: pending);
      expect(service.ads, 1);
      container.read(retainedKugouMutationProvider.notifier).publish(null);
      await flush();
      pending.complete(const RewardOutcome(true, 'late confirmed'));
      await flush();
      expect(service.ads, 1);
      expect(container.read(platformRewardsProvider).ownerId, isNull);
      expect(PlatformAdProgress.read(prefs, 'kg', '2026-11-10').count, 0);
    },
  );
}
