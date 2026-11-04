import '../../../shared/widgets/music_refresh_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../domain/social_models.dart';
import '../domain/listen_together.dart';
import '../domain/track_share.dart';
import '../social_providers.dart';
import '../../player/presentation/music_page_transition.dart';
import 'social_widgets.dart';

class SocialMessagesPage extends ConsumerWidget {
  const SocialMessagesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final top = MediaQuery.paddingOf(context).top;
    final conversations = ref.watch(socialConversationsProvider);
    return Column(
      children: [
        SizedBox(height: top + 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SocialPageHeader(
            title: '我的消息',
            subtitle: '只接收互相关注好友的私信',
            trailing: SocialHeaderButton(
              label: '收藏消息',
              icon: Icons.bookmarks_outlined,
              onTap: () => context.push('/social/saved-messages'),
            ),
          ),
        ),
        const SizedBox(height: 17),
        Expanded(
          child: conversations.when(
            loading: () => const SocialLoadingState(message: '正在加载会话与未读消息'),
            error: (error, stackTrace) => ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 170),
              children: [
                SocialErrorCard(
                  error: error,
                  onRetry: () => ref.invalidate(socialConversationsProvider),
                ),
              ],
            ),
            data: (items) => items.isEmpty
                ? ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 170),
                    children: const [
                      SocialEmptyState(
                        icon: Icons.forum_outlined,
                        title: '还没有消息',
                        message: '和互相关注的好友聊聊最近循环的歌吧。',
                      ),
                    ],
                  )
                : MusicRefreshIndicator(
                    onRefresh: () async {
                      ref.invalidate(socialConversationsProvider);
                      await ref.read(socialConversationsProvider.future);
                    },
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 2, 16, 170),
                      itemCount: items.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 9),
                      itemBuilder: (context, index) =>
                          _ConversationRow(conversation: items[index]),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

class _ConversationRow extends StatelessWidget {
  const _ConversationRow({required this.conversation});

  final SocialConversation conversation;

  @override
  Widget build(BuildContext context) {
    final message = conversation.lastMessage;
    return SocialGlass(
      radius: 20,
      child: InkWell(
        onTap: () => context.push(
          '/social/chat/${Uri.encodeComponent(conversation.peer.uid)}',
          extra: const MusicPageTransitionIntent.messagesConversation(),
        ),
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Row(
            children: [
              SocialAvatar(user: conversation.peer, size: 54),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      conversation.peer.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _preview(message),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 48,
                height: 54,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _time(conversation.updatedAt),
                      key: ValueKey(
                        'social-conversation-time-${conversation.peer.uid}',
                      ),
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 10,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (conversation.unreadCount > 0) ...[
                      const Spacer(),
                      SizedBox.square(
                        key: ValueKey(
                          'social-conversation-unread-${conversation.peer.uid}',
                        ),
                        dimension: 22,
                        child: DecoratedBox(
                          decoration: const BoxDecoration(
                            color: Color(0xFFC24A34),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              socialConversationUnreadLabel(
                                conversation.unreadCount,
                              ),
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: conversation.unreadCount > 99
                                    ? 8
                                    : 10,
                                height: 1,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String socialConversationUnreadLabel(int count) =>
    count > 99 ? '99+' : '$count';

String _preview(SocialMessage? message) {
  if (message == null) return '开始聊天';
  return switch (message.kind) {
    SocialMessageKind.text => _textPreview(message),
    SocialMessageKind.emoji => message.text,
    SocialMessageKind.image => '[图片]',
    SocialMessageKind.video => '[视频]',
    SocialMessageKind.voice => '[语音]',
  };
}

String _textPreview(SocialMessage message) {
  final together = decodeListenTogetherInvite(message.text);
  if (together != null) {
    return '[一起听] ${together.trackTitle}';
  }
  final track = decodeTrackShareMessage(message.text);
  return track == null ? message.text : '[歌曲] ${track.title} · ${track.artist}';
}

String _time(DateTime value) {
  final now = DateTime.now();
  if (now.difference(value).inDays == 0) {
    return '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
  }
  return '${value.month}/${value.day}';
}
