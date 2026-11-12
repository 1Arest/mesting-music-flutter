import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/widgets/music_notice.dart';
import '../../auth/presentation/beta_login_navigation.dart';
import '../../music_platform/music_platform_providers.dart';

/// Await credential recovery before deciding whether a personal mutation is
/// allowed. A storage failure never turns an existing identity into a guest.
Future<bool> ensureLibraryAccess(
  BuildContext context,
  WidgetRef ref, {
  required String reason,
  required String redirect,
}) async {
  try {
    final platform = await ref.read(platformAccountProvider.future);
    if (platform != null) return true;
    if (context.mounted) await openBetaLogin(context, redirect: redirect);
  } on Object {
    if (context.mounted) {
      showMusicNotice(
        context,
        icon: Icons.error_outline_rounded,
        title: '当前账号曲库尚未就绪，请重试',
        message: '',
      );
    }
  }
  return false;
}
