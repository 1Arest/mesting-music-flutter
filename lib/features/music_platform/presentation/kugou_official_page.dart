import '../../../core/network/system_music_io_client.dart';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:webview_flutter/webview_flutter.dart';

import '../../../shared/widgets/beta_glass_controls.dart';
import '../../../shared/widgets/beta_music_chrome_scope.dart';
import '../../../shared/widgets/beta_page_motion.dart';
import '../../../core/platform/share_bridge.dart';
import '../data/kugou_official_api.dart';
import '../data/kugou_official_web_contract.dart';
import '../domain/platform_session.dart';
import '../kugou_listening_profile_providers.dart';
import '../music_platform_providers.dart';
import 'kugou_standard_authorization_page.dart';
import '../../themes/music_typography.dart';

Future<void> openKugouOfficialPage(
  BuildContext context,
  WidgetRef ref,
  PlatformSession owner,
  Uri uri,
) async {
  if (!KugouOfficialWebContract.accepts(uri)) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('这个入口暂不能在 Mesting 中打开')));
    return;
  }
  await Navigator.of(
    context,
  ).push<void>(betaContentRoute(KugouOfficialPage(owner: owner, uri: uri)));
}

/// 官方规则、徽章详情和佩戴页复用官版提供的真实网页。
/// 每一份新主文档先由有界HTTP读取并校验重定向，再植入当前账号桥接。
/// 不把账号拼在URL，也不让支付或外部页面继承它。
class KugouOfficialPage extends ConsumerStatefulWidget {
  const KugouOfficialPage({required this.owner, required this.uri, super.key});
  final PlatformSession owner;
  final Uri uri;
  @override
  ConsumerState<KugouOfficialPage> createState() => _KugouOfficialPageState();
}

class _KugouOfficialPageState extends ConsumerState<KugouOfficialPage> {
  WebViewController? _web;
  http.Client? _client;
  Uri? _document;
  int _epoch = 0;
  bool _loading = true, _revoked = false;
  String? _error;
  final _history = <Uri>[];

