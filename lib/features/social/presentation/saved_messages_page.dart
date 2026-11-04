import '../../../shared/widgets/music_activity_indicator.dart';
import '../../../shared/widgets/beta_content_insets.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/persistence/app_preferences.dart';
import '../../../core/audio/playback_providers.dart';
import '../../../shared/widgets/liquid_glass_sheet.dart';
import '../../../shared/widgets/music_notice.dart';
import '../../auth/auth_providers.dart';
import '../data/social_repository.dart';
import '../domain/chat_message_actions.dart';
import '../domain/social_models.dart';
import '../domain/track_share.dart';
import '../social_providers.dart';
import 'chat_page.dart';
import 'social_widgets.dart';

typedef SavedMessageMediaResolver =
    Future<String?> Function(String value, {bool forceRefresh});
typedef SavedMessageMediaDownloader =
    Future<File> Function(String url, String cacheKey);

final BaseCacheManager _savedMessageMediaCache = DefaultCacheManager();

/// Resolves a fresh signed address and stores the complete media file locally
/// before handing it to a platform player.
///
/// CloudBase download addresses are temporary. Preparing the file at tap time
/// avoids an expired URL being retained by a long-lived widget or native
/// controller, and gives audio/video players a stable local source.
@visibleForTesting
Future<String> prepareSavedMessageMediaForPlayback({
  required String rawValue,
  String? resolvedValue,
  required SavedMessageMediaResolver resolve,
  required SavedMessageMediaDownloader download,
}) async {
  final value = rawValue.trim();
  if (value.isEmpty) {
    throw const SocialRequestException('收藏的媒体文件地址不存在');
  }
  if (_isLocalSavedMediaPath(value)) return value;

  final candidates = <String>[];
  void addCandidate(String? candidate) {
    final normalized = candidate?.trim() ?? '';
    if (normalized.isEmpty || normalized.startsWith('cloud://')) return;
    if (!candidates.contains(normalized)) candidates.add(normalized);
  }

  // Reuse the same already-resolved source that the live conversation can
  // play. DefaultCacheManager keys remote files by this URL, so this also
  // reuses a voice file that the chat page has already cached instead of
  // forcing a second CloudBase request and a separate download.
  addCandidate(resolvedValue);
  if (!value.startsWith('cloud://')) addCandidate(value);

  Object? lastFailure;
  final attemptedCandidates = <String>{};
  Future<String?> tryCandidates() async {
    for (final candidate in candidates) {
      if (!attemptedCandidates.add(candidate)) continue;
      try {
        if (_isLocalSavedMediaPath(candidate)) return candidate;
        final file = await download(
          candidate,
          candidate,
        ).timeout(const Duration(seconds: 90));
        if (await file.exists() && await file.length() > 0) return file.path;
        lastFailure = const SocialRequestException('收藏的媒体文件下载不完整');
      } on Object catch (error) {
        lastFailure = error;
      }
    }
    return null;
  }

  final existing = await tryCandidates();
  if (existing != null) return existing;

  // A cached/signed URL can expire. Only after the source already used by the
  // conversation fails do we ask CloudBase for a new one, then retry with a
  // different cache key derived from that fresh URL.
  addCandidate(await resolve(value, forceRefresh: true));
  final refreshed = await tryCandidates();
  if (refreshed != null) return refreshed;

  if (lastFailure is SocialRequestException) throw lastFailure!;
  throw const SocialRequestException('暂时无法恢复收藏的媒体文件');
}

bool _isLocalSavedMediaPath(String value) =>
    value.startsWith('file://') ||
    value.startsWith('/') ||
    RegExp(r'^[A-Za-z]:[\\/]').hasMatch(value);

