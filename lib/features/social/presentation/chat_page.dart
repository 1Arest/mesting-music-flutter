import '../../../core/platform/distribution_channel.dart';
import '../../../shared/widgets/beta_text_editing.dart';
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:just_audio/just_audio.dart' as just_audio;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import '../../../core/errors/user_facing_error.dart';
import '../../../core/audio/playback_providers.dart';
import '../../../core/persistence/app_preferences.dart';
import '../../../core/platform/share_bridge.dart';
import '../../../shared/layout/adaptive_layout.dart';
import '../../../shared/models/track.dart';
import '../../../shared/widgets/artwork_image.dart';
import '../../../shared/widgets/mesting_loading_indicator.dart';
import '../../../shared/widgets/music_notice.dart';
import '../../../shared/widgets/liquid_glass_sheet.dart';
import '../../auth/auth_providers.dart';
import '../../themes/mesting_palette.dart';
import '../domain/listen_together.dart';
import '../domain/chat_message_actions.dart';
import '../domain/social_models.dart';
import '../domain/track_share.dart';
import '../listen_together_providers.dart';
import '../social_providers.dart';
import '../social_attention.dart';
import 'social_widgets.dart';
import 'friend_profile_actions_sheet.dart';

@visibleForTesting
TextEditingValue insertChatEmoji(TextEditingValue current, String emoji) {
  final textLength = current.text.length;
  final selection = current.selection;
  final selectionStart = selection.isValid
      ? selection.start.clamp(0, textLength).toInt()
      : textLength;
  final selectionEnd = selection.isValid
      ? selection.end.clamp(selectionStart, textLength).toInt()
      : textLength;
  final nextText = current.text.replaceRange(
    selectionStart,
    selectionEnd,
    emoji,
  );
  final nextCaret = selectionStart + emoji.length;
  return TextEditingValue(
    text: nextText,
    selection: TextSelection.collapsed(offset: nextCaret),
  );
}

abstract interface class ChatVoiceRecorder {
  Future<bool> hasPermission();

  Future<void> start(String path);

  Future<String?> stop();

  Future<void> cancel();

  Future<void> dispose();
}

typedef ChatVoicePathFactory = Future<String> Function();

class DeviceChatVoiceRecorder implements ChatVoiceRecorder {
  DeviceChatVoiceRecorder() : _recorder = AudioRecorder();

  final AudioRecorder _recorder;

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  @override
  Future<void> start(String path) => _recorder.start(
    const RecordConfig(
      encoder: AudioEncoder.aacLc,
      bitRate: 96000,
      sampleRate: 44100,
      numChannels: 1,
      autoGain: true,
      echoCancel: true,
      noiseSuppress: true,
    ),
    path: path,
  );

  @override
  Future<String?> stop() => _recorder.stop();

  @override
  Future<void> cancel() => _recorder.cancel();

  @override
  Future<void> dispose() => _recorder.dispose();
}

