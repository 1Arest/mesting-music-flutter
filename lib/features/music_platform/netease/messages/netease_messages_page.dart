import '../../../../shared/widgets/beta_content_insets.dart';
import '../../../../shared/widgets/music_refresh_indicator.dart';
import '../../../../shared/widgets/music_loading_scope.dart';
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../shared/widgets/artwork_image.dart';
import '../../../../shared/widgets/beta_glass_action.dart';
import '../../../../shared/widgets/beta_glass_controls.dart';
import '../../../../shared/widgets/beta_bottom_search.dart';
import '../../../../shared/widgets/beta_page_search_layout.dart';
import '../../../../shared/widgets/beta_page_motion.dart';
import '../../../../shared/widgets/beta_swipe_pages.dart';
import '../../../../shared/widgets/keyboard_visibility_builder.dart';
import '../../platform_backend_providers.dart';
import '../../presentation/platform_design.dart';
import '../../presentation/platform_comment_composer.dart';
import '../../presentation/platform_comments_page.dart';
import '../netease_music_repository.dart';
import '../netease_user_page.dart';
import '../../domain/platform_search_user.dart';
import '../full/netease_together_page.dart';
import '../full/netease_entity_picker.dart';
import 'netease_messages_repository.dart';
import 'netease_emojis.dart';
import 'netease_message_card_view.dart';
import 'netease_message_diagnostic_action.dart';
import 'netease_unread.dart';
import '../../../../shared/widgets/beta_popup_menu_button.dart';

/// A conversation stays on the same stack as its message inbox. Pushing it on
/// the application root split a two-step Back sequence across the root and tab
/// navigators, allowing Android's next edge gesture to leave the Activity.
Future<T?> _open<T>(BuildContext context, Widget page) =>
    Navigator.of(context).push<T>(betaContentRoute<T>(page));

String neteaseMessageTime(DateTime time) {
  if (time.millisecondsSinceEpoch == 0) return '';
  final now = DateTime.now(), delta = DateTime.now().difference(time);
  if (delta.inMinutes < 1) return '刚刚';
  if (now.year == time.year && now.month == time.month && now.day == time.day) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
  return '${time.year == now.year ? '' : '${time.year}/'}${time.month}/${time.day}';
}

class NeteasePersonAvatar extends StatelessWidget {
  const NeteasePersonAvatar(this.person, {this.size = 48, super.key});
  final NeteasePerson person;
  final double size;
  @override
  Widget build(BuildContext context) => ClipOval(
    child: person.avatar.isEmpty
        ? SizedBox.square(
            dimension: size,
            child: ColoredBox(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: const Icon(CupertinoIcons.person_fill),
            ),
          )
        : ArtworkImage(uri: person.avatar, width: size, height: size),
  );
}

