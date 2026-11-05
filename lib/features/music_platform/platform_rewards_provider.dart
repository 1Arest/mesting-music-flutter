import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/persistence/app_preferences.dart';
import 'data/platform_rewards_repository.dart';
import 'domain/platform_rewards.dart';
import 'domain/platform_session.dart';
import 'retained_kugou_scope.dart';
import '../../core/diagnostics/diagnostic_activity.dart';
import 'netease/netease_rewards_provider.dart';

final platformRewardServiceProvider = Provider<PlatformRewardService>(
  (ref) => PlatformRewardsRepository(
    ref.watch(retainedKugouScopeProvider)!.api,
    allowMutation: () => ref.mounted && !ref.read(diagnosticActivityProvider),
  ),
);
typedef RewardDelay =
    Future<void> Function(Duration interval, Future<void> cancelled);
final platformRewardDelayProvider = Provider<RewardDelay>(
  (ref) => _waitForInterval,
);

Future<void> _waitForInterval(Duration interval, Future<void> cancelled) async {
  final done = Completer<void>();
  final timer = Timer(interval, () {
    if (!done.isCompleted) done.complete();
  });
  unawaited(
    cancelled.then((_) {
      if (!done.isCompleted) done.complete();
    }),
  );
  try {
    await done.future;
  } finally {
    timer.cancel();
  }
}

class PlatformRewardState {
  const PlatformRewardState({
    this.ownerId,
    this.snapshot,
    this.localDates = const {},
    this.loading = false,
    this.autoSignIn = true,
    this.action,
    this.adCount = 0,
    this.adWaiting = false,
    this.message,
    this.needsVerification = false,
  });
  final String? ownerId, message;
  final RewardSnapshot? snapshot;
  final Set<String> localDates;
  final bool loading, autoSignIn, adWaiting, needsVerification;
  final RewardAction? action;
  final int adCount;
  Set<String> get signedDates => {...?snapshot?.signedDates, ...localDates};
  PlatformRewardState copyWith({
    RewardSnapshot? snapshot,
    Set<String>? localDates,
    bool? loading,
    bool? autoSignIn,
    RewardAction? action,
    bool clearAction = false,
    int? adCount,
    bool? adWaiting,
    String? message,
    bool? needsVerification,
  }) => PlatformRewardState(
    ownerId: ownerId,
    snapshot: snapshot ?? this.snapshot,
    localDates: localDates ?? this.localDates,
    loading: loading ?? this.loading,
    autoSignIn: autoSignIn ?? this.autoSignIn,
    action: clearAction ? null : action ?? this.action,
    adCount: adCount ?? this.adCount,
    adWaiting: adWaiting ?? this.adWaiting,
    message: message ?? this.message,
    needsVerification: needsVerification ?? this.needsVerification,
  );
}

final platformRewardsProvider =
    NotifierProvider<PlatformRewardsController, PlatformRewardState>(
      PlatformRewardsController.new,
    );

/// Starting this provider keeps automation alive without rebuilding the entire
/// music shell for each reward progress update. Only the Beta shell watches it.
final platformRewardAutomationProvider = Provider<void>((ref) {
  ref.watch(platformRewardsProvider.select((s) => s.ownerId));
  ref.watch(neteaseRewardsProvider.select((s) => s.ownerId));
});

/// Account-owned orchestration. Every await is followed by an owner/generation
/// check; logout cancels pending intervals and discards old response state.
class PlatformRewardsController extends Notifier<PlatformRewardState> {
  static const autoSignInKey = 'md3_rewards.auto_sign_in';
  static String datesKey(String owner) => 'md3_rewards.signed_dates.$owner';
  int _generation = 0, _loadVersion = 0;
  Completer<void>? _adAbort;

