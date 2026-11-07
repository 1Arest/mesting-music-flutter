import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../shared/widgets/beta_glass_controls.dart';
import '../../../shared/widgets/beta_music_chrome_scope.dart';
import '../music_platform_providers.dart';
import 'qishui_api.dart';
import 'qishui_qr_login.dart';

final qishuiQrLoginFactoryProvider = Provider<QishuiQrLogin Function()>(
  (ref) =>
      () => QishuiQrLogin(const AndroidQishuiQrGateway()),
);

/// UI owns the transaction's lifetime, not its protocol. Switching to Qishui
/// pauses polling without cancelling the QR; leaving this route cancels it.
class QishuiQrLoginPage extends ConsumerStatefulWidget {
  const QishuiQrLoginPage({super.key});
  @override
  ConsumerState<QishuiQrLoginPage> createState() => _QishuiQrLoginPageState();
}

class _QishuiQrLoginPageState extends ConsumerState<QishuiQrLoginPage>
    with WidgetsBindingObserver {
  QishuiQrLogin? _login;
  QishuiQrStatus? _status;
  Timer? _timer;
  String? _error;
  bool _loading = true, _busy = false, _foreground = true;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_start());
  }

  @override
  void dispose() {
    ++_generation;
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    final login = _login;
    if (login != null) unawaited(login.close());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _timer?.cancel();
    if (_foreground && !_loading && !_busy && _error == null) {
      unawaited(_poll());
    }
  }

  Future<void> _start() async {
    final generation = ++_generation;
    _timer?.cancel();
    final old = _login;
    setState(() {
      _loading = true;
      _busy = false;
      _error = null;
      _status = null;
      _login = null;
    });
    await old?.close();
    if (!mounted || generation != _generation) return;
    final login = ref.read(qishuiQrLoginFactoryProvider)();
    _login = login;
    try {
      await login.start();
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _status = const QishuiQrStatus(QishuiQrPhase.waiting, '等待汽水音乐扫码');
      });
      _schedule();
    } on Object catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _loading = false;
          _error = _message(error);
        });
      }
    }
  }

  String _message(Object error) =>
      error is QishuiException ? error.message : '扫码登录未完成，请重试；原账号已保留';

  Future<void> _openScanner() async {
    final login = _login;
    if (login == null || _loading || _busy) return;
    try {
      final opened = await login.openScanner();
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('未找到可用的汽水扫一扫，请安装或更新汽水音乐官方App')),
        );
      }
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_message(error))));
      }
    }
  }

  void _schedule() {
    _timer?.cancel();
    if (!mounted ||
        !_foreground ||
        _error != null ||
        _status?.phase == QishuiQrPhase.expired ||
        _status?.phase == QishuiQrPhase.verificationRequired) {
      return;
    }
    _timer = Timer(const Duration(seconds: 3), () => unawaited(_poll()));
  }

  Future<void> _poll({bool verify = false}) async {
    final login = _login, generation = _generation;
    if (_busy || _loading || login == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final status = verify ? await login.verify() : await login.poll();
      if (!mounted || generation != _generation) return;
      setState(() => _status = status);
      final session = status.session;
      if (session != null) {
        await ref
            .read(platformAccountProvider.notifier)
            .acceptQishui(
              session,
              isCurrent: () => mounted && generation == _generation,
            );
        if (mounted && generation == _generation) {
          Navigator.of(context).pop(true);
        }
      }
    } on Object catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = _message(error));
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _busy = false);
        _schedule();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final url = _login?.scanUrl ?? '';
    final expired = _status?.phase == QishuiQrPhase.expired;
    return BetaMusicChromeCover(
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
                        Expanded(
                          child: Text(
                            '汽水扫码登录',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            '登录原有汽水账号',
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          const SizedBox(height: 12),
                          const Text('请使用已登录原有账号的「汽水音乐官方App」扫一扫，并在汽水音乐中确认登录。'),
                          const SizedBox(height: 24),
                          Center(
                            child: Semantics(
                              label: expired
                                  ? '汽水登录二维码已过期'
                                  : '汽水登录二维码，请使用汽水音乐扫一扫',
                              child: ExcludeSemantics(
                                child: Container(
                                  constraints: const BoxConstraints(
                                    maxWidth: 264,
                                  ),
                                  padding: const EdgeInsets.all(16),
                                  color: Colors.white,
                                  child: AspectRatio(
                                    aspectRatio: 1,
                                    child: _loading
                                        ? const Center(
                                            child: CircularProgressIndicator(),
                                          )
                                        : url.isEmpty || expired
                                        ? Icon(
                                            expired
                                                ? Icons.timer_off_outlined
                                                : Icons.qr_code_2,
                                            size: 72,
                                            color: Colors.black54,
                                          )
                                        : QrImageView(
                                            data: url,
                                            backgroundColor: Colors.white,
                                            padding: EdgeInsets.zero,
                                          ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Semantics(
                            liveRegion: true,
                            child: Text(
                              _loading
                                  ? '正在生成登录二维码…'
                                  : _error ?? _status?.message ?? '等待汽水音乐扫码',
                              textAlign: TextAlign.center,
                              style: _error == null
                                  ? null
                                  : TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.error,
                                    ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          if (_status?.phase ==
                              QishuiQrPhase.verificationRequired)
                            BetaGlassButton(
                              key: const ValueKey('qishui-qr-verify'),
                              blue: true,
                              loading: _busy,
                              onPressed: _busy
                                  ? null
                                  : () => _poll(verify: true),
                              child: const Text('完成安全验证'),
                            ),
                          if (_status?.phase ==
                              QishuiQrPhase.verificationRequired)
                            const SizedBox(height: 12),
                          if (_error != null && url.isNotEmpty && !expired) ...[
                            BetaGlassButton(
                              onPressed: _busy ? null : () => _poll(),
                              child: const Text('重试查询'),
                            ),
                            const SizedBox(height: 12),
                          ],
                          if (url.isNotEmpty && !expired) ...[
                            const Text('同一部手机请先截图保存二维码，再打开汽水扫一扫，从相册选择截图。'),
                            const SizedBox(height: 12),
                            BetaGlassButton(
                              key: const ValueKey('qishui-qr-open-scanner'),
                              onPressed: _busy ? null : _openScanner,
                              child: const Text('打开汽水扫一扫'),
                            ),
                            const SizedBox(height: 12),
                          ],
                          BetaGlassButton(
                            key: const ValueKey('qishui-qr-refresh'),
                            onPressed: _loading || _busy ? null : _start,
                            child: const Text('重新生成二维码'),
                          ),
                          const SizedBox(height: 20),
                          const Text('请勿将登录二维码发送给他人。'),
                          const SizedBox(height: 12),
                          const Text('部分汽水功能尚未适配扫码会话，会在操作时说明。'),
                        ],
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
}
