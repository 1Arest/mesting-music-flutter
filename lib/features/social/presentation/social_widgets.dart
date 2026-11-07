import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../core/errors/user_facing_error.dart';
import '../../../shared/widgets/artwork_image.dart';
import '../../../shared/widgets/mesting_loading_indicator.dart';
import '../domain/social_models.dart';

class SocialPageHeader extends StatelessWidget {
  const SocialPageHeader({
    required this.title,
    super.key,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _HeaderButton(
          label: '返回',
          icon: Icons.arrow_back_rounded,
          onTap: () => Navigator.maybePop(context),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}

class SocialHeaderButton extends StatelessWidget {
  const SocialHeaderButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.unreadCount = 0,
    super.key,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final int unreadCount;

  @override
  Widget build(BuildContext context) => _HeaderButton(
    label: label,
    icon: icon,
    onTap: onTap,
    unreadCount: unreadCount,
  );
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.unreadCount = 0,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final int unreadCount;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(19),
        child: Ink(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: dark
                ? Colors.white.withValues(alpha: .08)
                : Colors.white.withValues(alpha: .78),
            borderRadius: BorderRadius.circular(19),
            border: Border.all(
              color: dark
                  ? Colors.white.withValues(alpha: .13)
                  : Colors.black.withValues(alpha: .08),
            ),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Center(child: Icon(icon, size: 24)),
              if (unreadCount > 0)
                Positioned(
                  top: -6,
                  right: -6,
                  child: Semantics(
                    label: '$unreadCount 条未读消息',
                    child: Container(
                      key: const ValueKey('social-messages-unread-badge'),
                      constraints: const BoxConstraints(
                        minWidth: 20,
                        minHeight: 20,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 3,
                      ),
                      decoration: const BoxDecoration(
                        color: Color(0xFFC24A34),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        unreadCount > 99 ? '99+' : '$unreadCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          height: 1,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
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

class SocialAvatar extends StatelessWidget {
  const SocialAvatar({required this.user, this.size = 54, super.key});

  final SocialUser user;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [Color(0xFF8296F2), Color(0xFF3F9FB0)],
        ),
      ),
      child: user.avatarUrl?.trim().isNotEmpty == true
          ? ArtworkImage(
              uri: user.avatarUrl!,
              width: size,
              height: size,
              fit: BoxFit.cover,
              retryOnNetworkError: true,
              persistentNetworkCacheKey: 'social-avatar-${user.uid}',
            )
          : Icon(Icons.person_rounded, color: Colors.white, size: size * .52),
    );
  }
}

class SocialStatusBadge extends StatelessWidget {
  const SocialStatusBadge({
    required this.status,
    super.key,
    this.onTap,
    this.emptyLabel = '添加状态',
    this.plain = false,
  });

  final SocialStatus status;
  final VoidCallback? onTap;
  final String emptyLabel;
  final bool plain;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final empty = status.isEmpty;
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (empty)
          Icon(Icons.add_rounded, size: 16, color: accent)
        else
          Text(status.emoji, style: const TextStyle(fontSize: 15, height: 1)),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            empty ? emptyLabel : status.text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: empty ? accent : null,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        if (onTap != null && !plain) ...[
          const SizedBox(width: 3),
          Icon(Icons.expand_more_rounded, size: 15, color: accent),
        ],
      ],
    );
    final child = plain
        ? ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 32, maxWidth: 210),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
              child: content,
            ),
          )
        : Container(
            constraints: const BoxConstraints(minHeight: 32, maxWidth: 210),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: empty ? .08 : .13),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: accent.withValues(alpha: .20)),
            ),
            child: content,
          );
    if (onTap == null) return child;
    return Semantics(
      button: true,
      label: empty ? '添加状态' : '更换状态：${status.label}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: child,
      ),
    );
  }
}

class SocialGlass extends StatelessWidget {
  const SocialGlass({
    required this.child,
    super.key,
    this.radius = 24,
    this.borderRadius,
  });

  final Widget child;
  final double radius;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final resolvedBorderRadius = borderRadius ?? BorderRadius.circular(radius);
    return ClipRRect(
      borderRadius: resolvedBorderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: dark
                ? const Color(0xD918151E)
                : Colors.white.withValues(alpha: .82),
            borderRadius: resolvedBorderRadius,
            border: Border.all(
              color: dark
                  ? Colors.white.withValues(alpha: .12)
                  : Colors.black.withValues(alpha: .08),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

class SocialEmptyState extends StatelessWidget {
  const SocialEmptyState({
    required this.icon,
    required this.title,
    required this.message,
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return SocialGlass(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 36, 24, 38),
        child: Column(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: .12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: Theme.of(context).colorScheme.primary,
                size: 30,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 7),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                height: 1.5,
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SocialLoadingState extends StatelessWidget {
  const SocialLoadingState({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: MestingLoadingIndicator(
        key: const ValueKey('social-loading-animation'),
        size: 76,
        semanticLabel: message,
      ),
    );
  }
}

class SocialErrorCard extends StatelessWidget {
  const SocialErrorCard({
    required this.error,
    required this.onRetry,
    super.key,
  });

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return SocialGlass(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Icon(Icons.cloud_off_rounded, size: 30),
            const SizedBox(height: 10),
            Text(
              userFacingErrorMessage(error, fallback: '好友服务暂时不可用，请稍后重试'),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('重新加载'),
            ),
          ],
        ),
      ),
    );
  }
}
