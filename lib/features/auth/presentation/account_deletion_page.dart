import '../../../shared/widgets/artwork_scroll_frontier.dart';
import '../../../shared/widgets/beta_content_insets.dart';
import '../../../shared/widgets/music_activity_indicator.dart';
import '../../../shared/widgets/beta_text_editing.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/user_facing_error.dart';
import '../../../shared/widgets/music_notice.dart';
import '../../themes/music_theme_background.dart';
import '../../themes/music_theme_tokens.dart';
import '../auth_providers.dart';
import '../domain/auth_models.dart';
import '../../themes/music_typography.dart';

class AccountDeletionPage extends ConsumerStatefulWidget {
  const AccountDeletionPage({super.key});

  @override
  ConsumerState<AccountDeletionPage> createState() =>
      _AccountDeletionPageState();
}

class _AccountDeletionPageState extends ConsumerState<AccountDeletionPage> {
  final _codeController = TextEditingController();
  final _confirmationController = TextEditingController();
  SecurityVerificationChallenge? _challenge;
  String? _sudoToken;
  String? _error;
  bool _busy = false;
  int _countdown = 0;
  Timer? _timer;
  AuthMethod? _selectedMethod;

  AuthMethod? _identityMethodFor(AuthUser? user) {
    if (user == null) return null;
    if (user.hasEmailBinding && user.hasPhoneBinding) {
      return _selectedMethod ?? AuthMethod.email;
    }
    if (user.hasEmailBinding) return AuthMethod.email;
    if (user.hasPhoneBinding) return AuthMethod.phone;
    return null;
  }

  AuthMethod? get _identityMethod =>
      _identityMethodFor(ref.read(currentUserProvider));

  String get _maskedTarget {
    final user = ref.read(currentUserProvider);
    return _identityMethod == AuthMethod.email
        ? user?.emailMasked ?? ''
        : user?.phoneMasked ?? '';
  }