Future<String> _prepareSavedMessageMedia(
  WidgetRef ref,
  String rawValue, {
  String? resolvedValue,
}) {
  final repository = ref.read(socialRepositoryProvider);
  return prepareSavedMessageMediaForPlayback(
    rawValue: rawValue,
    resolvedValue: resolvedValue,
    resolve: (value, {forceRefresh = false}) {
      if (repository is SocialMediaUrlResolver) {
        return (repository as SocialMediaUrlResolver).resolveMediaUrl(
          value,
          forceRefresh: forceRefresh,
        );
      }
      return Future<String?>.value(value.startsWith('cloud://') ? null : value);
    },
    download: (url, cacheKey) =>
        _savedMessageMediaCache.getSingleFile(url, key: cacheKey),
  );
}

/// Personal message collection backed by the signed-in user's local storage.
///
/// Saved snapshots keep their own readable copy so removing a message from a
/// conversation never makes a deliberately saved item disappear here.
class SavedMessagesPage extends ConsumerStatefulWidget {
  const SavedMessagesPage({super.key});

  @override
  ConsumerState<SavedMessagesPage> createState() => _SavedMessagesPageState();
}

class _SavedMessagesPageState extends ConsumerState<SavedMessagesPage> {
  @override
  Widget build(BuildContext context) {
    return _SavedSnapshots(builder: (messages) => _content(context, messages));
  }

  Widget _content(BuildContext context, List<SavedChatMessage> messages) {
    final top = MediaQuery.paddingOf(context).top;
    return Column(
      children: [
        SizedBox(height: top + 12),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: SocialPageHeader(title: '收藏消息', subtitle: '点击查看详情，长按可以删除收藏'),
        ),
        const SizedBox(height: 17),
        Expanded(
          child: messages.isEmpty
              ? ListView(
                  padding: BetaContentInsets.musicPaddingOf(
                    context,
                    EdgeInsets.fromLTRB(16, 8, 16, 170),
                  ),
                  children: const [
                    SocialEmptyState(
                      icon: Icons.bookmark_outline_rounded,
                      title: '还没有收藏消息',
                      message: '在好友聊天中长按一条消息，选择“收藏”后就会出现在这里。',
                    ),
                  ],
                )
              : ListView.separated(
                  key: const ValueKey('saved-messages-list'),
                  padding: BetaContentInsets.musicPaddingOf(
                    context,
                    EdgeInsets.fromLTRB(16, 2, 16, 170),
                  ),
                  itemCount: messages.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 9),
                  itemBuilder: (context, index) => _SavedMessageRow(
                    message: messages[index],
                    onLongPress: () =>
                        _showSavedMessageActions(messages[index]),
                  ),
                ),
        ),
      ],
    );
  }

  Future<void> _showSavedMessageActions(SavedChatMessage message) async {
    final remove = await showLiquidGlassBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      showShadow: false,
      showDecorativeGlow: false,
      builder: (context) => _SavedMessageActionsSheet(message: message),
    );
    if (remove != true || !mounted) return;

    final uid = ref.read(currentUserProvider)?.uid.trim() ?? '';
    if (uid.isEmpty) return;
    try {
      final removed = await removeSavedChatMessage(
        ref.read(sharedPreferencesProvider),
        uid,
        message.id,
      );
      if (!mounted || !removed) return;
      setState(() {});
      showMusicNotice(
        context,
        icon: Icons.bookmark_remove_rounded,
        title: '已删除收藏',
        message: '好友会话里的原消息仍会保留',
      );
    } on Object {
      if (!mounted) return;
      showMusicNotice(
        context,
        icon: Icons.error_outline_rounded,
        title: '删除失败',
        message: '暂时无法更新收藏，请稍后重试',
      );
    }
  }
}

/// A saved message stays readable in its own collection view instead of
/// reopening the live conversation it originally came from.
class SavedMessageDetailPage extends ConsumerWidget {
  const SavedMessageDetailPage({required this.messageId, super.key});

