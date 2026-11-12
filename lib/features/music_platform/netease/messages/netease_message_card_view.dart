import '../../../../shared/widgets/beta_page_motion.dart';
import '../../../../shared/widgets/beta_content_insets.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../../shared/widgets/artwork_image.dart';
import '../../../../shared/widgets/beta_glass_controls.dart';
import '../../platform_backend_providers.dart';
import '../../presentation/platform_design.dart';
import 'netease_message_card.dart';
import 'netease_messages_repository.dart';
import '../together/together_record.dart';
import '../together/together_records_page.dart';
import '../../../themes/music_typography.dart';

/// Presentation only: reading a history card cannot end/create a room, rejoin
/// an old invitation, send a private message, or invent missing statistics.
class NeteaseMessageCardView extends StatelessWidget {
  const NeteaseMessageCardView({
    required this.card,
    required this.time,
    this.self,
    this.peer,
    super.key,
  });

  final NeteaseMessageCard card;
  final DateTime time;
  final NeteasePerson? self, peer;

  void _open(BuildContext context) =>
      Navigator.of(context, rootNavigator: true).push<void>(
        MestingPageRoute<void>(
          builder: (_) {
            if (card.togetherRecord && card.togetherRoomId.isNotEmpty) {
              return NeteaseTogetherRecordPage(
                roomId: card.togetherRoomId,
                messageTime: time,
                peer: peer == null
                    ? null
                    : NeteaseTogetherProfile(
                        id: peer!.id,
                        name: peer!.name,
                        avatar: peer!.avatar,
                      ),
              );
            }
            return NeteaseMessageCardDetailPage(card: card, time: time);
          },
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (card.togetherRecord) {
      // The rich message is one content link, rather than nested glass buttons.
      // InkWell supplies focus/semantics and cancels its press when chat scroll
      // wins the gesture; no independent press controller can remain stuck.
      return Material(
        key: const ValueKey('netease-together-message-card'),
        color: const Color(0xFFC72C43),
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: const ValueKey('netease-message-card-detail'),
          onTap: () => _open(context),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '我们一起听了',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: MusicTypography.footnoteSize,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        card.durationDescription.isNotEmpty
                            ? '${card.durationDescription} ›'
                            : card.duration != null
                            ? '${card.durationLabel} ›'
                            : '查看一起听记录 ›',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: MusicTypography.bodySize,
                          fontWeight: MusicTypography.titleWeight,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 62,
                  height: 40,
                  child: Stack(
                    children: [
                      _TogetherCardAvatar(
                        uri: card.togetherAvatars.firstOrNull ?? '',
                        person: card.togetherAvatars.isEmpty ? self : null,
                      ),
                      Positioned(
                        left: 22,
                        child: _TogetherCardAvatar(
                          uri: card.togetherAvatars.length > 1
                              ? card.togetherAvatars[1]
                              : '',
                          person: card.togetherAvatars.isEmpty ? peer : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              card.togetherRecord
                  ? CupertinoIcons.person_2_fill
                  : CupertinoIcons.doc_text,
              size: 24,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                card.title,
                style: const TextStyle(
                  fontSize: MusicTypography.calloutSize,
                  fontWeight: MusicTypography.bodyWeight,
                ),
              ),
            ),
          ],
        ),
        if (card.subtitle.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(card.subtitle, style: const TextStyle(height: 1.5)),
        ],
        if (card.duration != null) ...[
          const SizedBox(height: 8),
          Text('一起听时长 · ${card.durationLabel}'),
        ],
        const SizedBox(height: 12),
        BetaGlassButton(
          key: const ValueKey('netease-message-card-detail'),
          onPressed: () => _open(context),
          child: Text(card.togetherRecord ? '查看一起听记录' : '查看消息详情'),
        ),
      ],
    );
  }
}

class _TogetherCardAvatar extends StatelessWidget {
  const _TogetherCardAvatar({this.person, this.uri = ''});
  final NeteasePerson? person;
  final String uri;
  @override
  Widget build(BuildContext context) => Container(
    width: 40,
    height: 40,
    decoration: BoxDecoration(
      color: const Color(0xFF8D1C2D),
      shape: BoxShape.circle,
      border: Border.all(color: Colors.white, width: 1.5),
    ),
    padding: const EdgeInsets.all(1.5),
    child: ClipOval(
      child: uri.isNotEmpty || person?.avatar.isNotEmpty == true
          ? ArtworkImage(
              uri: uri.isNotEmpty ? uri : person!.avatar,
              width: 37,
              height: 37,
            )
          : const Icon(
              CupertinoIcons.person_fill,
              color: Colors.white,
              size: 22,
            ),
    ),
  );
}

class NeteaseMessageCardDetailPage extends ConsumerStatefulWidget {
  const NeteaseMessageCardDetailPage({
    required this.card,
    required this.time,
    super.key,
  });
  final NeteaseMessageCard card;
  final DateTime time;

