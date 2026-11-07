import '../../../shared/widgets/music_feature_page.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../../shared/widgets/beta_glass_controls.dart';
import '../../../shared/widgets/beta_music_chrome_scope.dart';
import '../../../shared/widgets/beta_page_motion.dart';
import '../music_platform_providers.dart';
import 'qishui_api.dart';
import 'qishui_login.dart';
import 'qishui_providers.dart';

/// Only a phone/OTP flow is offered. Navigation/disposal cancels this private
/// login client, and the account controller checks liveness before publishing.
class QishuiLoginPage extends ConsumerStatefulWidget {
  const QishuiLoginPage({super.key});
  @override
  ConsumerState<QishuiLoginPage> createState() => _QishuiLoginPageState();
}

class _QishuiLoginPageState extends ConsumerState<QishuiLoginPage> {
  final _area = TextEditingController(text: '+86');
  final _phone = TextEditingController(), _code = TextEditingController();
  late final QishuiLogin _login;
  bool _sending = false, _logging = false;
  int _seconds = 0;
  Timer? _timer;
  String? _error, _verificationUrl;
  bool get _busy => _sending || _logging;
  @override
  void initState() {
    super.initState();
    _login = QishuiLogin(ref.read(qishuiApiProvider));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _login.dispose();
    _area.dispose();
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  void _failure(Object error) {
    _error = error is QishuiException ? error.message : '操作未完成，请重试；原账号已保留';
    _verificationUrl = error is QishuiVerificationRequired ? error.url : null;
  }

  Future<void> _send() async {
    if (_busy || _seconds > 0) return;
    setState(() {
      _sending = true;
      _error = null;
      _verificationUrl = null;
    });
    try {
      await _login.sendCode(_area.text, _phone.text);
      if (!mounted) return;
      setState(() => _seconds = 60);
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted || _seconds <= 1) {
          timer.cancel();
        }
        if (mounted) setState(() => _seconds = (_seconds - 1).clamp(0, 60));
      });
    } on Object catch (error) {
      if (mounted) setState(() => _failure(error));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _logging = true;
      _error = null;
      _verificationUrl = null;
    });
    try {
      final session = await _login.login(_area.text, _phone.text, _code.text);
      if (!mounted) return;
      await ref
          .read(platformAccountProvider.notifier)
          .acceptQishui(session, isCurrent: () => mounted);
      if (mounted) Navigator.of(context).pop(true);
    } on Object catch (error) {
      if (mounted) setState(() => _failure(error));
    } finally {
      if (mounted) setState(() => _logging = false);
    }
  }

  @override
  Widget build(BuildContext context) => BetaMusicChromeCover(
    child: Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const BetaGlassBackButton(),
                      const SizedBox(width: 16),
                      Text(
                        '汽水登录',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
                    child: AutofillGroup(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            '登录你的汽水账号',
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          const SizedBox(height: 12),
                          const Text('使用原有账号的手机号，验证码由汽水发送。'),
                          const SizedBox(height: 32),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width:
                                    88 +
                                    ((MediaQuery.textScalerOf(
                                                  context,
                                                ).scale(16) -
                                                16) *
                                            2)
                                        .clamp(0, 24),
                                child: BetaGlassField(
                                  child: TextField(
                                    controller: _area,
                                    enabled: !_busy,
                                    keyboardType: TextInputType.phone,
                                    decoration: const InputDecoration(
                                      labelText: '区号',
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: BetaGlassField(
                                  child: TextField(
                                    controller: _phone,
                                    enabled: !_busy,
                                    keyboardType: TextInputType.phone,
                                    autofillHints: const [
                                      AutofillHints.telephoneNumberNational,
                                    ],
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                      LengthLimitingTextInputFormatter(15),
                                    ],
                                    decoration: const InputDecoration(
                                      labelText: '手机号',
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          BetaGlassField(
                            child: TextField(
                              controller: _code,
                              enabled: !_busy,
                              keyboardType: TextInputType.number,
                              autofillHints: const [AutofillHints.oneTimeCode],
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(8),
                              ],
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) => _submit(),
                              decoration: const InputDecoration(
                                labelText: '短信验证码',
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          BetaGlassButton(
                            key: const ValueKey('qishui-send-code'),
                            loading: _sending,
                            onPressed: _busy || _seconds > 0 ? null : _send,
                            child: Text(
                              _seconds > 0 ? '${_seconds}s 后重新获取' : '获取验证码',
                            ),
                          ),
                          const SizedBox(height: 16),
                          BetaGlassButton(
                            key: const ValueKey('qishui-login'),
                            blue: true,
                            loading: _logging,
                            onPressed: _busy ? null : _submit,
                            child: const Text('登录'),
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 20),
                            Semantics(
                              liveRegion: true,
                              child: Text(
                                _error!,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ),
                          ],
                          if (_verificationUrl != null) ...[
                            const SizedBox(height: 16),
                            BetaGlassButton(
                              onPressed: _busy
                                  ? null
                                  : () => Navigator.of(context).push(
                                      betaContentRoute<void>(
                                        QishuiVerificationPage(
                                          url: _verificationUrl!,
                                        ),
                                      ),
                                    ),
                              child: const Text('完成安全验证'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// The URL must come from a genuine Passport response and pass the adapter's
/// first-party allowlist. Closing a web page does not constitute verification.
class QishuiVerificationPage extends StatefulWidget {
  const QishuiVerificationPage({required this.url, super.key});
  final String url;
  @override
  State<QishuiVerificationPage> createState() => _QishuiVerificationPageState();
}

class _QishuiVerificationPageState extends State<QishuiVerificationPage> {
  bool _loading = true;
  late final _controller = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..setNavigationDelegate(
      NavigationDelegate(
        onPageFinished: (_) {
          if (mounted) setState(() => _loading = false);
        },
        onNavigationRequest: (request) {
          final uri = Uri.tryParse(request.url);
          return uri?.scheme == 'https' &&
                  uri!.userInfo.isEmpty &&
                  (uri.host.endsWith('.douyin.com') ||
                      uri.host == 'douyin.com' ||
                      uri.host.endsWith('.snssdk.com') ||
                      uri.host.endsWith('.bytedance.com'))
              ? NavigationDecision.navigate
              : NavigationDecision.prevent;
        },
      ),
    )
    ..loadRequest(Uri.parse(widget.url));
  @override
  Widget build(BuildContext context) => BetaMusicChromeCover(
    child: MusicFeaturePage(
      title: '汽水安全验证',
      child: Column(
        children: [
          if (_loading) const LinearProgressIndicator(),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('完成后返回登录页重试；关闭本页不会视为验证成功。'),
          ),
          Expanded(child: WebViewWidget(controller: _controller)),
        ],
      ),
    ),
  );
}
