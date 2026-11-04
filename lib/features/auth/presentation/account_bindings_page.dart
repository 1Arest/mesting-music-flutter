import '../../../shared/widgets/music_activity_indicator.dart';
import '../../../shared/widgets/beta_text_editing.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/user_facing_error.dart';
import '../../../shared/widgets/liquid_glass_sheet.dart';
import '../../themes/music_theme_background.dart';
import '../auth_providers.dart';
import '../domain/auth_models.dart';

class AccountBindingsPage extends ConsumerStatefulWidget {
  const AccountBindingsPage({super.key});

  @override
  ConsumerState<AccountBindingsPage> createState() =>
      _AccountBindingsPageState();
}

class _AccountBindingsPageState extends ConsumerState<AccountBindingsPage> {
  AuthUser? _cachedUser;
  String? _status;
  String? _refreshError;

  @override
  void initState() {
    super.initState();
    _cachedUser = ref.read(currentUserProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    final success = await ref
        .read(authControllerProvider.notifier)
        .refreshAccount();
    if (!mounted) return;
    setState(() {
      _cachedUser = ref.read(currentUserProvider) ?? _cachedUser;
      _refreshError = success
          ? null
          : userFacingErrorMessage(
              ref.read(authControllerProvider.notifier).lastError,
              fallback: '无法刷新绑定状态，请稍后重试',
            );
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final user = auth.value?.user ?? _cachedUser;
    if (user != null) _cachedUser = user;
    final topInset = MediaQuery.paddingOf(context).top;
    return MusicThemeBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: ListView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.fromLTRB(16, topInset + 12, 16, 150),
          children: [
            _SecurityHeader(
              onBack: () =>
                  context.canPop() ? context.pop() : context.go('/profile'),
            ),
            const SizedBox(height: 22),
            const Text(
              '登录方式',
              style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 7),
            Text(
              '绑定信息直接读取自云端账号。更换联系方式前，需要先验证当前身份。',
              style: TextStyle(
                height: 1.5,
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            if (_refreshError != null) ...[
              const SizedBox(height: 14),
              _InlineNotice(
                message: _refreshError!,
                error: true,
                actionLabel: '重试',
                onAction: _refresh,
              ),
            ],
            if (_status != null) ...[
              const SizedBox(height: 14),
              _InlineNotice(message: _status!),
            ],
            const SizedBox(height: 18),
            if (user == null)
              const _SecuritySurface(
                child: Padding(
                  padding: EdgeInsets.all(22),
                  child: Text('登录状态已失效，请返回登录后重试。'),
                ),
              )
            else ...[
              _BindingCard(
                method: AuthMethod.email,
                maskedValue: user.emailMasked,
                onTap: () => _openBindingFlow(user, AuthMethod.email),
              ),
              const SizedBox(height: 12),
              _BindingCard(
                method: AuthMethod.phone,
                maskedValue: user.phoneMasked,
                onTap: () => _openBindingFlow(user, AuthMethod.phone),
              ),
              const SizedBox(height: 18),
              _SecuritySurface(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _IconBadge(
                        icon: Icons.shield_outlined,
                        color: Color(0xFF4BA77E),
                      ),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '至少保留一种登录方式',
                              style: TextStyle(fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              '这里仅支持安全绑定与换绑，不提供移除最后一种登录方式的入口。验证令牌只保存在当前页面内存中。',
                              style: TextStyle(
                                height: 1.5,
                                fontSize: 11,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _openBindingFlow(AuthUser user, AuthMethod method) async {
    final changed = await showLiquidGlassBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      useRootNavigator: true,
      showDragHandle: true,
      barrierColor: Colors.black.withValues(alpha: .46),
      builder: (context) => _BindingFlowSheet(user: user, method: method),
    );
    if (changed != true || !mounted) return;
    setState(() {
      _cachedUser = ref.read(currentUserProvider) ?? _cachedUser;
      _status = '${method.label}已安全更新';
      _refreshError = null;
    });
  }
}

class _BindingFlowSheet extends ConsumerStatefulWidget {
  const _BindingFlowSheet({required this.user, required this.method});

  final AuthUser user;
  final AuthMethod method;

  @override
  ConsumerState<_BindingFlowSheet> createState() => _BindingFlowSheetState();
}

class _BindingFlowSheetState extends ConsumerState<_BindingFlowSheet> {
  final _accountController = TextEditingController();
  final _codeController = TextEditingController();
  Timer? _timer;
  int _countdown = 0;
  int _step = 0;
  bool _busy = false;
  String? _error;
  SecurityVerificationChallenge? _challenge;
  String? _sudoToken;

  AuthMethod get _identityMethod {
    if (widget.method == AuthMethod.email && widget.user.hasPhoneBinding) {
      return AuthMethod.phone;
    }
    if (widget.method == AuthMethod.phone && widget.user.hasEmailBinding) {
      return AuthMethod.email;
    }
    return widget.method;
  }

  String get _identityTarget => _identityMethod == AuthMethod.email
      ? widget.user.emailMasked ?? ''
      : widget.user.phoneMasked ?? '';

  @override
  void dispose() {
    _timer?.cancel();
    _accountController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final existing = widget.method == AuthMethod.email
        ? widget.user.hasEmailBinding
        : widget.user.hasPhoneBinding;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 12),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: media.size.height * .82),
          child: SingleChildScrollView(
            key: const ValueKey('account-binding-flow-sheet'),
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
            physics: const BouncingScrollPhysics(),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                Text(
                  _step == 0
                      ? '先确认是你本人'
                      : '${existing ? '更换' : '绑定'}${widget.method.label}',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  _step == 0
                      ? '验证码将发送到当前已绑定的${_identityMethod.label} $_identityTarget。'
                      : '新${widget.method.label}验证成功后会立即成为可用登录方式。',
                  style: TextStyle(
                    height: 1.5,
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 18),
                _StepRail(active: _step),
                const SizedBox(height: 20),
                if (_step == 0) _identityStep() else _newBindingStep(),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  _InlineNotice(message: _error!, error: true),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _identityStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_challenge != null) ...[
          _CodeField(controller: _codeController),
          const SizedBox(height: 12),
        ],
        _PrimaryAction(
          label: _challenge == null ? '发送当前身份验证码' : '验证当前身份',
          busy: _busy,
          onPressed: _challenge == null
              ? _requestIdentityCode
              : _verifyIdentity,
        ),
        if (_challenge != null)
          _ResendButton(
            countdown: _countdown,
            busy: _busy,
            onPressed: _requestIdentityCode,
          ),
      ],
    );
  }

  Widget _newBindingStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          contextMenuBuilder: buildBetaEditingMenu,
          selectionControls: mestingTextSelectionControls,
          cursorRadius: const Radius.circular(1),
          controller: _accountController,
          enabled: !_busy,
          keyboardType: widget.method == AuthMethod.email
              ? TextInputType.emailAddress
              : TextInputType.phone,
          autofillHints: widget.method == AuthMethod.email
              ? const [AutofillHints.email]
              : const [AutofillHints.telephoneNumber],
          decoration: InputDecoration(
            labelText: '新${widget.method.label}',
            prefixIcon: Icon(
              widget.method == AuthMethod.email
                  ? Icons.alternate_email_rounded
                  : Icons.phone_iphone_rounded,
            ),
          ),
        ),
        if (_challenge != null) ...[
          const SizedBox(height: 12),
          _CodeField(controller: _codeController),
        ],
        const SizedBox(height: 14),
        _PrimaryAction(
          label: _challenge == null ? '发送新${widget.method.label}验证码' : '确认安全更新',
          busy: _busy,
          onPressed: _challenge == null ? _requestNewCode : _completeBinding,
        ),
        if (_challenge != null)
          _ResendButton(
            countdown: _countdown,
            busy: _busy,
            onPressed: _requestNewCode,
          ),
      ],
    );
  }

  Future<void> _requestIdentityCode() async {
    if (_countdown > 0) return;
    await _guard(() async {
      final challenge = await ref
          .read(authControllerProvider.notifier)
          .requestCurrentIdentityCode(method: _identityMethod);
      if (!mounted) return;
      setState(() {
        _challenge = challenge;
        _codeController.clear();
      });
      _startCountdown();
    });
  }

  Future<void> _verifyIdentity() async {
    if (_codeController.text.trim().length != 6) {
      setState(() => _error = '请输入 6 位验证码');
      return;
    }
    await _guard(() async {
      final token = await ref
          .read(authControllerProvider.notifier)
          .verifyCurrentIdentity(
            verificationId: _challenge!.verificationId,
            verificationCode: _codeController.text,
          );
      if (!mounted) return;
      _timer?.cancel();
      setState(() {
        _sudoToken = token;
        _step = 1;
        _challenge = null;
        _countdown = 0;
        _codeController.clear();
      });
    });
  }

  Future<void> _requestNewCode() async {
    if (_countdown > 0) return;
    final accountError = _validateAccount(
      widget.method,
      _accountController.text,
    );
    if (accountError != null) {
      setState(() => _error = accountError);
      return;
    }
    await _guard(() async {
      final challenge = await ref
          .read(authControllerProvider.notifier)
          .requestBindingCode(
            method: widget.method,
            account: _accountController.text,
          );
      if (!mounted) return;
      setState(() {
        _challenge = challenge;
        _codeController.clear();
      });
      _startCountdown();
    });
  }

  Future<void> _completeBinding() async {
    if (_codeController.text.trim().length != 6) {
      setState(() => _error = '请输入 6 位验证码');
      return;
    }
    await _guard(() async {
      final success = await ref
          .read(authControllerProvider.notifier)
          .bindCredential(
            method: widget.method,
            account: _accountController.text,
            verificationId: _challenge!.verificationId,
            verificationCode: _codeController.text,
            sudoToken: _sudoToken!,
          );
      if (!success) {
        throw AuthRequestException(
          userFacingErrorMessage(
            ref.read(authControllerProvider.notifier).lastError,
            fallback: '安全更新失败，请重试',
          ),
        );
      }
      if (mounted) Navigator.of(context).pop(true);
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
      if (mounted) {
        setState(
          () => _error = userFacingErrorMessage(
            error,
            fallback: '账号绑定操作失败，请稍后重试',
          ),
        );
      }
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
}

String? _validateAccount(AuthMethod method, String raw) {
  final value = raw.trim();
  if (method == AuthMethod.email) {
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value)
        ? null
        : '请输入正确的邮箱地址';
  }
  return RegExp(r'^1\d{10}$').hasMatch(value) ? null : '请输入 11 位中国大陆手机号';
}

class _SecurityHeader extends StatelessWidget {
  const _SecurityHeader({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        InkWell(
          key: const ValueKey('account-bindings-back'),
          onTap: onBack,
          borderRadius: BorderRadius.circular(15),
          child: Ink(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.surface.withValues(alpha: .78),
              borderRadius: BorderRadius.circular(15),
            ),
            child: const Icon(Icons.arrow_back_rounded),
          ),
        ),
        const Spacer(),
        const Icon(Icons.lock_person_outlined, color: Color(0xFF4BA77E)),
      ],
    );
  }
}

class _BindingCard extends StatelessWidget {
  const _BindingCard({
    required this.method,
    required this.maskedValue,
    required this.onTap,
  });

  final AuthMethod method;
  final String? maskedValue;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bound = maskedValue?.trim().isNotEmpty == true;
    final color = method == AuthMethod.email
        ? const Color(0xFF7567D8)
        : const Color(0xFF3E9E7C);
    return _SecuritySurface(
      child: InkWell(
        key: ValueKey('manage-${method.name}-binding'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.all(17),
          child: Row(
            children: [
              _IconBadge(
                icon: method == AuthMethod.email
                    ? Icons.mail_outline_rounded
                    : Icons.phone_iphone_rounded,
                color: color,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      method.label,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      bound ? maskedValue! : '尚未绑定',
                      style: TextStyle(
                        fontSize: 12,
                        color: bound
                            ? Theme.of(context).colorScheme.onSurfaceVariant
                            : const Color(0xFFC24A34),
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                bound ? '更换' : '绑定',
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded, color: color),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepRail extends StatelessWidget {
  const _StepRail({required this.active});

  final int active;

  @override
  Widget build(BuildContext context) {
    final palette = _BindingFlowPalette.of(context);
    return Row(
      children: [
        _StepDot(label: '1', title: '验证当前身份', active: active == 0),
        Expanded(
          child: Container(
            height: 2,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            color: active == 1 ? palette.completedRail : palette.idleRail,
          ),
        ),
        _StepDot(label: '2', title: '验证新联系方式', active: active == 1),
      ],
    );
  }
}

class _BindingFlowPalette {
  const _BindingFlowPalette({
    required this.primary,
    required this.onPrimary,
    required this.inactiveSurface,
    required this.inactiveBorder,
    required this.idleRail,
    required this.completedRail,
  });

  factory _BindingFlowPalette.of(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _BindingFlowPalette(
      primary: scheme.primary,
      onPrimary: scheme.onPrimary,
      inactiveSurface: Color.alphaBlend(
        scheme.primary.withValues(alpha: .10),
        scheme.surface,
      ),
      inactiveBorder: scheme.primary.withValues(alpha: .18),
      idleRail: scheme.primary.withValues(alpha: .16),
      completedRail: scheme.primary.withValues(alpha: .58),
    );
  }

  final Color primary;
  final Color onPrimary;
  final Color inactiveSurface;
  final Color inactiveBorder;
  final Color idleRail;
  final Color completedRail;
}

class _StepDot extends StatelessWidget {
  const _StepDot({
    required this.label,
    required this.title,
    required this.active,
  });

  final String label;
  final String title;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final palette = _BindingFlowPalette.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active ? palette.primary : palette.inactiveSurface,
            border: Border.all(
              color: active ? palette.primary : palette.inactiveBorder,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: active ? palette.onPrimary : palette.primary,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          title,
          style: TextStyle(
            color: active ? scheme.onSurface : scheme.onSurfaceVariant,
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}

class _CodeField extends StatelessWidget {
  const _CodeField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return TextField(
      contextMenuBuilder: buildBetaEditingMenu,
      selectionControls: mestingTextSelectionControls,
      cursorRadius: const Radius.circular(1),
      controller: controller,
      keyboardType: TextInputType.number,
      maxLength: 6,
      autofillHints: const [AutofillHints.oneTimeCode],
      decoration: const InputDecoration(
        labelText: '6 位验证码',
        counterText: '',
        prefixIcon: Icon(Icons.password_rounded),
      ),
    );
  }
}

class _PrimaryAction extends StatelessWidget {
  const _PrimaryAction({
    required this.label,
    required this.busy,
    required this.onPressed,
  });

  final String label;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = _BindingFlowPalette.of(context);
    return SizedBox(
      height: 52,
      child: FilledButton(
        onPressed: busy ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: palette.primary,
          foregroundColor: palette.onPrimary,
          disabledBackgroundColor: palette.primary.withValues(alpha: .38),
          disabledForegroundColor: palette.onPrimary.withValues(alpha: .72),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(17),
          ),
        ),
        child: busy
            ? SizedBox.square(
                dimension: 20,
                child: MusicActivityIndicator(
                  independent: true,
                  color: palette.onPrimary,
                  strokeWidth: 2.3,
                ),
              )
            : Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
      ),
    );
  }
}

class _ResendButton extends StatelessWidget {
  const _ResendButton({
    required this.countdown,
    required this.busy,
    required this.onPressed,
  });

  final int countdown;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: countdown > 0 || busy ? null : onPressed,
      child: Text(countdown > 0 ? '$countdown 秒后可重新发送' : '重新发送验证码'),
    );
  }
}

class _InlineNotice extends StatelessWidget {
  const _InlineNotice({
    required this.message,
    this.error = false,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final bool error;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final color = error ? const Color(0xFFC24A34) : const Color(0xFF3E9E7C);
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 11, 10, 11),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .11),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(
            error ? Icons.error_outline_rounded : Icons.check_circle_outline,
            color: color,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(message, style: const TextStyle(fontSize: 11))),
          if (actionLabel != null)
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ),
    );
  }
}

class _SecuritySurface extends StatelessWidget {
  const _SecuritySurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final borderRadius = BorderRadius.circular(22);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: const [
          BoxShadow(
            color: Color(0x12252A39),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: dark
            ? const Color(0xE017141D)
            : Colors.white.withValues(alpha: .82),
        shape: RoundedRectangleBorder(
          borderRadius: borderRadius,
          side: BorderSide(
            color: Colors.white.withValues(alpha: dark ? .10 : .72),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
      ),
    );
  }
}

class _IconBadge extends StatelessWidget {
  const _IconBadge({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 43,
      height: 43,
      decoration: BoxDecoration(
        color: color.withValues(alpha: .13),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(icon, color: color, size: 22),
    );
  }
}