  @override
  PlatformRewardState build() {
    ref.watch(
      retainedKugouSessionProvider.select(
        (s) => (s?.userId, s?.token, s?.vipToken),
      ),
    );
    final owner = ref.read(retainedKugouSessionProvider);
    ref.listen(diagnosticActivityProvider, (_, running) {
      if (running) stopAds();
    });
    final ticket = ++_generation;
    _loadVersion++;
    _adAbort = null;
    ref.onDispose(() {
      _generation++;
      stopAds();
    });
    if (owner == null || owner.platform != MusicPlatform.kugou) {
      return const PlatformRewardState();
    }
    final preferences = ref.read(sharedPreferencesProvider);
    final dates =
        preferences.getStringList(datesKey(owner.userId))?.toSet() ??
        <String>{};
    final automatic = preferences.getBool(autoSignInKey) ?? true;
    unawaited(
      Future<void>.microtask(() async {
        if (!_valid(ticket, owner)) return;
        await refresh();
        if (!_valid(ticket, owner) ||
            !state.autoSignIn ||
            ref.read(diagnosticActivityProvider) ||
            state.action != null) {
          return;
        }
        final day = state.snapshot?.now ?? DateTime.now();
        if (!state.signedDates.contains(rewardDateKey(day))) await signIn();
      }),
    );
    return PlatformRewardState(
      ownerId: owner.userId,
      localDates: dates,
      loading: true,
      autoSignIn: automatic,
    );
  }

  bool _valid(int ticket, PlatformSession owner) {
    if (!ref.mounted || ticket != _generation) return false;
    final current = ref.read(retainedKugouSessionProvider);
    return current?.userId == owner.userId && current?.token == owner.token;
  }

  Future<void> setAutoSignIn(bool enabled) async {
    final owner = ref.read(retainedKugouSessionProvider);
    if (owner == null) return;
    final ticket = _generation;
    final saved = await ref
        .read(sharedPreferencesProvider)
        .setBool(autoSignInKey, enabled);
    if (!saved) throw StateError('自动签到设置未保存，请重试');
    if (!_valid(ticket, owner)) return;
    state = state.copyWith(autoSignIn: enabled);
    // Enabling is an explicit request; completed days are never claimed again.
    if (enabled &&
        !ref.read(diagnosticActivityProvider) &&
        !state.signedDates.contains(
          rewardDateKey(state.snapshot?.now ?? DateTime.now()),
        )) {
      unawaited(signIn());
    }
  }

  Future<void> refresh() async {
    final owner = ref.read(retainedKugouSessionProvider);
    if (owner == null) return;
    final ticket = _generation, load = ++_loadVersion;
    state = state.copyWith(loading: true);
    try {
      final snapshot = await ref
          .read(platformRewardServiceProvider)
          .load(owner);
      if (!_valid(ticket, owner) || load != _loadVersion) return;
      // Failed refreshes retain the last confirmed records, never replace them
      // with a fabricated zero-day history or an inactive membership.
      final previous = state.snapshot;
      state = state.copyWith(
        snapshot: RewardSnapshot(
          now: snapshot.now,
          signedDates: snapshot.recordsAvailable
              ? snapshot.signedDates
              : previous?.signedDates ?? {},
          memberships: snapshot.membershipsAvailable
              ? snapshot.memberships
              : previous?.memberships ?? [],
          recordsAvailable: snapshot.recordsAvailable,
          membershipsAvailable: snapshot.membershipsAvailable,
        ),
        loading: false,
      );
    } on Object {
      if (_valid(ticket, owner) && load == _loadVersion) {
        state = state.copyWith(loading: false, message: '签到信息暂时无法加载，请下拉重试');
      }
    }
  }

