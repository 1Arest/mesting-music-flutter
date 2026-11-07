import 'package:flutter/cupertino.dart';

import '../../../../shared/widgets/music_notice.dart';
import 'netease_together_controller.dart';
import '../../../themes/music_typography.dart';

/// One confirmation flow is shared by the player menu and the room panel.
/// It only ends the room: transport, current song and queue stay with the player.
Future<bool> confirmNeteaseTogetherExit(
  BuildContext context,
  NeteaseTogetherController controller,
) async {
  if (!controller.current || !controller.active || controller.busy) {
    return false;
  }
  final room = controller.roomId;
  final confirmed = await showCupertinoDialog<bool>(
    context: context,
    builder: (dialogContext) => CupertinoAlertDialog(
      title: const Text('退出一起听？', style: MusicTypography.titleEmphasis),
      content: const Text('退出后停止与朋友同步，当前音乐继续在本机播放。'),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('取消', style: MusicTypography.regularText),
        ),
        CupertinoDialogAction(
          isDestructiveAction: true,
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('退出一起听', style: MusicTypography.regularText),
        ),
      ],
    ),
  );
  // A dialog may outlive the selected account or the room it described.
  if (confirmed != true ||
      !context.mounted ||
      !controller.current ||
      controller.roomId != room ||
      controller.busy) {
    return false;
  }
  await controller.end();
  if (!context.mounted || !controller.current) return false;
  final exited = !controller.active && controller.error == null;
  showMusicNotice(
    context,
    icon: exited
        ? CupertinoIcons.check_mark
        : CupertinoIcons.exclamationmark_circle,
    title: exited ? '已退出一起听' : '退出未获确认',
    message: exited
        ? controller.player.playing
              ? '当前音乐继续播放。'
              : '已停止同步，当前音乐保持暂停。'
        : controller.error ?? '请刷新房间状态后重试。',
  );
  return exited;
}
