import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/diagnostics/diagnostic_activity.dart';
import '../../../core/network/system_music_io_client.dart';
import '../../../core/persistence/app_preferences.dart';
import '../domain/platform_rewards.dart' show rewardDateKey;
import '../music_platform_providers.dart';
import '../retained_kugou_scope.dart';
import 'netease_api.dart';
import 'netease_features_repository.dart';
import 'netease_music_repository.dart';
import 'netease_providers.dart';
import 'netease_rewards.dart';
import 'netease_rewards_repository.dart';

/// A separate cookie jar permits signing in to the saved NetEase account while
/// Kugou owns playback. Reward requests never reconfigure the music player API.
final retainedNeteaseRewardProvider =
    FutureProvider<NeteaseFeaturesRepository?>((ref) async {
      ref.watch(retainedNeteaseEpochProvider);
      ref.watch(
        platformAccountProvider.select(
          (a) => (a.value?.ownerId, a.value?.token),
        ),
      );
      final session = await ref
          .watch(neteaseSessionStoreProvider)
          .read()
          .timeout(const Duration(seconds: 5));
      if (!ref.mounted || session == null) return null;
      final client = SystemMusicIoClient();
      final api = NeteaseApi(client)..configure(session);
      ref.onDispose(() {
        api.configure(null);
        client.close();
      });
      return NeteaseFeaturesRepository(NeteaseMusicRepository(api));
    }, retry: (_, _) => null);

final neteaseRewardServiceProvider = FutureProvider<NeteaseRewardService?>((
  ref,
) async {
  final features = await ref.watch(retainedNeteaseRewardProvider.future);
  if (!ref.mounted || features == null) return null;
  return NeteaseRewardsRepository(
    features.music,
    preferences: ref.read(sharedPreferencesProvider),
    allowMutation: () => ref.mounted && !ref.read(diagnosticActivityProvider),
  );
}, retry: (_, _) => null);

typedef NeteaseRewardDelay =
    Future<void> Function(Duration interval, Future<void> cancelled);
final neteaseRewardDelayProvider = Provider<NeteaseRewardDelay>(
  (ref) => (interval, cancelled) async {
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
  },
);

/// This is a local batch guard, not an asserted NetEase daily entitlement.
final neteaseRewardBatchLimitProvider = Provider<int>((ref) => 8);
final neteaseRewardClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

class NeteaseRewardState {
  const NeteaseRewardState({
    this.ownerId,
    this.snapshot,
    this.localDates = const {},
    this.sessionLoading = false,
    this.sessionError = false,
    this.loading = false,
    this.autoSignIn = true,
    this.action,
    this.confirmedAds = 0,
    this.adWaiting = false,
    this.freeListenStale = false,
    this.message,
  });

  final String? ownerId, message;
  final NeteaseRewardSnapshot? snapshot;
  final Set<String> localDates;
  final bool sessionLoading, sessionError, loading, autoSignIn, adWaiting;
  final bool freeListenStale;
  final NeteaseRewardAction? action;
  final int confirmedAds;
  Set<String> get signedDates => {
    ...localDates,
    ...?snapshot?.signedDates,
    if (snapshot?.signedToday == true) rewardDateKey(snapshot!.now),
  };

  NeteaseRewardState copyWith({
    NeteaseRewardSnapshot? snapshot,
    Set<String>? localDates,
    bool? loading,
    bool? autoSignIn,
    NeteaseRewardAction? action,
    bool clearAction = false,
    int? confirmedAds,
    bool? adWaiting,
    bool? freeListenStale,
    String? message,
    bool clearMessage = false,
  }) => NeteaseRewardState(
    ownerId: ownerId,
    snapshot: snapshot ?? this.snapshot,
    localDates: localDates ?? this.localDates,
    sessionLoading: sessionLoading,
    sessionError: sessionError,
    loading: loading ?? this.loading,
    autoSignIn: autoSignIn ?? this.autoSignIn,
    action: clearAction ? null : action ?? this.action,
    confirmedAds: confirmedAds ?? this.confirmedAds,
    adWaiting: adWaiting ?? this.adWaiting,
    freeListenStale: freeListenStale ?? this.freeListenStale,
    message: clearMessage ? null : message ?? this.message,
  );
}

