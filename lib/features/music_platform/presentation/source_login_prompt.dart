import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/models/track.dart';
import '../../../shared/widgets/beta_page_motion.dart';
import '../domain/platform_session.dart';
import '../music_platform_providers.dart';
import '../source_media_scope.dart';
import 'platform_login_options_page.dart';

class _SourceLoginPrompt {
  bool busy = false;
}

final _sourceLoginPromptProvider = Provider((ref) => _SourceLoginPrompt());

/// Login is an explicit foreground action. Double taps cannot stack dialogs,
/// and a stale login completion cannot start playback under another UI owner.
Future<bool> ensureSourceLogin(
  BuildContext context,
  WidgetRef ref,
  TrackSource source, {
  bool forPlayback = true,
}) async {
  if (source != TrackSource.kugou && source != TrackSource.netease) return true;
  final owner = ref.read(platformAccountProvider).value;
  final identity = (owner?.ownerId, owner?.token);
  bool current() =>
      context.mounted &&
      (
            ref.read(platformAccountProvider).value?.ownerId,
            ref.read(platformAccountProvider).value?.token,
          ) ==
          identity;
  final scope = await ref.read(sourceMediaScopeProvider(source).future);
  if (!current()) return false;
  if (scope.session != null) return true;
  final prompt = ref.read(_sourceLoginPromptProvider);
  if (prompt.busy) return false;
  prompt.busy = true;
  try {
    final label = source == TrackSource.kugou ? '酷狗' : '网易云';
    if (!context.mounted) return false;
    final accept = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialog) => CupertinoAlertDialog(
        title: Text('登录$label${forPlayback ? '后播放' : '后参与评论'}'),
        content: Text(
          forPlayback
              ? '该资源来自$label，需要登录对应账号；能否播放完整版以账号会员权限为准。'
              : '使用$label账号参与该平台评论，登录后仍保留当前音乐界面。',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('去登录'),
          ),
        ],
      ),
    );
    if (accept != true || !current()) return false;
    if (!context.mounted) return false;
    await Navigator.of(context, rootNavigator: true).push<bool>(
      betaContentRoute(
        PlatformLoginOptionsPage(
          platform: source == TrackSource.kugou
              ? MusicPlatform.kugou
              : MusicPlatform.netease,
          retainCurrentPlatform: true,
        ),
      ),
    );
    if (!current()) return false;
    final updated = await ref.read(sourceMediaScopeProvider(source).future);
    return current() && updated.isCurrent() && updated.session != null;
  } finally {
    prompt.busy = false;
  }
}