  @override
  void dispose() {
    _timer?.cancel();
    _codeController.dispose();
    _confirmationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final topInset = MediaQuery.paddingOf(context).top;
    final method = _identityMethodFor(user);
    final verified = _sudoToken != null;
    final canDelete =
        verified && _confirmationController.text.trim() == '注销' && !_busy;

    return MusicThemeBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          bottom: false,
          child: ListView(
            physics: const ArtworkFrontierPhysics(
              parent: BouncingScrollPhysics(),
            ),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: BetaContentInsets.musicPaddingOf(
              context,
              EdgeInsets.fromLTRB(16, topInset + 8, 16, 164),
            ),
            children: [
              _Header(
                onBack: () => context.canPop()
                    ? context.pop()
                    : context.go('/music/settings'),
              ),
              const SizedBox(height: 24),
              const Icon(
                Icons.delete_forever_rounded,
                color: Color(0xFFC24A34),
                size: 34,
              ),
              const SizedBox(height: 14),
              const Text(
                '注销账号',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: MusicTypography.titleSize,
                  fontWeight: MusicTypography.titleWeight,
                ),
              ),
              const SizedBox(height: 9),
              Text(
                '此操作不可恢复。请确认这是你本人，并在最后一步输入“注销”后才会执行。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  height: 1.55,
                  fontSize: MusicTypography.footnoteSize,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 22),
              const _DeletionScopeCard(),
              const SizedBox(height: 16),
              if (user == null || method == null)
                const _DeletionSurface(
                  child: Padding(
                    padding: EdgeInsets.all(18),
                    child: Text('登录状态或账号绑定信息已失效，请重新登录后再试。'),
                  ),
                )
              else ...[
                _StepLabel(active: !verified, number: '1', label: '验证当前身份'),
                const SizedBox(height: 10),
                _DeletionSurface(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (user.hasEmailBinding && user.hasPhoneBinding)
                          _MethodPicker(
                            selected: method,
                            enabled: !_busy && !verified,
                            onSelected: (value) {
                              if (value == method) return;
                              _timer?.cancel();
                              setState(() {
                                _selectedMethod = value;
                                _challenge = null;
                                _codeController.clear();
                                _countdown = 0;
                                _error = null;
                              });
                            },
                          ),
                        Text(
                          verified
                              ? '当前身份已验证。验证凭证只在本次操作中短时有效。'
                              : '验证码将发送到已绑定的${method.label} $_maskedTarget。',
                          style: TextStyle(
                            height: 1.5,
                            fontSize: MusicTypography.captionSize,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (!verified && _challenge != null) ...[
                          const SizedBox(height: 14),
                          TextField(
                            contextMenuBuilder: buildBetaEditingMenu,
                            selectionControls: mestingTextSelectionControls,
                            cursorRadius: const Radius.circular(1),
                            key: const ValueKey('account-delete-code'),
                            controller: _codeController,
                            enabled: !_busy,
                            keyboardType: TextInputType.number,
                            maxLength: 6,
                            decoration: const InputDecoration(
                              labelText: '6 位验证码',
                              counterText: '',
                              prefixIcon: Icon(Icons.password_rounded),
                            ),
                          ),
                        ],
                        if (!verified) ...[
                          const SizedBox(height: 14),
                          _ActionButton(
                            key: const ValueKey('account-delete-verify'),
                            label: _challenge == null ? '发送身份验证码' : '验证当前身份',
                            busy: _busy,
                            onPressed: _challenge == null
                                ? _requestIdentityCode
                                : _verifyIdentity,
                          ),
                          if (_challenge != null)
                            TextButton(
                              onPressed: _busy || _countdown > 0
                                  ? null
                                  : _requestIdentityCode,
                              child: Text(
                                _countdown > 0
                                    ? '${_countdown}s 后可重新发送'
                                    : '重新发送验证码',
                              ),
                            ),
                        ] else
                          const _VerifiedBadge(),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                _StepLabel(active: verified, number: '2', label: '确认永久注销'),
                const SizedBox(height: 10),
                _DeletionSurface(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          '输入“注销”以确认永久删除',
                          style: TextStyle(
                            fontWeight: MusicTypography.titleWeight,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          '账号身份、资料、收藏与歌单、播放记录、关系链、私信和一起听记录都将删除。',
                          style: TextStyle(
                            height: 1.5,
                            fontSize: MusicTypography.captionSize,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          contextMenuBuilder: buildBetaEditingMenu,
                          selectionControls: mestingTextSelectionControls,
                          cursorRadius: const Radius.circular(1),
                          key: const ValueKey('account-delete-confirmation'),
                          controller: _confirmationController,
                          enabled: verified && !_busy,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            labelText: '请输入：注销',
                            prefixIcon: Icon(Icons.warning_amber_rounded),
                          ),
                        ),
                        const SizedBox(height: 14),
                        _ActionButton(
                          key: const ValueKey('account-delete-submit'),
                          label: '永久注销账号',
                          busy: _busy,
                          destructive: true,
                          onPressed: canDelete ? _deleteAccount : null,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 14),
                _ErrorNotice(message: _error!),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _requestIdentityCode() async {
    if (_countdown > 0) return;
    final method = _identityMethod;
    if (method == null) return;
    await _guard(() async {
      final challenge = await ref
          .read(authControllerProvider.notifier)
          .requestCurrentIdentityCode(method: method);
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
    final challenge = _challenge;
    if (challenge == null) return;
    await _guard(() async {
      final token = await ref
          .read(authControllerProvider.notifier)
          .verifyCurrentIdentity(
            verificationId: challenge.verificationId,
            verificationCode: _codeController.text,
          );
      if (!mounted) return;
      _timer?.cancel();
      setState(() {
        _sudoToken = token;
        _challenge = null;
        _codeController.clear();
        _countdown = 0;
      });
    });
  }

  Future<void> _deleteAccount() async {
    final token = _sudoToken;
    if (token == null || _confirmationController.text.trim() != '注销') return;
    await _guard(() async {
      await ref
          .read(authControllerProvider.notifier)
          .deleteAccount(sudoToken: token);
      if (!mounted) return;
      showMusicNotice(
        context,
        icon: Icons.check_rounded,
        title: '账号已注销',
        message: '本机登录与该账号缓存已清理',
      );
      context.go('/music/recommend');
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
          () =>
              _error = userFacingErrorMessage(error, fallback: '账号注销失败，请稍后重试'),
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

class _Header extends StatelessWidget {
  const _Header({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final tokens = context.musicThemeTokens;
    return Row(
      children: [
        Material(
          color: tokens.glassStrong,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            key: const ValueKey('account-delete-back'),
            onTap: onBack,
            borderRadius: BorderRadius.circular(16),
            child: const SizedBox(
              width: 46,
              height: 46,
              child: Icon(Icons.arrow_back_rounded),
            ),
          ),
        ),
        const Spacer(),
        Text(
          '账号安全',
          style: TextStyle(
            color: tokens.textSecondary,
            fontSize: MusicTypography.captionSize,
            fontWeight: MusicTypography.bodyWeight,
            letterSpacing: 1.1,
          ),
        ),
        const Spacer(),
        const SizedBox(width: 46),
      ],
    );
  }
}

class _DeletionScopeCard extends StatelessWidget {
  const _DeletionScopeCard();

  @override
  Widget build(BuildContext context) {
    return _DeletionSurface(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.info_outline_rounded, color: Color(0xFFC24A34)),
                SizedBox(width: 9),
                Text(
                  '将被永久删除',
                  style: TextStyle(fontWeight: MusicTypography.titleWeight),
                ),
              ],
            ),
            const SizedBox(height: 11),
            Text(
              '账号身份、个人资料与已关联头像/主页背景、收藏和歌单、播放记录、关注与拉黑关系、私信会话、一起听会话和记录。',
              style: TextStyle(
                height: 1.55,
                fontSize: MusicTypography.captionSize,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeletionSurface extends StatelessWidget {
  const _DeletionSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = context.musicThemeTokens;
    return Container(
      decoration: BoxDecoration(
        color: tokens.glassStrong.withValues(alpha: .82),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: tokens.borderStrong),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .07),
            blurRadius: 24,
            offset: const Offset(0, 11),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _StepLabel extends StatelessWidget {
  const _StepLabel({
    required this.active,
    required this.number,
    required this.label,
  });

  final bool active;
  final String number;
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = active
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      children: [
        Container(
          width: 23,
          height: 23,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: Text(
            number,
            style: const TextStyle(
              color: Colors.white,
              fontSize: MusicTypography.smallCaptionSize,
              fontWeight: MusicTypography.bodyWeight,
            ),
          ),
        ),
        const SizedBox(width: 9),
        Text(
          label,
          style: const TextStyle(fontWeight: MusicTypography.titleWeight),
        ),
      ],
    );
  }
}

class _MethodPicker extends StatelessWidget {
  const _MethodPicker({
    required this.selected,
    required this.enabled,
    required this.onSelected,
  });

  final AuthMethod selected;
  final bool enabled;
  final ValueChanged<AuthMethod> onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: AuthMethod.values
            .map((method) {
              final chosen = selected == method;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    right: method == AuthMethod.email ? 8 : 0,
                  ),
                  child: ChoiceChip(
                    label: Text('使用${method.label}验证'),
                    selected: chosen,
                    onSelected: enabled ? (_) => onSelected(method) : null,
                  ),
                ),
              );
            })
            .toList(growable: false),
      ),
    );
  }
}

class _VerifiedBadge extends StatelessWidget {
  const _VerifiedBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF54A17B).withValues(alpha: .12),
        borderRadius: BorderRadius.circular(15),
      ),
      child: const Row(
        children: [
          Icon(Icons.verified_rounded, color: Color(0xFF54A17B)),
          SizedBox(width: 9),
          Text(
            '身份验证完成',
            style: TextStyle(fontWeight: MusicTypography.titleWeight),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    super.key,
    required this.label,
    required this.busy,
    required this.onPressed,
    this.destructive = false,
  });

  final String label;
  final bool busy;
  final VoidCallback? onPressed;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? const Color(0xFFC24A34) : null;
    return FilledButton(
      style: color == null
          ? null
          : FilledButton.styleFrom(backgroundColor: color),
      onPressed: busy ? null : onPressed,
      child: SizedBox(
        height: 47,
        child: Center(
          child: busy
              ? const SizedBox(
                  width: 19,
                  height: 19,
                  child: MusicActivityIndicator(
                    independent: true,
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(label),
        ),
      ),
    );
  }
}

class _ErrorNotice extends StatelessWidget {
  const _ErrorNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFC24A34).withValues(alpha: .12),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Text(
        message,
        style: const TextStyle(
          color: Color(0xFFC24A34),
          fontSize: MusicTypography.captionSize,
        ),
      ),
    );
  }
}