final neteaseRewardsProvider =
    NotifierProvider<NeteaseRewardsController, NeteaseRewardState>(
      NeteaseRewardsController.new,
    );

/// Owns reward sequencing, independent of the tab's widget lifetime. Every
/// asynchronous continuation checks the service identity and retained epoch;
/// an A→B→A account transition cannot revive the first A's request or interval.
class NeteaseRewardsController extends Notifier<NeteaseRewardState> {
  static String datesKey(String owner) => 'netease_rewards.signed_dates.$owner';
  static String autoKey(String owner) => 'netease_rewards.auto_sign_in.$owner';
  static String attemptKey(String owner) =>
      'netease_rewards.auto_attempt.$owner';
  int _generation = 0, _loadVersion = 0, _epoch = 0, _settingsVersion = 0;
  Completer<void>? _adAbort;

  @override
  NeteaseRewardState build() {
    stopAds();
    _adAbort = null;
    final ticket = ++_generation;
    _loadVersion++;
    _epoch = ref.watch(retainedNeteaseEpochProvider);
    final value = ref.watch(neteaseRewardServiceProvider);
    ref.listen(diagnosticActivityProvider, (_, active) {
      if (active) stopAds();
    });
    ref.onDispose(() {
      _generation++;
      stopAds();
    });
    // AsyncValue can retain a previous value during recomputation. Never use
    // that cookie jar while the saved login is being replaced or read again.
    if (value.isLoading) {
      return const NeteaseRewardState(sessionLoading: true);
    }
    if (value.hasError) return const NeteaseRewardState(sessionError: true);
    final service = value.value;
    if (service == null) return const NeteaseRewardState();
    final preferences = ref.read(sharedPreferencesProvider);
    final dates = preferences.getStringList(datesKey(service.ownerId)) ?? [];
    final automatic = preferences.getBool(autoKey(service.ownerId)) ?? true;
    // Foreground restoration and a low-frequency day-boundary timer cover a
    // kept-alive session without a polling loop or a background reward service.
    final observer = AppLifecycleListener(
      onResume: () {
        if (_valid(ticket, service)) unawaited(resume());
      },
    );
    Timer? midnight;
    void scheduleDayBoundary() {
      final now = ref.read(neteaseRewardClockProvider)();
      final next = DateTime(now.year, now.month, now.day + 1, 0, 0, 2);
      midnight = Timer(next.difference(now), () {
        if (!_valid(ticket, service)) return;
        unawaited(resume());
        scheduleDayBoundary();
      });
    }

    scheduleDayBoundary();
    ref.onDispose(() {
      midnight?.cancel();
      observer.dispose();
    });
    unawaited(
      Future<void>.microtask(() async {
        if (_valid(ticket, service)) await resume();
      }),
    );
    return NeteaseRewardState(
      ownerId: service.ownerId,
      localDates: dates.where(_validDate).toSet(),
      autoSignIn: automatic,
      loading: true,
    );
  }

  static bool _validDate(String value) {
    final parsed = DateTime.tryParse(value);
    return parsed != null && rewardDateKey(parsed) == value;
  }

  NeteaseRewardService? get _service {
    final value = ref.read(neteaseRewardServiceProvider);
    return value.isLoading || value.hasError ? null : value.value;
  }

  bool _valid(int ticket, NeteaseRewardService service) =>
      ref.mounted &&
      ticket == _generation &&
      _epoch == ref.read(retainedNeteaseEpochProvider) &&
      identical(_service, service);

  DateTime get _day =>
      state.snapshot?.now ?? ref.read(neteaseRewardClockProvider)();

