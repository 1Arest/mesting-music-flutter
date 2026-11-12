import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/widgets/music_notice.dart';
import '../presentation/platform_feedback.dart';
import 'qishui_providers.dart';
import 'qishui_playlist_tools.dart';

Future<void> showQishuiCreatePlaylist(
  BuildContext context,
  WidgetRef ref,
) async {
  final music = ref.read(qishuiRepositoryProvider);
  final name = await askQishuiPlaylistName(context);
  if (name == null || !context.mounted || !music.current) return;
  try {
    await music.createPlaylist(name);
    if (context.mounted && music.current) {
      showMusicNotice(
        context,
        icon: Icons.check_rounded,
        title: '歌单已创建',
        message: '已核对汽水账号中的歌单',
      );
    }
  } on Object catch (error) {
    if (context.mounted && music.current) showPlatformFailure(context, error);
  }
}

/// Import exact official recording IDs, with a preview and explicit target.
/// Other platforms' names/IDs are never silently mapped to different songs.
Future<void> showQishuiImportPlaylist(
  BuildContext context,
  WidgetRef ref,
) async {
  final music = ref.read(qishuiRepositoryProvider);
  final id = await showDialog<String>(
    context: context,
    useRootNavigator: true,
    builder: (_) => const _ImportPlaylistDialog(),
  );
  if (id == null || !context.mounted || !music.current) return;
  try {
    final tracks = await music.playlist(id);
    if (!context.mounted || !music.current) return;
    if (tracks.isEmpty) {
      showMusicNotice(
        context,
        icon: Icons.info_outline,
        title: '没有可导入的歌曲',
        message: '此汽水歌单暂未返回歌曲',
      );
      return;
    }
    final target = await chooseQishuiPlaylistDestination(
      context,
      ref,
      excludeId: id,
      ownerIsCurrent: () => context.mounted && music.current,
    );
    if (target == null || !context.mounted || !music.current) return;
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (dialog) => AlertDialog(
        title: Text('导入 ${tracks.length} 首汽水歌曲？'),
        content: Text('将复制到“${target.name}”，并同步到你的汽水账号。原歌单不变。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('确认导入'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted || !music.current) return;
    await music.addPlaylistTracks(target.id, tracks);
    if (context.mounted && music.current) {
      showMusicNotice(
        context,
        icon: Icons.check_rounded,
        title: '歌曲已导入',
        message: '汽水歌单状态已核对',
      );
    }
  } on Object catch (error) {
    if (context.mounted && music.current) showPlatformFailure(context, error);
  }
}

class _ImportPlaylistDialog extends StatefulWidget {
  const _ImportPlaylistDialog();
  @override
  State<_ImportPlaylistDialog> createState() => _ImportPlaylistDialogState();
}

class _ImportPlaylistDialogState extends State<_ImportPlaylistDialog> {
  final _input = TextEditingController();
  String get id {
    final text = _input.text.trim();
    if (RegExp(r'^\d{5,30}$').hasMatch(text)) return text;
    final uri = Uri.tryParse(text);
    if (uri?.scheme != 'https' ||
        uri!.userInfo.isNotEmpty ||
        !(uri.host == 'qishui.com' || uri.host.endsWith('.qishui.com'))) {
      return '';
    }
    final value = uri.queryParameters['playlist_id'] ?? '';
    return RegExp(r'^\d{5,30}$').hasMatch(value) ? value : '';
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('导入汽水歌单'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('输入汽水歌单ID，或带 playlist_id 的汽水官方链接。先读取歌曲，再由你选择目标歌单。'),
          const SizedBox(height: 16),
          TextField(
            controller: _input,
            maxLength: 300,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: '汽水歌单ID或链接'),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      TextButton(
        onPressed: id.isEmpty ? null : () => Navigator.pop(context, id),
        child: const Text('读取歌单'),
      ),
    ],
  );
}
