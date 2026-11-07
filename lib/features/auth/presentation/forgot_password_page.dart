import '../../../shared/widgets/artwork_scroll_frontier.dart';
import '../../../shared/widgets/music_activity_indicator.dart';
import '../../../shared/widgets/beta_text_editing.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/user_facing_error.dart';
import '../../themes/music_theme_background.dart';
import '../auth_providers.dart';
import '../domain/auth_models.dart';
import '../domain/password_policy.dart';
import 'password_visibility_button.dart';
import '../../themes/music_typography.dart';

class ForgotPasswordPage extends ConsumerStatefulWidget {
  const ForgotPasswordPage({required this.redirect, super.key});

  final String redirect;

  @override
  ConsumerState<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends ConsumerState<ForgotPasswordPage> {
  final _accountController = TextEditingController();
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  AuthMethod _method = AuthMethod.email;
  SecurityVerificationChallenge? _challenge;
  PasswordResetProof? _proof;
  Timer? _timer;
  int _countdown = 0;
  int _step = 0;
  bool _busy = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  String? _error;
  String? _message;

  @override
  void dispose() {
    _timer?.cancel();
    _accountController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    return MusicThemeBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: SizedBox(
                width: double.infinity,
                child: SingleChildScrollView(
                  physics: const ArtworkFrontierPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  padding: EdgeInsets.fromLTRB(18, topInset + 12, 18, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(
                        Icons.lock_reset_rounded,
                        size: 42,
                        color: Color(0xFFC24A34),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _step == 2 ? '密码已经更新' : '安全找回密码',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: MusicTypography.titleSize,
                          fontWeight: MusicTypography.titleWeight,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _subtitle,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          height: 1.5,
                          fontSize: MusicTypography.captionSize,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 24),
                      _RecoverySurface(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 220),
                            layoutBuilder: (current, previous) => Stack(
                              alignment: Alignment.topCenter,
                              children: [...previous, ?current],
                            ),
                            child: switch (_step) {
                              0 => _verificationStep(),
                              1 => _newPasswordStep(),
                              _ => _successStep(),
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String get _subtitle => switch (_step) {
    0 => '用已绑定的邮箱或手机号接收验证码。我们不会透露账号是否存在。',
    1 => '验证已通过。重置凭据短时有效，离开页面后不会保存。',
    _ => '全部旧登录会话已撤销，请使用新密码重新登录。',
  };

  Widget _verificationStep() {
    return Column(
      key: const ValueKey('password-recovery-verification'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _RecoveryMethodSwitcher(
          method: _method,
          enabled: !_busy,
          onChanged: _switchMethod,
        ),
        const SizedBox(height: 18),
        TextField(
          contextMenuBuilder: buildBetaEditingMenu,
          selectionControls: mestingTextSelectionControls,
          cursorRadius: const Radius.circular(1),
          key: const ValueKey('password-recovery-account'),
          controller: _accountController,
          enabled: !_busy && _challenge == null,
          keyboardType: _method == AuthMethod.email
              ? TextInputType.emailAddress
              : TextInputType.phone,
          autofillHints: _method == AuthMethod.email
              ? const [AutofillHints.email]
              : const [AutofillHints.telephoneNumber],
          decoration: InputDecoration(
            labelText: _method == AuthMethod.email ? '邮箱地址' : '手机号码',
            prefixIcon: Icon(
              _method == AuthMethod.email
                  ? Icons.alternate_email_rounded
                  : Icons.phone_iphone_rounded,
            ),
          ),
        ),
        if (_challenge != null) ...[
          const SizedBox(height: 13),
          TextField(
            contextMenuBuilder: buildBetaEditingMenu,
            selectionControls: mestingTextSelectionControls,
            cursorRadius: const Radius.circular(1),
            key: const ValueKey('password-recovery-code'),
            controller: _codeController,
            keyboardType: TextInputType.number,
            maxLength: 6,
            autofillHints: const [AutofillHints.oneTimeCode],
            decoration: const InputDecoration(
              labelText: '6 位验证码',
              counterText: '',
              prefixIcon: Icon(Icons.password_rounded),
            ),
          ),
        ],
        if (_message != null) ...[
          const SizedBox(height: 12),
          _RecoveryNotice(message: _message!),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          _RecoveryNotice(message: _error!, error: true),
        ],
        const SizedBox(height: 17),
        _RecoveryAction(
          label: _challenge == null ? '发送验证码' : '验证并继续',
          busy: _busy,
          onPressed: _challenge == null ? _requestCode : _verifyCode,
        ),
        if (_challenge != null)
          TextButton(
            onPressed: _countdown > 0 || _busy ? null : _requestCode,
            child: Text(_countdown > 0 ? '$_countdown 秒后可重新发送' : '重新发送验证码'),
          ),
      ],
    );
  }

  Widget _newPasswordStep() {
    return Column(
      key: const ValueKey('password-recovery-new-password'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          contextMenuBuilder: buildBetaEditingMenu,
          selectionControls: mestingTextSelectionControls,
          cursorRadius: const Radius.circular(1),
          key: const ValueKey('password-recovery-password'),
          controller: _passwordController,
          obscureText: _obscurePassword,
          autofillHints: const [AutofillHints.newPassword],
          decoration: InputDecoration(
            labelText: '新密码',
            prefixIcon: const Icon(Icons.lock_outline_rounded),
            suffixIcon: PasswordVisibilityButton(
              buttonKey: const ValueKey(
                'password-recovery-password-visibility',
              ),
              obscured: _obscurePassword,
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
        ),
        const SizedBox(height: 13),
        TextField(
          contextMenuBuilder: buildBetaEditingMenu,
          selectionControls: mestingTextSelectionControls,
          cursorRadius: const Radius.circular(1),
          key: const ValueKey('password-recovery-confirm'),
          controller: _confirmController,
          obscureText: _obscureConfirm,
          autofillHints: const [AutofillHints.newPassword],
          decoration: InputDecoration(
            labelText: '确认新密码',
            prefixIcon: const Icon(Icons.lock_reset_rounded),
            suffixIcon: PasswordVisibilityButton(
              buttonKey: const ValueKey('password-recovery-confirm-visibility'),
              obscured: _obscureConfirm,
              onPressed: () =>
                  setState(() => _obscureConfirm = !_obscureConfirm),
            ),
          ),
        ),
        const SizedBox(height: 13),
        const _PasswordRules(),
        if (_error != null) ...[
          const SizedBox(height: 12),
          _RecoveryNotice(message: _error!, error: true),
        ],
        const SizedBox(height: 17),
        _RecoveryAction(
          label: '更新密码并退出旧设备',
          busy: _busy,
          onPressed: _resetPassword,
        ),
      ],
    );
  }

  Widget _successStep() {
    return Column(
      key: const ValueKey('password-recovery-success'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: 76,
          height: 76,
          margin: const EdgeInsets.only(bottom: 17),
          decoration: BoxDecoration(
            color: const Color(0xFF3E9E7C).withValues(alpha: .14),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.check_rounded,
            color: Color(0xFF3E9E7C),
            size: 42,
          ),
        ),
        const Text(
          '旧密码和旧会话均已失效。为保护账号，本应用没有替你保留新密码或重置 token。',
          textAlign: TextAlign.center,
          style: TextStyle(height: 1.6, fontSize: MusicTypography.captionSize),
        ),
        const SizedBox(height: 20),
        _RecoveryAction(label: '返回登录', busy: false, onPressed: _returnToLogin),
      ],
    );
  }

  void _switchMethod(AuthMethod method) {
    if (_method == method) return;
    _timer?.cancel();
    setState(() {
      _method = method;
      _challenge = null;
      _proof = null;
      _countdown = 0;
      _error = null;
      _message = null;
      _codeController.clear();
    });
  }

  Future<void> _requestCode() async {
    if (_countdown > 0) return;
    final accountError = _validateRecoveryAccount(
      _method,
      _accountController.text,
    );
    if (accountError != null) {
      setState(() => _error = accountError);
      return;
    }
    await _guard(() async {
      final challenge = await ref
          .read(authControllerProvider.notifier)
          .requestPasswordResetCode(
            method: _method,
            account: _accountController.text,
          );
      if (!mounted) return;
      setState(() {
        _challenge = challenge;
        _codeController.clear();
        _message = '如果该账号存在，验证码已发送。请在 10 分钟内完成验证。';
      });
      _startCountdown();
    });
  }

  Future<void> _verifyCode() async {
    if (_codeController.text.trim().length != 6) {
      setState(() => _error = '请输入 6 位验证码');
      return;
    }
    await _guard(() async {
      final proof = await ref
          .read(authControllerProvider.notifier)
          .verifyPasswordResetCode(
            method: _method,
            account: _accountController.text,
            verificationId: _challenge!.verificationId,
            verificationCode: _codeController.text,
          );
      if (!mounted) return;
      _timer?.cancel();
      setState(() {
        _proof = proof;
        _step = 1;
        _countdown = 0;
        _error = null;
        _message = null;
      });
    });
  }

  Future<void> _resetPassword() async {
    final passwordError = validateAccountPassword(_passwordController.text);
    if (passwordError != null) {
      setState(() => _error = passwordError);
      return;
    }
    if (_confirmController.text != _passwordController.text) {
      setState(() => _error = '两次输入的新密码不一致');
      return;
    }
    await _guard(() async {
      await ref
          .read(authControllerProvider.notifier)
          .resetPassword(proof: _proof!, newPassword: _passwordController.text);
      if (!mounted) return;
      _passwordController.clear();
      _confirmController.clear();
      _codeController.clear();
      setState(() {
        _proof = null;
        _challenge = null;
        _step = 2;
      });
    });
  }

  Future<void> _guard(Future<void> Function() operation) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await operation();
    } on Object catch (error) {
      if (mounted) setState(() => _error = forgotPasswordErrorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _startCountdown() {
    _timer?.cancel();
    setState(() => _countdown = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _countdown <= 1) {
        timer.cancel();
        if (mounted) setState(() => _countdown = 0);
      } else {
        setState(() => _countdown -= 1);
      }
    });
  }

  void _returnToLogin() {
    final redirect = Uri.encodeComponent(widget.redirect);
    context.go('/auth?mode=login&redirect=$redirect');
  }
}

String forgotPasswordErrorMessage(Object error) {
  return userFacingErrorMessage(error, fallback: '密码重置失败，请稍后重试');
}

String? _validateRecoveryAccount(AuthMethod method, String raw) {
  final value = raw.trim();
  if (method == AuthMethod.email) {
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value)
        ? null
        : '请输入正确的邮箱地址';
  }
  return RegExp(r'^1\d{10}$').hasMatch(value) ? null : '请输入 11 位中国大陆手机号';
}

class _RecoveryMethodSwitcher extends StatelessWidget {
  const _RecoveryMethodSwitcher({
    required this.method,
    required this.enabled,
    required this.onChanged,
  });

  final AuthMethod method;
  final bool enabled;
  final ValueChanged<AuthMethod> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: AuthMethod.values
            .map(
              (value) => Expanded(
                child: InkWell(
                  key: ValueKey('recover-by-${value.name}'),
                  onTap: enabled ? () => onChanged(value) : null,
                  borderRadius: BorderRadius.circular(12),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 170),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    decoration: BoxDecoration(
                      color: method == value
                          ? Theme.of(context).colorScheme.surface
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      value.label,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: MusicTypography.titleWeight),
                    ),
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _PasswordRules extends StatelessWidget {
  const _PasswordRules();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Text(
        '8–64 位 · 可使用纯字母，也可以不含数字或符号',
        style: TextStyle(
          fontSize: MusicTypography.smallCaptionSize,
          height: 1.5,
        ),
      ),
    );
  }
}

class _RecoveryAction extends StatelessWidget {
  const _RecoveryAction({
    required this.label,
    required this.busy,
    required this.onPressed,
  });

  final String label;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: FilledButton(
        onPressed: busy ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFFC24A34),
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(
            0xFFC24A34,
          ).withValues(alpha: .56),
          disabledForegroundColor: Colors.white.withValues(alpha: .78),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(17),
          ),
        ),
        child: busy
            ? const SizedBox.square(
                dimension: 20,
                child: MusicActivityIndicator(
                  independent: true,
                  color: Colors.white,
                  strokeWidth: 2.3,
                ),
              )
            : Text(
                label,
                style: const TextStyle(fontWeight: MusicTypography.titleWeight),
              ),
      ),
    );
  }
}

class _RecoveryNotice extends StatelessWidget {
  const _RecoveryNotice({required this.message, this.error = false});

  final String message;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final color = error ? const Color(0xFFC24A34) : const Color(0xFF3E9E7C);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .11),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            error ? Icons.error_outline_rounded : Icons.info_outline_rounded,
            color: color,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: MusicTypography.smallCaptionSize,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecoverySurface extends StatelessWidget {
  const _RecoverySurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(25),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: dark
              ? const Color(0xE017141D)
              : Colors.white.withValues(alpha: .84),
          borderRadius: BorderRadius.circular(25),
          border: Border.all(
            color: Colors.white.withValues(alpha: dark ? .10 : .74),
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x17252A39),
              blurRadius: 24,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: child,
      ),
    );
  }
}