  Future<void> resume() async {
    final service = _service;
    if (service == null || state.action != null) return;
    final ticket = _generation;
    await refresh();
    if (!_valid(ticket, service) || !state.autoSignIn) return;
    final day = rewardDateKey(_day);
    if (state.signedDates.contains(day) ||
        ref.read(diagnosticActivityProvider) ||
        ref
                .read(sharedPreferencesProvider)
                .getString(attemptKey(service.ownerId)) ==
            day) {
      return;
    }
    await signIn(automatic: true);
  }

  Future<void> setAutoSignIn(bool enabled) async {
    final service = _service;
    if (service == null) return;
    final ticket = _generation;
    final setting = ++_settingsVersion;
    final saved = await ref
        .read(sharedPreferencesProvider)
        .setBool(autoKey(service.ownerId), enabled);
    if (!_valid(ticket, service) || setting != _settingsVersion) return;
    if (!saved) throw StateError('自动签到设置未保存');
    state = state.copyWith(autoSignIn: enabled);
    if (enabled) unawaited(resume());
  }

  Future<void> refresh() async {
    final service = _service;
    if (service == null) return;
    final ticket = _generation, version = ++_loadVersion;
    state = state.copyWith(loading: true);
    try {
      final incoming = await service.load();
      if (!_valid(ticket, service) || version != _loadVersion) return;
      final previous = state.snapshot;
      final sameDay =
          previous != null &&
          rewardDateKey(previous.now) == rewardDateKey(incoming.now);
      // Historical confirmed dates survive a failed record read. Today's flags
      // and daily ad progress can only be carried within the same server day.
      final previousFree = sameDay ? previous.freeListen : null;
      final newFree = incoming.freeListen;
      final free = newFree == null
          ? previousFree
          : NeteaseFreeListenSnapshot(
              remainingSeconds:
                  newFree.remainingSeconds ?? previousFree?.remainingSeconds,
              adCount: newFree.adCount ?? previousFree?.adCount,
              adTarget: newFree.adTarget ?? previousFree?.adTarget,
              adLimit: newFree.adLimit ?? previousFree?.adLimit,
              todayFree: newFree.todayFree ?? previousFree?.todayFree,
              claimInterval:
                  newFree.claimInterval ?? previousFree?.claimInterval,
              message: newFree.message,
              progressTitle:
                  newFree.progressTitle ?? previousFree?.progressTitle,
              progressSubtitle:
                  newFree.progressSubtitle ?? previousFree?.progressSubtitle,
              milestones: newFree.milestones.isNotEmpty
                  ? newFree.milestones
                  : previousFree?.milestones ?? const [],
            );
      final knownDates = <String>{
        ...?previous?.signedDates,
        ...incoming.signedDates,
        if (incoming.signedToday == true) rewardDateKey(incoming.now),
      };
      state = state.copyWith(
        snapshot: NeteaseRewardSnapshot(
          now: incoming.now,
          signedDates: incoming.recordsAvailable
              ? {
                  ...incoming.signedDates,
                  if (incoming.signedToday == true) rewardDateKey(incoming.now),
                }
              : knownDates,
          signedToday:
              incoming.signedToday ?? (sameDay ? previous.signedToday : null),
          recordsAvailable: incoming.recordsAvailable,
          freeListen: free,
          message: incoming.message,
        ),
        loading: false,
        freeListenStale:
            newFree == null ||
            (newFree.remainingSeconds == null &&
                previousFree?.remainingSeconds != null) ||
            (newFree.adCount == null && previousFree?.adCount != null) ||
            (newFree.milestones.isEmpty &&
                previousFree?.milestones.isNotEmpty == true),
      );
      // A read of today's authoritative signed flag is also a real receipt.
      // Retain its exact date so tomorrow's calendar survives a cold restart.
      final confirmedDates = {
        ...state.localDates,
        for (final date in incoming.signedDates)
          if (_validDate(date) &&
              date.compareTo(rewardDateKey(incoming.now)) <= 0)
            date,
        if (incoming.signedToday == true) rewardDateKey(incoming.now),
      };
      if (confirmedDates.length != state.localDates.length) {
        state = state.copyWith(localDates: confirmedDates);
        final persisted = await ref
            .read(sharedPreferencesProvider)
            .setStringList(
              datesKey(service.ownerId),
              confirmedDates.toList()..sort(),
            );
        if (!_valid(ticket, service) || version != _loadVersion) return;
        if (!persisted) {
          // The platform confirmation remains valid even if disk persistence
          // fails. Report only the local durability problem, never undo a day.
          state = state.copyWith(message: '签到已确认，本机记录未保存，请刷新平台状态');
        }
      }
    } catch (_) {
      if (!_valid(ticket, service) || version != _loadVersion) return;
      final now = ref.read(neteaseRewardClockProvider)();
      final previous = state.snapshot;
      final sameDay =
          previous != null && rewardDateKey(previous.now) == rewardDateKey(now);
      state = state.copyWith(
        snapshot: NeteaseRewardSnapshot(
          now: now,
          signedDates: previous?.signedDates ?? const {},
          signedToday: sameDay ? previous.signedToday : null,
          recordsAvailable: false,
          freeListen: sameDay ? previous.freeListen : null,
        ),
        loading: false,
        freeListenStale: true,
        message: '签到与免费听信息暂未更新，下拉可重试',
      );
    }
  }

