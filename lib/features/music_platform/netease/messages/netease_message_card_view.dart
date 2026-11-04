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

/// Presentation only: reading a history card cannot end/create a room, rejoin
/// an old invitation, send a private message, or invent missing statistics.
class NeteaseMessageCardView extends StatelessWidget {
  const NeteaseMessageCardView({
    required this.card,
    required this.time,
    super.key,
  });

  final NeteaseMessageCard card;
  final DateTime time;

  @override
  Widget build(BuildContext context) => Column(
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
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
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
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) =>
                NeteaseMessageCardDetailPage(card: card, time: time),
          ),
        ),
        child: Text(card.togetherRecord ? '查看一起听记录' : '查看消息详情'),
      ),
    ],
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
              style: const TextStyle(fontSize: 16, height: 1.6),
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
                MaterialPageRoute<void>(
                  builder: (_) => _OfficialMessagePage(url: card.detailUrl!),
                ),
              ),
              child: const Text('查看网易云原始详情'),
            )
          else
            const Text('以上为平台消息中提供的记录；这条消息未附带网页详情。'),
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