class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({
    required this.uid,
    this.voiceRecorder,
    this.voicePathFactory,
    super.key,
  });

  final String uid;
  final ChatVoiceRecorder? voiceRecorder;
  final ChatVoicePathFactory? voicePathFactory;

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _picker = ImagePicker();
  late final ChatVoiceRecorder _voiceRecorder;
  List<_ChatMessageEntry> _messages = const [];
  Timer? _pollTimer;
  Timer? _voiceTimer;
  bool _loading = true;
  bool _emojiPanelVisible = false;
  bool _voiceMode = false;
  bool _voicePreparing = false;
  bool _voiceRecording = false;
  bool _voiceCancelPending = false;
  bool _voiceFinishing = false;
  bool _voicePointerHeld = false;
  double? _voiceStartGlobalY;
  Stopwatch? _voiceStopwatch;
  Duration _voiceDuration = Duration.zero;
  Object? _error;
  int _localMessageSequence = 0;
  bool _stickToLatestMessage = true;
  bool _latestMessageScrollScheduled = false;
  bool _messageLoadInFlight = false;
  final Set<String> _hiddenMessageIds = <String>{};
  Set<String> _savedMessageIds = <String>{};
  Map<String, SavedChatMessage> _savedMessages = <String, SavedChatMessage>{};
  Set<String> _selectedMessageIds = <String>{};
  ChatMessageQuote? _quoteDraft;
  bool _friendActionWorking = false;
  bool _initialMessageViewportReady = false;
  bool _revealMessagesAfterNextScroll = false;

  @override
  void initState() {
    super.initState();
    _voiceRecorder = widget.voiceRecorder ?? DeviceChatVoiceRecorder();
    _restoreSavedMessageIds();
    _loadMessages();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _loadMessages(silent: true),
    );
  }

  bool get _isSelectingMessages => _selectedMessageIds.isNotEmpty;

  void _restoreSavedMessageIds() {
    final uid = ref.read(currentUserProvider)?.uid;
    if (uid == null || uid.isEmpty) return;
    try {
      final saved = readSavedChatMessageIds(
        ref.read(sharedPreferencesProvider),
        uid,
      );
      final savedMessages = readSavedChatMessages(
        ref.read(sharedPreferencesProvider),
        uid,
      );
      _savedMessages = {
        for (final message in savedMessages) message.id: message,
      };
      _savedMessageIds = {...saved, ..._savedMessages.keys};
    } on Object {
      // Lightweight previews and widget tests may not supply preferences.
    }
  }

  SavedChatMessage _savedSnapshotFor(_ChatMessageEntry entry) {
    final currentUser = ref.read(currentUserProvider);
    final mine = entry.message.senderUid == currentUser?.uid;
    final authorName = mine
        ? currentUser?.nickname ?? '我'
        : ref.read(socialUserProvider(widget.uid)).value?.displayName ?? '好友';
    return SavedChatMessage.fromMessage(
      entry.message,
      conversationUid: widget.uid,
      authorName: authorName,
    );
  }

  Future<void> _persistSavedMessages(
    String uid,
    Set<String> messageIds,
    Map<String, SavedChatMessage> savedMessages,
  ) async {
    final preferences = ref.read(sharedPreferencesProvider);
    await Future.wait([
      writeSavedChatMessageIds(preferences, uid, messageIds),
      writeSavedChatMessages(
        preferences,
        uid,
        savedMessages.values.where(
          (message) => messageIds.contains(message.id),
        ),
      ),
    ]);
  }

  void _recoverSavedMessageSnapshots(Iterable<_ChatMessageEntry> entries) {
    final uid = ref.read(currentUserProvider)?.uid;
    if (uid == null || uid.isEmpty || _savedMessageIds.isEmpty) return;
    final recovered = Map<String, SavedChatMessage>.from(_savedMessages);
    for (final entry in entries) {
      final id = entry.message.id;
      if (_savedMessageIds.contains(id) && !recovered.containsKey(id)) {
        recovered[id] = _savedSnapshotFor(entry);
      }
    }
    if (recovered.length == _savedMessages.length) return;
    setState(() => _savedMessages = recovered);
    unawaited(_persistSavedMessages(uid, _savedMessageIds, recovered));
  }

  void _dismissComposerFocus() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _voiceTimer?.cancel();
    if (_voicePreparing || _voiceRecording) {
      unawaited(_voiceRecorder.cancel());
    }
    unawaited(_voiceRecorder.dispose());
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final peer = ref.watch(socialUserProvider(widget.uid));
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final wide = viewportWidth >= MestingAdaptiveBreakpoints.medium;
    final top = MediaQuery.paddingOf(context).top;
    final bottom = MediaQuery.viewPaddingOf(context).bottom;
    final chatContent = Column(
      children: [
        SizedBox(height: wide ? 14 : top + 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: _isSelectingMessages
              ? _MessageSelectionHeader(
                  selectedCount: _selectedMessageIds.length,
                  onCancel: _exitMessageSelection,
                )
              : SocialPageHeader(
                  title: peer.value?.displayName ?? '聊天',
                  subtitle: peer.value?.isFriend == true ? '互相关注好友' : '好友状态已变化',
                  trailing: peer.value?.isFriend == true
                      ? SocialHeaderButton(
                          label: '更多操作',
                          icon: Icons.more_horiz_rounded,
                          onTap: _friendActionWorking
                              ? () {}
                              : () => _showFriendActions(peer.value!),
                        )
                      : null,
                ),
        ),
        const SizedBox(height: 10),
        Divider(height: 1, color: Theme.of(context).dividerColor),
        Expanded(child: _buildMessages(context, peer.value)),
        if (_isSelectingMessages)
          _MessageSelectionToolbar(
            selectedCount: _selectedMessageIds.length,
            onSave: _saveSelectedMessages,
            onDelete: _deleteSelectedMessages,
            bottomPadding: wide ? 4 : bottom,
          )
        else
          _Composer(
            controller: _messageController,
            enabled: peer.value?.isFriend == true,
            onSend: _sendText,
            quote: _quoteDraft,
            onClearQuote: _clearQuoteDraft,
            emojiPanelVisible: _emojiPanelVisible,
            onEmojiToggle: _toggleEmojiPanel,
            onEmojiSelected: _insertEmoji,
            onTyping: _hideEmojiPanel,
            onImage: () => _pickMedia(SocialMessageKind.image),
            onVideo: () => _pickMedia(SocialMessageKind.video),
            voiceMode: _voiceMode,
            voicePreparing: _voicePreparing,
            voiceRecording: _voiceRecording,
            voiceCancelPending: _voiceCancelPending,
            voiceDuration: _voiceDuration,
            onVoiceToggle: _toggleVoiceMode,
            onVoiceStart: _startVoiceRecording,
            onVoiceMove: _updateVoiceCancelState,
            onVoiceEnd: _endVoiceRecording,
            onVoiceCancel: _cancelVoiceRecordingGesture,
            bottomPadding: wide ? 4 : bottom,
          ),
      ],
    );
    if (!wide) return chatContent;

    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(24, top + 16, 24, bottom + 16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(30),
            child: DecoratedBox(
              key: const ValueKey('chat-tablet-surface'),
              decoration: BoxDecoration(
                color: scheme.surface.withValues(alpha: .84),
                border: Border.all(
                  color: scheme.outline.withValues(alpha: .2),
                  width: .8,
                ),
              ),
              child: chatContent,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMessages(BuildContext context, SocialUser? peer) {
    if (_loading) {
      return const Center(
        child: MestingLoadingIndicator(
          key: ValueKey('chat-curve-loader'),
          size: 92,
          semanticLabel: '正在进入好友会话',
        ),
      );
    }
    if (_error != null && _messages.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [SocialErrorCard(error: _error!, onRetry: _loadMessages)],
      );
    }
    if (_messages.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(28),
          child: Text('打个招呼吧，也可以分享文字、图片、视频和语音。'),
        ),
      );
    }
    final currentUser = ref.watch(currentUserProvider);
    final currentUid = currentUser?.uid;
    final currentSocialUser = SocialUser(
      uid: currentUid ?? '',
      nickname: currentUser?.nickname ?? '我',
      bio: currentUser?.bio ?? '',
      avatarUrl: currentUser?.avatarUrl,
    );
    final peerSocialUser = peer ?? SocialUser(uid: widget.uid, nickname: '好友');
    return AnimatedOpacity(
      key: const ValueKey('chat-message-list-reveal'),
      opacity: _initialMessageViewportReady ? 1 : 0,
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      child: NotificationListener<ScrollMetricsNotification>(
        onNotification: _handleMessageMetricsChanged,
        child: NotificationListener<ScrollNotification>(
          onNotification: _handleMessageScroll,
          child: ListView.builder(
            key: const ValueKey('chat-message-list'),
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(14, 18, 14, 18),
            itemCount: _messages.length,
            itemBuilder: (context, index) {
              final entry = _messages[index];
              final message = entry.message;
              final mine = message.senderUid == currentUid;
              final previousMessage = index > 0
                  ? _messages[index - 1].message
                  : null;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (shouldShowChatMessageTimestamp(previousMessage, message))
                    _MessageTimestamp(
                      key: ValueKey('chat-message-time-${message.id}'),
                      sentAt: message.sentAt,
                    ),
                  _MessageBubble(
                    key: ValueKey(message.id),
                    message: message,
                    mine: mine,
                    avatarUser: mine ? currentSocialUser : peerSocialUser,
                    onAvatarTap: () => mine
                        ? context.push(
                            DistributionChannel.isBeta
                                ? '/profile/view'
                                : '/profile',
                          )
                        : context.push(
                            '/social/users/${Uri.encodeComponent(widget.uid)}',
                          ),
                    delivery: entry.delivery,
                    onRetry: entry.delivery == _MessageDelivery.failed
                        ? () => _retryMessage(entry)
                        : null,
                    onLongPressStart:
                        entry.delivery == _MessageDelivery.sent &&
                            !message.recalled
                        ? (anchor) => _showMessageActions(
                            entry,
                            mine: mine,
                            anchor: anchor,
                          )
                        : null,
                    selectionMode: _isSelectingMessages,
                    selected: _selectedMessageIds.contains(message.id),
                    onTap: _isSelectingMessages
                        ? () => _toggleMessageSelection(entry)
                        : null,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _loadMessages({bool silent = false}) async {
    if (_messageLoadInFlight) return;
    _messageLoadInFlight = true;
    final initialLoad = _loading && _messages.isEmpty;
    if (!silent && mounted) setState(() => _loading = true);
    try {
      if (silent) ref.invalidate(socialMessagesProvider(widget.uid));
      final remoteMessages = await ref.read(
        socialMessagesProvider(widget.uid).future,
      );
      final messages = remoteMessages
          .where((message) => !_hiddenMessageIds.contains(message.id))
          .toList(growable: false);
      final currentUid = ref.read(currentUserProvider)?.uid;
      final currentRemoteIds = _messages
          .where((entry) => entry.delivery == _MessageDelivery.sent)
          .map((entry) => entry.message.id)
          .toSet();
      final receivedNewMessage = messages.any(
        (message) =>
            message.senderUid != currentUid &&
            !currentRemoteIds.contains(message.id),
      );
      if (receivedNewMessage) {
        await ref.read(socialRepositoryProvider).markRead(widget.uid);
        if (currentUid != null) {
          unawaited(_refreshSocialAttention(currentUid));
        }
      }
      if (!mounted) return;
      final changed =
          messages.length != currentRemoteIds.length ||
          messages.any((message) => !currentRemoteIds.contains(message.id));
      if (receivedNewMessage) {
        ref
          ..invalidate(socialSummaryProvider)
          ..invalidate(socialConversationsProvider);
      }
      final remoteEntries = messages.map(_ChatMessageEntry.sent).toList();
      final remoteIds = messages.map((message) => message.id).toSet();
      // CloudBase reads can briefly lag the successful send response. Keep
      // already-sent local entries that are missing from this snapshot so a
      // poll cannot make the user's bubble (and its avatar) blink away.
      final preservedSent = _messages.where(
        (entry) =>
            entry.delivery == _MessageDelivery.sent &&
            !_hiddenMessageIds.contains(entry.message.id) &&
            !remoteIds.contains(entry.message.id),
      );
      final localPending = _messages.where(
        (entry) => entry.delivery != _MessageDelivery.sent,
      );
      final merged = [...remoteEntries, ...preservedSent, ...localPending]
        ..sort(
          (left, right) => left.message.sentAt.compareTo(right.message.sentAt),
        );
      final needsInitialPosition = initialLoad && messages.isNotEmpty;
      setState(() {
        _messages = merged;
        _loading = false;
        _error = null;
        _initialMessageViewportReady = !needsInitialPosition;
      });
      _recoverSavedMessageSnapshots(merged);
      if (changed || needsInitialPosition) {
        _scrollToEnd(
          immediate: initialLoad,
          revealMessagesAfterScroll: needsInitialPosition,
        );
      }
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error;
      });
    } finally {
      _messageLoadInFlight = false;
    }
  }

  Future<void> _refreshSocialAttention(String uid) async {
    try {
      await ref
          .read(socialAttentionControllerProvider.notifier)
          .refreshFor(uid, postSystemNotifications: false);
    } on Object {
      // Isolated previews and widget tests may not provide app preferences;
      // a reminder refresh must never surface as a chat error.
    }
  }

  Future<void> _sendText() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    final quote = _quoteDraft;
    _messageController.clear();
    setState(() {
      _emojiPanelVisible = false;
      _quoteDraft = null;
    });
    _queueMessage(
      kind: SocialMessageKind.text,
      text: quote == null
          ? text
          : encodeChatMessageQuote(excerpt: quote.excerpt, content: text),
    );
  }

  void _clearQuoteDraft() {
    if (_quoteDraft == null) return;
    setState(() => _quoteDraft = null);
  }

  void _toggleEmojiPanel() {
    FocusScope.of(context).unfocus();
    setState(() {
      _voiceMode = false;
      _emojiPanelVisible = !_emojiPanelVisible;
    });
  }

  void _hideEmojiPanel() {
    if (!_emojiPanelVisible || !mounted) return;
    setState(() => _emojiPanelVisible = false);
  }

  void _insertEmoji(String emoji) {
    setState(() {
      _messageController.value = insertChatEmoji(
        _messageController.value,
        emoji,
      );
    });
  }

  Future<void> _pickMedia(SocialMessageKind kind) async {
    _hideEmojiPanel();
    if (_voiceMode && mounted) setState(() => _voiceMode = false);
    final picked = kind == SocialMessageKind.image
        ? await _picker.pickImage(
            source: ImageSource.gallery,
            imageQuality: 88,
            maxWidth: 2048,
            maxHeight: 2048,
          )
        : await _picker.pickVideo(
            source: ImageSource.gallery,
            maxDuration: const Duration(minutes: 3),
          );
    if (picked == null) return;
    String? thumbnailPath;
    if (kind == SocialMessageKind.video) {
      thumbnailPath = await generateChatVideoThumbnail(picked.path);
    }
    _queueMessage(
      kind: kind,
      mediaPath: picked.path,
      thumbnailPath: thumbnailPath,
    );
  }

  void _toggleVoiceMode() {
    if (_voiceRecording || _voicePreparing || _voiceFinishing) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _emojiPanelVisible = false;
      _voiceMode = !_voiceMode;
    });
  }

  Future<void> _startVoiceRecording(LongPressStartDetails details) async {
    if (_voicePreparing || _voiceRecording || _voiceFinishing) return;
    _voicePointerHeld = true;
    _voiceStartGlobalY = details.globalPosition.dy;
    setState(() {
      _voicePreparing = true;
      _voiceCancelPending = false;
      _voiceDuration = Duration.zero;
    });
    try {
      if (!await _voiceRecorder.hasPermission()) {
        throw const SocialRequestException('需要麦克风权限才能发送语音消息');
      }
      if (!_voicePointerHeld || !mounted) {
        if (mounted) setState(() => _voicePreparing = false);
        return;
      }
      final path =
          await (widget.voicePathFactory?.call() ??
              createChatVoiceRecordingPath());
      try {
        await ref.read(audioHandlerProvider).pause();
      } on Object {
        // Widget tests and isolated previews may not provide the audio handler.
      }
      await _voiceRecorder.start(path);
      if (!_voicePointerHeld || !mounted) {
        await _voiceRecorder.cancel();
        if (mounted) setState(() => _voicePreparing = false);
        return;
      }
      _voiceStopwatch = Stopwatch()..start();
      _voiceTimer?.cancel();
      _voiceTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        if (!mounted || !_voiceRecording) return;
        final stopwatchElapsed = _voiceStopwatch?.elapsed ?? Duration.zero;
        final timerElapsed = _voiceDuration + const Duration(milliseconds: 100);
        final elapsed = stopwatchElapsed > timerElapsed
            ? stopwatchElapsed
            : timerElapsed;
        if (elapsed >= const Duration(seconds: 60)) {
          unawaited(_finishVoiceRecording(cancel: false));
          return;
        }
        setState(() => _voiceDuration = elapsed);
      });
      if (!mounted) return;
      setState(() {
        _voicePreparing = false;
        _voiceRecording = true;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _voicePreparing = false;
        _voiceRecording = false;
        _voiceCancelPending = false;
      });
      _showVoiceNotice(
        title: '无法开始录音',
        message: userFacingErrorMessage(error, fallback: '录音启动失败，请稍后重试'),
      );
    }
  }

  void _updateVoiceCancelState(LongPressMoveUpdateDetails details) {
    if (!_voiceRecording) return;
    final startY = _voiceStartGlobalY;
    if (startY == null) return;
    final cancel = details.globalPosition.dy < startY - 72;
    if (cancel == _voiceCancelPending) return;
    setState(() => _voiceCancelPending = cancel);
  }

  void _endVoiceRecording(LongPressEndDetails details) {
    _voicePointerHeld = false;
    if (_voiceRecording) {
      unawaited(_finishVoiceRecording(cancel: _voiceCancelPending));
    }
  }

  void _cancelVoiceRecordingGesture() {
    _voicePointerHeld = false;
    if (_voiceRecording || _voicePreparing) {
      unawaited(_finishVoiceRecording(cancel: true));
    }
  }

  Future<void> _finishVoiceRecording({required bool cancel}) async {
    if (_voiceFinishing || (!_voiceRecording && !_voicePreparing)) return;
    _voiceFinishing = true;
    _voiceTimer?.cancel();
    _voiceTimer = null;
    _voiceStopwatch?.stop();
    final stopwatchDuration = _voiceStopwatch?.elapsed ?? Duration.zero;
    final duration = stopwatchDuration > _voiceDuration
        ? stopwatchDuration
        : _voiceDuration;
    String? path;
    try {
      if (cancel) {
        await _voiceRecorder.cancel();
      } else {
        path = await _voiceRecorder.stop();
      }
    } on Object catch (error) {
      if (mounted) {
        _showVoiceNotice(
          title: '录音未发送',
          message: userFacingErrorMessage(error, fallback: '录音保存失败，请重新录制'),
        );
      }
    } finally {
      _voiceStopwatch = null;
      _voicePointerHeld = false;
      _voiceStartGlobalY = null;
      _voiceFinishing = false;
      if (mounted) {
        setState(() {
          _voicePreparing = false;
          _voiceRecording = false;
          _voiceCancelPending = false;
          _voiceDuration = Duration.zero;
        });
      }
    }
    final recordedPath = path;
    if (!mounted || cancel || recordedPath == null || recordedPath.isEmpty) {
      return;
    }
    if (duration < const Duration(milliseconds: 700)) {
      unawaited(_deleteFileQuietly(recordedPath));
      _showVoiceNotice(title: '录音时间太短', message: '请按住说话至少 1 秒');
      return;
    }
    _queueMessage(
      kind: SocialMessageKind.voice,
      text: duration.inMilliseconds.toString(),
      mediaPath: recordedPath,
    );
  }

  void _showVoiceNotice({required String title, required String message}) {
    if (!mounted) return;
    showMusicNotice(
      context,
      icon: Icons.mic_none_rounded,
      title: title,
      message: message,
    );
  }

  void _queueMessage({
    required SocialMessageKind kind,
    String text = '',
    String? mediaPath,
    String? thumbnailPath,
  }) {
    final senderUid = ref.read(currentUserProvider)?.uid;
    if (senderUid == null) {
      _showError(const SocialRequestException('登录状态已失效，请重新登录'));
      return;
    }
    final localId =
        'local-${DateTime.now().microsecondsSinceEpoch}-${_localMessageSequence++}';
    final entry = _ChatMessageEntry(
      message: SocialMessage(
        id: localId,
        senderUid: senderUid,
        receiverUid: widget.uid,
        kind: kind,
        text: text,
        mediaUrl: mediaPath,
        thumbnailUrl: thumbnailPath,
        sentAt: DateTime.now(),
      ),
      delivery: _MessageDelivery.sending,
      localMediaPath: mediaPath,
      localThumbnailPath: thumbnailPath,
    );
    setState(() {
      _initialMessageViewportReady = true;
      _messages = [..._messages, entry];
    });
    _scrollToEnd();
    unawaited(_deliverMessage(entry));
  }

  Future<void> _retryMessage(_ChatMessageEntry entry) async {
    final index = _messages.indexWhere(
      (candidate) => candidate.message.id == entry.message.id,
    );
    if (index < 0) return;
    final pending = entry.copyWith(delivery: _MessageDelivery.sending);
    setState(() {
      final next = [..._messages];
      next[index] = pending;
      _messages = next;
    });
    await _deliverMessage(pending);
  }

  Future<void> _deliverMessage(_ChatMessageEntry entry) async {
    var deliveryEntry = entry;
    try {
      var mediaUrl = deliveryEntry.uploadedMediaUrl;
      var thumbnailUrl = deliveryEntry.uploadedThumbnailUrl;
      final localThumbnailPath = deliveryEntry.localThumbnailPath;
      final kind = deliveryEntry.message.kind;
      if ((kind == SocialMessageKind.image ||
              kind == SocialMessageKind.video ||
              kind == SocialMessageKind.voice) &&
          mediaUrl == null) {
        final path = deliveryEntry.localMediaPath;
        if (path == null || path.isEmpty) {
          throw const SocialRequestException('选择的媒体文件已经不存在，请重新选择');
        }
        final upload = await ref
            .read(socialRepositoryProvider)
            .uploadMedia(path: path, kind: kind);
        // CloudBase download links are temporary, so its stable object ID is
        // kept in the message and resolved to a fresh playable URL on demand.
        // The independent Java/MySQL and local-preview channels do not expose
        // that CloudBase resolver, so they retain their direct upload URL.
        mediaUrl =
            ref.read(authBackendKindProvider) == AuthBackendKind.cloudBase
            ? upload.cloudObjectId
            : upload.downloadUrl;
        deliveryEntry = deliveryEntry.copyWith(uploadedMediaUrl: mediaUrl);
        _replaceLocalEntry(deliveryEntry);
      }
      if (kind == SocialMessageKind.video &&
          thumbnailUrl == null &&
          localThumbnailPath != null &&
          localThumbnailPath.isNotEmpty) {
        final thumbnailUpload = await ref
            .read(socialRepositoryProvider)
            .uploadMedia(
              path: localThumbnailPath,
              kind: SocialMessageKind.image,
            );
        thumbnailUrl =
            ref.read(authBackendKindProvider) == AuthBackendKind.cloudBase
            ? thumbnailUpload.cloudObjectId
            : thumbnailUpload.downloadUrl;
        deliveryEntry = deliveryEntry.copyWith(
          uploadedThumbnailUrl: thumbnailUrl,
        );
        _replaceLocalEntry(deliveryEntry);
      }
      final message = await ref
          .read(socialRepositoryProvider)
          .sendMessage(
            widget.uid,
            kind: kind,
            text: deliveryEntry.message.text,
            mediaUrl: mediaUrl,
            thumbnailUrl: thumbnailUrl,
          );
      final localMediaPath = deliveryEntry.localMediaPath;
      if (kind == SocialMessageKind.voice &&
          localMediaPath != null &&
          localMediaPath.isNotEmpty) {
        unawaited(_deleteFileQuietly(localMediaPath));
      }
      if (!mounted) return;
      _replaceLocalEntry(
        _ChatMessageEntry.sent(message, localId: deliveryEntry.localId),
      );
      ref
        ..invalidate(socialConversationsProvider)
        ..invalidate(socialMessagesProvider(widget.uid));
      _scrollToEnd();
    } on Object catch (error) {
      if (!mounted) return;
      _replaceLocalEntry(
        deliveryEntry.copyWith(delivery: _MessageDelivery.failed, error: error),
      );
    }
  }

  void _replaceLocalEntry(_ChatMessageEntry replacement) {
    if (!mounted) return;
    setState(() {
      final localId = replacement.localId;
      final next = _messages
          .where(
            (entry) =>
                entry.message.id != replacement.message.id &&
                entry.message.id != localId,
          )
          .toList();
      final originalIndex = _messages.indexWhere(
        (entry) => entry.message.id == localId,
      );
      next.insert(
        originalIndex < 0
            ? next.length
            : originalIndex.clamp(0, next.length).toInt(),
        replacement,
      );
      _messages = next;
    });
  }

  void _showError(Object error) {
    if (!mounted) return;
    showMusicNotice(
      context,
      icon: Icons.error_outline_rounded,
      title: '发送失败',
      message: userFacingErrorMessage(error, fallback: '消息发送失败，请稍后重试'),
    );
  }

  Future<void> _showFriendActions(SocialUser user) async {
    final action = await showFriendProfileActions(context, user: user);
    if (action == null || !mounted) return;
    switch (action) {
      case FriendProfileAction.remark:
        await _editPeerRemark(user);
      case FriendProfileAction.share:
        await _sharePeer(user);
      case FriendProfileAction.removeFollower:
        await _removePeerFollower(user);
      case FriendProfileAction.block:
        await _blockPeer(user);
    }
  }

  Future<void> _editPeerRemark(SocialUser user) async {
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
    await _runFriendAction(
      () => ref.read(socialRepositoryProvider).setRemark(user.uid, value),
      successTitle: value.trim().isEmpty ? '已清除备注' : '备注已保存',
    );
  }

  Future<void> _sharePeer(SocialUser user) async {
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

  Future<void> _removePeerFollower(SocialUser user) async {
    final confirmed = await _confirmFriendAction(
      title: '移除 ${user.displayName}？',
      message: '对方会从你的粉丝列表中消失，系统不会发送通知。',
      action: '移除粉丝',
    );
    if (confirmed != true) return;
    await _runFriendAction(
      () => ref.read(socialRepositoryProvider).removeFollower(user.uid),
      successTitle: '已移除粉丝',
    );
  }

  Future<void> _blockPeer(SocialUser user) async {
    final confirmed = await _confirmFriendAction(
      title: '将 ${user.displayName} 加入黑名单？',
      message: '双方关注关系会解除，之后不能互相发消息。',
      action: '加入黑名单',
    );
    if (confirmed != true) return;
    await _runFriendAction(
      () => ref
          .read(socialRepositoryProvider)
          .setBlocked(user.uid, blocked: true),
      successTitle: '已加入黑名单',
    );
  }

  Future<bool?> _confirmFriendAction({
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

  Future<void> _runFriendAction(
    Future<Object?> Function() action, {
    required String successTitle,
  }) async {
    setState(() => _friendActionWorking = true);
    try {
      await action();
      ref
        ..invalidate(socialUserProvider(widget.uid))
        ..invalidate(socialSummaryProvider)
        ..invalidate(socialConversationsProvider);
      if (mounted) {
        showMusicNotice(
          context,
          icon: Icons.check_rounded,
          title: successTitle,
          message: '',
        );
      }
    } on Object catch (error) {
      if (mounted) {
        showMusicNotice(
          context,
          icon: Icons.error_outline_rounded,
          title: '操作失败',
          message: userFacingErrorMessage(error, fallback: '请稍后重试'),
        );
      }
    } finally {
      if (mounted) setState(() => _friendActionWorking = false);
    }
  }

  Future<void> _showMessageActions(
    _ChatMessageEntry entry, {
    required bool mine,
    required Offset anchor,
  }) async {
    _dismissComposerFocus();
    final message = entry.message;
    final supportsCopy =
        message.kind == SocialMessageKind.text ||
        message.kind == SocialMessageKind.emoji;
    final now = DateTime.now();
    final canRecall =
        mine &&
        !message.sentAt.isAfter(now) &&
        now.difference(message.sentAt) <= const Duration(minutes: 2);
    final actions = <_ChatMessageAction>[
      if (supportsCopy) _ChatMessageAction.copy,
      _ChatMessageAction.favorite,
      _ChatMessageAction.quote,
      if (message.kind == SocialMessageKind.voice)
        _ChatMessageAction.transcribe,
      if (canRecall) _ChatMessageAction.recall,
      _ChatMessageAction.delete,
      _ChatMessageAction.multiSelect,
    ];
    final action = await showGeneralDialog<_ChatMessageAction>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: true,
      barrierLabel: '关闭消息操作',
      barrierColor: Colors.black.withValues(alpha: .46),
      transitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (context, _, _) => _ChatMessageActionPopover(
        anchor: anchor,
        actions: actions,
        favorite: _savedMessageIds.contains(message.id),
      ),
      transitionBuilder: (context, animation, _, child) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: SlideTransition(
          position:
              Tween<Offset>(
                begin: const Offset(0, .025),
                end: Offset.zero,
              ).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
              ),
          child: child,
        ),
      ),
    );
    if (action == null || !mounted) return;
    switch (action) {
      case _ChatMessageAction.copy:
        await Clipboard.setData(ClipboardData(text: message.text));
        if (mounted) {
          showMusicNotice(
            context,
            icon: Icons.content_copy_rounded,
            title: '已复制',
            message: '',
          );
        }
      case _ChatMessageAction.favorite:
        await _toggleSavedMessage(entry);
      case _ChatMessageAction.quote:
        _beginQuote(entry);
      case _ChatMessageAction.transcribe:
        _showTranscriptionUnavailable();
      case _ChatMessageAction.recall:
        await _recallMessage(entry);
      case _ChatMessageAction.delete:
        await _deleteMessage(entry);
      case _ChatMessageAction.multiSelect:
        _startMessageSelection(entry);
    }
  }

  Future<void> _toggleSavedMessage(_ChatMessageEntry entry) async {
    final uid = ref.read(currentUserProvider)?.uid;
    if (uid == null || uid.isEmpty) return;
    final messageId = entry.message.id;
    final next = {..._savedMessageIds};
    final nextSavedMessages = Map<String, SavedChatMessage>.from(
      _savedMessages,
    );
    final saved = next.add(messageId);
    if (saved) {
      nextSavedMessages[messageId] = _savedSnapshotFor(entry);
    } else {
      next.remove(messageId);
      nextSavedMessages.remove(messageId);
    }
    setState(() {
      _savedMessageIds = next;
      _savedMessages = nextSavedMessages;
    });
    try {
      await _persistSavedMessages(uid, next, nextSavedMessages);
      if (mounted) {
        showMusicNotice(
          context,
          icon: saved
              ? Icons.bookmark_added_rounded
              : Icons.bookmark_remove_rounded,
          title: saved ? '已收藏消息' : '已取消收藏',
          message: '',
        );
      }
    } on Object {
      // Keep the current session usable even if local preference storage is
      // unavailable (for example in an isolated preview).
    }
  }

  void _beginQuote(_ChatMessageEntry entry) {
    final currentUser = ref.read(currentUserProvider);
    final mine = entry.message.senderUid == currentUser?.uid;
    final author = mine
        ? currentUser?.nickname ?? '我'
        : ref.read(socialUserProvider(widget.uid)).value?.displayName ?? '对方';
    setState(() {
      _emojiPanelVisible = false;
      _voiceMode = false;
      _quoteDraft = ChatMessageQuote(
        excerpt: '$author：${chatMessageQuoteExcerpt(entry.message)}',
        content: '',
      );
    });
  }

  void _startMessageSelection(_ChatMessageEntry entry) {
    setState(() {
      _emojiPanelVisible = false;
      _voiceMode = false;
      _quoteDraft = null;
      _selectedMessageIds = {entry.message.id};
    });
  }

  void _toggleMessageSelection(_ChatMessageEntry entry) {
    if (entry.delivery != _MessageDelivery.sent || entry.message.recalled) {
      return;
    }
    final next = {..._selectedMessageIds};
    if (!next.add(entry.message.id)) next.remove(entry.message.id);
    setState(() => _selectedMessageIds = next);
  }

  void _exitMessageSelection() {
    if (!_isSelectingMessages) return;
    setState(() => _selectedMessageIds = <String>{});
  }

  Future<void> _saveSelectedMessages() async {
    final entries = _messages
        .where((entry) => _selectedMessageIds.contains(entry.message.id))
        .toList(growable: false);
    if (entries.isEmpty) return;
    final uid = ref.read(currentUserProvider)?.uid;
    if (uid == null || uid.isEmpty) return;
    final next = {
      ..._savedMessageIds,
      ...entries.map((entry) => entry.message.id),
    };
    final nextSavedMessages = Map<String, SavedChatMessage>.from(
      _savedMessages,
    );
    for (final entry in entries) {
      nextSavedMessages[entry.message.id] = _savedSnapshotFor(entry);
    }
    setState(() {
      _savedMessageIds = next;
      _savedMessages = nextSavedMessages;
      _selectedMessageIds = <String>{};
    });
    try {
      await _persistSavedMessages(uid, next, nextSavedMessages);
      if (mounted) {
        showMusicNotice(
          context,
          icon: Icons.bookmark_added_rounded,
          title: '已收藏 ${entries.length} 条消息',
          message: '',
        );
      }
    } on Object {
      // Local preview environments do not always register preferences.
    }
  }

  Future<void> _deleteSelectedMessages() async {
    final entries = _messages
        .where((entry) => _selectedMessageIds.contains(entry.message.id))
        .toList(growable: false);
    if (entries.isEmpty) return;
    final deletedIds = <String>{};
    Object? firstError;
    for (final entry in entries) {
      try {
        await ref
            .read(socialRepositoryProvider)
            .deleteMessage(widget.uid, entry.message.id);
        deletedIds.add(entry.message.id);
      } on Object catch (error) {
        firstError ??= error;
      }
    }
    if (deletedIds.isNotEmpty && mounted) {
      setState(() {
        _hiddenMessageIds.addAll(deletedIds);
        _messages = _messages
            .where((entry) => !deletedIds.contains(entry.message.id))
            .toList(growable: false);
        _selectedMessageIds.removeAll(deletedIds);
      });
      ref
        ..invalidate(socialConversationsProvider)
        ..invalidate(socialMessagesProvider(widget.uid));
    }
    if (firstError != null) {
      _showError(firstError);
    } else if (mounted) {
      showMusicNotice(
        context,
        icon: Icons.delete_outline_rounded,
        title: '已删除 ${deletedIds.length} 条消息',
        message: '',
      );
    }
  }

  void _showTranscriptionUnavailable() {
    _dismissComposerFocus();
    showMusicNotice(
      context,
      icon: Icons.text_fields_rounded,
      title: '语音转文字尚未配置',
      message: '需要接入真实语音识别服务后才能转写录音，当前不会生成不准确的伪文字。',
    );
  }

  Future<void> _recallMessage(_ChatMessageEntry entry) async {
    try {
      final recalled = await ref
          .read(socialRepositoryProvider)
          .recallMessage(widget.uid, entry.message.id);
      if (!mounted) return;
      _replaceLocalEntry(
        _ChatMessageEntry.sent(recalled, localId: entry.localId),
      );
      ref
        ..invalidate(socialConversationsProvider)
        ..invalidate(socialMessagesProvider(widget.uid));
    } on Object catch (error) {
      _showError(error);
    }
  }

  Future<void> _deleteMessage(_ChatMessageEntry entry) async {
    try {
      await ref
          .read(socialRepositoryProvider)
          .deleteMessage(widget.uid, entry.message.id);
      if (!mounted) return;
      setState(() {
        _hiddenMessageIds.add(entry.message.id);
        _messages = _messages
            .where((candidate) => candidate.message.id != entry.message.id)
            .toList(growable: false);
      });
      ref
        ..invalidate(socialConversationsProvider)
        ..invalidate(socialMessagesProvider(widget.uid));
    } on Object catch (error) {
      _showError(error);
    }
  }

  bool _handleMessageMetricsChanged(ScrollMetricsNotification notification) {
    if (_stickToLatestMessage) _scheduleLatestMessageScroll(immediate: true);
    return false;
  }

  bool _handleMessageScroll(ScrollNotification notification) {
    if (notification case ScrollStartNotification(dragDetails: != null)) {
      _stickToLatestMessage = false;
    } else if (notification is ScrollEndNotification) {
      _stickToLatestMessage = notification.metrics.extentAfter <= 36;
    }
    return false;
  }

  void _scrollToEnd({
    bool immediate = false,
    bool revealMessagesAfterScroll = false,
  }) {
    _stickToLatestMessage = true;
    _revealMessagesAfterNextScroll |= revealMessagesAfterScroll;
    _scheduleLatestMessageScroll(immediate: immediate);
  }

  void _scheduleLatestMessageScroll({required bool immediate}) {
    if (_latestMessageScrollScheduled) return;
    _latestMessageScrollScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _latestMessageScrollScheduled = false;
      if (!mounted || !_scrollController.hasClients) return;
      final position = _scrollController.position;
      final target = position.maxScrollExtent;
      if ((position.pixels - target).abs() >= .5 && immediate) {
        position.jumpTo(target);
      } else if ((position.pixels - target).abs() >= .5) {
        unawaited(
          position.animateTo(
            target,
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
          ),
        );
      }
      if (_revealMessagesAfterNextScroll) {
        _revealMessagesAfterNextScroll = false;
        if (!_initialMessageViewportReady) {
          setState(() => _initialMessageViewportReady = true);
        }
      }
    });
  }
}