  Future<NeteaseRewardResult> _run(
    NeteaseRewardAction action,
    Future<NeteaseRewardResult> Function(NeteaseRewardService, int) operation,
  ) async {
    final service = _service;
    if (service == null) {
      return const NeteaseRewardResult(success: false, message: '请先登录网易云账号');
    }
    if (ref.read(diagnosticActivityProvider)) {
      return const NeteaseRewardResult(
        success: false,
        message: '流畅度诊断期间暂停签到与奖励领取',
      );
    }
    if (state.action != null) {
      return const NeteaseRewardResult(success: false, message: '当前操作尚未完成，请稍候');
    }
    final ticket = _generation;
    state = state.copyWith(
      action: action,
      confirmedAds: 0,
      adWaiting: false,
      clearMessage: true,
    );
    NeteaseRewardResult result;
    try {
      result = await operation(service, ticket);
    } catch (_) {
      result = const NeteaseRewardResult(
        success: false,
        uncertain: true,
        message: '请求结果未确认，请刷新核对；本次不会自动重试',
      );
    }
    if (!_valid(ticket, service)) {
      return const NeteaseRewardResult(
        success: false,
        message: '账号已变化，本次操作已停止',
      );
    }
    if (action == NeteaseRewardAction.ad) {
      stopAds();
      _adAbort = null;
    }
    state = state.copyWith(
      clearAction: true,
      adWaiting: false,
      message: result.message,
    );
    unawaited(refresh());
    return result;
  }

