import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/beta_glass_controls.dart';
import '../../../shared/widgets/beta_music_chrome_scope.dart';
import '../../auth/presentation/beta_welcome_page.dart';
import '../data/kugou_account_store.dart';
import '../domain/platform_session.dart';
import '../music_platform_providers.dart';
import 'platform_avatar.dart';
import 'platform_login_options_page.dart';
import 'kugou_standard_authorization_page.dart';
import '../../themes/music_typography.dart';

/// 登录管理页不持有凭据；切换、播放快照和持久化均交给现有账号协调层。
class KugouAccountsPage extends ConsumerStatefulWidget {
  const KugouAccountsPage({super.key});

  @override
  ConsumerState<KugouAccountsPage> createState() => _KugouAccountsPageState();
}

class _KugouAccountsPageState extends ConsumerState<KugouAccountsPage> {
  bool _managing = false, _busy = false;
  String? _error, _pending;

  Future<void> _run(String key, Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _pending = key;
      _error = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) setState(() => _error = '操作未完成，请重试。');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _pending = null;
        });
      }
    }
  }

  Future<void> _login() async {
    await Navigator.of(context).push<bool>(
      betaEntryRoute(
        const PlatformLoginOptionsPage(platform: MusicPlatform.kugou),
      ),
    );
    if (mounted) ref.invalidate(savedKugouAccountsProvider);
  }

  Future<void> _remove(KugouSavedAccount account, bool active) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialog) => CupertinoAlertDialog(
        title: Text(
          '移除${account.nickname.isEmpty ? '这个账号' : '“${account.nickname}”'}的本机登录？',
          style: MusicTypography.titleEmphasis,
        ),
        content: const Text('音乐库、队列、进度、历史和置顶记录会保留。以后登录同一账号可以恢复。'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('取消', style: MusicTypography.regularText),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('移除登录', style: MusicTypography.regularText),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(
      account.userId,
      () => active
          ? ref.read(platformAccountProvider.notifier).signOut()
          : ref
                .read(platformAccountProvider.notifier)
                .removeKugouAccount(account.userId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(savedKugouAccountsProvider);
    final selected = ref.watch(platformAccountProvider).value;
    return BetaMusicChromeCover(
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 14, 18, 14),
                child: Row(
                  children: [
                    const BetaGlassBackButton(),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        '切换酷狗账号',
                        maxLines: 2,
                        style: TextStyle(
                          fontSize:
                              MediaQuery.textScalerOf(context).scale(14) > 21
                              ? MusicTypography.headingSize
                              : MusicTypography.titleSize,
                          fontWeight: MusicTypography.titleWeight,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() => _managing = !_managing),
                      child: Text(_managing ? '完成' : '管理'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: accounts.when(
                  loading: () => const Center(child: BetaActivityIndicator()),
                  error: (_, _) => Center(
                    child: TextButton(
                      onPressed: () =>
                          ref.invalidate(savedKugouAccountsProvider),
                      child: const Text('账号列表读取失败，重试'),
                    ),
                  ),
                  data: (rows) => ListView(
                    padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
                    children: [
                      for (final row in rows)
                        Builder(
                          builder: (context) {
                            final active =
                                selected?.platform == MusicPlatform.kugou &&
                                selected?.userId == row.userId;
                            return ListTile(
                              key: ValueKey('kugou-account-${row.userId}'),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 12,
                              ),
                              leading: PlatformAvatar(
                                url: row.avatarUrl,
                                size: 58,
                              ),
                              title: Text(
                                row.nickname.isEmpty ? '酷狗账号' : row.nickname,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                '${row.methodLabel}${row.standardAuthorized ? ' · 官版功能已验证' : ''}',
                              ),
                              trailing: _pending == row.userId
                                  ? const BetaActivityIndicator()
                                  : _managing
                                  ? IconButton(
                                      tooltip: '移除本机登录',
                                      onPressed: _busy
                                          ? null
                                          : () => _remove(row, active),
                                      icon: const Icon(
                                        CupertinoIcons.minus_circle,
                                      ),
                                    )
                                  : active
                                  ? const Text('当前登录')
                                  : TextButton(
                                      onPressed: _busy
                                          ? null
                                          : () => _run(
                                              row.userId,
                                              () => ref
                                                  .read(
                                                    platformAccountProvider
                                                        .notifier,
                                                  )
                                                  .switchKugouAccount(
                                                    row.userId,
                                                  ),
                                            ),
                                      child: const Text('切换'),
                                    ),
                            );
                          },
                        ),
                      if (rows.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(22),
                          child: Text('添加酷狗账号后，可以在这里切换。'),
                        ),
                      ListTile(
                        key: const ValueKey('kugou-add-account'),
                        leading: const Icon(
                          CupertinoIcons.add_circled,
                          size: 34,
                        ),
                        title: const Text('添加账号'),
                        onTap: _busy ? null : _login,
                      ),
                      if (selected?.platform == MusicPlatform.kugou)
                        ListTile(
                          leading: const Icon(CupertinoIcons.checkmark_shield),
                          title: Text(
                            selected!.kugouStandardToken.isEmpty
                                ? '验证酷狗官方功能'
                                : '更新酷狗官方授权',
                          ),
                          subtitle: const Text('使用同一账号扫码验证听歌统计、等级与徽章。'),
                          onTap: _busy
                              ? null
                              : () => openKugouStandardAuthorization(
                                  context,
                                  selected,
                                ),
                        ),
                      if (rows.isNotEmpty)
                        ListTile(
                          leading: const Icon(CupertinoIcons.arrow_clockwise),
                          title: const Text('重新登录账号'),
                          subtitle: const Text('登录同一账号会更新凭据，保留本机音乐数据。'),
                          onTap: _busy ? null : _login,
                        ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            _error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