  bool get _current {
    if (!mounted || _revoked) return false;
    final value = ref.read(platformAccountProvider).value;
    return mounted &&
        !_revoked &&
        value?.platform == MusicPlatform.kugou &&
        value?.userId == widget.owner.userId &&
        value?.token == widget.owner.token &&
        value?.kugouStandardToken == widget.owner.kugouStandardToken;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load(widget.uri));
  }

  Future<void> _revoke() async {
    _revoked = true;
    _epoch++;
    _client?.close();
    final web = _web;
    if (web == null) return;
    try {
      await web.runJavaScript('window.__mestingKugouRevoke?.()');
      await web.removeJavaScriptChannel('MestingKugou');
      await web.loadHtmlString('<!doctype html><html></html>');
      await web.clearLocalStorage();
      await web.clearCache();
    } catch (_) {
      // 原生视图可能已经释放；页面先同步撤下，不再显示任何旧账号内容。
    }
  }

  Future<(Uri, String)> _html(http.Client client, Uri start) async {
    var uri = start;
    for (var hop = 0; hop < 4; hop++) {
      if (!KugouOfficialWebContract.accepts(uri)) {
        throw const KugouOfficialException('这个入口暂不能在 Mesting 中打开');
      }
      final request = http.Request('GET', uri)..followRedirects = false;
      request.headers.addAll({
        'Accept': 'text/html',
        'Cache-Control': 'no-store',
      });
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 15));
      if ({301, 302, 303, 307, 308}.contains(response.statusCode)) {
        final location = response.headers['location'];
        await response.stream.drain<void>();
        if (location == null) break;
        uri = uri.resolve(location);
        continue;
      }
      if (response.statusCode != 200 ||
          !(response.headers['content-type'] ?? '').contains('text/html')) {
        break;
      }
      final bytes = <int>[];
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 15),
      )) {
        bytes.addAll(chunk);
        if (bytes.length > 4 * 1024 * 1024) throw const FormatException();
      }
      return (uri, utf8.decode(bytes));
    }
    throw const KugouOfficialException('官方页面读取失败，请稍后重试');
  }

  Future<void> _load(Uri uri, {bool remember = true}) async {
    if (!_current) return;
    final epoch = ++_epoch;
    _client?.close();
    final client = _client = SystemMusicIoClient();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(musicPlatformApiProvider);
      final reader = ref.read(kugouListeningProfileReaderProvider);
      // 已有等级成功快照可以直接提供给官方页面，避免重复读取。
      final values = await Future.wait<Object>([
        _html(client, uri),
        KugouOfficialApi.registeredDevice(api),
      ]);
      if (!_current || epoch != _epoch) return;
      final (resolved, html) = values[0] as (Uri, String);
      final device = values[1] as Map<String, String>;
      final bridge = KugouOfficialWebContract.bootstrap(
        session: widget.owner,
        device: device,
        grade: reader?.grade.value?.raw ?? const {},
      );
      final previous = _document;
      if (remember && previous != null && previous != resolved) {
        _history.add(previous);
      }
      _document = resolved;
      final web = _web ??= WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..addJavaScriptChannel('MestingKugou', onMessageReceived: _message)
        ..setNavigationDelegate(
          NavigationDelegate(
            onNavigationRequest: (request) {
              if (!request.isMainFrame) return NavigationDecision.navigate;
              final next = Uri.tryParse(request.url);
              if (next?.scheme == 'about' || next?.scheme == 'data') {
                return NavigationDecision.navigate;
              }
              if (!_current ||
                  next == null ||
                  !KugouOfficialWebContract.accepts(next)) {
                return NavigationDecision.prevent;
              }
              if (next.replace(fragment: '') ==
                  _document?.replace(fragment: '')) {
                return NavigationDecision.navigate;
              }
              unawaited(_load(next));
              return NavigationDecision.prevent;
            },
            onPageFinished: (_) {
              if (mounted && _current) setState(() => _loading = false);
            },
            onWebResourceError: (error) {
              if (error.isForMainFrame == true && mounted && _current) {
                setState(() {
                  _loading = false;
                  _error = '官方页面加载失败，请重试';
                });
              }
            },
          ),
        );
      await web.loadHtmlString(
        KugouOfficialWebContract.inject(html, bridge),
        baseUrl: resolved.toString(),
      );
    } catch (error) {
      if (_current && epoch == _epoch) {
        setState(() {
          _loading = false;
          _error = error is KugouOfficialException
              ? error.message
              : '官方页面加载失败，请检查网络后重试';
        });
      }
    } finally {
      client.close();
    }
  }

  void _message(JavaScriptMessage message) {
    if (!_current || message.message.length > 8192) return;
    try {
      final value = jsonDecode(message.message);
      if (value is! Map) return;
      final data = value['data'];
      if (value['cmd'] == 158) {
        Navigator.of(context).maybePop();
      } else if (value['cmd'] == 123 && data is Map) {
        final uri = Uri.tryParse('${data['url'] ?? data['URL'] ?? ''}');
        if (uri != null && KugouOfficialWebContract.accepts(uri)) {
          unawaited(_load(uri));
        }
      } else if (value['cmd'] == 102) {
        unawaited(openKugouStandardAuthorization(context, widget.owner));
      } else if (value['cmd'] == 115) {
        unawaited(_share());
      }
    } catch (_) {
      // 不信任网页消息，不执行任意JS或返回敏感资料。
    }
  }

  Future<void> _back() async {
    if (_history.isNotEmpty && _current) {
      await _load(_history.removeLast(), remember: false);
    } else if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _share() async {
    final uri = _document;
    if (!_current || uri == null || !KugouOfficialWebContract.accepts(uri)) {
      return;
    }
    try {
      await ShareBridge.shareText(uri.toString(), title: '酷狗官方详情');
    } catch (_) {
      if (mounted && _current) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('分享暂未打开，请稍后重试')));
      }
    }
  }

  @override
  void dispose() {
    unawaited(_revoke());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(platformAccountProvider, (_, next) {
      if (next.value?.userId != widget.owner.userId ||
          next.value?.token != widget.owner.token ||
          next.value?.kugouStandardToken != widget.owner.kugouStandardToken ||
          next.value?.platform != MusicPlatform.kugou) {
        unawaited(_revoke());
        if (mounted) {
          setState(() {
            _error = '账号已变化，请返回后重新打开';
            _loading = false;
          });
        }
      }
    });
    return PopScope(
      canPop: _history.isEmpty,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_back());
      },
      child: BetaMusicChromeCover(
        child: Scaffold(
          backgroundColor: Theme.of(context).colorScheme.surface,
          body: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 12, 12, 12),
                  child: Row(
                    children: [
                      BetaGlassBackButton(onPressed: _back),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Text(
                          '酷狗官方详情',
                          style: TextStyle(
                            fontSize: MusicTypography.sectionTitleSize,
                            fontWeight: MusicTypography.titleWeight,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: '分享',
                        onPressed: _revoked || _document == null
                            ? null
                            : _share,
                        icon: const Icon(Icons.ios_share),
                      ),
                      IconButton(
                        tooltip: '刷新',
                        onPressed: _loading || _revoked
                            ? null
                            : () => _load(
                                _document ?? widget.uri,
                                remember: false,
                              ),
                        icon: const Icon(Icons.refresh),
                      ),
                    ],
                  ),
                ),
                if (_loading) const LinearProgressIndicator(minHeight: 2),
                Expanded(
                  child: _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(_error!, textAlign: TextAlign.center),
                                if (!_revoked)
                                  TextButton(
                                    onPressed: () => _load(
                                      _document ?? widget.uri,
                                      remember: false,
                                    ),
                                    child: const Text('重试'),
                                  ),
                              ],
                            ),
                          ),
                        )
                      : _web == null
                      ? const Center(child: BetaActivityIndicator())
                      : WebViewWidget(controller: _web!),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
