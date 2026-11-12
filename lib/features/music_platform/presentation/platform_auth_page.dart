import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../auth/beta_entry_flow.dart';
import '../../auth/presentation/beta_welcome_page.dart';
import '../music_platform_providers.dart';
import 'platform_account_page.dart';

/// Routed platform/guest entry. Credential protocols remain in their own
/// controllers; this widget only handles navigation after an explicit choice.
class PlatformAuthPage extends ConsumerWidget {
  const PlatformAuthPage({this.redirect = '/music/recommend', super.key});
  final String redirect;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(platformAccountProvider).value != null) {
      return const PlatformAccountPage();
    }
    return BetaWelcomePage(
      onExperience: () => context.go(
        ref.read(betaEntryFlowProvider) == BetaEntryStage.app
            ? '/music/recommend'
            : redirect,
      ),
    );
  }
}