  final String messageId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _SavedSnapshots(
      builder: (messages) => _content(context, ref, messages),
    );
  }

  Widget _content(
    BuildContext context,
    WidgetRef ref,
    List<SavedChatMessage> messages,
  ) {
    final top = MediaQuery.paddingOf(context).top;
    final message = _savedMessageWithId(messages, messageId);
    return Column(
      children: [
        SizedBox(height: top + 12),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: SocialPageHeader(title: '收藏详情', subtitle: '已保存的独立消息快照'),
        ),
        const SizedBox(height: 17),
        Expanded(
          child: message == null
              ? ListView(
                  padding: BetaContentInsets.musicPaddingOf(
                    context,
                    EdgeInsets.fromLTRB(16, 8, 16, 170),
                  ),
                  children: const [
                    SocialEmptyState(
                      icon: Icons.bookmark_remove_outlined,
                      title: '收藏内容不可用',
                      message: '这条收藏可能已被移除，请返回收藏消息查看其他内容。',
                    ),
                  ],
                )
              : ListView(
                  key: const ValueKey('saved-message-detail'),
                  padding: BetaContentInsets.musicPaddingOf(
                    context,
                    EdgeInsets.fromLTRB(16, 2, 16, 170),
                  ),
                  children: [
                    Semantics(
                      label:
                          '收藏详情：${message.authorName}的${_savedMessageKindLabel(message.kind)}',
                      child: SocialGlass(
                        radius: 22,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 19, 20, 22),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _SavedMessageDetailMeta(message: message),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 18,
                                ),
                                child: Divider(
                                  height: 1,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .outlineVariant
                                      .withValues(alpha: .42),
                                ),
                              ),
                              Text(
                                _savedMessageKindLabel(message.kind),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 11),
                              _SavedMessageDetailContent(message: message),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _SavedMessageRow extends StatelessWidget {
  const _SavedMessageRow({required this.message, required this.onLongPress});

  final SavedChatMessage message;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SocialGlass(
      radius: 18,
      child: InkWell(
        key: ValueKey('saved-message-row-${message.id}'),
        onTap: () => context.push(
          '/social/saved-messages/${Uri.encodeComponent(message.id)}',
        ),
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: .12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _kindIcon(message.kind),
                  size: 22,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      message.authorName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _messagePreview(message),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _savedMessageTime(message.sentAt),
                    style: TextStyle(
                      fontSize: 10,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 11),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SavedMessageActionsSheet extends StatelessWidget {
  const _SavedMessageActionsSheet({required this.message});

  final SavedChatMessage message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 26),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 44,
              height: 4,
              margin: const EdgeInsets.only(bottom: 18),
              decoration: BoxDecoration(
                color: scheme.onSurface.withValues(alpha: .20),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          const Text(
            '收藏操作',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 5),
          Text(
            '只会移除这条收藏，不会删除好友会话里的原消息或媒体文件。',
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontSize: 12,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),
          Semantics(
            button: true,
            label: '删除收藏：${message.authorName}',
            child: InkWell(
              key: ValueKey('delete-saved-message-${message.id}'),
              onTap: () => Navigator.of(context).pop(true),
              borderRadius: BorderRadius.circular(14),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 64),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: scheme.error.withValues(alpha: .12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.delete_outline_rounded,
                        color: scheme.error,
                      ),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '删除收藏',
                            style: TextStyle(
                              color: scheme.error,
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _messagePreview(message),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: scheme.error.withValues(alpha: .72),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SavedMessageDetailMeta extends StatelessWidget {
  const _SavedMessageDetailMeta({required this.message});

  final SavedChatMessage message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: .12),
            shape: BoxShape.circle,
          ),
          child: Icon(_kindIcon(message.kind), color: scheme.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                message.authorName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '收藏于 ${_savedMessageDateTime(message.sentAt)}',
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SavedMessageDetailContent extends ConsumerWidget {
  const _SavedMessageDetailContent({required this.message});

  final SavedChatMessage message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    if (message.kind == SocialMessageKind.text) {
      final track = decodeTrackShareMessage(message.text);
      if (track != null) {
        return SocialSharedTrackMessage(
          messageId: message.id,
          track: track,
          mine: false,
          keyPrefix: 'saved-message',
          onPlay: track.isPlayable
              ? () => ref.read(audioHandlerProvider).playSingleTrack(track)
              : null,
        );
      }
      final quote = decodeChatMessageQuote(message.text);
      final content = quote?.content ?? message.text.trim();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (quote != null) ...[
            Text(
              '回复 ${quote.excerpt}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
          ],
          SelectableText(
            content.isEmpty ? '文字消息' : content,
            style: const TextStyle(fontSize: 16, height: 1.55),
          ),
        ],
      );
    }
    if (message.kind == SocialMessageKind.emoji) {
      return Text(message.text, style: const TextStyle(fontSize: 44));
    }
    if (message.kind == SocialMessageKind.voice) {
      return _SavedMessageVoicePreview(message: message);
    }
    if (message.kind == SocialMessageKind.video) {
      return _SavedMessageVideoPreview(message: message);
    }
    return _SavedMessageAttachmentPreview(
      icon: Icons.image_outlined,
      label: '已保存图片',
    );
  }
}

class _SavedMessageVoicePreview extends ConsumerWidget {
  const _SavedMessageVoicePreview({required this.message});

  final SavedChatMessage message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rawSource = message.mediaUrl?.trim() ?? '';
    final sourceState = rawSource.startsWith('cloud://')
        ? ref.watch(socialMediaUrlProvider(rawSource))
        : null;
    // A CloudBase object ID is not a media URL a platform player can open.
    // Do not create a player until its short-lived HTTPS download URL has
    // arrived; otherwise the player holds on to the failed `cloud://` source
    // even after the resolver finishes.
    final source = playableSavedMessageMediaUrl(rawSource, sourceState?.value);
    if (source.isEmpty) {
      final label = rawSource.isEmpty
          ? '未保存语音文件'
          : sourceState?.isLoading == true
          ? '正在恢复语音…'
          : '语音暂时无法恢复';
      return _SavedMessageAttachmentPreview(
        icon: Icons.graphic_eq_rounded,
        label: label,
      );
    }
    return SocialVoiceMessage(
      messageId: message.id,
      url: source,
      duration: chatVoiceDurationFromText(message.text),
      mine: false,
      keyPrefix: 'saved-message',
      playbackSourceProvider: () =>
          _prepareSavedMessageMedia(ref, rawSource, resolvedValue: source),
    );
  }
}

class _SavedMessageVideoPreview extends ConsumerWidget {
  const _SavedMessageVideoPreview({required this.message});

  final SavedChatMessage message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rawSource = message.mediaUrl?.trim() ?? '';
    final rawThumbnail = message.thumbnailUrl?.trim() ?? '';
    final sourceState = rawSource.startsWith('cloud://')
        ? ref.watch(socialMediaUrlProvider(rawSource))
        : null;
    final source = playableSavedMessageMediaUrl(rawSource, sourceState?.value);
    final thumbnailState = rawThumbnail.startsWith('cloud://')
        ? ref.watch(socialMediaUrlProvider(rawThumbnail))
        : null;
    final thumbnail = playableSavedMessageMediaUrl(
      rawThumbnail,
      thumbnailState?.value,
    );
    if (source.isEmpty) {
      final label = rawSource.isEmpty
          ? '未保存视频文件'
          : sourceState?.isLoading == true
          ? '正在恢复视频…'
          : '视频暂时无法恢复';
      return _SavedMessageAttachmentPreview(
        icon: Icons.videocam_outlined,
        label: label,
      );
    }
    return SocialVideoMessage(
      messageId: message.id,
      url: source,
      thumbnailUrl: thumbnail,
      keyPrefix: 'saved-message',
      playbackSourceProvider: () =>
          _prepareSavedMessageMedia(ref, rawSource, resolvedValue: source),
    );
  }
}

/// Returns a source that can safely be given to an audio or video player.
///
/// Current saved snapshots can contain either a directly playable local/HTTPS
/// address or CloudBase's stable `cloud://` object ID. The latter must wait for
/// [resolvedCloudUrl], rather than being forwarded as if it were a network
/// address. This is intentionally shared by saved voice, video, and video
/// thumbnail previews so their first controller always receives a valid URL.
String playableSavedMessageMediaUrl(String rawValue, String? resolvedCloudUrl) {
  final value = rawValue.trim();
  if (value.isEmpty) return '';
  if (!value.startsWith('cloud://')) return value;
  return resolvedCloudUrl?.trim() ?? '';
}

class _SavedMessageAttachmentPreview extends StatelessWidget {
  const _SavedMessageAttachmentPreview({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: .72),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: scheme.primary),
          const SizedBox(width: 10),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

IconData _kindIcon(SocialMessageKind kind) => switch (kind) {
  SocialMessageKind.text => Icons.chat_bubble_outline_rounded,
  SocialMessageKind.emoji => Icons.sentiment_satisfied_alt_rounded,
  SocialMessageKind.image => Icons.image_outlined,
  SocialMessageKind.video => Icons.videocam_outlined,
  SocialMessageKind.voice => Icons.graphic_eq_rounded,
};

String _messagePreview(SavedChatMessage message) {
  if (message.kind == SocialMessageKind.text) {
    final track = decodeTrackShareMessage(message.text);
    if (track != null) return '🎵 ${track.title} · ${track.artist}';
    final quote = decodeChatMessageQuote(message.text);
    if (quote != null && quote.content.trim().isNotEmpty) {
      return quote.content;
    }
    return message.text.trim().isEmpty ? '文字消息' : message.text;
  }
  return switch (message.kind) {
    SocialMessageKind.text => '文字消息',
    SocialMessageKind.emoji => message.text,
    SocialMessageKind.image => '[图片]',
    SocialMessageKind.video => '[视频]',
    SocialMessageKind.voice => '[语音消息]',
  };
}

SavedChatMessage? _savedMessageWithId(
  Iterable<SavedChatMessage> messages,
  String id,
) {
  for (final message in messages) {
    if (message.id == id) return message;
  }
  return null;
}

String _savedMessageKindLabel(SocialMessageKind kind) => switch (kind) {
  SocialMessageKind.text => '文字消息',
  SocialMessageKind.emoji => '表情',
  SocialMessageKind.image => '图片',
  SocialMessageKind.video => '视频',
  SocialMessageKind.voice => '语音消息',
};

String _savedMessageDateTime(DateTime value) {
  final local = value.toLocal();
  return '${local.year}/${local.month.toString().padLeft(2, '0')}/'
      '${local.day.toString().padLeft(2, '0')} '
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}

String _savedMessageTime(DateTime value) {
  final local = value.toLocal();
  final now = DateTime.now();
  if (now.difference(local).inDays == 0) {
    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
  return '${local.month}/${local.day}';
}

/// Large saved collections hydrate once per stored snapshot, with no parsing
/// during player/theme rebuilds and no previous-account data while waiting.
class _SavedSnapshots extends ConsumerStatefulWidget {
  const _SavedSnapshots({required this.builder});
  final Widget Function(List<SavedChatMessage>) builder;
  @override
  ConsumerState<_SavedSnapshots> createState() => _SavedSnapshotsState();
}

class _SavedSnapshotsState extends ConsumerState<_SavedSnapshots> {
  (String, String)? _key;
  Future<List<SavedChatMessage>>? _future;
  @override
  Widget build(BuildContext context) {
    final uid = ref.watch(currentUserProvider)?.uid ?? '';
    final preferences = ref.watch(sharedPreferencesProvider);
    final raw = preferences.getString(savedChatMessagesKey(uid)) ?? '';
    if (uid.isEmpty || raw.length < 128 * 1024) {
      return widget.builder(
        uid.isEmpty ? const [] : readSavedChatMessages(preferences, uid),
      );
    }
    final key = (uid, raw);
    if (key != _key) {
      _key = key;
      _future = readSavedChatMessagesAsync(preferences, uid);
    }
    return FutureBuilder<List<SavedChatMessage>>(
      key: ValueKey(uid),
      future: _future,
      builder: (context, snapshot) =>
          snapshot.connectionState != ConnectionState.done
          ? const Center(child: MusicActivityIndicator())
          : widget.builder(snapshot.data ?? const []),
    );
  }
}
