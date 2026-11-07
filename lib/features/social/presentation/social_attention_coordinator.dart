import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_providers.dart';
import '../social_attention.dart';

const socialAttentionPollInterval = Duration(minutes: 10);
const socialAttentionMinimumRefreshGap = Duration(minutes: 2);

class SocialAttentionCoordinator extends ConsumerStatefulWidget {
  const SocialAttentionCoordinator({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<SocialAttentionCoordinator> createState() =>
      _SocialAttentionCoordinatorState();
}

class _SocialAttentionCoordinatorState
    extends ConsumerState<SocialAttentionCoordinator>
    with WidgetsBindingObserver {
  Timer? _timer;
  Future<void>? _refreshInFlight;
  String? _activeUid;
  DateTime? _lastRefreshAt;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      unawaited(_resumeAndRestartPolling());
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uid = ref.watch(currentUserProvider)?.uid;
    if (uid != _activeUid) {
      _activeUid = uid;
      _lastRefreshAt = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => _activate(uid));
    }
    return widget.child;
  }

  Future<void> _activate(String? uid) async {
    _timer?.cancel();
    if (!mounted || uid != _activeUid || uid == null || uid.trim().isEmpty) {
      ref.read(socialAttentionControllerProvider.notifier).clear();
      return;
    }
    await ref.read(socialNotificationBridgeProvider).requestPermission();
    await _refresh(postSystemNotifications: true, force: true);
    _startPolling();
  }

  void _startPolling() {
    _timer?.cancel();
    if (!_foreground || !mounted || _activeUid == null) return;
    _timer = Timer.periodic(
      socialAttentionPollInterval,
      (_) => unawaited(_refresh(postSystemNotifications: true)),
    );
  }

  Future<void> _resumeAndRestartPolling() async {
    _timer?.cancel();
    _timer = null;
    await _refresh(postSystemNotifications: true);
    if (mounted && _foreground) _startPolling();
  }

  Future<void> _refresh({
    required bool postSystemNotifications,
    bool force = false,
  }) async {
    final inFlight = _refreshInFlight;
    if (inFlight != null) {
      await inFlight;
      return;
    }
    final uid = _activeUid;
    if (!mounted || uid == null || uid.trim().isEmpty) return;
    final now = DateTime.now();
    final lastRefreshAt = _lastRefreshAt;
    if (!force &&
        lastRefreshAt != null &&
        now.difference(lastRefreshAt) < socialAttentionMinimumRefreshGap) {
      return;
    }
    _lastRefreshAt = now;
    final refresh = _performRefresh(
      uid,
      postSystemNotifications: postSystemNotifications,
      force: force,
    );
    _refreshInFlight = refresh;
    try {
      await refresh;
    } finally {
      if (identical(_refreshInFlight, refresh)) _refreshInFlight = null;
    }
  }

  Future<void> _performRefresh(
    String uid, {
    required bool postSystemNotifications,
    required bool force,
  }) async {
    try {
      await ref
          .read(socialAttentionControllerProvider.notifier)
          .refreshFor(
            uid,
            postSystemNotifications: postSystemNotifications,
            force: force,
          );
    } on Object {
      // Social attention must not block playback or page navigation when the
      // social service is temporarily unavailable.
    }
  }
}
