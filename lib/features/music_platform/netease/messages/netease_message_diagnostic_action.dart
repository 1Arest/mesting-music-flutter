import '../../../../shared/widgets/music_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../shared/widgets/beta_glass_controls.dart';
import 'netease_message_diagnostics.dart';
import '../../../themes/music_typography.dart';

/// Export belongs to the user's explicit action, never to polling or parsing.
/// The owner callback also prevents copying a stale report after an account
/// change while the preview dialog was open.
class NeteaseMessageDiagnosticAction extends StatelessWidget {
  const NeteaseMessageDiagnosticAction({
    required this.report,
    required this.isCurrent,
    super.key,
  });
  final NeteaseMessageDiagnostics report;
  final bool Function() isCurrent;

  Future<void> _preview(BuildContext context) async {
    if (!isCurrent()) return;
    final copy = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('导出此条消息诊断'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '仅包含消息字段结构和类型，不包含聊天正文、账号、头像或链接内容。复制后可手动发给开发者，不会自动上传。',
                ),
                const SizedBox(height: 16),
                SelectableText(
                  report.json,
                  style: const TextStyle(fontSize: MusicTypography.captionSize),
                ),
              ],
            ),
          ),
        ),
        actions: [
          BetaGlassButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          BetaGlassButton(
            blue: true,
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('复制诊断'),
          ),
        ],
      ),
    );
    if (copy != true || !context.mounted || !isCurrent()) return;
    await Clipboard.setData(ClipboardData(text: report.json));
    if (!context.mounted || !isCurrent()) return;
    showMusicNotice(
      context,
      icon: Icons.check_rounded,
      title: '已复制这条消息的脱敏诊断',
      message: '',
    );
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: BetaGlassButton(
      key: const ValueKey('netease-message-export-diagnostic'),
      onPressed: () => _preview(context),
      child: const Text('导出此条诊断'),
    ),
  );
}
