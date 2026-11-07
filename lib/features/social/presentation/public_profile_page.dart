import '../../../shared/widgets/artwork_scroll_frontier.dart';
import '../../../shared/widgets/beta_content_insets.dart';
import '../../../shared/widgets/beta_text_editing.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/user_facing_error.dart';
import '../../../core/platform/share_bridge.dart';
import '../../../shared/widgets/liquid_glass_sheet.dart';
import '../../../shared/widgets/mesting_loading_indicator.dart';
import '../../../shared/widgets/music_notice.dart';
import '../domain/social_models.dart';
import '../social_providers.dart';
import 'friend_profile_actions_sheet.dart';
import 'social_widgets.dart';

class PublicProfilePage extends ConsumerStatefulWidget {
  const PublicProfilePage({required this.uid, super.key});

  final String uid;

  @override
  ConsumerState<PublicProfilePage> createState() => _PublicProfilePageState();
}

class _PublicProfilePageState extends ConsumerState<PublicProfilePage> {
  bool _working = false;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final user = ref.watch(socialUserProvider(widget.uid));
    return user.when(
      loading: () => const Center(
        child: MestingLoadingIndicator(
          key: ValueKey('public-profile-loading-animation'),
          size: 92,
          semanticLabel: '正在加载好友主页',
        ),
      ),
      error: (error, stackTrace) => ListView(
        padding: BetaContentInsets.musicPaddingOf(
          context,
          EdgeInsets.fromLTRB(16, top + 12, 16, 170),
        ),
        children: [
          const SocialPageHeader(title: '用户主页'),
          const SizedBox(height: 22),
          SocialErrorCard(
            error: error,
            onRetry: () => ref.invalidate(socialUserProvider(widget.uid)),
          ),
        ],
      ),
      data: (profile) => CustomScrollView(
        physics: const ArtworkFrontierPhysics(parent: BouncingScrollPhysics()),
        slivers: [
          SliverPadding(
            padding: BetaContentInsets.musicPaddingOf(
              context,
              EdgeInsets.fromLTRB(16, top + 12, 16, 170),
            ),
            sliver: SliverList.list(
              children: [
                Row(
                  children: [
                    SocialHeaderButton(
                      label: '返回',
                      icon: Icons.arrow_back_rounded,
                      onTap: () => Navigator.maybePop(context),
                    ),
                    const Spacer(),
                    SocialHeaderButton(
                      label: '更多',
                      icon: Icons.more_horiz_rounded,
                      onTap: _working ? () {} : () => _showActions(profile),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _ProfileHero(user: profile),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _ActionButton(
                        primary: !profile.isFollowing,
                        icon: profile.isFollowing
                            ? Icons.person_rounded
                            : Icons.person_add_alt_1_rounded,
                        label: profile.isFollowing
                            ? profile.isFriend
                                  ? '互相关注'
                                  : '已关注'
                            : '关注',
                        busy: _working,
                        onTap: () => _toggleFollow(profile),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ActionButton(
                        primary: profile.isFriend,
                        icon: Icons.chat_bubble_rounded,
                        label: profile.isFriend ? '聊天' : '互关后可聊天',
                        onTap: profile.isFriend
                            ? () => context.push(
                                '/social/chat/${Uri.encodeComponent(profile.uid)}',
                              )
                            : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                SocialGlass(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 19, 20, 21),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '音乐名片',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 13),
                        _InfoLine(
                          icon: Icons.graphic_eq_rounded,
                          title: '最近常听',
                          value: '暂未公开',
                        ),
                        const SizedBox(height: 12),
                        _InfoLine(
                          icon: Icons.favorite_outline_rounded,
                          title: '喜欢的音乐',
                          value: '由用户隐私设置决定',
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleFollow(SocialUser user) async {
    setState(() => _working = true);
    try {
      await ref
          .read(socialRepositoryProvider)
          .setFollowing(user.uid, following: !user.isFollowing);
      _refresh();
      if (mounted) {
        showMusicNotice(
          context,
          icon: Icons.check_rounded,
          title: user.isFollowing ? '已取消关注' : '已关注',
          message: !user.isFollowing && user.followsMe ? '你们现在可以聊天了' : '',
        );
      }
    } on Object catch (error) {
      _showError('操作失败', error);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _showActions(SocialUser user) async {
    final action = await showFriendProfileActions(context, user: user);
    if (action == null || !mounted) return;
    switch (action) {
      case FriendProfileAction.remark:
        await _editRemark(user);
      case FriendProfileAction.share:
        await _share(user);
      case FriendProfileAction.removeFollower:
        await _removeFollower(user);
      case FriendProfileAction.block:
        await _block(user);
    }
  }

  Future<void> _editRemark(SocialUser user) async {
    final controller = TextEditingController(text: user.remark);
    final value = await showLiquidGlassBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SocialGlass(
          radius: 30,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '设置备注名',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                Text(
                  '备注只对你可见，留空即可恢复显示原昵称。',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  contextMenuBuilder: buildBetaEditingMenu,
                  selectionControls: mestingTextSelectionControls,
                  cursorRadius: const Radius.circular(1),
                  controller: controller,
                  autofocus: true,
                  maxLength: 24,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (text) => Navigator.pop(context, text),
                  decoration: const InputDecoration(hintText: '输入备注名'),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 50,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, controller.text),
                    child: const Text('保存备注'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    controller.dispose();
    if (value == null || !mounted) return;
    await _runAction(
      () => ref.read(socialRepositoryProvider).setRemark(user.uid, value),
      successTitle: value.trim().isEmpty ? '已清除备注' : '备注已保存',
    );
  }

  Future<void> _share(SocialUser user) async {
    final text =
        '在 Mesting Music 认识 ${user.nickname}\nMesting 用户 ID：${user.uid}';
    try {
      await ShareBridge.shareText(text, title: '分享用户主页');
    } on MissingPluginException {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) {
        showMusicNotice(
          context,
          icon: Icons.copy_rounded,
          title: '主页信息已复制',
          message: '可以粘贴给好友',
        );
      }
    }
  }

  Future<void> _removeFollower(SocialUser user) async {
    final confirmed = await _confirmDestructive(
      title: '移除 ${user.displayName}？',
      message: '对方会从你的粉丝列表中消失，系统不会发送通知。',
      action: '移除粉丝',
    );
    if (confirmed != true) return;
    await _runAction(
      () => ref.read(socialRepositoryProvider).removeFollower(user.uid),
      successTitle: '已移除粉丝',
    );
  }

  Future<void> _block(SocialUser user) async {
    final confirmed = await _confirmDestructive(
      title: '将 ${user.displayName} 加入黑名单？',
      message: '双方关注关系会解除，之后不能互相发消息。',
      action: '加入黑名单',
    );
    if (confirmed != true) return;
    await _runAction(
      () => ref
          .read(socialRepositoryProvider)
          .setBlocked(user.uid, blocked: true),
      successTitle: '已加入黑名单',
    );
  }

  Future<bool?> _confirmDestructive({
    required String title,
    required String message,
    required String action,
  }) {
    return showLiquidGlassBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      builder: (context) => SocialGlass(
        radius: 30,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 9),
              Text(message),
              const SizedBox(height: 20),
              SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFC24A34),
                  ),
                  child: Text(action),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _runAction(
    Future<Object?> Function() action, {
    required String successTitle,
  }) async {
    setState(() => _working = true);
    try {
      await action();
      _refresh();
      if (mounted) {
        showMusicNotice(
          context,
          icon: Icons.check_rounded,
          title: successTitle,
          message: '',
        );
      }
    } on Object catch (error) {
      _showError('操作失败', error);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _showError(String title, Object error) {
    if (!mounted) return;
    showMusicNotice(
      context,
      icon: Icons.error_outline_rounded,
      title: title,
      message: userFacingErrorMessage(error, fallback: '好友操作失败，请稍后重试'),
    );
  }

  void _refresh() {
    ref.invalidate(socialUserProvider(widget.uid));
    ref.invalidate(socialSummaryProvider);
    ref.invalidate(socialConnectionsProvider);
    ref.invalidate(socialConversationsProvider);
  }
}

class _ProfileHero extends StatelessWidget {
  const _ProfileHero({required this.user});

  final SocialUser user;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return SocialGlass(
      radius: 30,
      child: Container(
        padding: const EdgeInsets.fromLTRB(22, 28, 22, 25),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              accent.withValues(alpha: .20),
              const Color(0xFF3F9FB0).withValues(alpha: .08),
            ],
          ),
        ),
        child: Column(
          children: [
            SocialAvatar(user: user, size: 96),
            const SizedBox(height: 16),
            Text(
              user.displayName,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w900),
            ),
            if (user.remark.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(
                '昵称：${user.nickname}',
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (user.status.isNotEmpty) ...[
              const SizedBox(height: 10),
              SocialStatusBadge(status: user.status),
            ],
            if (user.age != null || user.zodiac.trim().isNotEmpty) ...[
              const SizedBox(height: 11),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (user.age != null)
                    _ProfileDetailChip(
                      key: const ValueKey('public-profile-age'),
                      icon: Icons.cake_outlined,
                      label: '${user.age} 岁',
                    ),
                  if (user.zodiac.trim().isNotEmpty)
                    _ProfileDetailChip(
                      key: const ValueKey('public-profile-zodiac'),
                      icon: Icons.auto_awesome_outlined,
                      label: user.zodiac.trim(),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 9),
            Text(
              user.bio.trim().isEmpty ? '这个人很安静，还没有留下简介。' : user.bio,
              textAlign: TextAlign.center,
              style: const TextStyle(height: 1.5, fontSize: 12),
            ),
            const SizedBox(height: 21),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _Count(value: user.followingCount, label: '关注'),
                Container(
                  width: 1,
                  height: 29,
                  margin: const EdgeInsets.symmetric(horizontal: 30),
                  color: Theme.of(context).dividerColor,
                ),
                _Count(value: user.followerCount, label: '粉丝'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileDetailChip extends StatelessWidget {
  const _ProfileDetailChip({
    required this.icon,
    required this.label,
    super.key,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: .58),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .48)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: scheme.primary),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _Count extends StatelessWidget {
  const _Count({required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        '$value',
        style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
      ),
      Text(label, style: const TextStyle(fontSize: 11)),
    ],
  );
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.primary,
    required this.icon,
    required this.label,
    this.onTap,
    this.busy = false,
  });

  final bool primary;
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: primary
          ? FilledButton.icon(
              onPressed: busy ? null : onTap,
              icon: Icon(icon),
              label: Text(label),
            )
          : OutlinedButton.icon(
              onPressed: busy ? null : onTap,
              icon: Icon(icon),
              label: Text(label),
            ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({
    required this.icon,
    required this.title,
    required this.value,
  });

  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 21),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            Text(
              value,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}
