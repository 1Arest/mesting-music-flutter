import 'package:flutter/material.dart';
import '../beta_entry_flow.dart';
import 'beta_entry_coordinator.dart';

// Preserve the existing completion key across upgrades. All account-capable
// channels now enter through the same three-platform/guest coordinator.
const firstLaunchAuthCompletedPreferenceKey = BetaEntryFlow.completedKey;

class FirstLaunchAuthCoordinator extends StatelessWidget {
  const FirstLaunchAuthCoordinator({
    required this.child,
    this.onBetaLogout,
    this.betaBackDispatcher,
    super.key,
  });
  final Widget child;
  final VoidCallback? onBetaLogout;
  final BackButtonDispatcher? betaBackDispatcher;

  @override
  Widget build(BuildContext context) => BetaEntryCoordinator(
    backDispatcher: betaBackDispatcher,
    onLogout: onBetaLogout,
    child: child,
  );
}