  @override
  ConsumerState<NeteaseMessageCardDetailPage> createState() =>
      _MessageCardDetailState();
}

class _MessageCardDetailState
    extends ConsumerState<NeteaseMessageCardDetailPage> {
  late final _owner = ref
      .read(neteaseMessagesRepositoryProvider)
      .music
      .credential;

  @override
  Widget build(BuildContext context) {
    final music = ref.watch(neteaseMessagesRepositoryProvider).music;
    if (!ref.watch(usesNeteaseProvider) || music.credential != _owner) {
      return const PlatformPageFrame(
        title: '消息详情',
        child: Center(child: Text('账号已变化，请返回聊天后重新打开')),
      );
    }
    final card = widget.card, time = widget.time;
    return PlatformPageFrame(
      title: card.togetherRecord ? '一起听记录' : '消息详情',
      actions: [
        if (card.togetherRecord)
          BetaGlassButton(
            key: const ValueKey('together-legacy-all-records'),
            height: 44,
            onPressed: () => Navigator.of(context, rootNavigator: true).push(
              MestingPageRoute<void>(
                builder: (_) => const NeteaseTogetherHistoryPage(),
              ),
            ),
            child: const Text('全部记录'),
          ),
      ],
      child: ListView(
        padding: BetaContentInsets.musicPaddingOf(
          context,
          const EdgeInsets.fromLTRB(22, 16, 22, 40),
        ),
        children: [
          if (card.cover.isNotEmpty) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: ArtworkImage(
                uri: card.cover,
                height: 200,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 20),
          ],
          Text(card.title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          if (time.millisecondsSinceEpoch > 0)
            Text(
              '消息时间 · ${time.year}/${time.month}/${time.day} '
              '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
            ),
          if (card.subtitle.isNotEmpty) ...[
            const SizedBox(height: 20),
            SelectableText(
              card.subtitle,
              style: const TextStyle(
                fontSize: MusicTypography.calloutSize,
                height: 1.6,
              ),
            ),
          ],
          if (card.duration != null) ...[
            const SizedBox(height: 16),
            Text('一起听时长 · ${card.durationLabel}'),
          ],
          const SizedBox(height: 24),
          if (card.detailUrl != null)
            BetaGlassButton(
              blue: true,
              onPressed: () => Navigator.of(context).push(
                MestingPageRoute<void>(
                  builder: (_) => _OfficialMessagePage(url: card.detailUrl!),
                ),
              ),
              child: const Text('查看网易云原始详情'),
            )
          else
            Text(
              card.togetherRecord
                  ? '这条旧消息未提供可定位的本次报告，可从全部记录中选择查看。'
                  : '以上为平台消息中提供的记录；这条消息未附带网页详情。',
            ),
        ],
      ),
    );
  }
}

/// The official URL is received in the message, never constructed from an
/// assumed endpoint. No account cookie, native bridge or arbitrary deep link
/// is injected into a web page. Account changes invalidate the visible page.
class _OfficialMessagePage extends ConsumerStatefulWidget {
  const _OfficialMessagePage({required this.url});
  final Uri url;
  @override
  ConsumerState<_OfficialMessagePage> createState() =>
      _OfficialMessagePageState();
}

class _OfficialMessagePageState extends ConsumerState<_OfficialMessagePage> {
  WebViewController? _web;
  late final String? _owner;
  String? _error;
  bool _loading = true;

  bool get _current =>
      mounted &&
      ref.read(usesNeteaseProvider) &&
      ref.read(neteaseMessagesRepositoryProvider).music.credential == _owner;

  @override
  void initState() {
    super.initState();
    _owner = ref.read(neteaseMessagesRepositoryProvider).music.credential;
    Future.microtask(_load);
  }

  Future<void> _load() async {
    if (!_current) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final web = _web ??= WebViewController();
      await web.setJavaScriptMode(JavaScriptMode.unrestricted);
      await web.setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) =>
              _current && NeteaseMessageCard.canNavigateWeb(request.url)
              ? NavigationDecision.navigate
              : NavigationDecision.prevent,
          onPageFinished: (_) {
            if (_current) setState(() => _loading = false);
          },
          onWebResourceError: (error) {
            if (_current && error.isForMainFrame == true) {
              setState(() {
                _error = '网易云详情加载失败，请重试';
                _loading = false;
              });
            }
          },
        ),
      );
      if (!_current) return;
      await web.loadRequest(widget.url);
    } catch (_) {
      if (_current) {
        setState(() {
          _error = '此设备暂时无法打开网易云网页详情';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(usesNeteaseProvider);
    ref.watch(neteaseMessagesRepositoryProvider);
    if (!_current) {
      return const PlatformPageFrame(
        title: '网易云详情',
        child: Center(child: Text('账号已变化，请返回聊天后重新打开')),
      );
    }
    return PlatformPageFrame(
      title: '网易云详情',
      child: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!),
                    const SizedBox(height: 16),
                    BetaGlassButton(onPressed: _load, child: const Text('重试')),
                  ],
                ),
              ),
            )
          : Stack(
              children: [
                if (_web != null)
                  Positioned.fill(child: WebViewWidget(controller: _web!)),
                if (_loading) const Center(child: BetaActivityIndicator()),
              ],
            ),
    );
  }
}
