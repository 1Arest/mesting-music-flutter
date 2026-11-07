import 'package:flutter/material.dart';

import '../../../shared/widgets/liquid_glass_sheet.dart';
import '../domain/social_models.dart';
import 'social_widgets.dart';

/// Actions shared by a friend's profile and the conversation header.
enum FriendProfileAction { remark, share, removeFollower, block }

Future<FriendProfileAction?> showFriendProfileActions(
  BuildContext context, {
  required SocialUser user,
}) {
  return showLiquidGlassBottomSheet<FriendProfileAction>(
    context: context,
    useRootNavigator: true,
    useSafeArea: true,
    // This menu deliberately has square edges so it reads as a utility panel,
    // instead of a floating card with the rounded lower corners seen before.
    borderRadius: BorderRadius.zero,
    showShadow: false,
    showDecorativeGlow: false,
    builder: (context) => FriendProfileActionsSheet(user: user),
  );
}

class FriendProfileActionsSheet extends StatelessWidget {
  const FriendProfileActionsSheet({required this.user, super.key});

  final SocialUser user;

  @override
  Widget build(BuildContext context) {
    return SocialGlass(
      radius: 0,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 25),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 4,
              margin: const EdgeInsets.only(bottom: 13),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: .20),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            _FriendProfileActionRow(
              icon: Icons.edit_note_rounded,
              title: '设置备注名',
              onTap: () => Navigator.pop(context, FriendProfileAction.remark),
            ),
            _FriendProfileActionRow(
              icon: Icons.ios_share_rounded,
              title: '分享',
              onTap: () => Navigator.pop(context, FriendProfileAction.share),
            ),
            if (user.followsMe)
              _FriendProfileActionRow(
                icon: Icons.person_remove_alt_1_rounded,
                title: '移除粉丝',
                onTap: () =>
                    Navigator.pop(context, FriendProfileAction.removeFollower),
              ),
            _FriendProfileActionRow(
              icon: Icons.block_rounded,
              title: '加入黑名单',
              destructive: true,
              onTap: () => Navigator.pop(context, FriendProfileAction.block),
            ),
          ],
        ),
      ),
    );
  }
}

class _FriendProfileActionRow extends StatelessWidget {
  const _FriendProfileActionRow({
    required this.icon,
    required this.title,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? const Color(0xFFC24A34) : null;
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: color),
      title: Text(
        title,
        style: TextStyle(color: color, fontWeight: FontWeight.w800),
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
    );
  }
}