/// A page owns polling only while visible. The conversation itself remains in
/// NetEase, and the together session has independent application ownership.
abstract class _MessageState<T extends ConsumerStatefulWidget>
    extends ConsumerState<T>
    with WidgetsBindingObserver {
  late final NeteaseMessagesRepository repository;
  bool foreground = true;
  bool get current =>
      mounted &&
      ref.read(usesNeteaseProvider) &&
      ref.read(neteaseMessagesRepositoryProvider).music.credential ==
          repository.music.credential;
  @override
  void initState() {
    super.initState();
    repository = ref.read(neteaseMessagesRepositoryProvider);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Widget stale() => const PlatformPageFrame(
    title: '我的消息',
    child: Center(child: Text('账号已变化，请返回后重新打开')),
  );
}

class NeteaseMessagesPage extends ConsumerStatefulWidget {
  const NeteaseMessagesPage({super.key});
  @override
  ConsumerState<NeteaseMessagesPage> createState() =>
      _NeteaseMessagesPageState();
}

class _NeteaseMessagesPageState extends _MessageState<NeteaseMessagesPage> {
  final _conversations = <NeteaseConversation>[];
  Map<String, int> _counts = {};
  String _filter = '';
  String? _error;
  bool _busy = false, _more = true;
  int _offset = 0;
  late final _search = BetaPageSearchController(
    hintText: '搜索消息或联系人',
    onSubmitted: _filterList,
    onChanged: _filterList,
    onCleared: () => _filterList(''),
  );
  void _filterList(String value) {
    if (mounted) setState(() => _filter = value);
  }

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool next = false}) async {
    if (_busy || !current) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final list = await repository.conversations(next ? _offset : 0);
      if (!current) return;
      setState(() {
        if (!next) {
          _conversations.clear();
          _offset = 0;
        }
        _offset += list.length;
        final ids = _conversations.map((c) => c.peer.id).toSet();
        _conversations.addAll(list.where((c) => ids.add(c.peer.id)));
        _more = list.length >= 30;
      });
      try {
        final counts = await repository.counts();
        if (current) setState(() => _counts = counts);
      } catch (_) {
        /* Conversation reading remains useful if counts fail. */
      }
    } catch (e) {
      if (current) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _chat(NeteasePerson peer) async {
    await _open<void>(context, NeteaseChatPage(peer: peer));
    if (current) await _load();
  }

  Widget _category(
    String title,
    String subtitle,
    IconData icon,
    Color color,
    int count,
    NeteaseNoticeKind kind,
  ) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
    leading: CircleAvatar(
      radius: 26,
      backgroundColor: color,
      child: Icon(icon, color: Colors.white),
    ),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
    subtitle: Text(subtitle),
    trailing: count > 0
        ? _UnreadBadge(count)
        : const Icon(CupertinoIcons.chevron_right, size: 16),
    onTap: () async {
      await _open<void>(context, NeteaseNoticesPage(initial: kind));
      if (current) await _load();
    },
  );
  @override
  Widget build(BuildContext context) {
    ref.watch(neteaseMessagesRepositoryProvider);
    ref.watch(usesNeteaseProvider);
    if (!current) return stale();
    ref.watch(neteaseMessageReadRevisionProvider);
    final counts = repository.visibleCounts(_counts);
    final list = _conversations
        .map(repository.visibleConversation)
        .where(
          (c) => '${c.peer.name} ${c.last.text}'.toLowerCase().contains(
            _filter.toLowerCase(),
          ),
        );
    return BetaPageSearchLayout(
      controller: _search,
      child: PlatformPageFrame(
        title: '我的消息',
        actions: [
          BetaGlassAction(
            label: '发起聊天',
            icon: CupertinoIcons.square_pencil,
            blue: false,
            onPressed: () async {
              final peer = await _open<NeteasePerson>(
                context,
                const NeteaseFriendsPage(),
              );
              if (peer != null && current) await _chat(peer);
            },
          ),
        ],
        child: MusicRefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: BetaContentInsets.musicPaddingOf(context, EdgeInsets.zero),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              if (_filter.isEmpty) ...[
                _category(
                  '新增粉丝',
                  '关注你的朋友',
                  CupertinoIcons.person_fill,
                  const Color(0xFFFF4D63),
                  counts['newFollowerCount'] ?? 0,
                  NeteaseNoticeKind.fans,
                ),
                _category(
                  '评论和@提及',
                  '查看评论、回复和提及',
                  CupertinoIcons.chat_bubble_text_fill,
                  const Color(0xFF289AD9),
                  (counts['commentCount'] ?? 0) + (counts['forwardCount'] ?? 0),
                  NeteaseNoticeKind.comments,
                ),
                _category(
                  '赞和通知',
                  '互动与平台通知',
                  CupertinoIcons.hand_thumbsup_fill,
                  const Color(0xFFFFB634),
                  counts['noticeCount'] ?? 0,
                  NeteaseNoticeKind.notices,
                ),
                const Divider(indent: 22, endIndent: 22),
              ],
              if (_error != null) _MessageFeedback(_error!, retry: _load),
              if (_busy)
                const MusicLoadingPlaceholder(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(child: BetaActivityIndicator()),
                  ),
                ),
              for (final conversation in list)
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 8,
                  ),
                  leading: NeteasePersonAvatar(conversation.peer, size: 54),
                  title: Text(
                    conversation.peer.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    conversation.last.image.isEmpty
                        ? conversation.last.text
                        : '[图片]',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        neteaseMessageTime(conversation.last.time),
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                      if (conversation.unread > 0) ...[
                        const SizedBox(height: 5),
                        _UnreadBadge(conversation.unread),
                      ],
                    ],
                  ),
                  onTap: () => _chat(conversation.peer),
                ),
              if (!_busy && _error == null && list.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    '暂无会话，点击右上角选择朋友开始聊天',
                    textAlign: TextAlign.center,
                  ),
                ),
              if (_more && _conversations.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(22),
                  child: BetaGlassButton(
                    onPressed: _busy ? null : () => _load(next: true),
                    child: const Text('更多会话'),
                  ),
                ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge(this.count);
  final int count;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: NeteaseUnreadColors.background,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      count > 99 ? '99+' : '$count',
      style: const TextStyle(
        color: NeteaseUnreadColors.foreground,
        fontSize: 12,
      ),
    ),
  );
}

