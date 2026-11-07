import '../../../shared/widgets/beta_content_insets.dart';
import '../../../shared/widgets/music_refresh_indicator.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import '../../../shared/widgets/beta_swipe_pages.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/user_facing_error.dart';
import '../../../shared/widgets/liquid_glass_sheet.dart';
import '../../../shared/widgets/music_notice.dart';
import '../../auth/auth_providers.dart';
import '../domain/social_models.dart';
import '../social_providers.dart';
import '../social_attention.dart';
import 'social_widgets.dart';
import '../../themes/music_typography.dart';

class SocialConnectionsPage extends ConsumerStatefulWidget {
  const SocialConnectionsPage({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  ConsumerState<SocialConnectionsPage> createState() =>
      _SocialConnectionsPageState();
}

class _SocialConnectionsPageState extends ConsumerState<SocialConnectionsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 1),
    );
    if (widget.initialTab == 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final uid = ref.read(currentUserProvider)?.uid ?? '';
        unawaited(
          ref
              .read(socialAttentionControllerProvider.notifier)
              .markFollowersSeen(uid),
        );
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final attention = ref.watch(socialAttentionControllerProvider);
    return Padding(
      padding: EdgeInsets.only(top: top + 12),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SocialPageHeader(
              title: '好友',
              subtitle: '互相关注后即可聊天',
              trailing: SocialHeaderButton(
                label: '消息',
                icon: Icons.chat_bubble_outline_rounded,
                unreadCount: attention.messageUnreadCount,
                onTap: () => context.push('/social/messages'),
              ),
            ),
          ),
          const SizedBox(height: 15),
          TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: '关注'),
              Tab(text: '粉丝'),
            ],
          ),
          const SizedBox(height: 8),
          if (attention.messageUnreadCount > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: _UnreadMessagesNotice(
                count: attention.messageUnreadCount,
                onTap: () => context.push('/social/messages'),
              ),
            ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                BetaTabScrollRelay(
                  controller: _tabController,
                  index: 0,
                  child: const _ConnectionList(
                    kind: SocialConnectionKind.following,
                  ),
                ),
                BetaTabScrollRelay(
                  controller: _tabController,
                  index: 1,
                  child: const _ConnectionList(
                    kind: SocialConnectionKind.followers,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UnreadMessagesNotice extends StatelessWidget {
  const _UnreadMessagesNotice({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = const Color(0xFFC24A34);
    return SocialGlass(
      radius: 16,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
          child: Row(
            children: [
              const Icon(
                Icons.mark_chat_unread_outlined,
                size: 19,
                color: Color(0xFFC24A34),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  '你有 $count 条未读私信，点击查看消息来源',
                  style: const TextStyle(
                    fontSize: MusicTypography.captionSize,
                    fontWeight: MusicTypography.bodyWeight,
                  ),
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: accent, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConnectionList extends ConsumerWidget {
  const _ConnectionList({required this.kind});

  final SocialConnectionKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final users = ref.watch(socialConnectionsProvider(kind));
    return users.when(
      loading: () => const SocialLoadingState(message: '正在加载关注与粉丝列表'),
      error: (error, stackTrace) => ListView(
        padding: BetaContentInsets.musicPaddingOf(
          context,
          EdgeInsets.fromLTRB(16, 10, 16, 170),
        ),
        children: [
          SocialErrorCard(
            error: error,
            onRetry: () => ref.invalidate(socialConnectionsProvider(kind)),
          ),
        ],
      ),
      data: (items) {
        if (items.isEmpty) {
          return ListView(
            padding: BetaContentInsets.musicPaddingOf(
              context,
              EdgeInsets.fromLTRB(16, 12, 16, 170),
            ),
            children: [
              SocialEmptyState(
                icon: switch (kind) {
                  SocialConnectionKind.following =>
                    Icons.person_add_alt_1_rounded,
                  SocialConnectionKind.followers =>
                    Icons.people_outline_rounded,
                  SocialConnectionKind.recommended =>
                    Icons.person_add_alt_1_rounded,
                },
                title: switch (kind) {
                  SocialConnectionKind.following => '还没有关注任何人',
                  SocialConnectionKind.followers => '还没有新的听友',
                  SocialConnectionKind.recommended => '还没有关注任何人',
                },
                message: kind == SocialConnectionKind.followers
                    ? '当其他用户关注你时，会在这里出现。'
                    : '去搜索页输入昵称，找到和你口味相近的听友。',
              ),
            ],
          );
        }
        return MusicRefreshIndicator(
          onRefresh: () async {
            ref.invalidate(socialConnectionsProvider(kind));
            await ref.read(socialConnectionsProvider(kind).future);
          },
          child: ListView.separated(
            padding: BetaContentInsets.musicPaddingOf(
              context,
              EdgeInsets.fromLTRB(16, 4, 16, 170),
            ),
            itemCount: items.length,
            separatorBuilder: (context, index) => const SizedBox(height: 9),
            itemBuilder: (context, index) => _UserRow(
              user: items[index],
              followerMenu: kind == SocialConnectionKind.followers,
            ),
          ),
        );
      },
    );
  }
}

class _UserRow extends ConsumerStatefulWidget {
  const _UserRow({required this.user, required this.followerMenu});

  final SocialUser user;
  final bool followerMenu;

  @override
  ConsumerState<_UserRow> createState() => _UserRowState();
}

class _UserRowState extends ConsumerState<_UserRow> {
  bool _working = false;

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    return SocialGlass(
      radius: 20,
      child: InkWell(
        onTap: () =>
            context.push('/social/users/${Uri.encodeComponent(user.uid)}'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(13, 12, 10, 12),
          child: Row(
            children: [
              SocialAvatar(user: user, size: 52),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: MusicTypography.subheadlineSize,
                        fontWeight: MusicTypography.bodyWeight,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      user.remark.isNotEmpty
                          ? '昵称：${user.nickname}'
                          : user.bio.trim().isEmpty
                          ? user.isFriend
                                ? '互相关注 · 可以聊天'
                                : '在 Mesting Music 听歌'
                          : user.bio,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: MusicTypography.smallCaptionSize,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _FollowButton(
                following: user.isFollowing,
                friend: user.isFriend,
                busy: _working,
                onTap: () => _toggleFollow(user),
              ),
              if (widget.followerMenu) ...[
                const SizedBox(width: 2),
                IconButton(
                  tooltip: '粉丝管理',
                  onPressed: _working ? null : () => _showFollowerMenu(user),
                  icon: const Icon(Icons.more_vert_rounded),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _toggleFollow(SocialUser user) async {
    setState(() => _working = true);
    try {
      await ref
          .read(socialRepositoryProvider)
          .setFollowing(user.uid, following: !user.isFollowing);
      _refresh(user.uid);
      if (mounted) {
        showMusicNotice(
          context,
          icon: Icons.check_rounded,
          title: user.isFollowing ? '已取消关注' : '已关注',
          message: !user.isFollowing && user.followsMe ? '你们现在可以聊天了' : '',
        );
      }
    } on Object catch (error) {
      if (mounted) {
        showMusicNotice(
          context,
          icon: Icons.error_outline_rounded,
          title: '操作失败',
          message: userFacingErrorMessage(error, fallback: '好友操作失败，请稍后重试'),
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _showFollowerMenu(SocialUser user) async {
    final remove = await showLiquidGlassBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      builder: (context) => _RemoveFollowerSheet(user: user),
    );
    if (remove != true || !mounted) return;
    setState(() => _working = true);
    try {
      await ref.read(socialRepositoryProvider).removeFollower(user.uid);
      _refresh(user.uid);
      if (mounted) {
        showMusicNotice(
          context,
          icon: Icons.check_rounded,
          title: '已移除粉丝',
          message: '${user.displayName} 已从你的粉丝列表中移除',
        );
      }
    } on Object catch (error) {
      if (mounted) {
        showMusicNotice(
          context,
          icon: Icons.error_outline_rounded,
          title: '移除失败',
          message: userFacingErrorMessage(error, fallback: '移除粉丝失败，请稍后重试'),
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _refresh(String uid) {
    ref.invalidate(socialSummaryProvider);
    ref.invalidate(socialConnectionsProvider);
    ref.invalidate(socialUserProvider(uid));
  }
}

class _FollowButton extends StatelessWidget {
  const _FollowButton({
    required this.following,
    required this.friend,
    required this.busy,
    required this.onTap,
  });

  final bool following;
  final bool friend;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: following
          ? OutlinedButton(
              onPressed: busy ? null : onTap,
              child: Text(friend ? '互相关注' : '已关注'),
            )
          : FilledButton.tonalIcon(
              onPressed: busy ? null : onTap,
              icon: const Icon(Icons.add_rounded, size: 17),
              label: const Text('关注'),
            ),
    );
  }
}

class _RemoveFollowerSheet extends StatelessWidget {
  const _RemoveFollowerSheet({required this.user});

  final SocialUser user;

  @override
  Widget build(BuildContext context) {
    return SocialGlass(
      radius: 30,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: .22),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '移除 ${user.displayName}？',
              style: const TextStyle(
                fontSize: MusicTypography.headingSize,
                fontWeight: MusicTypography.titleWeight,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '移除后，对方会从你的粉丝列表中消失；系统不会向对方发送通知。',
              style: TextStyle(
                height: 1.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: () => Navigator.pop(context, true),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFC24A34),
                ),
                icon: const Icon(Icons.person_remove_alt_1_rounded),
                label: const Text('移除粉丝'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
