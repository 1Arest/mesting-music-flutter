import '../../../shared/widgets/music_feature_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/widgets/beta_glass_controls.dart';
import '../music_platform_providers.dart';
import '../platform_profile_provider.dart';
import '../presentation/platform_avatar.dart';
import 'qishui_page_scope.dart';

/// Shared account-management entry for Soda. It never shows the other
/// platforms' credential formats, QR authorizations or profile-write forms.
class QishuiAccountPage extends ConsumerStatefulWidget {
  const QishuiAccountPage({super.key});
  @override
  ConsumerState<QishuiAccountPage> createState() => _QishuiAccountPageState();
}

class _QishuiAccountPageState extends ConsumerState<QishuiAccountPage>
    with QishuiOwnedPage<QishuiAccountPage> {
  bool _busy = false;
  String? _error;
  Future<void> _logout() async {
    if (_busy || !ownerCurrent) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(platformAccountProvider.notifier).signOut();
      if (mounted) Navigator.of(context).maybePop();
    } on Object {
      if (mounted) setState(() => _error = '退出未完成，登录资料已保留，请重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!watchOwner()) return changedAccount();
    final account = ref.watch(platformAccountProvider).value;
    final profile = ref.watch(platformProfileProvider).value;
    return MusicFeaturePage(
      title: '汽水账号',
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: PlatformAvatar(
              url: profile?.avatarUrl ?? account?.avatarUrl ?? '',
            ),
          ),
          const SizedBox(height: 20),
          Text(
            profile?.nickname ?? account?.nickname ?? '汽水账号',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          const Text('扫码登录 · 汽水音乐'),
          const SizedBox(height: 28),
          BetaGlassButton(
            onPressed: _busy
                ? null
                : () => ref.invalidate(platformProfileProvider),
            child: const Text('刷新账号资料'),
          ),
          const SizedBox(height: 16),
          BetaGlassButton(
            loading: _busy,
            onPressed: _busy ? null : _logout,
            child: const Text('退出汽水账号'),
          ),
          if (_error != null) ...[const SizedBox(height: 20), Text(_error!)],
        ],
      ),
    );
  }
}
