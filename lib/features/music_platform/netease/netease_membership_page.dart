import '../../../shared/widgets/beta_content_insets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/widgets/beta_glass_controls.dart';
import '../domain/platform_session.dart';
import '../music_platform_providers.dart';
import '../presentation/platform_design.dart';
import '../presentation/platform_feedback.dart';
import 'netease_fallback.dart';
import 'netease_playback_options.dart';
import '../../themes/music_typography.dart';

class NeteaseLocalSvipBadge extends ConsumerWidget {
  const NeteaseLocalSvipBadge({this.inline = false, super.key});
  final bool inline;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(neteaseLocalSvipProvider)) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: '网易云本地 SVIP 已启用',
      child: Container(
        margin: inline ? EdgeInsets.zero : const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: scheme.primaryContainer,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          '本地 SVIP',
          style: TextStyle(
            color: scheme.onPrimaryContainer,
            fontSize: MusicTypography.captionSize,
            fontWeight: MusicTypography.bodyWeight,
          ),
        ),
      ),
    );
  }
}

/// A native membership surface rather than a raw membership API form. It uses
/// local policy exclusively; server-backed tasks keep their own API outcomes.
class NeteaseMembershipPage extends ConsumerStatefulWidget {
  const NeteaseMembershipPage({super.key});
  @override
  ConsumerState<NeteaseMembershipPage> createState() =>
      _NeteaseMembershipPageState();
}

class _NeteaseMembershipPageState extends ConsumerState<NeteaseMembershipPage> {
  final _uids = TextEditingController();
  late final String? _owner;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _owner = ref.read(platformAccountProvider).value?.ownerId;
    _uids.text = ref
        .read(neteaseLocalMembershipSettingsProvider)
        .allowedUids
        .join(', ');
  }

  @override
  void dispose() {
    _uids.dispose();
    super.dispose();
  }

  bool get _current =>
      ref.read(platformAccountProvider).value?.ownerId == _owner;
  Future<void> _change(Future<void> Function() action) async {
    if (_busy || !_current) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted && _current) showPlatformFailure(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(platformAccountProvider).value;
    if (!_current || account?.platform != MusicPlatform.netease) {
      return const PlatformPageFrame(
        title: '我的会员',
        child: Center(child: Text('请使用当前网易云账号重新打开')),
      );
    }
    final settings = ref.watch(neteaseLocalMembershipSettingsProvider);
    final enabled = ref.watch(neteaseLocalSvipProvider);
    final uid = account!.userId;
    return PlatformPageFrame(
      title: '我的会员',
      child: ListView(
        padding: BetaContentInsets.musicPaddingOf(
          context,
          EdgeInsets.fromLTRB(22, 12, 22, 180),
        ),
        children: [
          PlatformPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  enabled
                      ? Icons.workspace_premium_outlined
                      : Icons.person_outline,
                  size: 36,
                ),
                const SizedBox(height: 14),
                Text(
                  enabled ? '本地黑胶 SVIP' : '本地会员已关闭',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text('网易云账号 UID：$uid'),
                const SizedBox(height: 8),
                const Text('在 Mesting Music 内生效 · 设置保存在本机'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('当前账号启用本地 SVIP'),
            subtitle: Text(
              settings.allowedUids.isNotEmpty &&
                      !settings.allowedUids.contains(uid)
                  ? '当前 UID 不在指定名单中，修改名单后生效'
                  : '启用时同时开启同曲补源',
            ),
            value: settings.accounts[uid] ?? true,
            onChanged: _busy
                ? null
                : (value) => _change(() async {
                    await ref
                        .read(neteaseLocalMembershipSettingsProvider.notifier)
                        .setEnabled(uid, value);
                    if (value && mounted && _current) {
                      await ref
                          .read(neteaseFallbackEnabledProvider.notifier)
                          .setEnabled(true);
                    }
                  }),
          ),
          const SizedBox(height: 16),
          const Text(
            '本地功能',
            style: TextStyle(
              fontSize: MusicTypography.bodySize,
              fontWeight: MusicTypography.titleWeight,
            ),
          ),
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.high_quality_outlined),
            title: Text('无损与高品质音源选择'),
            subtitle: Text('实际音质以音源提供的文件为准'),
          ),
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.multitrack_audio),
            title: Text('同曲完整版本补源'),
            subtitle: Text('官方 → 新音源 → BugPk，保留网易云收藏与评论关联'),
          ),
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.badge_outlined),
            title: Text('本地 SVIP 标识与会员入口'),
            subtitle: Text('切换账号后按对应 UID 的设置展示'),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _uids,
            enabled: !_busy,
            keyboardType: TextInputType.text,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: '生效 UID',
              hintText: '多个 UID 用逗号分隔',
              helperText: '可选。留空时所有网易云账号均可使用各自的本地开关',
              helperMaxLines: 3,
            ),
          ),
          const SizedBox(height: 18),
          BetaGlassButton(
            key: const ValueKey('local-svip-save-uids'),
            loading: _busy,
            onPressed: _busy
                ? null
                : () => _change(
                    () => ref
                        .read(neteaseLocalMembershipSettingsProvider.notifier)
                        .setAllowedUids(_uids.text),
                  ),
            child: const Text('保存 UID 范围'),
          ),
        ],
      ),
    );
  }
}
