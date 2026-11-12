import 'dart:async';
import 'music_entry_dispatcher.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/router/app_router.dart';
import '../../core/persistence/app_preferences.dart';
import '../auth/beta_entry_back_state.dart';
import '../auth/beta_entry_flow.dart';
import '../legal/presentation/disclaimer_dialog.dart';
import '../music_platform/domain/platform_session.dart';
import '../music_platform/music_platform_providers.dart';
import '../music_platform/retained_kugou_scope.dart';
import 'notification_bridge.dart';
import 'notification_models.dart';
import 'notification_runner.dart';
import 'notification_sources.dart';
import 'notification_target.dart';

final musicNoticeRevision = ValueNotifier<int>(0);

/// The shell owns foreground lifetime; the native scheduler owns background
/// lifetime. Entry requests remain queued through account restore and onboarding
/// and are acknowledged only after their actual destination has been selected.
class MusicNotificationCoordinator extends ConsumerStatefulWidget {
  const MusicNotificationCoordinator({required this.child, super.key});
  final Widget child;
  @override
  ConsumerState<MusicNotificationCoordinator> createState() =>
      _NoticeCoordinatorState();
}

class _NoticeCoordinatorState
    extends ConsumerState<MusicNotificationCoordinator>
    with WidgetsBindingObserver {
  final bridge = const MusicNotificationBridge();
  Timer? timer;
  bool polling = false, rerun = false, loginOpened = false;
  late final entries = MusicEntryDispatcher(
    peek: () async {
      final raw = await bridge.call<String>('entry');
      return raw == null ? null : noticeMap(raw);
    },
    prepare: _prepareEntry,
    navigate: appRouter.go,
    acknowledge: (id) => bridge.call<void>('acknowledge', {'id': id}),
    active: () => mounted,
  );

  @override
  void initState() {
    super.initState();
    if (!bridge.supported) return;
    MusicNoticeRunner.installCredentialGuard();
    WidgetsBinding.instance.addObserver(this);
    MusicNotificationBridge.channel.setMethodCallHandler((call) async {
      if (call.method == 'entryAvailable') await _entry();
    });
    timer = Timer.periodic(const Duration(seconds: 30), (_) => _wake());
    WidgetsBinding.instance.addPostFrameCallback((_) => _wake());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _wake();
  }

  void _wake() {
    if (!mounted || !bridge.supported) return;
    unawaited(_entry());
    if (WidgetsBinding.instance.lifecycleState != null &&
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    if (polling) {
      rerun = true;
      return;
    }
    final prefs = ref.read(sharedPreferencesProvider);
    if (prefs.getBool(disclaimerAcceptedPreferenceKey) != true) return;
    unawaited(_poll());
  }

  Future<void> _poll() async {
    polling = true;
    try {
      // Permission is requested once, after a real retained account exists.
      // A rejection remains a system choice; settings exposes a manual action.
      final prefs = ref.read(sharedPreferencesProvider);
      if (prefs.getBool('mesting_notice_permission_prompted_v1') != true) {
        var account = false;
        for (final platform in noticePlatforms) {
          try {
            account |= await readNoticeAccount(platform) != null;
          } on Object {
            /* Unknown storage stays unknown. */
          }
        }
        if (account &&
            mounted &&
            ref.read(betaEntryBackStateProvider).canHandlePop == null) {
          await prefs.setBool('mesting_notice_permission_prompted_v1', true);
          await bridge.call<bool>('permission');
        }
      }
      await MusicNoticeRunner(bridge: bridge).poll();
      musicNoticeRevision.value++;
    } on Object {
      /* Native status remains available from notification settings. */
    } finally {
      polling = false;
      if (rerun && mounted) {
        rerun = false;
        _wake();
      }
    }
  }

  Future<void> _entry() async {
    if (!mounted || !bridge.supported) return;
    final stage = ref.read(betaEntryFlowProvider);
    if (ref.read(betaEntryBackStateProvider).canHandlePop != null ||
        stage == BetaEntryStage.welcome ||
        stage == BetaEntryStage.guide ||
        stage == BetaEntryStage.success) {
      return;
    }
    final prefs = ref.read(sharedPreferencesProvider);
    if (prefs.getBool(disclaimerAcceptedPreferenceKey) != true ||
        prefs.getBool(BetaEntryFlow.completedKey) != true &&
            stage != BetaEntryStage.app) {
      return;
    }
    try {
      await entries.dispatch();
    } on Object {
      /* Keep the queued request for recovery. */
    }
  }

  Future<String?> _prepareEntry(Map<String, dynamic> entry) async {
    if (!mounted) return null;
    final route = musicEntryRoute(entry);
    if (route == null) {
      await bridge.call<void>('acknowledge', {'id': entry['id']});
      return null;
    }
    final current = await ref.read(platformAccountProvider.future);
    if (!mounted) return null;
    final currentPlatform = current?.platform;
    final name = entry['action'] == 'notifications'
        ? '${entry['platform']}'
        : currentPlatform == MusicPlatform.netease ||
              currentPlatform == MusicPlatform.kugou
        ? currentPlatform!.name
        : await bridge.call<String>('lastPlatform');
    final platform = name == 'netease'
        ? MusicPlatform.netease
        : MusicPlatform.kugou;
    if (entry['action'] == 'notifications' &&
        (await readNoticeAccount(platform))?.scope != entry['scope']) {
      await bridge.call<void>('acknowledge', {'id': entry['id']});
      return null;
    }
    if (current?.platform != platform) {
      final controller = ref.read(platformAccountProvider.notifier);
      final retained = await controller.retainedIdentity(platform);
      if (retained == null) {
        if (!loginOpened) {
          loginOpened = true;
          appRouter.go(
            Uri(path: '/auth', queryParameters: {'redirect': route}).toString(),
          );
        }
        return null;
      }
      await controller.switchPlatform(platform);
    }
    if (!mounted) return null;
    // A login can change while switching the visible platform. Verify the
    // original notification's retained scope once more before navigation.
    if (entry['action'] == 'notifications' &&
        (await readNoticeAccount(platform))?.scope != entry['scope']) {
      return null;
    }
    loginOpened = false;
    return route;
  }

  @override
  Widget build(BuildContext context) {
    if (!bridge.supported) return widget.child;
    ref.listen(platformAccountProvider, (_, next) {
      final platform = next.isLoading ? null : next.value?.platform;
      if (platform == MusicPlatform.netease ||
          platform == MusicPlatform.kugou) {
        unawaited(
          bridge.call<String>('lastPlatform', {'platform': platform!.name}),
        );
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => _wake());
    });
    ref.listen(retainedKugouMutationProvider, (_, _) => _wake());
    ref.listen(retainedNeteaseEpochProvider, (_, _) => _wake());
    ref.listen(
      betaEntryFlowProvider,
      (_, _) => WidgetsBinding.instance.addPostFrameCallback((_) => _wake()),
    );
    return widget.child;
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    if (bridge.supported) {
      MusicNotificationBridge.channel.setMethodCallHandler(null);
    }
    super.dispose();
  }
}

/// Pure allowlist, also exercised without Android. Native extras cannot request
/// arbitrary router paths, web URLs, or account-changing commands.
String? musicEntryRoute(Map<String, dynamic> entry) =>
    switch (entry['action']) {
      'favorites' => '/music/library?view=favorites',
      'recognize' => '/music/recognize',
      'search' => '/music/search',
      'notifications' when ['netease', 'kugou'].contains(entry['platform']) =>
        noticeDestinationRoute(entry),
      _ => null,
    };
