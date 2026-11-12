import '../../../shared/widgets/beta_content_insets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/widgets/beta_glass_controls.dart';
import '../music_platform_providers.dart';
import '../platform_backend_providers.dart';
import '../presentation/platform_design.dart';
import '../presentation/platform_feedback.dart';
import 'netease_music_repository.dart';

/// Import is an explicit account write. A created task is not a completed
/// playlist: status is read separately and a timeout never re-submits a task.
class NeteasePlaylistImportPage extends ConsumerStatefulWidget {
  const NeteasePlaylistImportPage({super.key});
  @override
  ConsumerState<NeteasePlaylistImportPage> createState() =>
      _NeteasePlaylistImportPageState();
}

class _NeteasePlaylistImportPageState
    extends ConsumerState<NeteasePlaylistImportPage> {
  final _name = TextEditingController(), _songs = TextEditingController();
  late final String? _owner, _token;
  String? _task, _status;
  bool _busy = false;
  bool get _current =>
      ref.read(usesNeteaseProvider) &&
      ref.read(platformAccountProvider).value?.ownerId == _owner &&
      ref.read(platformAccountProvider).value?.token == _token;
  @override
  void initState() {
    super.initState();
    final a = ref.read(platformAccountProvider).value;
    _owner = a?.ownerId;
    _token = a?.token;
  }

  @override
  void dispose() {
    _name.dispose();
    _songs.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_current) return;
    if (_name.text.trim().isEmpty || _songs.text.trim().isEmpty) {
      setState(() => _status = '请填写歌单名称和歌曲列表');
      return;
    }
    setState(() => _busy = true);
    try {
      final result = await ref.read(neteaseMusicRepositoryProvider).call(
        '/playlist/import/name/task/create',
        {'name': _name.text.trim(), 'text': _songs.text.trim()},
      );
      if (!mounted || !_current) return;
      final data = NeteaseMusicRepository.object(result['data']);
      final task = '${data['taskId'] ?? result['taskId'] ?? ''}';
      setState(() {
        _task = task.isEmpty ? null : task;
        _status = task.isEmpty
            ? '网易云已接收请求，未返回任务标识。请先刷新云端歌单确认，避免重复导入。'
            : '导入任务已创建，点击下方按钮查询实际进度。';
      });
    } catch (e) {
      if (mounted) showPlatformFailure(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refresh() async {
    if (_busy || !_current || _task == null) return;
    setState(() => _busy = true);
    try {
      final result = await ref.read(neteaseMusicRepositoryProvider).call(
        '/playlist/import/task/status',
        {'id': _task},
      );
      if (!mounted || !_current) return;
      final raw = result['data'];
      final data = NeteaseMusicRepository.object(
        raw is List && raw.isNotEmpty ? raw.first : raw,
      );
      setState(
        () => _status =
            '${data['message'] ?? data['msg'] ?? '网易云任务状态：${data['status'] ?? data['state'] ?? '处理中'}'}',
      );
    } catch (e) {
      if (mounted) showPlatformFailure(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(platformAccountProvider);
    return PlatformPageFrame(
      title: '导入网易云歌单',
      child: !_current
          ? const Center(child: Text('账号已变化，请返回后重新打开'))
          : ListView(
              padding: BetaContentInsets.musicPaddingOf(
                context,
                EdgeInsets.fromLTRB(22, 16, 22, 190),
              ),
              children: [
                const Text('每行填写一首歌曲，可写成“歌名 - 歌手”。网易云会识别并导入到当前账号。'),
                const SizedBox(height: 20),
                TextField(
                  controller: _name,
                  enabled: !_busy && _task == null,
                  maxLength: 40,
                  decoration: const InputDecoration(labelText: '歌单名称'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _songs,
                  enabled: !_busy && _task == null,
                  minLines: 8,
                  maxLines: 16,
                  maxLength: 10000,
                  decoration: const InputDecoration(labelText: '歌曲列表'),
                ),
                const SizedBox(height: 20),
                BetaGlassButton(
                  onPressed: _busy || _task != null ? null : _submit,
                  child: Text(_busy ? '正在处理…' : '导入到当前网易云账号'),
                ),
                if (_task != null)
                  TextButton(
                    onPressed: _busy ? null : _refresh,
                    child: const Text('查询导入进度'),
                  ),
                if (_status != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(_status!),
                  ),
              ],
            ),
    );
  }
}
