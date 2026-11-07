import '../../auth/presentation/beta_login_navigation.dart';
import 'package:flutter/material.dart';
import '../../../shared/widgets/music_notice.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/distribution_channel.dart';
import '../../auth/presentation/auth_gate.dart';
import '../../auth/beta_account_choice.dart';
import '../../auth/auth_providers.dart';
import '../../music_platform/music_platform_providers.dart';

/// Listening stays available to guests; persistent personal mutations require
/// a real account. All protected widgets share the same welcome destination.
Future<bool> ensureLibraryAccess(
  BuildContext context,
  WidgetRef ref, {
  required String reason,
  required String redirect,
}) async {
  if (DistributionChannel.isBeta) {
    try {
      // Never write guest data while an existing platform login is restoring.
      await ref.read(platformAccountProvider.future);
      if (ref.read(betaAccountChoiceProvider) == BetaAccountChoice.mesting) {
        await ref.read(authControllerProvider.future);
      }
      if (ref.read(platformAccountProvider).value != null ||
          ref.read(currentUserProvider) != null) {
        return true;
      }
      if (context.mounted) await openBetaLogin(context, redirect: redirect);
      return false;
    } catch (_) {
      if (context.mounted) {
        showMusicNotice(
          context,
          icon: Icons.error_outline_rounded,
          title: '当前账号曲库尚未就绪，请重试',
          message: '',
        );
      }
      return false;
    }
  }
  return ensureAuthenticated(context, ref, reason: reason, redirect: redirect);
}
