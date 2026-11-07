import 'package:flutter/material.dart';
import '../data/platform_comments_repository.dart';
import '../../themes/music_theme_tokens.dart';
import 'platform_avatar.dart';

/// Comment content has its own presentation component; thread identity and
/// writes remain owned by the page/repository instead of the visual card.
class PlatformCommentCard extends StatelessWidget {
  const PlatformCommentCard({
    required this.comment,
    this.onReply,
    this.onThread,
    this.onDelete,
    this.onReaction,
    this.onHug,
    super.key,
  });
  final PlatformComment comment;
  final VoidCallback? onReply;
  final VoidCallback? onThread;
  final VoidCallback? onDelete;
  final VoidCallback? onReaction;
  final VoidCallback? onHug;
  @override
  Widget build(BuildContext context) {
    final tokens = context.musicThemeTokens;
    final time = comment.time?.toLocal();
    final date = time == null
        ? ''
        : '${time.year}.${time.month.toString().padLeft(2, '0')}.${time.day.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PlatformAvatar(url: comment.avatar, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        comment.nickname,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (comment.isSinger)
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Text(
                          '歌手',
                          style: TextStyle(
                            color: tokens.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    if (date.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 10),
                        child: Text(
                          date,
                          style: TextStyle(
                            color: tokens.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 9),
                SelectableText(
                  comment.content,
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontSize: 15,
                    height: 1.55,
                  ),
                ),
                const SizedBox(height: 3),
                Wrap(
                  spacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (onReaction == null)
                      Padding(
                        padding: const EdgeInsets.only(right: 9),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.thumb_up_outlined,
                              size: 15,
                              color: tokens.textSecondary,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              '${comment.likes}',
                              style: TextStyle(
                                color: tokens.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      TextButton.icon(
                        onPressed: onReaction,
                        icon: Icon(
                          comment.liked
                              ? Icons.thumb_up_rounded
                              : Icons.thumb_up_outlined,
                          size: 16,
                        ),
                        label: Text('${comment.likes}'),
                      ),
                    TextButton(onPressed: onReply, child: const Text('回复')),
                    if (onHug != null)
                      TextButton(onPressed: onHug, child: const Text('抱一抱')),
                    if (onThread != null)
                      TextButton.icon(
                        onPressed: onThread,
                        icon: const Icon(
                          Icons.subdirectory_arrow_right_rounded,
                          size: 16,
                        ),
                        label: Text('查看回复（${comment.replies}）'),
                      ),
                    if (onDelete != null)
                      IconButton(
                        tooltip: '删除自己的评论',
                        onPressed: onDelete,
                        icon: Icon(
                          Icons.delete_outline_rounded,
                          color: tokens.textSecondary,
                          size: 19,
                        ),
                      ),
                  ],
                ),
                Divider(
                  height: 1,
                  color: tokens.textPrimary.withValues(alpha: .07),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