class _MessageFeedback extends StatelessWidget {
  const _MessageFeedback(this.text, {this.retry});
  final String text;
  final VoidCallback? retry;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(20),
    child: Column(
      children: [
        Text(text, textAlign: TextAlign.center),
        if (retry != null) ...[
          const SizedBox(height: 12),
          BetaGlassButton(onPressed: retry, child: const Text('重新加载')),
        ],
      ],
    ),
  );
}

/// Friends and recent contacts are immediately available; online search is an
/// optional way to start a new conversation, never a prerequisite to replying.
class NeteaseFriendsPage extends ConsumerStatefulWidget {
  const NeteaseFriendsPage({super.key});
  @override
  ConsumerState<NeteaseFriendsPage> createState() => _NeteaseFriendsPageState();
}

class _NeteaseFriendsPageState extends _MessageState<NeteaseFriendsPage> {
  final _people = <NeteasePerson>[];
  List<NeteasePerson>? _results;
  String _filter = '';
  String? _error;
  bool _busy = false, _more = false;
  int _offset = 0, _epoch = 0;
  late final _search = BetaPageSearchController(
    hintText: '搜索朋友',
    onSubmitted: _online,
    onChanged: (value) {
      _epoch++;
      setState(() {
        _filter = value;
        _results = null;
        _busy = false;
      });
    },
    onCleared: () {
      _epoch++;
      setState(() {
        _filter = '';
        _results = null;
        _busy = false;
      });
    },
  );
  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _epoch++;
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_busy || !current) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final friends = await repository.friends(_offset);
      if (!current) return;
      final ids = _people.map((p) => p.id).toSet();
      setState(() {
        _people.addAll(friends.where((p) => ids.add(p.id)));
        _offset += friends.length;
        _more = friends.length >= 50;
      });
      if (_offset == friends.length) {
        try {
          final conversations = await repository.conversations();
          if (current) {
            setState(
              () => _people.addAll(
                conversations.map((c) => c.peer).where((p) => ids.add(p.id)),
              ),
            );
          }
        } catch (_) {
          /* The friend list does not depend on private history. */
        }
      }
    } catch (e) {
      if (current) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _online(String query) async {
    if (query.trim().isEmpty || !current) return;
    final epoch = ++_epoch;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await repository.music.call('/search', {
        'keywords': query.trim(),
        'type': 1002,
        'limit': 50,
      });
      final result = NeteaseMusicRepository.object(r['result']);
      if (current && epoch == _epoch) {
        setState(
          () => _results = NeteaseMusicRepository.rows(
            result['userprofiles'],
          ).map(NeteasePerson.parse).toList(),
        );
      }
    } catch (e) {
      if (current && epoch == _epoch) setState(() => _error = '$e');
    } finally {
      if (mounted && epoch == _epoch) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(neteaseMessagesRepositoryProvider);
    ref.watch(usesNeteaseProvider);
    if (!current) return stale();
    final people =
        (_results ??
                _people.where(
                  (p) => p.name.toLowerCase().contains(_filter.toLowerCase()),
                ))
            .where((p) => p.id.isNotEmpty && p.id != repository.self);
    return BetaPageSearchLayout(
      controller: _search,
      child: PlatformPageFrame(
        title: '选择朋友',
        child: ListView(
          padding: BetaContentInsets.musicPaddingOf(context, EdgeInsets.zero),
          children: [
            if (_error != null) _MessageFeedback(_error!, retry: _load),
            if (_busy)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: BetaActivityIndicator(),
                ),
              ),
            for (final person in people)
              ListTile(
                leading: NeteasePersonAvatar(person),
                title: Text(person.name),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 6,
                ),
                onTap: () => Navigator.of(context).pop(person),
              ),
            if (!_busy && people.isEmpty)
              const _MessageFeedback('暂无匹配的朋友，可以在底部搜索网易云用户'),
            if (_more && _results == null)
              Padding(
                padding: const EdgeInsets.all(22),
                child: BetaGlassButton(
                  onPressed: _busy ? null : _load,
                  child: const Text('更多朋友'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class NeteaseChatPage extends ConsumerStatefulWidget {
  const NeteaseChatPage({required this.peer, this.share, super.key});
  final NeteasePerson peer;
  final NeteaseChatShare? share;
  @override
  ConsumerState<NeteaseChatPage> createState() => _NeteaseChatPageState();
}

class _NeteaseChatPageState extends _MessageState<NeteaseChatPage> {
  final _draft = TextEditingController();
  final _messages = <NeteaseChatMessage>[];
  final _scroll = ScrollController();
  Timer? _poll;
  Uint8List? _picture;
  NeteaseChatShare? _share;
  String? _error;
  bool _loading = false,
      _sending = false,
      _emojis = false,
      _more = false,
      _uncertain = false;
  @override
  void initState() {
    super.initState();
    _share = widget.share;
    _scroll.addListener(_displayedLatest);
    Future.microtask(_load);
    _poll = Timer.periodic(const Duration(seconds: 8), (_) {
      if (foreground &&
          current &&
          (ModalRoute.of(context)?.isCurrent ?? false)) {
        _load(quiet: true);
      }
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _draft.clear();
    _draft.dispose();
    _picture = null;
    _scroll.dispose();
    super.dispose();
  }

  void _displayedLatest() {
    if (!current ||
        !foreground ||
        !(ModalRoute.of(context)?.isCurrent ?? false) ||
        !_scroll.hasClients ||
        _scroll.offset > 80 ||
        _messages.isEmpty) {
      return;
    }
    repository.reads.displayed(widget.peer.id, _messages.first.time);
  }

  Future<void> _load({bool older = false, bool quiet = false}) async {
    if (_loading || !current) return;
    setState(() {
      _loading = true;
      if (!quiet) _error = null;
    });
    try {
      final before = older && _messages.isNotEmpty
          ? _messages.last.time.millisecondsSinceEpoch
          : 0;
      final rows = await repository.history(widget.peer.id, before);
      if (!current) return;
      setState(() {
        final byId = {
          for (final m in _messages) m.id: m,
          for (final m in rows) m.id: m,
        };
        _messages
          ..clear()
          ..addAll(
            byId.values.toList()..sort((a, b) => b.time.compareTo(a.time)),
          );
        if (older || !quiet) _more = rows.length >= 30;
        _uncertain = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _displayedLatest());
    } catch (e) {
      if (current && !quiet) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickPicture() async {
    if (_sending || !current) return;
    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 90,
      );
      if (image == null || !current) return;
      final bytes = await image.readAsBytes();
      if (current) {
        setState(() {
          _picture = bytes;
          _emojis = false;
        });
      }
    } catch (_) {
      if (current) setState(() => _error = '图片未能读取，请重新选择');
    }
  }

  Future<void> _send() async {
    if (_sending || _uncertain || !current) return;
    final text = _draft.text.trim(), picture = _picture;
    final share = _share;
    if (text.isEmpty && picture == null && share == null) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      List<NeteaseChatMessage> rows;
      if (picture != null) {
        final codec = await ui.instantiateImageCodec(picture);
        final frame = await codec.getNextFrame();
        final width = frame.image.width, height = frame.image.height;
        frame.image.dispose();
        codec.dispose();
        if (!current) return;
        rows = await repository.sendPicture(
          widget.peer.id,
          picture,
          width,
          height,
        );
      } else if (share != null) {
        rows = await repository.sendResource(widget.peer.id, share, text);
      } else {
        rows = await repository.sendText(widget.peer.id, text);
      }
      if (!current) return;
      setState(() {
        if (picture != null) {
          _picture = null;
        } else {
          _share = null;
          if (_draft.text.trim() == text) _draft.clear();
        }
        final ids = _messages.map((m) => m.id).toSet();
        _messages.insertAll(0, rows.where((m) => ids.add(m.id)));
      });
      await _load(quiet: true);
      if (_scroll.hasClients) {
        await _scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    } catch (e) {
      if (current) {
        setState(() {
          _uncertain = true;
          _error = '$e\n草稿已保留，请先刷新聊天核对是否送达，再决定是否重发。';
        });
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _appendEmoji(String emoji) {
    final selection = _draft.selection;
    final at = selection.isValid ? selection.start : _draft.text.length;
    final end = selection.isValid ? selection.end : at;
    _draft.value = TextEditingValue(
      text: _draft.text.replaceRange(at, end, emoji),
      selection: TextSelection.collapsed(offset: at + emoji.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(neteaseMessagesRepositoryProvider);
    ref.watch(usesNeteaseProvider);
    if (!current) return stale();
    return KeyboardVisibilityBuilder(
      builder: (context, keyboard) => PlatformPageFrame(
        musicChrome: false,
        title: widget.peer.name,
        centerTitle: true,
        titleWeight: FontWeight.w500,
        titleFontSize: MediaQuery.sizeOf(context).width < 360 ? 16 : 18,
        actions: [
          Tooltip(
            message: '一起听',
            child: BetaGlassButton(
              label: '一起听',
              height: 40,
              width: MediaQuery.sizeOf(context).width < 360 ? 44 : null,
              horizontalPadding: 10,
              blue: false,
              onPressed: () => _open<void>(
                context,
                NeteaseTogetherPage(invitee: widget.peer),
              ),
              child: MediaQuery.sizeOf(context).width < 360
                  ? const Icon(CupertinoIcons.headphones, size: 18)
                  : const Text(
                      '一起听',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 4),
          BetaPopupMenuButton<String>(
            tooltip: '聊天菜单',
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'refresh', child: Text('刷新消息')),
              PopupMenuItem(value: 'earlier', child: Text('查看更早消息')),
            ],
            onSelected: (value) => _load(older: value == 'earlier'),
          ),
        ],
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                controller: _scroll,
                reverse: true,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                itemCount: _messages.length + 1,
                itemBuilder: (context, index) {
                  if (index == _messages.length) {
                    return Column(
                      children: [
                        if (_loading)
                          const Padding(
                            padding: EdgeInsets.all(16),
                            child: BetaActivityIndicator(),
                          ),
                        if (_more)
                          BetaGlassButton(
                            onPressed: _loading
                                ? null
                                : () => _load(older: true),
                            child: const Text('更早的消息'),
                          ),
                        if (!_loading && _messages.isEmpty)
                          const _MessageFeedback('和朋友打个招呼吧'),
                      ],
                    );
                  }
                  final message = _messages[index];
                  final mine = message.from.id == repository.self;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    child: Column(
                      children: [
                        Text(
                          neteaseMessageTime(message.time),
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: mine
                              ? MainAxisAlignment.end
                              : MainAxisAlignment.start,
                          children: [
                            if (!mine) ...[
                              Semantics(
                                button: true,
                                label: '查看${widget.peer.name}的个人主页',
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: widget.peer.id.isEmpty
                                      ? null
                                      : () {
                                          FocusManager.instance.primaryFocus
                                              ?.unfocus();
                                          openNeteaseUser(
                                            context,
                                            PlatformSearchUser(
                                              id: widget.peer.id,
                                              nickname: widget.peer.name,
                                              avatar: widget.peer.avatar,
                                            ),
                                          );
                                        },
                                  child: NeteasePersonAvatar(
                                    widget.peer,
                                    size: 36,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 9),
                            ],
                            Flexible(
                              child: Container(
                                constraints: const BoxConstraints(
                                  maxWidth: 300,
                                ),
                                padding: message.card?.togetherRecord == true
                                    ? EdgeInsets.zero
                                    : const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: message.card?.togetherRecord == true
                                      ? Colors.transparent
                                      : mine
                                      ? Theme.of(
                                          context,
                                        ).colorScheme.primaryContainer
                                      : Theme.of(
                                          context,
                                        ).colorScheme.surfaceContainerLow,
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (message.card != null)
                                      NeteaseMessageCardView(
                                        card: message.card!,
                                        time: message.time,
                                        peer: widget.peer,
                                        self: message.from.id == repository.self
                                            ? message.from
                                            : message.to,
                                      )
                                    else if (message.image.isNotEmpty)
                                      GestureDetector(
                                        onTap: () => _open<void>(
                                          context,
                                          PlatformPageFrame(
                                            title: '图片',
                                            child: InteractiveViewer(
                                              child: Center(
                                                child: ArtworkImage(
                                                  uri: message.image,
                                                  fit: BoxFit.contain,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            9,
                                          ),
                                          child: ArtworkImage(
                                            uri: message.image,
                                            width: 180,
                                            height: 220,
                                            fit: BoxFit.contain,
                                          ),
                                        ),
                                      )
                                    else
                                      SelectableText(
                                        displayNeteaseEmojis(message.text),
                                        style: const TextStyle(
                                          fontSize: 16,
                                          height: 1.45,
                                          fontFamilyFallback: [
                                            'Noto Color Emoji',
                                            'Apple Color Emoji',
                                            'Segoe UI Emoji',
                                          ],
                                        ),
                                      ),
                                    if (message.text.contains(
                                      'st.music.163.com/listen-together/',
                                    ))
                                      Padding(
                                        padding: const EdgeInsets.only(top: 8),
                                        child: BetaGlassButton(
                                          onPressed: () => _open<void>(
                                            context,
                                            NeteaseTogetherPage(
                                              invitation: message.text,
                                            ),
                                          ),
                                          child: const Text('加入一起听'),
                                        ),
                                      ),
                                    if (message.diagnostics != null)
                                      NeteaseMessageDiagnosticAction(
                                        report: message.diagnostics!,
                                        isCurrent: () => current,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            if (mine) ...[
                              const SizedBox(width: 9),
                              NeteasePersonAvatar(message.from, size: 36),
                            ],
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Column(
                  children: [
                    Text(_error!, maxLines: 4, overflow: TextOverflow.ellipsis),
                    BetaGlassButton(
                      onPressed: _loading || _sending ? null : _load,
                      child: const Text('刷新聊天'),
                    ),
                  ],
                ),
              ),
            if (_picture != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.memory(
                        _picture!,
                        width: 90,
                        height: 90,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _draft.text.isEmpty ? '图片已选择，点击发送' : '图片已选择，发送后文字保留为草稿',
                      ),
                    ),
                    BetaGlassAction(
                      label: '移除图片',
                      icon: CupertinoIcons.xmark,
                      blue: false,
                      onPressed: _sending
                          ? null
                          : () => setState(() => _picture = null),
                    ),
                  ],
                ),
              ),
            if (_share != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: ListTile(
                  leading: const Icon(CupertinoIcons.music_note),
                  title: Text('分享：${_share!.name}'),
                  trailing: BetaGlassAction(
                    label: '取消分享',
                    icon: CupertinoIcons.xmark,
                    blue: false,
                    onPressed: _sending
                        ? null
                        : () => setState(() => _share = null),
                  ),
                ),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                BetaGlassAction(
                  label: '表情',
                  icon: CupertinoIcons.smiley,
                  blue: false,
                  onPressed: _sending
                      ? null
                      : () {
                          FocusScope.of(context).unfocus();
                          setState(() => _emojis = !_emojis);
                        },
                ),
                const SizedBox(width: 6),
                BetaGlassAction(
                  label: '发送图片',
                  icon: CupertinoIcons.photo,
                  blue: false,
                  onPressed: _sending ? null : _pickPicture,
                ),
                const SizedBox(width: 6),
                BetaGlassAction(
                  label: '分享歌曲',
                  icon: CupertinoIcons.music_note,
                  blue: false,
                  onPressed: _sending
                      ? null
                      : () async {
                          final picked = await Navigator.of(context)
                              .push<NeteasePickedEntity>(
                                MaterialPageRoute(
                                  builder: (_) => const NeteaseEntityPicker(
                                    kind: 'song',
                                    includeDetails: true,
                                  ),
                                ),
                              );
                          if (picked != null && current) {
                            setState(() {
                              _share = NeteaseChatShare(
                                'song',
                                picked.id,
                                picked.name,
                              );
                              _picture = null;
                            });
                          }
                        },
                ),
                const SizedBox(width: 18),
              ],
            ),
            PlatformCommentComposer(
              controller: _draft,
              sending: _sending || _uncertain,
              onSend: _send,
              keyboardVisible: keyboard,
              hintText: '发送消息…',
              sendLabel: '发送消息',
            ),
            if (_emojis && !keyboard)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final emoji in const [
                      '😀',
                      '😄',
                      '🥰',
                      '😘',
                      '😂',
                      '😎',
                      '🥹',
                      '😭',
                      '😮',
                      '🤔',
                      '👍',
                      '👏',
                      '❤️',
                      '🌹',
                      '🎵',
                      '🎉',
                    ])
                      SizedBox(
                        width: 48,
                        height: 42,
                        child: BetaGlassButton(
                          width: 48,
                          height: 42,
                          horizontalPadding: 0,
                          onPressed: () => _appendEmoji(emoji),
                          child: Center(
                            child: Text(
                              emoji,
                              style: const TextStyle(
                                fontSize: 23,
                                fontFamilyFallback: [
                                  'Noto Color Emoji',
                                  'Apple Color Emoji',
                                  'Segoe UI Emoji',
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A share starts from its content, then chooses a real conversation partner.
/// The last step is the same chat composer and explicit Send as ordinary text.
class NeteaseShareMessagePage extends ConsumerStatefulWidget {
  const NeteaseShareMessagePage({
    required this.kind,
    this.id = '',
    this.name = '',
    super.key,
  });
  final String kind, id, name;
  @override
  ConsumerState<NeteaseShareMessagePage> createState() =>
      _NeteaseShareMessagePageState();
}

class _NeteaseShareMessagePageState
    extends _MessageState<NeteaseShareMessagePage> {
  NeteaseChatShare? _share;
  @override
  void initState() {
    super.initState();
    if (widget.id.isNotEmpty) {
      _share = NeteaseChatShare(
        widget.kind,
        widget.id,
        widget.name.isEmpty
            ? '已选${neteaseEntityLabel(widget.kind)}'
            : widget.name,
      );
    }
  }

  Future<void> _choose() async {
    final picked = await _open<NeteasePickedEntity>(
      context,
      NeteaseEntityPicker(kind: widget.kind, includeDetails: true),
    );
    if (current && picked != null) {
      setState(
        () => _share = NeteaseChatShare(widget.kind, picked.id, picked.name),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(usesNeteaseProvider);
    ref.watch(neteaseMessagesRepositoryProvider);
    if (!current) return stale();
    return PlatformPageFrame(
      title: '分享${neteaseEntityLabel(widget.kind)}',
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              title: Text(
                _share?.name ?? '选择${neteaseEntityLabel(widget.kind)}',
              ),
              trailing: const Icon(CupertinoIcons.chevron_right),
              onTap: _choose,
            ),
            const SizedBox(height: 22),
            BetaGlassButton(
              blue: true,
              onPressed: _share == null
                  ? null
                  : () async {
                      final peer = await _open<NeteasePerson>(
                        context,
                        const NeteaseFriendsPage(),
                      );
                      if (!context.mounted || !current || peer == null) return;
                      await _open<void>(
                        context,
                        NeteaseChatPage(peer: peer, share: _share),
                      );
                    },
              child: const Text('选择朋友'),
            ),
          ],
        ),
      ),
    );
  }
}

class NeteaseNoticesPage extends StatefulWidget {
  const NeteaseNoticesPage({required this.initial, super.key});
  final NeteaseNoticeKind initial;
  @override
  State<NeteaseNoticesPage> createState() => _NeteaseNoticesPageState();
}

class _NeteaseNoticesPageState extends State<NeteaseNoticesPage> {
  late int _index = widget.initial == NeteaseNoticeKind.mentions ? 1 : 0;
  @override
  Widget build(BuildContext context) {
    if (widget.initial != NeteaseNoticeKind.comments &&
        widget.initial != NeteaseNoticeKind.mentions) {
      return _NeteaseNoticeList(initial: widget.initial);
    }
    return PlatformPageFrame(
      title: '评论和@提及',
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: CupertinoSlidingSegmentedControl<int>(
              groupValue: _index,
              children: const {0: Text('评论'), 1: Text('@我')},
              onValueChanged: (index) {
                if (index != null) {
                  setState(() => _index = index);
                }
              },
            ),
          ),
          Expanded(
            child: BetaSwipePages(
              index: _index,
              length: 2,
              onChanged: (index) {
                if (_index != index) {
                  setState(() => _index = index);
                }
              },
              itemBuilder: (context, index) => _NeteaseNoticeList(
                key: ValueKey(index),
                embedded: true,
                initial: index == 0
                    ? NeteaseNoticeKind.comments
                    : NeteaseNoticeKind.mentions,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NeteaseNoticeList extends ConsumerStatefulWidget {
  const _NeteaseNoticeList({
    required this.initial,
    this.embedded = false,
    super.key,
  });
  final bool embedded;
  final NeteaseNoticeKind initial;
  @override
  ConsumerState<_NeteaseNoticeList> createState() => _NeteaseNoticeListState();
}

class _NeteaseNoticeListState extends _MessageState<_NeteaseNoticeList> {
  late final NeteaseNoticeKind _kind = widget.initial;
  final _rows = <NeteaseMessageNotice>[];
  String? _error;
  bool _busy = false, _more = false;
  int _offset = 0, _before = -1;
  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load({bool next = false}) async {
    if (_busy || !current) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final rows = await repository.notices(
        _kind,
        next ? _before : -1,
        next ? _offset : 0,
      );
      if (!current) return;
      setState(() {
        if (!next) {
          _rows.clear();
          _offset = 0;
        }
        final ids = _rows.map((r) => r.id).toSet();
        _rows.addAll(rows.where((r) => ids.add(r.id)));
        _offset += rows.length;
        if (rows.isNotEmpty) _before = rows.last.time.millisecondsSinceEpoch;
        _more = rows.length >= 30;
      });
    } catch (e) {
      if (current) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _detail(NeteaseMessageNotice row) async {
    final songId =
        RegExp(r'R_SO_4_(\d+)').firstMatch(row.threadId)?.group(1) ??
        (row.resourceType == 'song' ? row.resourceId : '');
    if (songId.isNotEmpty) {
      try {
        final r = await repository.music.call('/song/detail', {
          'ids': [songId],
        });
        final tracks = NeteaseMusicRepository.tracks(r['songs']);
        if (mounted && current && tracks.isNotEmpty) {
          await openPlatformSongComments(context, ref, tracks.first);
          return;
        }
      } catch (_) {
        /* Keep the full notice readable when the resource vanished. */
      }
    }
    if (!mounted || !current) return;
    await _open<void>(
      context,
      PlatformPageFrame(
        title: row.person.name,
        child: ListView(
          padding: BetaContentInsets.musicPaddingOf(
            context,
            const EdgeInsets.all(24),
          ),
          children: [
            Text(neteaseMessageTime(row.time)),
            const SizedBox(height: 18),
            SelectableText(row.text, style: const TextStyle(fontSize: 17)),
            if (row.person.id.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 24),
                child: BetaGlassButton(
                  onPressed: () =>
                      _open<void>(context, NeteaseChatPage(peer: row.person)),
                  child: const Text('发送私信'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(neteaseMessagesRepositoryProvider);
    ref.watch(usesNeteaseProvider);
    if (!current) return stale();
    final title = switch (_kind) {
      NeteaseNoticeKind.fans => '新增粉丝',
      NeteaseNoticeKind.comments => '评论和@提及',
      NeteaseNoticeKind.mentions => '评论和@提及',
      NeteaseNoticeKind.notices => '赞和通知',
    };
    final list = MusicRefreshIndicator(
      onRefresh: _load,
      child: ListView(
        key: PageStorageKey('notices-${_kind.name}'),
        padding: BetaContentInsets.musicPaddingOf(
          context,
          EdgeInsets.only(bottom: 190),
        ),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          if (_error != null) _MessageFeedback(_error!, retry: _load),
          if (_busy)
            const MusicLoadingPlaceholder(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: BetaActivityIndicator()),
              ),
            ),
          for (final row in _rows)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 22,
                vertical: 8,
              ),
              leading: NeteasePersonAvatar(row.person),
              title: Text(row.person.name),
              subtitle: Text(
                row.text,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Text(
                neteaseMessageTime(row.time),
                style: Theme.of(context).textTheme.labelSmall,
              ),
              onTap: () => _detail(row),
            ),
          if (!_busy && _rows.isEmpty && _error == null)
            const _MessageFeedback('暂时没有消息'),
          if (_more)
            Padding(
              padding: const EdgeInsets.all(22),
              child: BetaGlassButton(
                onPressed: _busy ? null : () => _load(next: true),
                child: const Text('加载更多'),
              ),
            ),
        ],
      ),
    );
    return widget.embedded
        ? list
        : PlatformPageFrame(title: title, child: list);
  }
}