  Future<NeteaseRewardResult> signIn({
    bool automatic = false,
  }) => _run(NeteaseRewardAction.signIn, (service, ticket) async {
    await refresh();
    if (!_valid(ticket, service) || ref.read(diagnosticActivityProvider)) {
      return const NeteaseRewardResult(success: false, message: '账号已变化或诊断已启动');
    }
    final day = rewardDateKey(_day);
    if (state.signedDates.contains(day)) {
      return const NeteaseRewardResult(
        success: true,
        signed: true,
        message: '网易云今日签到已确认',
      );
    }
    final preferences = ref.read(sharedPreferencesProvider);
    if (automatic &&
        preferences.getString(attemptKey(service.ownerId)) == day) {
      return const NeteaseRewardResult(
        success: false,
        message: '今日已尝试自动签到，可刷新记录后手动核对',
      );
    }
    // Persist before the POST: process death or a lost reply must not cause
    // the next startup to replay an automatic write with unknown outcome.
    final saved = await preferences.setString(attemptKey(service.ownerId), day);
    if (!_valid(ticket, service) || ref.read(diagnosticActivityProvider)) {
      return const NeteaseRewardResult(success: false, message: '账号已变化或诊断已启动');
    }
    if (!saved) {
      return const NeteaseRewardResult(
        success: false,
        message: '签到防重复记录未保存，请稍后重试',
      );
    }
    final result = await service.signIn();
    if (!_valid(ticket, service)) {
      return const NeteaseRewardResult(success: false, message: '账号已变化');
    }
    if (result.success && result.signed) {
      final confirmedDay = result.signedDate ?? day;
      if (!_validDate(confirmedDay)) {
        return const NeteaseRewardResult(
          success: false,
          uncertain: true,
          message: '平台未确认签到日期，请刷新核对',
        );
      }
      final dates = {...state.localDates, confirmedDay};
      final stored = await preferences.setStringList(
        datesKey(service.ownerId),
        dates.toList()..sort(),
      );
      if (!_valid(ticket, service)) {
        return const NeteaseRewardResult(success: false, message: '账号已变化');
      }
      state = state.copyWith(localDates: dates);
      if (!stored) {
        return const NeteaseRewardResult(
          success: true,
          signed: true,
          message: '签到已确认，本机记录未保存，请刷新平台状态',
        );
      }
    }
    return result;
  });

  void stopAds() {
    final abort = _adAbort;
    if (abort != null && !abort.isCompleted) abort.complete();
  }

  Future<NeteaseRewardResult> ads() => _run(NeteaseRewardAction.ad, (
    service,
    ticket,
  ) async {
    final abort = Completer<void>();
    _adAbort = abort;
    await refresh();
    if (!_valid(ticket, service)) {
      return const NeteaseRewardResult(success: false, message: '账号已变化');
    }
    var successes = 0;
    final limit = ref.read(neteaseRewardBatchLimitProvider).clamp(1, 8);
    for (var attempt = 0; attempt < limit; attempt++) {
      if (!_valid(ticket, service) ||
          abort.isCompleted ||
          ref.read(diagnosticActivityProvider)) {
        break;
      }
      final free = state.snapshot?.freeListen;
      if (free?.adCount != null &&
          free?.adLimit != null &&
          free!.adCount! >= free.adLimit!) {
        return NeteaseRewardResult(
          success: true,
          quotaDone: true,
          message: '平台今日领取次数已用完，本次已确认 $successes 次',
        );
      }
      final result = await service.claimAd(
        stillCurrent: () =>
            _valid(ticket, service) &&
            !abort.isCompleted &&
            !ref.read(diagnosticActivityProvider),
      );
      if (!_valid(ticket, service)) {
        return const NeteaseRewardResult(success: false, message: '账号已变化');
      }
      if (result.quotaDone ||
          !result.success ||
          result.uncertain ||
          result.needsVerification) {
        return NeteaseRewardResult(
          success: result.success,
          quotaDone: result.quotaDone,
          uncertain: result.uncertain,
          needsVerification: result.needsVerification,
          message: '本次已确认 $successes 次；${result.message}',
        );
      }
      successes++;
      state = state.copyWith(confirmedAds: successes);
      await refresh();
      if (!_valid(ticket, service) || abort.isCompleted) break;
      if (attempt + 1 < limit) {
        state = state.copyWith(adWaiting: true);
        final interval =
            result.nextClaimAfter ??
            state.snapshot?.freeListen?.claimInterval ??
            const Duration(seconds: 30);
        await ref.read(neteaseRewardDelayProvider)(interval, abort.future);
        if (!_valid(ticket, service)) {
          return const NeteaseRewardResult(success: false, message: '账号已变化');
        }
        state = state.copyWith(adWaiting: false);
      }
    }
    return NeteaseRewardResult(
      success: true,
      message: '${abort.isCompleted ? '已停止领取' : '本批领取结束'}，本次已确认 $successes 次',
    );
  });
}
