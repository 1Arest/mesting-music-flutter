import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/persistence/app_preferences.dart';
import '../../../core/platform/distribution_channel.dart';
import '../../auth/beta_entry_flow.dart';
import '../../auth/presentation/first_launch_auth_coordinator.dart';
import '../../legal/presentation/disclaimer_dialog.dart';
import '../app_update_providers.dart';
import '../data/release_notes_receipt.dart';
import '../domain/release_history.dart';
import 'app_update_sheet.dart';
import 'release_notes_sheet.dart';

class AppUpdateCoordinator extends ConsumerStatefulWidget {
  const AppUpdateCoordinator({
    required this.child,
    this.navigatorKey,
    super.key,
  });
  final Widget child;
  final GlobalKey<NavigatorState>? navigatorKey;
  @override
  ConsumerState<AppUpdateCoordinator> createState() =>
      _AppUpdateCoordinatorState();
}

/// Checks only after entry is complete. Foreground probes are throttled and
/// never replace the active controller/download. Public updates need no login.
class _AppUpdateCoordinatorState extends ConsumerState<AppUpdateCoordinator>
    with WidgetsBindingObserver {
  bool _scheduled = false;
  bool _presenting = false;
  bool _notesChecked = false;
  bool _foreground = true;
  DateTime? _lastCheck;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scheduleCheck());
  }

  bool _eligible() {
    if (!_foreground) return false;
    final preferences = ref.read(sharedPreferencesProvider);
    if (preferences.getBool(firstLaunchAuthCompletedPreferenceKey) != true) {
      return false;
    }
    if (DistributionChannel.isBeta) {
      final stage = ref.read(betaEntryFlowProvider);
      return stage == BetaEntryStage.idle || stage == BetaEntryStage.app;
    }
    return hasAcceptedLegalDocuments(preferences);
  }

  void _scheduleCheck() {
    if (!mounted || _scheduled || _presenting || !_eligible()) {
      return;
    }
    final notesPending =
        ref.read(autoInstalledReleaseNotesEnabledProvider) && !_notesChecked;
    if (!notesPending &&
        (!ref.read(autoAppUpdateChecksEnabledProvider) || _checkThrottled)) {
      return;
    }
    _scheduled = true;
    unawaited(_checkAfterLaunch());
  }

  bool get _checkThrottled =>
      _lastCheck != null &&
      DateTime.now().difference(_lastCheck!) < const Duration(minutes: 15);

  // MaterialApp.builder is above its Router's Navigator. Resolve the injected
  // root overlay instead of attempting to present from that ancestor context.
  BuildContext? get _presentationContext =>
      widget.navigatorKey?.currentState?.overlay?.context ??
      (Navigator.maybeOf(context) != null ? context : null);

  Future<void> _showInstalledNotes() async {
    if (_notesChecked || !ref.read(autoInstalledReleaseNotesEnabledProvider)) {
      return;
    }
    try {
      final installed = await ref.read(appVersionProvider.future);
      if (!mounted || !_eligible()) return;
      final notes = notesForMusicVersion(installed.versionName);
      final receipt = ReleaseNotesReceipt(ref.read(sharedPreferencesProvider));
      if (notes.isEmpty || receipt.hasSeen(installed)) {
        _notesChecked = true;
        return;
      }
      final presentation = _presentationContext;
      if (presentation == null || !presentation.mounted) return;
      _presenting = true;
      try {
        await showMusicReleaseNotes(
          presentation,
          version: installed.versionName,
          notes: notes,
        );
        if (!mounted) return;
        await receipt.acknowledge(installed);
        _notesChecked = true;
      } finally {
        _presenting = false;
      }
    } catch (_) {
      // Reading or saving local metadata can be retried on a later foreground
      // launch. It must never block playback or remote update discovery.
    }
  }

  Future<void> _checkAfterLaunch() async {
    try {
      await Future<void>.delayed(const Duration(milliseconds: 1800));
      if (!mounted || !_eligible()) return;
      await _showInstalledNotes();
      if (!mounted ||
          !_eligible() ||
          !ref.read(autoAppUpdateChecksEnabledProvider) ||
          _checkThrottled) {
        return;
      }
      _lastCheck = DateTime.now();
      final result = await ref
          .read(appUpdateControllerProvider.notifier)
          .check();
      if (!mounted ||
          result == null ||
          !result.updateAvailable ||
          _presenting) {
        return;
      }
      _presenting = true;
      try {
        final presentation = _presentationContext;
        if (presentation != null && presentation.mounted) {
          await showAppUpdateSheet(presentation);
        }
      } finally {
        _presenting = false;
      }
    } finally {
      _scheduled = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (state == AppLifecycleState.resumed) _scheduleCheck();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (DistributionChannel.isBeta) {
      ref.listen(betaEntryFlowProvider, (_, next) {
        if (next == BetaEntryStage.app) _scheduleCheck();
      });
    }
    return widget.child;
  }
}