@visibleForTesting
Future<String> createChatVoiceRecordingPath() async {
  final root = await getTemporaryDirectory();
  final directory = Directory(
    '${root.path}${Platform.pathSeparator}social_voice_messages',
  );
  await directory.create(recursive: true);
  return '${directory.path}${Platform.pathSeparator}'
      'voice-${DateTime.now().microsecondsSinceEpoch}.m4a';
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.enabled,
    required this.onSend,
    required this.quote,
    required this.onClearQuote,
    required this.emojiPanelVisible,
    required this.onEmojiToggle,
    required this.onEmojiSelected,
    required this.onTyping,
    required this.onImage,
    required this.onVideo,
    required this.voiceMode,
    required this.voicePreparing,
    required this.voiceRecording,
    required this.voiceCancelPending,
    required this.voiceDuration,
    required this.onVoiceToggle,
    required this.onVoiceStart,
    required this.onVoiceMove,
    required this.onVoiceEnd,
    required this.onVoiceCancel,
    required this.bottomPadding,
  });

  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onSend;
  final ChatMessageQuote? quote;
  final VoidCallback onClearQuote;
  final bool emojiPanelVisible;
  final VoidCallback onEmojiToggle;
  final ValueChanged<String> onEmojiSelected;
  final VoidCallback onTyping;
  final VoidCallback onImage;
  final VoidCallback onVideo;
  final bool voiceMode;
  final bool voicePreparing;
  final bool voiceRecording;
  final bool voiceCancelPending;
  final Duration voiceDuration;
  final VoidCallback onVoiceToggle;
  final GestureLongPressStartCallback onVoiceStart;
  final GestureLongPressMoveUpdateCallback onVoiceMove;
  final GestureLongPressEndCallback onVoiceEnd;
  final VoidCallback onVoiceCancel;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SocialGlass(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: Material(
        color: Colors.transparent,
        child: Padding(
          padding: EdgeInsets.fromLTRB(10, 9, 10, bottomPadding + 9),
          child: Column(
            children: [
              if (quote != null) ...[
                _QuoteDraftPreview(
                  excerpt: quote!.excerpt,
                  onClear: onClearQuote,
                ),
                const SizedBox(height: 7),
              ],
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _VoiceToggleButton(
                    voiceMode: voiceMode,
                    enabled: enabled && !voiceRecording && !voicePreparing,
                    onTap: onVoiceToggle,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: voiceMode
                        ? _HoldToRecordButton(
                            enabled: enabled,
                            preparing: voicePreparing,
                            recording: voiceRecording,
                            cancelPending: voiceCancelPending,
                            duration: voiceDuration,
                            onStart: onVoiceStart,
                            onMove: onVoiceMove,
                            onEnd: onVoiceEnd,
                            onCancel: onVoiceCancel,
                          )
                        : Container(
                            key: const ValueKey('chat-message-field-surface'),
                            constraints: const BoxConstraints(minHeight: 48),
                            clipBehavior: Clip.antiAlias,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(24),
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  scheme.surface.withValues(alpha: .9),
                                  scheme.surfaceContainerHighest.withValues(
                                    alpha: .5,
                                  ),
                                ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: scheme.shadow.withValues(alpha: .045),
                                  blurRadius: 14,
                                  offset: const Offset(0, 5),
                                ),
                              ],
                            ),
                            foregroundDecoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: scheme.outline.withValues(alpha: .34),
                                width: 1.1,
                              ),
                            ),
                            child: TextField(
                              contextMenuBuilder: buildBetaEditingMenu,
                              selectionControls: mestingTextSelectionControls,
                              cursorRadius: const Radius.circular(1),
                              controller: controller,
                              enabled: enabled,
                              minLines: 1,
                              maxLines: 4,
                              textInputAction: TextInputAction.send,
                              onTap: onTyping,
                              onSubmitted: (_) => onSend(),
                              decoration: InputDecoration(
                                hintText: enabled ? '写点什么…' : '互相关注后才能聊天',
                                hintStyle: TextStyle(
                                  color: scheme.onSurfaceVariant.withValues(
                                    alpha: .72,
                                  ),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 17,
                                  vertical: 13,
                                ),
                                isDense: true,
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                              ),
                            ),
                          ),
                  ),
                  if (!voiceMode) ...[
                    const SizedBox(width: 8),
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: controller,
                      builder: (context, value, _) => _ChatSendButton(
                        enabled: enabled,
                        active: value.text.trim().isNotEmpty,
                        onTap: onSend,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  _ComposerAction(
                    icon: Icons.emoji_emotions_outlined,
                    label: '表情',
                    selected: emojiPanelVisible,
                    onTap: enabled ? onEmojiToggle : null,
                  ),
                  _ComposerAction(
                    icon: Icons.image_outlined,
                    label: '图片',
                    onTap: enabled ? onImage : null,
                  ),
                  _ComposerAction(
                    icon: Icons.videocam_outlined,
                    label: '视频',
                    onTap: enabled ? onVideo : null,
                  ),
                ],
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: emojiPanelVisible
                    ? _InlineEmojiPanel(onSelected: onEmojiSelected)
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuoteDraftPreview extends StatelessWidget {
  const _QuoteDraftPreview({required this.excerpt, required this.onClear});

  final String excerpt;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: '正在引用：$excerpt',
      child: Container(
        key: const ValueKey('chat-quote-draft'),
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 8, 7, 8),
        decoration: BoxDecoration(
          color: scheme.primary.withValues(alpha: .10),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.format_quote_rounded, color: scheme.primary, size: 19),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                '回复：$excerpt',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            IconButton(
              tooltip: '取消引用',
              onPressed: onClear,
              icon: const Icon(Icons.close_rounded, size: 19),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageSelectionHeader extends StatelessWidget {
  const _MessageSelectionHeader({
    required this.selectedCount,
    required this.onCancel,
  });

  final int selectedCount;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          IconButton(
            tooltip: '取消多选',
            onPressed: onCancel,
            icon: const Icon(Icons.close_rounded),
          ),
          const SizedBox(width: 6),
          Text(
            '已选 $selectedCount 项',
            style: TextStyle(
              color: scheme.onSurface,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageSelectionToolbar extends StatelessWidget {
  const _MessageSelectionToolbar({
    required this.selectedCount,
    required this.onSave,
    required this.onDelete,
    required this.bottomPadding,
  });

  final int selectedCount;
  final VoidCallback onSave;
  final VoidCallback onDelete;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: '已选择 $selectedCount 条消息',
      child: SocialGlass(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 11, 20, bottomPadding + 11),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _MessageSelectionAction(
                icon: Icons.bookmark_add_outlined,
                label: '收藏',
                onTap: onSave,
              ),
              _MessageSelectionAction(
                icon: Icons.delete_outline_rounded,
                label: '删除',
                color: scheme.error,
                onTap: onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageSelectionAction extends StatelessWidget {
  const _MessageSelectionAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final Color? color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? Theme.of(context).colorScheme.onSurface;
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 88,
          height: 54,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 22, color: effectiveColor),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: effectiveColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VoiceToggleButton extends StatelessWidget {
  const _VoiceToggleButton({
    required this.voiceMode,
    required this.enabled,
    required this.onTap,
  });

  final bool voiceMode;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = voiceMode ? '切换到键盘' : '切换到语音';
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: Tooltip(
        message: label,
        child: InkWell(
          key: const ValueKey('chat-voice-toggle'),
          onTap: enabled ? onTap : null,
          customBorder: const CircleBorder(),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: voiceMode
                  ? scheme.primary.withValues(alpha: .16)
                  : scheme.surface.withValues(alpha: .72),
              border: Border.all(
                color: voiceMode
                    ? scheme.primary.withValues(alpha: .52)
                    : scheme.outlineVariant.withValues(alpha: .46),
              ),
              boxShadow: [
                BoxShadow(
                  color: scheme.shadow.withValues(alpha: .055),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              transitionBuilder: (child, animation) => RotationTransition(
                turns: Tween<double>(begin: .88, end: 1).animate(animation),
                child: FadeTransition(opacity: animation, child: child),
              ),
              child: Icon(
                voiceMode ? Icons.keyboard_alt_rounded : Icons.mic_none_rounded,
                key: ValueKey(voiceMode),
                color: enabled
                    ? (voiceMode ? scheme.primary : scheme.onSurface)
                    : scheme.onSurface.withValues(alpha: .34),
                size: 22,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChatSendButton extends StatelessWidget {
  const _ChatSendButton({
    required this.enabled,
    required this.active,
    required this.onTap,
  });

  final bool enabled;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      enabled: enabled,
      label: '发送消息',
      child: Tooltip(
        message: '发送',
        child: InkWell(
          key: const ValueKey('chat-send-button'),
          onTap: enabled ? onTap : null,
          customBorder: const CircleBorder(),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: active
                  ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color.lerp(scheme.primary, Colors.white, .14)!,
                        scheme.primary,
                      ],
                    )
                  : null,
              color: active
                  ? null
                  : scheme.surfaceContainerHighest.withValues(alpha: .68),
              border: Border.all(
                color: active
                    ? Colors.white.withValues(alpha: .46)
                    : scheme.outlineVariant.withValues(alpha: .38),
              ),
              boxShadow: active
                  ? [
                      BoxShadow(
                        color: scheme.primary.withValues(alpha: .24),
                        blurRadius: 18,
                        offset: const Offset(0, 7),
                      ),
                    ]
                  : null,
            ),
            child: Icon(
              Icons.arrow_upward_rounded,
              color: active
                  ? scheme.onPrimary
                  : scheme.onSurfaceVariant.withValues(alpha: .52),
              size: 23,
            ),
          ),
        ),
      ),
    );
  }
}

class _HoldToRecordButton extends StatelessWidget {
  const _HoldToRecordButton({
    required this.enabled,
    required this.preparing,
    required this.recording,
    required this.cancelPending,
    required this.duration,
    required this.onStart,
    required this.onMove,
    required this.onEnd,
    required this.onCancel,
  });

  final bool enabled;
  final bool preparing;
  final bool recording;
  final bool cancelPending;
  final Duration duration;
  final GestureLongPressStartCallback onStart;
  final GestureLongPressMoveUpdateCallback onMove;
  final GestureLongPressEndCallback onEnd;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final activeColor = cancelPending ? scheme.error : scheme.primary;
    final label = !enabled
        ? '互相关注后才能聊天'
        : preparing
        ? '正在准备麦克风…'
        : cancelPending
        ? '松开取消'
        : recording
        ? '松开发送 · ${formatChatVoiceDuration(duration)}'
        : '按住说话';
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      hint: enabled ? '长按开始录音，录音时向上滑动可取消' : null,
      child: GestureDetector(
        key: const ValueKey('chat-hold-to-record'),
        behavior: HitTestBehavior.opaque,
        onLongPressStart: enabled ? onStart : null,
        onLongPressMoveUpdate: enabled ? onMove : null,
        onLongPressEnd: enabled ? onEnd : null,
        onLongPressCancel: enabled ? onCancel : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: recording || preparing
                ? activeColor.withValues(alpha: .14)
                : scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: recording || preparing
                  ? activeColor.withValues(alpha: .68)
                  : scheme.outlineVariant.withValues(alpha: .45),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                cancelPending
                    ? Icons.delete_outline_rounded
                    : recording
                    ? Icons.graphic_eq_rounded
                    : Icons.mic_none_rounded,
                size: 20,
                color: recording || preparing
                    ? activeColor
                    : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: recording || preparing
                      ? activeColor
                      : scheme.onSurface,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ComposerAction extends StatelessWidget {
  const _ComposerAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TextButton.icon(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: selected ? scheme.primary : scheme.onSurfaceVariant,
        backgroundColor: selected
            ? scheme.primary.withValues(alpha: .11)
            : Colors.transparent,
        shape: const StadiumBorder(),
      ),
      icon: Icon(icon, size: 19),
      label: Text(label),
    );
  }
}

enum _MessageDelivery { sending, sent, failed }

enum _ChatMessageAction {
  copy,
  favorite,
  quote,
  transcribe,
  recall,
  delete,
  multiSelect,
}

@visibleForTesting
String formatChatMessageTimestamp(DateTime sentAt, {DateTime? now}) {
  final localSentAt = sentAt.toLocal();
  final localNow = (now ?? DateTime.now()).toLocal();
  final time =
      '${localSentAt.hour.toString().padLeft(2, '0')}:'
      '${localSentAt.minute.toString().padLeft(2, '0')}';

  if (localSentAt.year != localNow.year) {
    return '${localSentAt.year}年${localSentAt.month}月${localSentAt.day}日 $time';
  }
  if (localSentAt.month != localNow.month) {
    return '${localSentAt.month}月${localSentAt.day}日 $time';
  }

  final sentDay = DateTime(
    localSentAt.year,
    localSentAt.month,
    localSentAt.day,
  );
  final today = DateTime(localNow.year, localNow.month, localNow.day);
  final dayDifference = today.difference(sentDay).inDays;
  if (dayDifference <= 0) return time;
  if (dayDifference == 1) return '昨天 $time';
  if (dayDifference == 2) return '前天 $time';

  final weekStart = today.subtract(Duration(days: today.weekday - 1));
  if (!sentDay.isBefore(weekStart)) {
    const weekdayLabels = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    return '${weekdayLabels[localSentAt.weekday - 1]} $time';
  }
  return '${localSentAt.day}日 $time';
}

@visibleForTesting
bool shouldShowChatMessageTimestamp(
  SocialMessage? previous,
  SocialMessage current,
) {
  if (previous == null) return true;
  final previousLocal = previous.sentAt.toLocal();
  final currentLocal = current.sentAt.toLocal();
  final differentDay =
      previousLocal.year != currentLocal.year ||
      previousLocal.month != currentLocal.month ||
      previousLocal.day != currentLocal.day;
  return differentDay ||
      currentLocal.difference(previousLocal).abs() >=
          const Duration(minutes: 5);
}

Future<String?> generateChatVideoThumbnail(String videoPath) async {
  try {
    final bytes = await VideoThumbnail.thumbnailData(
      video: videoPath,
      imageFormat: ImageFormat.JPEG,
      maxWidth: 720,
      timeMs: 0,
      quality: 84,
    );
    if (bytes == null || bytes.isEmpty) return null;
    final root = await getTemporaryDirectory();
    final directory = Directory(
      '${root.path}${Platform.pathSeparator}social_video_thumbnails',
    );
    await directory.create(recursive: true);
    final file = File(
      '${directory.path}${Platform.pathSeparator}'
      'video-${DateTime.now().microsecondsSinceEpoch}.jpg',
    );
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  } on Object {
    return null;
  }
}

Future<void> _deleteFileQuietly(String path) async {
  try {
    final file = File(path);
    if (await file.exists()) await file.delete();
  } on Object {
    // Temporary media cleanup must never turn a sent message into a failure.
  }
}

class _MessageTimestamp extends StatelessWidget {
  const _MessageTimestamp({required this.sentAt, super.key});

  final DateTime sentAt;

  @override
  Widget build(BuildContext context) {
    final label = formatChatMessageTimestamp(sentAt);
    return Semantics(
      label: '消息发送时间 $label',
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(
          label,
          style: TextStyle(
            color: Theme.of(
              context,
            ).colorScheme.onSurfaceVariant.withValues(alpha: .62),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _ChatMessageEntry {
  _ChatMessageEntry({
    required this.message,
    required this.delivery,
    this.localMediaPath,
    this.localThumbnailPath,
    this.uploadedMediaUrl,
    this.uploadedThumbnailUrl,
    this.error,
    String? localId,
  }) : localId = localId ?? message.id;

  factory _ChatMessageEntry.sent(SocialMessage message, {String? localId}) =>
      _ChatMessageEntry(
        message: message,
        delivery: _MessageDelivery.sent,
        localId: localId,
      );

  final SocialMessage message;
  final _MessageDelivery delivery;
  final String localId;
  final String? localMediaPath;
  final String? localThumbnailPath;
  final String? uploadedMediaUrl;
  final String? uploadedThumbnailUrl;
  final Object? error;

  _ChatMessageEntry copyWith({
    _MessageDelivery? delivery,
    String? uploadedMediaUrl,
    String? uploadedThumbnailUrl,
    Object? error,
  }) {
    return _ChatMessageEntry(
      message: message,
      delivery: delivery ?? this.delivery,
      localId: localId,
      localMediaPath: localMediaPath,
      localThumbnailPath: localThumbnailPath,
      uploadedMediaUrl: uploadedMediaUrl ?? this.uploadedMediaUrl,
      uploadedThumbnailUrl: uploadedThumbnailUrl ?? this.uploadedThumbnailUrl,
      error: error,
    );
  }
}

class _MessageBubble extends ConsumerWidget {
  const _MessageBubble({
    required this.message,
    required this.mine,
    required this.avatarUser,
    required this.onAvatarTap,
    required this.delivery,
    this.onRetry,
    this.onLongPressStart,
    this.selectionMode = false,
    this.selected = false,
    this.onTap,
    super.key,
  });

  final SocialMessage message;
  final bool mine;
  final SocialUser avatarUser;
  final VoidCallback onAvatarTap;
  final _MessageDelivery delivery;
  final VoidCallback? onRetry;
  final ValueChanged<Offset>? onLongPressStart;
  final bool selectionMode;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (message.recalled) {
      return Align(
        alignment: Alignment.center,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            mine ? '你撤回了一条消息' : '对方撤回了一条消息',
            key: ValueKey('chat-message-recalled-${message.id}'),
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }
    final accent = Theme.of(context).colorScheme.primary;
    final quote = message.kind == SocialMessageKind.text
        ? decodeChatMessageQuote(message.text)
        : null;
    final togetherInvite =
        message.kind == SocialMessageKind.text && quote == null
        ? decodeListenTogetherInvite(message.text)
        : null;
    final sharedTrack =
        message.kind == SocialMessageKind.text &&
            quote == null &&
            togetherInvite == null
        ? decodeTrackShareMessage(message.text)
        : null;
    final rawMediaUrl = message.mediaUrl?.trim() ?? '';
    final rawThumbnailUrl = message.thumbnailUrl?.trim() ?? '';
    // Existing HTTP/file URLs must reach the video controller in its first
    // build. Only historical CloudBase IDs need an asynchronous resolution.
    final resolvedMediaUrl = rawMediaUrl.startsWith('cloud://')
        ? ref.watch(socialMediaUrlProvider(rawMediaUrl)).value ?? ''
        : rawMediaUrl;
    final resolvedThumbnailUrl = rawThumbnailUrl.startsWith('cloud://')
        ? ref.watch(socialMediaUrlProvider(rawThumbnailUrl)).value
        : rawThumbnailUrl;
    final isMedia =
        message.kind == SocialMessageKind.image ||
        message.kind == SocialMessageKind.video ||
        togetherInvite != null ||
        sharedTrack != null;
    final maxBubbleWidth = (MediaQuery.sizeOf(context).width * .62)
        .clamp(160.0, 520.0)
        .toDouble();
    final bubble = Container(
      key: ValueKey('chat-message-bubble-${message.id}'),
      constraints: BoxConstraints(maxWidth: maxBubbleWidth),
      padding: isMedia
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
      decoration: isMedia
          ? null
          : BoxDecoration(
              color: mine
                  ? accent
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(19),
                topRight: const Radius.circular(19),
                bottomLeft: Radius.circular(mine ? 19 : 5),
                bottomRight: Radius.circular(mine ? 5 : 19),
              ),
            ),
      child: switch (message.kind) {
        SocialMessageKind.text =>
          togetherInvite != null
              ? _ListenTogetherInviteMessage(
                  messageId: message.id,
                  invite: togetherInvite,
                  artworkUrl: message.thumbnailUrl,
                  mine: mine,
                )
              : sharedTrack == null
              ? quote == null
                    ? Text(
                        message.text,
                        style: TextStyle(
                          color: mine ? Colors.white : null,
                          height: 1.4,
                        ),
                      )
                    : Text(
                        quote.content,
                        style: TextStyle(
                          color: mine ? Colors.white : null,
                          height: 1.4,
                        ),
                      )
              : SocialSharedTrackMessage(
                  messageId: message.id,
                  track: sharedTrack,
                  mine: mine,
                  onPlay: sharedTrack.isPlayable
                      ? () => ref
                            .read(audioHandlerProvider)
                            .playSingleTrack(sharedTrack)
                      : null,
                ),
        SocialMessageKind.emoji => Text(
          message.text,
          style: const TextStyle(fontSize: 38, height: 1.2),
        ),
        SocialMessageKind.image => _ChatImagePreview(
          messageId: message.id,
          url: resolvedMediaUrl,
        ),
        SocialMessageKind.video => SocialVideoMessage(
          messageId: message.id,
          url: resolvedMediaUrl,
          thumbnailUrl: resolvedThumbnailUrl,
        ),
        SocialMessageKind.voice => SocialVoiceMessage(
          messageId: message.id,
          url: resolvedMediaUrl,
          duration: chatVoiceDurationFromText(message.text),
          mine: mine,
        ),
      },
    );
    final messageContent = quote == null
        ? bubble
        : _QuotedTextMessage(
            messageId: message.id,
            quote: quote,
            mine: mine,
            maxWidth: maxBubbleWidth,
            bubble: bubble,
          );
    final alignedMessage = Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: mine
            ? Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (delivery != _MessageDelivery.sent) ...[
                    _DeliveryIndicator(
                      messageId: message.id,
                      delivery: delivery,
                      onRetry: onRetry,
                    ),
                    const SizedBox(width: 7),
                  ],
                  messageContent,
                  const SizedBox(width: 4),
                  _MessageAvatar(
                    messageId: message.id,
                    user: avatarUser,
                    mine: true,
                    onTap: onAvatarTap,
                  ),
                ],
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _MessageAvatar(
                    messageId: message.id,
                    user: avatarUser,
                    mine: false,
                    onTap: onAvatarTap,
                  ),
                  const SizedBox(width: 4),
                  messageContent,
                ],
              ),
      ),
    );
    return GestureDetector(
      onTap: onTap,
      onLongPressStart: onLongPressStart == null
          ? null
          : (details) => onLongPressStart!(details.globalPosition),
      behavior: HitTestBehavior.opaque,
      child: selectionMode
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 36,
                  child: Center(
                    child: _MessageSelectionIndicator(
                      messageId: message.id,
                      selected: selected,
                    ),
                  ),
                ),
                Expanded(child: alignedMessage),
              ],
            )
          : alignedMessage,
    );
  }
}

class _MessageSelectionIndicator extends StatelessWidget {
  const _MessageSelectionIndicator({
    required this.messageId,
    required this.selected,
  });

  final String messageId;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const selectedColor = Color(0xFF61C777);
    return Semantics(
      label: selected ? '已选择此消息' : '未选择此消息',
      child: Container(
        key: ValueKey('chat-message-selection-marker-$messageId'),
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? selectedColor : scheme.surfaceContainerHighest,
          border: Border.all(
            color: selected
                ? selectedColor
                : selectedColor.withValues(alpha: .68),
            width: 1.4,
          ),
        ),
        child: selected
            ? const Icon(Icons.check_rounded, size: 19, color: Colors.white)
            : null,
      ),
    );
  }
}

class _QuotedTextMessage extends StatelessWidget {
  const _QuotedTextMessage({
    required this.messageId,
    required this.quote,
    required this.mine,
    required this.maxWidth,
    required this.bubble,
  });

  final String messageId;
  final ChatMessageQuote quote;
  final bool mine;
  final double maxWidth;
  final Widget bubble;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: mine
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        bubble,
        const SizedBox(height: 5),
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Semantics(
            label: '引用原消息：${quote.excerpt}',
            child: Text(
              quote.excerpt,
              key: ValueKey('chat-quote-context-$messageId'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: mine ? TextAlign.right : TextAlign.left,
              style: TextStyle(
                color: scheme.onSurfaceVariant.withValues(alpha: .78),
                fontSize: 12,
                height: 1.3,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ChatMessageActionPopover extends StatelessWidget {
  const _ChatMessageActionPopover({
    required this.anchor,
    required this.actions,
    required this.favorite,
  });

  final Offset anchor;
  final List<_ChatMessageAction> actions;
  final bool favorite;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final popupColor = isDark
        ? Color.alphaBlend(
            scheme.primary.withValues(alpha: .12),
            scheme.surfaceContainerHigh,
          )
        : const Color(0xFF2E3038);
    final columns = actions.length <= 4 ? actions.length : 3;
    final rows = (actions.length / columns).ceil();
    final popupHeight = 12.0 + rows * 66;
    final preferredWidth = (16 + columns * 78).clamp(130, 300).toDouble();
    final viewPadding = MediaQuery.paddingOf(context);

    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).pop(),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = preferredWidth
                .clamp(130.0, constraints.maxWidth - 24)
                .toDouble();
            final minTop = viewPadding.top + 10;
            final maxTop =
                constraints.maxHeight - viewPadding.bottom - popupHeight - 10;
            final above = anchor.dy - popupHeight - 14;
            final top = (above >= minTop ? above : anchor.dy + 14)
                .clamp(minTop, maxTop)
                .toDouble();
            final left = (anchor.dx - width / 2)
                .clamp(12.0, constraints.maxWidth - width - 12)
                .toDouble();
            return Stack(
              children: [
                Positioned(
                  key: const ValueKey('chat-message-action-popover'),
                  left: left,
                  top: top,
                  width: width,
                  height: popupHeight,
                  child: GestureDetector(
                    onTap: () {},
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: popupColor,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Colors.white.withValues(
                            alpha: isDark ? .12 : .09,
                          ),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: .30),
                            offset: const Offset(0, 12),
                            blurRadius: 28,
                          ),
                        ],
                      ),
                      child: GridView.builder(
                        physics: const NeverScrollableScrollPhysics(),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          mainAxisExtent: 66,
                        ),
                        itemCount: actions.length,
                        itemBuilder: (context, index) {
                          final action = actions[index];
                          return _ChatMessageActionButton(
                            action: action,
                            favorite: favorite,
                            onTap: () => Navigator.of(context).pop(action),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ChatMessageActionButton extends StatelessWidget {
  const _ChatMessageActionButton({
    required this.action,
    required this.favorite,
    required this.onTap,
  });

  final _ChatMessageAction action;
  final bool favorite;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final destructive = action == _ChatMessageAction.delete;
    final color = destructive ? const Color(0xFFFF8771) : Colors.white;
    return Semantics(
      button: true,
      label: _chatMessageActionLabel(action, favorite: favorite),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 60),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _chatMessageActionIcon(action, favorite: favorite),
                  color: color,
                  size: 21,
                ),
                const SizedBox(height: 5),
                Text(
                  _chatMessageActionLabel(action, favorite: favorite),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

IconData _chatMessageActionIcon(
  _ChatMessageAction action, {
  required bool favorite,
}) => switch (action) {
  _ChatMessageAction.copy => Icons.content_copy_rounded,
  _ChatMessageAction.favorite =>
    favorite ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
  _ChatMessageAction.quote => Icons.format_quote_rounded,
  _ChatMessageAction.transcribe => Icons.text_fields_rounded,
  _ChatMessageAction.recall => Icons.undo_rounded,
  _ChatMessageAction.delete => Icons.delete_outline_rounded,
  _ChatMessageAction.multiSelect => Icons.checklist_rounded,
};

String _chatMessageActionLabel(
  _ChatMessageAction action, {
  required bool favorite,
}) => switch (action) {
  _ChatMessageAction.copy => '复制',
  _ChatMessageAction.favorite => favorite ? '取消收藏' : '收藏',
  _ChatMessageAction.quote => '引用',
  _ChatMessageAction.transcribe => '转文字',
  _ChatMessageAction.recall => '撤回',
  _ChatMessageAction.delete => '删除',
  _ChatMessageAction.multiSelect => '多选',
};

class _ListenTogetherInviteMessage extends ConsumerStatefulWidget {
  const _ListenTogetherInviteMessage({
    required this.messageId,
    required this.invite,
    required this.artworkUrl,
    required this.mine,
  });

  final String messageId;
  final ListenTogetherInvite invite;
  final String? artworkUrl;
  final bool mine;

  @override
  ConsumerState<_ListenTogetherInviteMessage> createState() =>
      _ListenTogetherInviteMessageState();
}

class _ListenTogetherInviteMessageState
    extends ConsumerState<_ListenTogetherInviteMessage> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final session = ref.watch(listenTogetherControllerProvider).value;
    final matches =
        session?.invitationMatches(widget.invite.invitationId) == true;
    final active = matches && session?.isActive == true;
    final pending = matches && session?.isPending == true;
    final unavailable =
        matches &&
        session != null &&
        session.status != ListenTogetherStatus.pending &&
        session.status != ListenTogetherStatus.active;
    final statusText = active
        ? '已加入 · 正在一起听'
        : unavailable
        ? '这次一起听已经结束'
        : widget.mine
        ? '等待好友加入'
        : '好友邀请你进入同一播放空间';

    return Container(
      key: ValueKey('chat-listen-together-${widget.messageId}'),
      width: 266,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: widget.mine
              ? [
                  scheme.primary.withValues(alpha: .96),
                  Color.lerp(scheme.primary, MestingPalette.heart, .45)!,
                ]
              : [
                  scheme.surfaceContainerHighest,
                  scheme.primaryContainer.withValues(alpha: .72),
                ],
        ),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(21),
          topRight: const Radius.circular(21),
          bottomLeft: Radius.circular(widget.mine ? 21 : 6),
          bottomRight: Radius.circular(widget.mine ? 6 : 21),
        ),
        border: Border.all(
          color: widget.mine
              ? Colors.white.withValues(alpha: .2)
              : scheme.primary.withValues(alpha: .2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 54,
                height: 54,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: widget.artworkUrl?.trim().isNotEmpty == true
                    ? ArtworkImage(
                        uri: widget.artworkUrl!,
                        width: 54,
                        height: 54,
                        fit: BoxFit.cover,
                        retryOnNetworkError: true,
                      )
                    : const Icon(Icons.headphones_rounded, size: 28),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '好友一起听',
                      style: TextStyle(
                        color: widget.mine ? Colors.white : scheme.onSurface,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.invite.trackTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: widget.mine
                            ? Colors.white.withValues(alpha: .82)
                            : scheme.onSurfaceVariant,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            statusText,
            style: TextStyle(
              color: widget.mine
                  ? Colors.white.withValues(alpha: .84)
                  : scheme.onSurfaceVariant,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (active) ...[
            const SizedBox(height: 10),
            FilledButton.icon(
              key: ValueKey('chat-listen-together-open-${widget.messageId}'),
              onPressed: () => context.push('/player'),
              style: FilledButton.styleFrom(
                foregroundColor: widget.mine ? scheme.primary : Colors.white,
                backgroundColor: widget.mine ? Colors.white : scheme.primary,
              ),
              icon: const Icon(Icons.album_rounded, size: 18),
              label: const Text('查看唱片页'),
            ),
          ] else if (!widget.mine && !unavailable && (!matches || pending)) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 48,
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      key: ValueKey(
                        'chat-listen-together-decline-${widget.messageId}',
                      ),
                      onPressed: _busy ? null : () => _respond(accept: false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: scheme.onSurfaceVariant,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        minimumSize: const Size.fromHeight(48),
                      ),
                      child: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text('暂不加入', maxLines: 1, softWrap: false),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      key: ValueKey(
                        'chat-listen-together-accept-${widget.messageId}',
                      ),
                      onPressed: _busy ? null : () => _respond(accept: true),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        minimumSize: const Size.fromHeight(48),
                      ),
                      child: _busy
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                '加入一起听',
                                maxLines: 1,
                                softWrap: false,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _respond({required bool accept}) async {
    setState(() => _busy = true);
    try {
      final controller = ref.read(listenTogetherControllerProvider.notifier);
      if (accept) {
        await controller.accept(widget.invite.invitationId);
      } else {
        await controller.decline(widget.invite.invitationId);
      }
      if (!mounted) return;
      showMusicNotice(
        context,
        icon: accept ? Icons.headphones_rounded : Icons.close_rounded,
        title: accept ? '已加入一起听' : '已婉拒邀请',
        message: accept ? '播放状态和音乐列表正在同步' : '以后还可以再次接受好友邀请',
      );
      if (accept && context.mounted) context.push('/player');
    } on Object catch (error) {
      if (!mounted) return;
      showMusicNotice(
        context,
        icon: Icons.error_outline_rounded,
        title: '无法处理邀请',
        message: userFacingErrorMessage(error, fallback: '请稍后再试'),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class SocialSharedTrackMessage extends StatelessWidget {
  const SocialSharedTrackMessage({
    required this.messageId,
    required this.track,
    required this.mine,
    required this.onPlay,
    this.keyPrefix = 'chat',
    super.key,
  });

  final String messageId;
  final Track track;
  final bool mine;
  final VoidCallback? onPlay;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: ValueKey('$keyPrefix-shared-track-$messageId'),
      width: 248,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: mine
            ? scheme.primary.withValues(alpha: .92)
            : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(21),
          topRight: const Radius.circular(21),
          bottomLeft: Radius.circular(mine ? 21 : 6),
          bottomRight: Radius.circular(mine ? 6 : 21),
        ),
        border: Border.all(
          color: mine
              ? Colors.white.withValues(alpha: .18)
              : scheme.outlineVariant.withValues(alpha: .55),
        ),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: ArtworkImage(
              uri: track.coverAsset,
              width: 58,
              height: 58,
              fit: BoxFit.cover,
              retryOnNetworkError: true,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: mine ? Colors.white : scheme.onSurface,
                    fontSize: 13,
                    height: 1.2,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  track.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: mine
                        ? Colors.white.withValues(alpha: .72)
                        : scheme.onSurfaceVariant,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Semantics(
            button: onPlay != null,
            label: onPlay == null ? '歌曲暂时无法播放' : '播放《${track.title}》',
            child: IconButton.filled(
              key: ValueKey('$keyPrefix-shared-track-play-$messageId'),
              tooltip: onPlay == null ? '暂时无法播放' : '播放',
              onPressed: onPlay,
              style: IconButton.styleFrom(
                backgroundColor: mine
                    ? Colors.white.withValues(alpha: .16)
                    : scheme.primary.withValues(alpha: .12),
                foregroundColor: mine ? Colors.white : scheme.primary,
                disabledForegroundColor: mine
                    ? Colors.white38
                    : scheme.onSurfaceVariant.withValues(alpha: .45),
                minimumSize: const Size.square(38),
                maximumSize: const Size.square(38),
                padding: EdgeInsets.zero,
              ),
              icon: const Icon(Icons.play_arrow_rounded, size: 21),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageAvatar extends StatelessWidget {
  const _MessageAvatar({
    required this.messageId,
    required this.user,
    required this.mine,
    required this.onTap,
  });

  final String messageId;
  final SocialUser user;
  final bool mine;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = mine ? '查看我的个人主页' : '查看${user.displayName}的个人主页';
    return Semantics(
      button: true,
      label: label,
      child: Tooltip(
        message: label,
        child: InkResponse(
          key: ValueKey('chat-message-avatar-$messageId'),
          onTap: onTap,
          radius: 22,
          containedInkWell: true,
          customBorder: const CircleBorder(),
          child: SizedBox.square(
            dimension: 44,
            child: Center(child: SocialAvatar(user: user, size: 36)),
          ),
        ),
      ),
    );
  }
}

class _DeliveryIndicator extends StatelessWidget {
  const _DeliveryIndicator({
    required this.messageId,
    required this.delivery,
    required this.onRetry,
  });

  final String messageId;
  final _MessageDelivery delivery;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    if (delivery == _MessageDelivery.sending) {
      return Semantics(
        label: '消息发送中',
        child: SizedBox.square(
          key: ValueKey('chat-message-sending-$messageId'),
          dimension: 18,
          child: CircularProgressIndicator(
            strokeWidth: 1.8,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      );
    }
    return Tooltip(
      message: '发送失败，点按重试',
      child: Semantics(
        button: true,
        label: '消息发送失败，点按重试',
        child: InkResponse(
          key: ValueKey('chat-message-failed-$messageId'),
          onTap: onRetry,
          radius: 18,
          child: const Icon(
            Icons.error_rounded,
            size: 21,
            color: Color(0xFFC24A34),
          ),
        ),
      ),
    );
  }
}

class _ChatImagePreview extends StatelessWidget {
  const _ChatImagePreview({required this.messageId, required this.url});

  final String messageId;
  final String url;

  @override
  Widget build(BuildContext context) {
    final viewport = MediaQuery.sizeOf(context);
    final maxWidth = (viewport.width * .62).clamp(160.0, 260.0).toDouble();
    return InkWell(
      key: ValueKey('chat-image-preview-$messageId'),
      onTap: url.isEmpty
          ? null
          : () => Navigator.of(context, rootNavigator: true).push(
              MaterialPageRoute<void>(builder: (_) => _ImageViewer(url: url)),
            ),
      borderRadius: BorderRadius.circular(15),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: 360),
          child: ArtworkImage(
            key: ValueKey('chat-image-content-$messageId'),
            uri: url,
            decodeWidth: maxWidth,
            fit: BoxFit.contain,
            retryOnNetworkError: true,
          ),
        ),
      ),
    );
  }
}

class _ImageViewer extends StatelessWidget {
  const _ImageViewer({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Scaffold(
      key: const ValueKey('chat-image-viewer'),
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          SizedBox.expand(
            key: const ValueKey('chat-image-viewer-canvas'),
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 5,
              constrained: false,
              alignment: Alignment.center,
              child: SizedBox(
                width: size.width,
                height: size.height,
                child: Center(
                  child: ArtworkImage(
                    key: const ValueKey('chat-image-viewer-content'),
                    uri: url,
                    width: size.width,
                    height: size.height,
                    decodeWidth: size.width,
                    fit: BoxFit.contain,
                    retryOnNetworkError: true,
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: IconButton.filled(
                  tooltip: '关闭图片预览',
                  onPressed: () => Navigator.of(context).pop(),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black.withValues(alpha: .55),
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.close_rounded),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Duration chatVoiceDurationFromText(String value) {
  final milliseconds = int.tryParse(value) ?? 0;
  return Duration(milliseconds: milliseconds.clamp(0, 3600000));
}

@visibleForTesting
String formatChatVoiceDuration(Duration duration) {
  final totalSeconds = ((duration.inMilliseconds + 999) ~/ 1000)
      .clamp(0, 3599)
      .toInt();
  if (totalSeconds < 60) return '$totalSeconds″';
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

class SocialVoiceMessage extends ConsumerStatefulWidget {
  const SocialVoiceMessage({
    required this.messageId,
    required this.url,
    required this.duration,
    required this.mine,
    this.keyPrefix = 'chat',
    this.playbackSourceProvider,
    super.key,
  });

  final String messageId;
  final String url;
  final Duration duration;
  final bool mine;
  final String keyPrefix;
  final Future<String?> Function()? playbackSourceProvider;

  @override
  ConsumerState<SocialVoiceMessage> createState() => _SocialVoiceMessageState();
}

class _SocialVoiceMessageState extends ConsumerState<SocialVoiceMessage> {
  static _SocialVoiceMessageState? _activeVoice;

  just_audio.AudioPlayer? _player;
  StreamSubscription<just_audio.PlayerState>? _playerStateSubscription;
  late String _stableUrl;
  bool _sourceReady = false;
  bool _busy = false;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _stableUrl = widget.url.trim();
  }

  @override
  void didUpdateWidget(covariant SocialVoiceMessage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_stableUrl.isEmpty && widget.url.trim().isNotEmpty) {
      _stableUrl = widget.url.trim();
    }
  }

  @override
  void dispose() {
    if (identical(_activeVoice, this)) _activeVoice = null;
    _playerStateSubscription?.cancel();
    unawaited(_player?.dispose());
    super.dispose();
  }

  Future<void> _togglePlayback() async {
    if (_busy ||
        (_stableUrl.isEmpty && widget.playbackSourceProvider == null)) {
      return;
    }
    final player = _player;
    if (player?.playing == true) {
      await player!.pause();
      return;
    }
    setState(() => _busy = true);
    try {
      final playbackSourceProvider = widget.playbackSourceProvider;
      if (playbackSourceProvider != null) {
        final prepared = (await playbackSourceProvider())?.trim() ?? '';
        if (prepared.isEmpty) {
          throw const SocialRequestException('暂时无法恢复收藏的语音文件');
        }
        if (prepared != _stableUrl) {
          await _replacePlaybackSource(prepared);
        }
      }
      final active = _activeVoice;
      if (active != null && !identical(active, this)) {
        await active._pauseForAnotherVoice();
      }
      _activeVoice = this;
      try {
        await ref.read(audioHandlerProvider).pause();
      } on Object {
        // Widget tests and local previews may not provide the global audio handler.
      }
      final readyPlayer = await _ensurePlayer();
      if (readyPlayer.processingState == just_audio.ProcessingState.completed) {
        await readyPlayer.seek(Duration.zero);
      }
      unawaited(readyPlayer.play());
    } on Object catch (error) {
      if (mounted) {
        showMusicNotice(
          context,
          icon: Icons.volume_off_outlined,
          title: '语音暂时无法播放',
          message: userFacingErrorMessage(error, fallback: '请稍后重试'),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _replacePlaybackSource(String value) async {
    _stableUrl = value;
    _sourceReady = false;
    _playing = false;
    await _playerStateSubscription?.cancel();
    _playerStateSubscription = null;
    await _player?.dispose();
    _player = null;
  }

  Future<just_audio.AudioPlayer> _ensurePlayer() async {
    final existing = _player;
    if (existing != null && _sourceReady) return existing;
    final player = existing ?? just_audio.AudioPlayer();
    _player = player;
    _playerStateSubscription ??= player.playerStateStream.listen((state) {
      if (!mounted) return;
      final playing =
          state.playing &&
          state.processingState != just_audio.ProcessingState.completed;
      if (playing != _playing) setState(() => _playing = playing);
      if (state.processingState == just_audio.ProcessingState.completed &&
          identical(_activeVoice, this)) {
        _activeVoice = null;
      }
    });
    if (_isLocalMediaPath(_stableUrl)) {
      final file = _stableUrl.startsWith('file://')
          ? File.fromUri(Uri.parse(_stableUrl))
          : File(_stableUrl);
      await player.setFilePath(file.path);
    } else {
      // Keep remote voice clips on disk after the first successful playback.
      // Re-entering the chat therefore reuses the local file instead of
      // rebuilding an HTTP audio source and showing the loading state again.
      final cachedFile = await _ChatVoiceMediaCache.fileFor(_stableUrl);
      await player.setFilePath(cachedFile.path);
    }
    _sourceReady = true;
    return player;
  }

  Future<void> _pauseForAnotherVoice() async {
    final player = _player;
    if (player?.playing == true) await player!.pause();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = widget.mine ? Colors.white : scheme.primary;
    final seconds = ((widget.duration.inMilliseconds + 999) ~/ 1000).clamp(
      1,
      60,
    );
    final width = (96 + seconds * 1.35).clamp(104, 176).toDouble();
    final durationLabel = formatChatVoiceDuration(widget.duration);
    return Semantics(
      button: true,
      label: '${_playing ? '暂停' : '播放'}语音消息，时长 $durationLabel',
      child: InkWell(
        key: ValueKey('${widget.keyPrefix}-voice-message-${widget.messageId}'),
        onTap: _stableUrl.isEmpty && widget.playbackSourceProvider == null
            ? null
            : _togglePlayback,
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          width: width,
          height: 28,
          child: Row(
            children: [
              if (_busy)
                SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: foreground,
                  ),
                )
              else
                Icon(
                  _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  size: 24,
                  color: foreground,
                ),
              const SizedBox(width: 7),
              Expanded(
                child: _VoiceWaveform(
                  active: _playing,
                  color: foreground,
                  seed: widget.messageId.hashCode,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                durationLabel,
                key: ValueKey(
                  '${widget.keyPrefix}-voice-duration-${widget.messageId}',
                ),
                style: TextStyle(
                  color: foreground,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VoiceWaveform extends StatefulWidget {
  const _VoiceWaveform({
    required this.active,
    required this.color,
    required this.seed,
  });

  final bool active;
  final Color color;
  final int seed;

  @override
  State<_VoiceWaveform> createState() => _VoiceWaveformState();
}

class _VoiceWaveformState extends State<_VoiceWaveform>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 760),
    );
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant _VoiceWaveform oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) _syncAnimation();
  }

  void _syncAnimation() {
    if (widget.active) {
      _controller.repeat();
    } else {
      _controller
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const heights = [8.0, 15.0, 11.0, 20.0, 13.0, 18.0, 9.0, 16.0];
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(heights.length, (index) {
          final shiftedIndex = (index + widget.seed.abs()) % heights.length;
          final pulse = ((_controller.value * 8).floor() + shiftedIndex) % 4;
          final multiplier = widget.active ? .62 + pulse * .13 : .72;
          return Container(
            width: 2.5,
            height: heights[shiftedIndex] * multiplier,
            decoration: BoxDecoration(
              color: widget.color.withValues(alpha: widget.active ? .96 : .66),
              borderRadius: BorderRadius.circular(99),
            ),
          );
        }),
      ),
    );
  }
}

bool _isLocalMediaPath(String value) =>
    value.startsWith('file://') ||
    value.startsWith('/') ||
    RegExp(r'^[A-Za-z]:[\\/]').hasMatch(value);

class _ChatVoiceMediaCache {
  _ChatVoiceMediaCache._();

  static final BaseCacheManager _manager = DefaultCacheManager();

  static Future<File> fileFor(String url) => _manager.getSingleFile(url);
}

class SocialVideoMessage extends StatefulWidget {
  const SocialVideoMessage({
    required this.messageId,
    required this.url,
    this.thumbnailUrl,
    this.keyPrefix = 'chat',
    this.playbackSourceProvider,
    super.key,
  });

  final String messageId;
  final String url;
  final String? thumbnailUrl;
  final String keyPrefix;
  final Future<String?> Function()? playbackSourceProvider;

  @override
  State<SocialVideoMessage> createState() => _SocialVideoMessageState();
}

class _SocialVideoMessageState extends State<SocialVideoMessage> {
  VideoPlayerController? _controller;
  String? _stableThumbnailUrl;
  Duration? _stableDuration;
  bool _initializationFailed = false;
  bool _opening = false;
  int _controllerGeneration = 0;

  @override
  void initState() {
    super.initState();
    _stableThumbnailUrl = _usableThumbnail(widget.thumbnailUrl);
    _initializeController(widget.url);
  }

  @override
  void didUpdateWidget(covariant SocialVideoMessage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _stableThumbnailUrl ??= _usableThumbnail(widget.thumbnailUrl);
    if (oldWidget.url == widget.url) return;
    if (oldWidget.url.isEmpty ||
        (_stableDuration == null && _initializationFailed)) {
      _initializeController(widget.url);
    }
  }

  void _initializeController(String url) {
    final generation = ++_controllerGeneration;
    _controller?.dispose();
    _controller = null;
    _initializationFailed = false;
    if (url.isEmpty) return;
    final controller = chatVideoController(url);
    _controller = controller;
    controller.initialize().then(
      (_) {
        if (!mounted || generation != _controllerGeneration) return;
        controller
          ..setVolume(0)
          ..pause();
        setState(() => _stableDuration = controller.value.duration);
      },
      onError: (_) {
        if (!mounted || generation != _controllerGeneration) return;
        setState(() => _initializationFailed = true);
      },
    );
  }

  @override
  void dispose() {
    _controllerGeneration++;
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _openVideo() async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      var source = widget.url.trim();
      final playbackSourceProvider = widget.playbackSourceProvider;
      if (playbackSourceProvider != null) {
        source = (await playbackSourceProvider())?.trim() ?? '';
      }
      if (source.isEmpty) {
        throw const SocialRequestException('暂时无法恢复收藏的视频文件');
      }
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => _VideoViewer(url: source),
        ),
      );
    } on Object catch (error) {
      if (mounted) {
        showMusicNotice(
          context,
          icon: Icons.videocam_off_outlined,
          title: '视频暂时无法播放',
          message: userFacingErrorMessage(error, fallback: '请稍后重试'),
        );
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final initialized = controller?.value.isInitialized ?? false;
    final duration = _stableDuration;
    return InkWell(
      key: ValueKey('${widget.keyPrefix}-video-message-${widget.messageId}'),
      onTap: widget.url.isEmpty && widget.playbackSourceProvider == null
          ? null
          : _openVideo,
      borderRadius: BorderRadius.circular(15),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: SizedBox(
          key: const ValueKey('chat-video-preview'),
          width: 220,
          height: 140,
          child: Stack(
            fit: StackFit.expand,
            children: [
              const ColoredBox(color: Color(0xFF17131B)),
              if (_stableThumbnailUrl case final thumbnailUrl?
                  when thumbnailUrl.isNotEmpty)
                ArtworkImage(
                  key: const ValueKey('chat-video-thumbnail'),
                  uri: thumbnailUrl,
                  width: 220,
                  height: 140,
                  decodeWidth: 440,
                  fit: BoxFit.cover,
                  retryOnNetworkError: true,
                )
              else if (initialized)
                Center(
                  child: AspectRatio(
                    aspectRatio: controller!.value.aspectRatio > 0
                        ? controller.value.aspectRatio
                        : 16 / 9,
                    child: VideoPlayer(controller),
                  ),
                ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: [.45, 1],
                    colors: [Colors.transparent, Color(0xA8000000)],
                  ),
                ),
              ),
              Center(
                child: Container(
                  key: const ValueKey('chat-video-preview-play'),
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: .52),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xCCFFFFFF)),
                  ),
                  child: _opening
                      ? const Padding(
                          padding: EdgeInsets.all(14),
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(
                          Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 31,
                        ),
                ),
              ),
              Positioned(
                right: 10,
                bottom: 9,
                child: _VideoTimePill(
                  key: const ValueKey('chat-video-duration'),
                  label: duration != null
                      ? formatChatVideoDuration(duration)
                      : '--:--',
                  semanticsLabel: duration != null
                      ? '视频时长 ${formatChatVideoDuration(duration)}'
                      : '正在读取视频时长',
                ),
              ),
              if (_initializationFailed)
                const Positioned(
                  left: 10,
                  bottom: 10,
                  child: Text(
                    '点按打开视频',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
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

String? _usableThumbnail(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}

class _VideoTimePill extends StatelessWidget {
  const _VideoTimePill({
    required this.label,
    required this.semanticsLabel,
    super.key,
  });

  final String label;
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticsLabel,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: .62),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: .22)),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            height: 1,
            fontWeight: FontWeight.w800,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}

String formatChatVideoDuration(Duration duration) {
  final totalSeconds = duration.inSeconds.clamp(0, 359999).toInt();
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  final minuteText = minutes.toString().padLeft(2, '0');
  final secondText = seconds.toString().padLeft(2, '0');
  return hours > 0
      ? '${hours.toString().padLeft(2, '0')}:$minuteText:$secondText'
      : '$minuteText:$secondText';
}

VideoPlayerController chatVideoController(String url) {
  if (url.startsWith('file://')) {
    return VideoPlayerController.file(File.fromUri(Uri.parse(url)));
  }
  if (url.startsWith('/') || RegExp(r'^[A-Za-z]:[\\/]').hasMatch(url)) {
    return VideoPlayerController.file(File(url));
  }
  return VideoPlayerController.networkUrl(Uri.parse(url));
}

class _VideoPlaybackSurface extends StatelessWidget {
  const _VideoPlaybackSurface({required this.controller});

  final VideoPlayerController controller;

  @override
  Widget build(BuildContext context) {
    final aspectRatio = controller.value.aspectRatio;
    return Center(
      child: AspectRatio(
        aspectRatio: aspectRatio > 0 ? aspectRatio : 16 / 9,
        child: VideoPlayer(controller),
      ),
    );
  }
}

class _VideoControlBar extends StatelessWidget {
  const _VideoControlBar({required this.controller, required this.value});

  final VideoPlayerController controller;
  final VideoPlayerValue value;

  @override
  Widget build(BuildContext context) {
    final durationMilliseconds = value.duration.inMilliseconds;
    final maximum = durationMilliseconds > 0
        ? durationMilliseconds.toDouble()
        : 1.0;
    final positionMilliseconds = value.position.inMilliseconds
        .clamp(0, durationMilliseconds > 0 ? durationMilliseconds : 0)
        .toDouble();
    return Container(
      key: const ValueKey('chat-video-controls'),
      padding: const EdgeInsets.fromLTRB(10, 8, 14, 8),
      decoration: BoxDecoration(
        color: const Color(0xD91A171E),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0x38FFFFFF)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x59000000),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          IconButton.filled(
            key: ValueKey('chat-video-control-${value.isPlaying}'),
            tooltip: value.isPlaying ? '暂停视频' : '播放视频',
            onPressed: value.isInitialized
                ? () => value.isPlaying ? controller.pause() : controller.play()
                : null,
            style: IconButton.styleFrom(
              fixedSize: const Size.square(46),
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF211D25),
              disabledBackgroundColor: const Color(0x66FFFFFF),
            ),
            icon: Icon(chatVideoPlaybackIcon(value.isPlaying), size: 27),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 2,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 5,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 14,
                    ),
                    activeTrackColor: Colors.white,
                    inactiveTrackColor: const Color(0x4DFFFFFF),
                    thumbColor: Colors.white,
                    overlayColor: const Color(0x24FFFFFF),
                  ),
                  child: Slider(
                    key: const ValueKey('chat-video-progress'),
                    min: 0,
                    max: maximum,
                    value: positionMilliseconds.clamp(0.0, maximum).toDouble(),
                    onChanged: value.isInitialized && durationMilliseconds > 0
                        ? (next) => controller.seekTo(
                            Duration(milliseconds: next.round()),
                          )
                        : null,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        formatChatVideoDuration(value.position),
                        key: const ValueKey('chat-video-position'),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                      Text(
                        formatChatVideoDuration(value.duration),
                        key: const ValueKey('chat-video-total-duration'),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
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

class _InlineEmojiPanel extends StatefulWidget {
  const _InlineEmojiPanel({required this.onSelected});

  final ValueChanged<String> onSelected;

  @override
  State<_InlineEmojiPanel> createState() => _InlineEmojiPanelState();
}

class _InlineEmojiPanelState extends State<_InlineEmojiPanel> {
  static const _categories =
      <({String label, IconData icon, List<String> items})>[
        (
          label: '常用',
          icon: Icons.emoji_emotions_outlined,
          items: [
            '😀',
            '😊',
            '☺️',
            '😍',
            '😘',
            '😱',
            '😭',
            '😚',
            '😳',
            '😔',
            '😁',
            '😝',
            '😒',
            '😡',
            '😉',
            '😓',
            '😖',
            '😰',
            '😨',
            '😷',
            '😂',
            '😵',
            '😈',
            '😄',
            '😜',
            '😞',
            '😢',
            '❤️',
          ],
        ),
        (
          label: '心情',
          icon: Icons.favorite_border_rounded,
          items: [
            '🥰',
            '🥹',
            '🤩',
            '🤔',
            '😴',
            '🥳',
            '🤗',
            '🤭',
            '🫣',
            '🫠',
            '🙃',
            '😇',
            '🤓',
            '😎',
            '👏',
            '👍',
            '👎',
            '🫶',
            '🙏',
            '💪',
            '💔',
            '💕',
            '💖',
            '💯',
            '✨',
            '🔥',
            '🌙',
            '☀️',
          ],
        ),
        (
          label: '音乐',
          icon: Icons.music_note_rounded,
          items: [
            '🎧',
            '🎵',
            '🎶',
            '🎤',
            '🎸',
            '🎹',
            '🥁',
            '🎷',
            '🎺',
            '🎻',
            '💿',
            '📻',
            '🔊',
            '🔇',
            '▶️',
            '⏸️',
            '⏭️',
            '🔁',
            '🔀',
            '💃',
            '🕺',
            '🐱',
            '🐰',
            '🍑',
            '🌹',
            '⭐',
            '🌈',
            '🎉',
          ],
        ),
      ];

  int _selectedCategory = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final category = _categories[_selectedCategory];
    return Container(
      key: const ValueKey('chat-inline-emoji-panel'),
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.fromLTRB(4, 10, 4, 2),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: theme.dividerColor.withValues(alpha: .55)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              'emoji · ${category.label}',
              style: theme.textTheme.labelLarge?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 7),
          SizedBox(
            height: 196,
            child: GridView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              itemCount: category.items.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisSpacing: 2,
                crossAxisSpacing: 2,
              ),
              itemBuilder: (context, index) {
                final emoji = category.items[index];
                return InkWell(
                  key: ValueKey('chat-emoji-$emoji'),
                  onTap: () => widget.onSelected(emoji),
                  borderRadius: BorderRadius.circular(14),
                  child: Center(
                    child: Text(emoji, style: const TextStyle(fontSize: 28)),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              for (var index = 0; index < _categories.length; index++)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: IconButton(
                    key: ValueKey('chat-emoji-category-$index'),
                    tooltip: _categories[index].label,
                    onPressed: () => setState(() => _selectedCategory = index),
                    style: IconButton.styleFrom(
                      foregroundColor: index == _selectedCategory
                          ? scheme.primary
                          : scheme.onSurfaceVariant,
                      backgroundColor: index == _selectedCategory
                          ? scheme.primary.withValues(alpha: .12)
                          : Colors.transparent,
                    ),
                    icon: Icon(_categories[index].icon, size: 21),
                  ),
                ),
              const Spacer(),
              Icon(
                Icons.keyboard_alt_outlined,
                size: 18,
                color: scheme.onSurfaceVariant.withValues(alpha: .58),
              ),
              const SizedBox(width: 7),
              Text(
                '点按插入输入框',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant.withValues(alpha: .72),
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ],
      ),
    );
  }
}

class _VideoViewer extends StatefulWidget {
  const _VideoViewer({required this.url});

  final String url;

  @override
  State<_VideoViewer> createState() => _VideoViewerState();
}

class _VideoViewerState extends State<_VideoViewer> {
  late final VideoPlayerController _controller;
  late final Future<void> _initialize;

  @override
  void initState() {
    super.initState();
    _controller = chatVideoController(widget.url);
    _initialize = _controller.initialize().then((_) {
      if (!mounted) return;
      _controller
        ..setLooping(true)
        ..play();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('视频'),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: FutureBuilder<void>(
              future: _initialize,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Text(
                    '视频暂时无法播放',
                    style: TextStyle(color: Colors.white),
                  );
                }
                if (snapshot.connectionState != ConnectionState.done) {
                  return const CircularProgressIndicator(color: Colors.white);
                }
                return _VideoPlaybackSurface(controller: _controller);
              },
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 14,
            child: SafeArea(
              top: false,
              child: ValueListenableBuilder<VideoPlayerValue>(
                valueListenable: _controller,
                builder: (context, value, child) =>
                    _VideoControlBar(controller: _controller, value: value),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

IconData chatVideoPlaybackIcon(bool isPlaying) =>
    isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded;
