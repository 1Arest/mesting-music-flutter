import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import '../shared/widgets/beta_back_state_changes.dart';

/// Keeps Android's back callback in sync with the retained Flutter navigator.
///
/// AudioService can keep Dart and its pages alive after their Android Activity
/// is destroyed. A new Activity starts without the old OnBackInvokedCallback,
/// even though no Dart route changed. NavigationNotification alone therefore
/// cannot restore system edge Back: republish its latest value on resume.
class SystemBackCoordinator extends StatefulWidget {
  const SystemBackCoordinator({
    required this.child,
    this.canPop,
    this.navigationChanges,
    super.key,
  });

  final bool Function()? canPop;

  /// Router changes and Navigator notifications have different lifecycles.
  /// Listen to both, then query only the live active stack after the frame.
  final Listenable? navigationChanges;

  final Widget child;

  @override
  State<SystemBackCoordinator> createState() => _SystemBackCoordinatorState();
}

class _SystemBackCoordinatorState extends State<SystemBackCoordinator>
    with WidgetsBindingObserver {
  bool? _canHandlePop;
  bool _synchronizationScheduled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.navigationChanges?.addListener(_scheduleSynchronization);
    BetaBackStateChanges.shared.addListener(_scheduleSynchronization);
    _scheduleSynchronization();
  }

  void _synchronize() {
    final canHandlePop = widget.canPop?.call() ?? _canHandlePop;
    if (!mounted || canHandlePop == null) return;
    unawaited(SystemNavigator.setFrameworkHandlesBack(canHandlePop));
  }

  void _scheduleSynchronization() {
    if (!mounted || _synchronizationScheduled) return;
    _synchronizationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _synchronizationScheduled = false;
      if (mounted) _synchronize();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void didUpdateWidget(covariant SystemBackCoordinator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.navigationChanges != widget.navigationChanges) {
      oldWidget.navigationChanges?.removeListener(_scheduleSynchronization);
      widget.navigationChanges?.addListener(_scheduleSynchronization);
    }
    _scheduleSynchronization();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    _synchronize();
    // The first resumed frame can also restore local search history or an
    // entry overlay. Re-read the latest notification after that frame settles.
    _scheduleSynchronization();
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<NavigationNotification>(
        onNotification: (notification) {
          _canHandlePop = notification.canHandlePop;
          // Notifications from a covered nested route can arrive after pop.
          // Query the live router's root + shell stacks after the frame rather
          // than OR-ing a stale notification into the current Back state.
          if (widget.canPop != null) {
            _scheduleSynchronization();
          }
          // Keep WidgetsApp's normal aggregation and local-history reporting.
          return false;
        },
        child: widget.child,
      );

  @override
  void dispose() {
    widget.navigationChanges?.removeListener(_scheduleSynchronization);
    BetaBackStateChanges.shared.removeListener(_scheduleSynchronization);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