  Future<RewardOutcome> _run(
    RewardAction action,
    Future<RewardOutcome> Function(PlatformSession owner, int ticket) operation,
  ) async {
    final owner = ref.read(retainedKugouSessionProvider);
    if (owner == null) return const RewardOutcome(false, '请先登录酷狗账号');
    if (ref.read(diagnosticActivityProvider)) {
      return const RewardOutcome(false, '流畅度诊断期间暂停签到与奖励领取');
    }
    if (state.action != null) return const RewardOutcome(false, '当前领取尚未完成，请稍候');
    final ticket = _generation;
    state = state.copyWith(action: action, adCount: 0, adWaiting: false);
    RewardOutcome result;
    try {
      result = await operation(owner, ticket);
    } on Object {
      result = const RewardOutcome(false, '请求未完成，请检查网络后重试；结果以平台记录为准');
    }
    if (!_valid(ticket, owner)) {
      return const RewardOutcome(false, '账号已变化，本次操作已停止');
    }
    state = state.copyWith(
      message: result.message,
      needsVerification: result.needsVerification,
      clearAction: true,
      adWaiting: false,
    );
    if (action == RewardAction.ad) {
      stopAds();
      _adAbort = null;
    }
    // Confirmation is immediate; a slow record refresh cannot turn a completed
    // write into a failure or hold its success message behind a loading state.
    unawaited(refresh());
    return result;
  }

  Future<RewardOutcome> signIn({RewardVerifier? verify}) => _run(
    RewardAction.signIn,
    (owner, ticket) async {
      // Re-read server time before a manual retry (including across midnight).
      await refresh();
      if (!_valid(ticket, owner) || ref.read(diagnosticActivityProvider)) {
        return const RewardOutcome(false, '账号已变化或诊断已启动');
      }
      final day = state.snapshot?.now ?? DateTime.now();
      if (state.signedDates.contains(rewardDateKey(day))) {
        return const RewardOutcome(true, '今日签到已确认', signed: true);
      }
      final result = await ref
          .read(platformRewardServiceProvider)
          .signIn(
            owner,
            day,
            verify: verify == null
                ? null
                : (challenge) async {
                    if (!_valid(ticket, owner)) return null;
                    final proof = await verify(challenge);
                    return _valid(ticket, owner) ? proof : null;
                  },
          );
      if (_valid(ticket, owner) && result.signed) {
        final dates = {...state.localDates, rewardDateKey(day)};
        final saved = await ref
            .read(sharedPreferencesProvider)
            .setStringList(datesKey(owner.userId), dates.toList()..sort());
        if (_valid(ticket, owner)) {
          state = state.copyWith(localDates: dates);
          if (!saved) {
            return const RewardOutcome(
              true,
              '签到已确认，本机记录未保存，请刷新平台记录',
              signed: true,
            );
          }
        }
      }
      return result;
    },
  );

  Future<RewardOutcome> listen() => _run(
    RewardAction.listen,
    (owner, _) => ref.read(platformRewardServiceProvider).listen(owner),
  );

  void stopAds() {
    final abort = _adAbort;
    if (abort != null && !abort.isCompleted) abort.complete();
  }

  Future<RewardOutcome> ads() => _run(RewardAction.ad, (owner, ticket) async {
    final abort = Completer<void>();
    _adAbort = abort;
    var successes = 0;
    // Preserve upstream's maximum eight claims and 30s successful-claim gap.
    // A quota response is terminal; cancellation/owner change prevents any
    // later request rather than merely hiding its UI.
    for (var attempt = 0; attempt < 8; attempt++) {
      if (!_valid(ticket, owner) ||
          abort.isCompleted ||
          ref.read(diagnosticActivityProvider)) {
        break;
      }
      final result = await ref.read(platformRewardServiceProvider).ad(owner);
      if (!_valid(ticket, owner)) break;
      if (result.quotaDone) {
        return RewardOutcome(
          true,
          '今日广告次数已用完，已确认 $successes 次',
          quotaDone: true,
        );
      }
      if (!result.success) {
        return RewardOutcome(false, '已确认 $successes 次；${result.message}');
      }
      successes++;
      state = state.copyWith(adCount: successes);
      if (attempt != 7) {
        state = state.copyWith(adWaiting: true);
        await ref.read(platformRewardDelayProvider)(
          const Duration(seconds: 30),
          abort.future,
        );
        if (_valid(ticket, owner)) state = state.copyWith(adWaiting: false);
      }
    }
    return RewardOutcome(
      true,
      abort.isCompleted ? '已停止广告领取，已确认 $successes 次' : '广告奖励已领取 $successes/8 次',
    );
  });
}
