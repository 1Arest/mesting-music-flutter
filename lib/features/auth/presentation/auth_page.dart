import '../../../shared/widgets/beta_page_motion.dart';
import '../../../shared/widgets/artwork_scroll_frontier.dart';
import '../../../shared/widgets/music_activity_indicator.dart';
import '../../../shared/widgets/beta_text_editing.dart';
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/user_facing_error.dart';
import '../../../core/persistence/app_preferences.dart';
import '../../../core/platform/distribution_channel.dart';
import '../../music_platform/presentation/platform_account_page.dart';
import '../../music_platform/music_platform_providers.dart';
import '../beta_account_choice.dart';
import '../../../shared/widgets/liquid_glass_sheet.dart';
import '../../legal/presentation/disclaimer_dialog.dart';
import '../../library/library_providers.dart';
import '../auth_providers.dart';
import '../data/device_phone_number_service.dart';
import '../domain/auth_models.dart';
import '../domain/password_policy.dart';
import 'password_visibility_button.dart';
import '../../../shared/widgets/beta_glass_controls.dart';
import 'beta_welcome_page.dart';
import '../beta_entry_flow.dart';

class AuthPage extends ConsumerStatefulWidget {
  const AuthPage({
    required this.initialMode,
    required this.redirect,
    this.firstLaunch = false,
    this.onExperience,
    this.mestingOnly = false,
    super.key,
  });

  final String initialMode;
  final String redirect;
  final bool firstLaunch;
  final VoidCallback? onExperience;
  final bool mestingOnly;

  @override
  ConsumerState<AuthPage> createState() => _AuthPageState();
}

enum _AuthView { phone, email }

class _AuthPageState extends ConsumerState<AuthPage>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _accountController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _codeController = TextEditingController();
  final _phoneNumberService = const DevicePhoneNumberService();
  late final AnimationController _disclaimerShakeController;

  _AuthView _view = _AuthView.phone;
  late bool _emailRegistering;
  bool _phoneCodeVisible = false;
  bool _phoneRegistration = false;
  bool _acceptedTerms = false;
  bool _disclaimerRead = false;
  // Registration consent is deliberately session-scoped. A prior login or
  // first-launch disclaimer must never pre-check consent for a new account.
  bool _registrationTermsRead = false;
  bool _registrationTermsAccepted = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _sendingCode = false;
  bool _detectingPhone = false;
  int _countdown = 0;
  Timer? _timer;
  String? _localError;
  String? _localMessage;
  String? _detectedPhone;
  AuthSession? _rememberedSession;
  EmailVerificationChallenge? _emailChallenge;
  String? _verificationEmail;
  PhoneVerificationChallenge? _phoneChallenge;
  String? _verificationPhone;

  @override
  void initState() {
    super.initState();
    _disclaimerShakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 440),
    );
    final preferences = ref.read(sharedPreferencesProvider);
    _emailRegistering = widget.initialMode != 'login';
    final accepted = hasAcceptedLegalDocuments(preferences);
    final read =
        accepted ||
        preferences.getBool(legalDocumentsReadPreferenceKey) == true;
    _acceptedTerms = accepted;
    _disclaimerRead = read;
    _registrationTermsRead = read;
    unawaited(_loadRememberedAccount());
    if (widget.firstLaunch && !DistributionChannel.isBeta) {
      unawaited(_detectDataSimPhoneNumber());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _disclaimerShakeController.dispose();
    _accountController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (DistributionChannel.isBeta &&
        ref.watch(platformAccountProvider).value == null &&
        ref.watch(currentUserProvider) == null) {
      return BetaWelcomePage(
        onExperience: () {
          if (widget.firstLaunch) {
            widget.onExperience?.call();
          } else {
            context.go(
              ref.read(betaEntryFlowProvider) == BetaEntryStage.app
                  ? '/music/recommend'
                  : widget.redirect,
            );
          }
        },
      );
    }
    if (DistributionChannel.isBeta &&
        (ref.watch(platformAccountProvider).value != null ||
            ref.watch(currentUserProvider) != null)) {
      return const PlatformAccountPage();
    }
    final platformBrightness = MediaQuery.platformBrightnessOf(context);
    final dark = platformBrightness == Brightness.dark;
    final palette = _AuthPalette.forBrightness(platformBrightness);
    final authState = ref.watch(authControllerProvider);
    final error =
        _localError ??
        (authState.hasError
            ? userFacingErrorMessage(authState.error, fallback: '登录失败，请稍后重试')
            : null);
    final topInset = MediaQuery.paddingOf(context).top;

    return Theme(
      data: ThemeData(
        brightness: platformBrightness,
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF5268D7),
          brightness: platformBrightness,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: palette.field,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 17,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: BorderSide(color: palette.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: BorderSide(color: palette.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: const BorderSide(color: Color(0xFF5268D7), width: 1.4),
          ),
        ),
      ),
      child: Scaffold(
        backgroundColor: palette.background,
        body: Stack(
          children: [
            Positioned.fill(child: _AuthBackdrop(dark: dark)),
            SafeArea(
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
                      padding: EdgeInsets.fromLTRB(20, topInset + 12, 20, 28),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _TopActions(
                              firstLaunch: widget.firstLaunch,
                              onBack: _leaveAuth,
                              onExperience: _experienceNow,
                            ),
                            SizedBox(height: widget.firstLaunch ? 54 : 24),
                            const _AuthBrand(),
                            if (DistributionChannel.isBeta &&
                                authState.value == null) ...[
                              const SizedBox(height: 24),
                              OutlinedButton.icon(
                                key: const ValueKey('music-platform-login'),
                                onPressed: _openMusicPlatform,
                                icon: const Icon(Icons.music_note_outlined),
                                label: const Text('使用音乐平台账号登录'),
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'Mesting 账号登录 / 注册',
                                textAlign: TextAlign.center,
                              ),
                            ],
                            const SizedBox(height: 46),
                            if (_rememberedSession != null) ...[
                              _RememberedAccountCard(
                                session: _rememberedSession!,
                                loading: authState.isLoading,
                                onLogin: _acceptedTerms ? _quickSignIn : null,
                                onForget: _forgetRememberedAccount,
                              ),
                              const SizedBox(height: 18),
                            ],
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 320),
                              switchInCurve: Curves.easeOutCubic,
                              switchOutCurve: Curves.easeInCubic,
                              transitionBuilder: (child, animation) =>
                                  FadeTransition(
                                    opacity: animation,
                                    child: SlideTransition(
                                      position: Tween(
                                        begin: const Offset(.08, 0),
                                        end: Offset.zero,
                                      ).animate(animation),
                                      child: child,
                                    ),
                                  ),
                              child: _view == _AuthView.phone
                                  ? _buildPhoneForm(
                                      palette,
                                      authState.isLoading,
                                      error,
                                    )
                                  : _buildEmailForm(
                                      palette,
                                      authState.isLoading,
                                      error,
                                    ),
                            ),
                            const SizedBox(height: 18),
                            _DisclaimerAgreement(
                              read: _isRegistrationFlow
                                  ? _registrationTermsRead
                                  : _disclaimerRead,
                              accepted: _currentTermsAccepted,
                              shakeAnimation: _disclaimerShakeController,
                              onRead: _isRegistrationFlow
                                  ? _showRegistrationDisclaimer
                                  : _readDisclaimer,
                              onUnreadCheckboxTap: _isRegistrationFlow
                                  ? _acceptRegistrationTerms
                                  : () => _readDisclaimer(
                                      acceptAfterReading: true,
                                    ),
                              onChanged:
                                  (_isRegistrationFlow
                                      ? _registrationTermsRead
                                      : _disclaimerRead)
                                  ? (value) => setState(() {
                                      if (_isRegistrationFlow) {
                                        _registrationTermsAccepted = value;
                                      } else {
                                        _acceptedTerms = value;
                                      }
                                    })
                                  : null,
                            ),
                            const SizedBox(height: 25),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                TextButton(
                                  onPressed: _showLoginHelp,
                                  child: const Text('登录遇到问题'),
                                ),
                                Container(
                                  width: 1,
                                  height: 14,
                                  color: palette.border,
                                ),
                                TextButton(
                                  key: const ValueKey('auth-method-switch'),
                                  onPressed: _switchAuthView,
                                  child: Text(
                                    _view == _AuthView.phone
                                        ? '邮箱账号登录'
                                        : '手机号快捷登录',
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhoneForm(_AuthPalette palette, bool loading, String? error) {
    return Column(
      key: const ValueKey('phone-auth-form'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_detectingPhone) ...[
          Row(
            children: [
              Icon(Icons.sim_card_outlined, size: 16, color: palette.secondary),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  '正在识别当前上网卡，可拒绝权限并手动输入',
                  style: TextStyle(color: palette.secondary, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
        ],
        _glassAuthField(
          TextFormField(
            contextMenuBuilder: buildBetaEditingMenu,
            selectionControls: mestingTextSelectionControls,
            cursorRadius: const Radius.circular(1),
            key: const ValueKey('phone-number-field'),
            controller: _accountController,
            readOnly: _detectedPhone != null,
            keyboardType: TextInputType.phone,
            autofillHints: const [AutofillHints.telephoneNumberDevice],
            decoration: InputDecoration(
              labelText: '手机号码',
              prefixIcon: const Padding(
                padding: EdgeInsets.only(left: 16, right: 5),
                child: Center(
                  widthFactor: 1,
                  child: Text(
                    '+86',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ),
              suffixIcon: _detectedPhone != null
                  ? IconButton(
                      tooltip: '改用其他手机号',
                      onPressed: _useManualPhoneInput,
                      icon: const Icon(Icons.edit_rounded),
                    )
                  : _detectingPhone
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: SizedBox.square(
                        dimension: 18,
                        child: MusicActivityIndicator(
                          independent: true,
                          strokeWidth: 2,
                        ),
                      ),
                    )
                  : null,
            ),
            validator: (_) => RegExp(r'^1\d{10}$').hasMatch(_phoneValue)
                ? null
                : '请输入 11 位中国大陆手机号',
            onChanged: (_) {
              _resetPhoneVerification();
              _resetRegistrationConsent();
            },
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 330),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: !_phoneCodeVisible
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(top: 13),
                  child: _glassAuthField(
                    TextFormField(
                      contextMenuBuilder: buildBetaEditingMenu,
                      selectionControls: mestingTextSelectionControls,
                      cursorRadius: const Radius.circular(1),
                      key: const ValueKey('phone-code-field'),
                      controller: _codeController,
                      keyboardType: TextInputType.number,
                      autofillHints: const [AutofillHints.oneTimeCode],
                      maxLength: 6,
                      decoration: InputDecoration(
                        labelText: '短信验证码',
                        counterText: '',
                        prefixIcon: const Icon(Icons.verified_user_outlined),
                        suffixIcon: Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: TextButton(
                            onPressed: _countdown > 0 || _sendingCode
                                ? null
                                : _startPhoneLogin,
                            child: Text(
                              _sendingCode
                                  ? '发送中'
                                  : _countdown > 0
                                  ? '已获取 $_countdown秒'
                                  : '重新获取',
                            ),
                          ),
                        ),
                      ),
                      validator: (value) => (value ?? '').trim().length == 6
                          ? null
                          : '请输入 6 位短信验证码',
                    ),
                  ),
                ),
        ),
        if (error != null) ...[
          const SizedBox(height: 12),
          _MessageBanner(error, error: true),
        ],
        if (_localMessage != null) ...[
          const SizedBox(height: 12),
          _MessageBanner(_localMessage!),
        ],
        const SizedBox(height: 18),
        SizedBox(
          height: 56,
          child: (DistributionChannel.isBeta
              ? BetaGlassButton(
                  key: const ValueKey('phone-primary-action'),
                  loading: loading || _sendingCode,
                  onPressed: loading || _sendingCode
                      ? null
                      : _handlePhonePrimaryAction,
                  child: Text(_phoneCodeVisible ? '验证并登录' : '一键登录'),
                )
              : FilledButton(
                  key: const ValueKey('phone-primary-action'),
                  onPressed: loading ? null : _handlePhonePrimaryAction,
                  style: FilledButton.styleFrom(
                    backgroundColor: _currentTermsAccepted
                        ? const Color(0xFF5268D7)
                        : const Color(0xFF5268D7).withValues(alpha: .25),
                    disabledBackgroundColor: const Color(
                      0xFF5268D7,
                    ).withValues(alpha: .25),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  child: loading || _sendingCode
                      ? const SizedBox.square(
                          dimension: 21,
                          child: MusicActivityIndicator(
                            independent: true,
                            strokeWidth: 2.4,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          _phoneCodeVisible ? '验证并登录' : '一键登录',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                )),
        ),
      ],
    );
  }

  Widget _buildEmailForm(_AuthPalette palette, bool loading, String? error) {
    return Column(
      key: const ValueKey('email-auth-form'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _EmailModeSwitch(
          palette: palette,
          registering: _emailRegistering,
          onChanged: _setEmailRegistering,
        ),
        const SizedBox(height: 14),
        _glassAuthField(
          TextFormField(
            contextMenuBuilder: buildBetaEditingMenu,
            selectionControls: mestingTextSelectionControls,
            cursorRadius: const Radius.circular(1),
            key: const ValueKey('email-account-field'),
            controller: _accountController,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            decoration: const InputDecoration(
              labelText: '邮箱地址',
              prefixIcon: Icon(Icons.alternate_email_rounded),
            ),
            validator: (value) {
              final account = (value ?? '').trim();
              return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(account)
                  ? null
                  : '请输入正确的邮箱地址';
            },
            onChanged: (_) {
              _resetEmailVerification();
              _resetRegistrationConsent();
            },
          ),
        ),
        if (_emailRegistering) ...[
          const SizedBox(height: 13),
          _glassAuthField(
            TextFormField(
              contextMenuBuilder: buildBetaEditingMenu,
              selectionControls: mestingTextSelectionControls,
              cursorRadius: const Radius.circular(1),
              key: const ValueKey('email-code-field'),
              controller: _codeController,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              maxLength: 6,
              decoration: InputDecoration(
                labelText: '邮箱验证码',
                counterText: '',
                prefixIcon: const Icon(Icons.mark_email_read_outlined),
                suffixIcon: TextButton(
                  onPressed: _countdown > 0 || _sendingCode
                      ? null
                      : _sendEmailCode,
                  child: Text(
                    _sendingCode
                        ? '发送中'
                        : _countdown > 0
                        ? '$_countdown秒'
                        : '获取验证码',
                  ),
                ),
              ),
              validator: (value) =>
                  (value ?? '').trim().length == 6 ? null : '请输入 6 位邮箱验证码',
            ),
          ),
        ],
        const SizedBox(height: 13),
        _glassAuthField(
          TextFormField(
            contextMenuBuilder: buildBetaEditingMenu,
            selectionControls: mestingTextSelectionControls,
            cursorRadius: const Radius.circular(1),
            key: const ValueKey('email-password-field'),
            controller: _passwordController,
            obscureText: _obscurePassword,
            autofillHints: _emailRegistering
                ? const [AutofillHints.newPassword]
                : const [AutofillHints.password],
            decoration: InputDecoration(
              labelText: '密码',
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              suffixIcon: PasswordVisibilityButton(
                buttonKey: const ValueKey('email-password-visibility'),
                obscured: _obscurePassword,
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
            validator: (value) => validateAccountPassword(value ?? ''),
            onChanged: (_) => _resetRegistrationConsent(),
          ),
        ),
        if (_emailRegistering) ...[
          const SizedBox(height: 13),
          _glassAuthField(
            TextFormField(
              contextMenuBuilder: buildBetaEditingMenu,
              selectionControls: mestingTextSelectionControls,
              cursorRadius: const Radius.circular(1),
              key: const ValueKey('email-confirm-password-field'),
              controller: _confirmPasswordController,
              obscureText: _obscureConfirmPassword,
              autofillHints: const [AutofillHints.newPassword],
              decoration: InputDecoration(
                labelText: '确认密码',
                prefixIcon: const Icon(Icons.lock_reset_rounded),
                suffixIcon: PasswordVisibilityButton(
                  buttonKey: const ValueKey(
                    'email-confirm-password-visibility',
                  ),
                  obscured: _obscureConfirmPassword,
                  onPressed: () => setState(
                    () => _obscureConfirmPassword = !_obscureConfirmPassword,
                  ),
                ),
              ),
              validator: (value) {
                if ((value ?? '').isEmpty) return '请再次输入密码';
                if (value != _passwordController.text) {
                  return '两次输入的密码不一致';
                }
                return null;
              },
              onChanged: (_) => _resetRegistrationConsent(),
            ),
          ),
        ],
        if (error != null) ...[
          const SizedBox(height: 12),
          _MessageBanner(error, error: true),
        ],
        if (_localMessage != null) ...[
          const SizedBox(height: 12),
          _MessageBanner(_localMessage!),
        ],
        const SizedBox(height: 18),
        SizedBox(
          height: 56,
          child: (DistributionChannel.isBeta
              ? BetaGlassButton(
                  key: const ValueKey('email-primary-action'),
                  loading: loading,
                  onPressed: loading ? null : _handleEmailPrimaryAction,
                  child: Text(_emailRegistering ? '注册并登录' : '登录'),
                )
              : FilledButton(
                  key: const ValueKey('email-primary-action'),
                  onPressed: loading ? null : _handleEmailPrimaryAction,
                  style: FilledButton.styleFrom(
                    backgroundColor: _currentTermsAccepted
                        ? const Color(0xFF5268D7)
                        : const Color(0xFF5268D7).withValues(alpha: .25),
                    disabledBackgroundColor: const Color(
                      0xFF5268D7,
                    ).withValues(alpha: .25),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  child: loading
                      ? const SizedBox.square(
                          dimension: 21,
                          child: MusicActivityIndicator(
                            independent: true,
                            strokeWidth: 2.4,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          _emailRegistering ? '注册并登录' : '登录',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                )),
        ),
        if (!_emailRegistering)
          TextButton(
            onPressed: () => context.push(
              '/auth/recover?redirect=${Uri.encodeComponent(widget.redirect)}',
            ),
            child: const Text('忘记邮箱密码？'),
          ),
      ],
    );
  }

  String get _phoneValue => _detectedPhone ?? _accountController.text.trim();

  bool get _isRegistrationFlow => _view == _AuthView.phone || _emailRegistering;

  bool get _currentTermsAccepted =>
      _isRegistrationFlow ? _registrationTermsAccepted : _acceptedTerms;

  Future<void> _loadRememberedAccount() async {
    final remembered = await ref
        .read(authControllerProvider.notifier)
        .rememberedAccount();
    if (!mounted) return;
    setState(() => _rememberedSession = remembered);
  }

  Future<void> _detectDataSimPhoneNumber() async {
    setState(() => _detectingPhone = true);
    final result = await _phoneNumberService.getDataSimPhoneNumber();
    if (!mounted) return;
    setState(() {
      _detectingPhone = false;
      if (result.available) {
        _detectedPhone = result.phoneNumber;
        _accountController.text = result.maskedPhoneNumber;
      } else if (result.unavailableReason == 'permission_denied') {
        _localMessage = '未获得手机号读取权限，请手动输入手机号';
      } else if (result.unavailableReason == 'number_unavailable') {
        _localMessage = '系统未提供当前上网卡号码，请手动输入手机号';
      }
    });
  }

  void _useManualPhoneInput() {
    setState(() {
      _detectedPhone = null;
      _accountController.clear();
      _resetPhoneVerification();
    });
  }

  Future<void> _readDisclaimer({bool acceptAfterReading = false}) async {
    final read = await showRequiredDisclaimerReading(
      context,
      minimumReadDuration: _disclaimerRead
          ? Duration.zero
          : const Duration(seconds: 5),
    );
    if (!mounted || !read) return;
    await ref
        .read(sharedPreferencesProvider)
        .setBool(legalDocumentsReadPreferenceKey, true);
    if (!mounted) return;
    setState(() {
      _disclaimerRead = true;
      if (acceptAfterReading) _acceptedTerms = true;
      _localError = null;
    });
  }

  Future<void> _showRegistrationDisclaimer() async {
    final read = await showRequiredDisclaimerReading(
      context,
      minimumReadDuration: _registrationTermsRead
          ? Duration.zero
          : const Duration(seconds: 5),
    );
    if (!mounted || !read) return;
    await ref
        .read(sharedPreferencesProvider)
        .setBool(legalDocumentsReadPreferenceKey, true);
    if (!mounted) return;
    setState(() {
      _registrationTermsRead = true;
      _localError = null;
    });
  }

  Future<void> _acceptRegistrationTerms() async {
    final read = await showRequiredDisclaimerReading(
      context,
      minimumReadDuration: _registrationTermsRead
          ? Duration.zero
          : const Duration(seconds: 5),
    );
    if (!mounted || !read) return;
    await ref
        .read(sharedPreferencesProvider)
        .setBool(legalDocumentsReadPreferenceKey, true);
    if (!mounted) return;
    setState(() {
      _registrationTermsRead = true;
      _registrationTermsAccepted = true;
      _localError = null;
    });
  }

  bool _ensureTermsAcceptedForCurrentFlow() {
    if (!_isRegistrationFlow) {
      if (_acceptedTerms) return true;
      _remindDisclaimerAcceptance();
      return false;
    }
    if (_registrationTermsAccepted) return true;
    setState(() => _localError = '请阅读用户协议与隐私政策，并完成 5 秒阅读后再继续注册');
    _remindDisclaimerAcceptance();
    return false;
  }

  void _handlePhonePrimaryAction() {
    if (_isRegistrationFlow && !(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    if (!_ensureTermsAcceptedForCurrentFlow()) return;
    if (_phoneCodeVisible) {
      unawaited(_verifyPhone());
    } else {
      unawaited(_startPhoneLogin());
    }
  }

  void _handleEmailPrimaryAction() {
    if (_isRegistrationFlow && !(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    if (!_ensureTermsAcceptedForCurrentFlow()) return;
    unawaited(_submitEmail());
  }

  void _remindDisclaimerAcceptance() {
    _disclaimerShakeController.forward(from: 0);
  }

  Future<void> _startPhoneLogin() async {
    _clearMessages();
    if (!_ensureTermsAcceptedForCurrentFlow()) return;
    if (!RegExp(r'^1\d{10}$').hasMatch(_phoneValue)) {
      _formKey.currentState?.validate();
      return;
    }
    setState(() => _sendingCode = true);
    try {
      final challenge = await ref
          .read(authControllerProvider.notifier)
          .requestPhoneCode(phone: _phoneValue, registration: false);
      if (!mounted) return;
      setState(() {
        _phoneChallenge = challenge;
        _verificationPhone = _phoneValue;
        _phoneRegistration = !challenge.isExistingUser;
        _phoneCodeVisible = true;
        _sendingCode = false;
        _localMessage = challenge.isExistingUser
            ? '验证码已发送，请完成登录'
            : '该手机号将自动创建账号，验证码已发送';
      });
      _startCountdown();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _sendingCode = false;
        _localError = userFacingErrorMessage(error, fallback: '验证码发送失败，请稍后重试');
      });
    }
  }

  Future<void> _verifyPhone() async {
    _clearMessages();
    if (!_ensureTermsAcceptedForCurrentFlow()) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final challenge = _phoneChallenge;
    if (challenge == null || _verificationPhone != _phoneValue) {
      setState(() => _localError = '请先向当前手机号获取验证码');
      return;
    }
    final success = await ref
        .read(authControllerProvider.notifier)
        .verifyPhoneCode(
          phone: _phoneValue,
          code: _codeController.text.trim(),
          verificationId: challenge.verificationId,
          registration: _phoneRegistration,
        );
    if (success) await _finishAuthentication();
  }

  Future<void> _sendEmailCode() async {
    _clearMessages();
    if (_emailRegistering && !_ensureTermsAcceptedForCurrentFlow()) return;
    final email = _accountController.text.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      _formKey.currentState?.validate();
      return;
    }
    setState(() => _sendingCode = true);
    try {
      final challenge = await ref
          .read(authControllerProvider.notifier)
          .requestEmailCode(email: email);
      if (!mounted) return;
      setState(() {
        _emailChallenge = challenge;
        _verificationEmail = email.toLowerCase();
        _sendingCode = false;
        _localMessage = challenge.isExistingUser
            ? '该邮箱已有账号，请切换到邮箱登录'
            : '验证码已发送，请在 10 分钟内完成注册';
      });
      _startCountdown();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _sendingCode = false;
        _localError = userFacingErrorMessage(
          error,
          fallback: '邮箱验证码发送失败，请稍后重试',
        );
      });
    }
  }

  Widget _glassAuthField(Widget child) =>
      DistributionChannel.isBeta ? BetaGlassField(child: child) : child;

  Future<void> _submitEmail() async {
    _clearMessages();
    if (!_ensureTermsAcceptedForCurrentFlow()) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final controller = ref.read(authControllerProvider.notifier);
    final email = _accountController.text.trim();
    bool success;
    if (_emailRegistering) {
      final challenge = _emailChallenge;
      if (challenge == null || _verificationEmail != email.toLowerCase()) {
        setState(() => _localError = '请先向当前邮箱获取验证码');
        return;
      }
      if (challenge.isExistingUser) {
        setState(() => _localError = '该邮箱已经注册，请切换到邮箱登录');
        return;
      }
      success = await controller.registerWithEmail(
        email: email,
        password: _passwordController.text,
        verificationId: challenge.verificationId,
        verificationCode: _codeController.text.trim(),
      );
    } else {
      success = await controller.signInWithEmail(
        email: email,
        password: _passwordController.text,
      );
    }
    if (success) await _finishAuthentication();
  }

  Future<void> _quickSignIn() async {
    _clearMessages();
    final success = await ref
        .read(authControllerProvider.notifier)
        .quickSignIn();
    if (!mounted) return;
    if (success) {
      await _finishAuthentication();
    } else {
      setState(() {
        _localError = '快捷登录凭证已失效，请使用验证码或邮箱重新登录';
        _rememberedSession = null;
      });
    }
  }

  Future<void> _finishAuthentication() async {
    final preferences = ref.read(sharedPreferencesProvider);
    await saveLegalDocumentConsent(preferences);
    await _offerLegacyLibraryImport();
    if (!mounted) return;
    if (DistributionChannel.isBeta) {
      ref.read(betaEntryFlowProvider.notifier).authenticated();
    }
    if (widget.firstLaunch) {
      widget.onExperience?.call();
      return;
    }
    context.go(widget.redirect);
  }

  Future<void> _forgetRememberedAccount() async {
    await ref.read(authControllerProvider.notifier).forgetRememberedAccount();
    if (mounted) setState(() => _rememberedSession = null);
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

  void _switchAuthView() {
    setState(() {
      _view = _view == _AuthView.phone ? _AuthView.email : _AuthView.phone;
      _accountController.clear();
      _passwordController.clear();
      _confirmPasswordController.clear();
      _detectedPhone = null;
      _clearMessages();
      _resetAllVerification();
      _registrationTermsAccepted = false;
    });
  }

  void _setEmailRegistering(bool value) {
    if (_emailRegistering == value) return;
    setState(() {
      _emailRegistering = value;
      _registrationTermsAccepted = false;
      _clearMessages();
      _resetEmailVerification();
    });
  }

  void _resetPhoneVerification() {
    _timer?.cancel();
    _phoneChallenge = null;
    _verificationPhone = null;
    _phoneCodeVisible = false;
    _phoneRegistration = false;
    _countdown = 0;
    _codeController.clear();
  }

  void _resetEmailVerification() {
    _timer?.cancel();
    _emailChallenge = null;
    _verificationEmail = null;
    _countdown = 0;
    _codeController.clear();
  }

  void _resetAllVerification() {
    _resetPhoneVerification();
    _resetEmailVerification();
    _sendingCode = false;
  }

  void _resetRegistrationConsent() {
    if (!_registrationTermsAccepted) return;
    setState(() => _registrationTermsAccepted = false);
  }

  void _clearMessages() {
    setState(() {
      _localError = null;
      _localMessage = null;
    });
  }

  void _leaveAuth() {
    if (widget.firstLaunch) {
      _experienceNow();
    } else if (context.canPop()) {
      context.pop(false);
    } else {
      context.go('/music/recommend');
    }
  }

  Future<void> _experienceNow() async {
    if (DistributionChannel.isBeta &&
        ref.read(platformAccountProvider).value == null &&
        ref.read(authControllerProvider).value == null) {
      await ref
          .read(betaAccountChoiceProvider.notifier)
          .select(BetaAccountChoice.guest);
    }
    if (!mounted) return;
    if (DistributionChannel.isBeta) {
      await ref.read(betaEntryFlowProvider.notifier).finish();
    }
    if (!mounted) return;
    widget.onExperience?.call();
    if (!widget.firstLaunch) context.go('/music/recommend');
  }

  Future<void> _openMusicPlatform() async {
    final success = await Navigator.of(context).push<bool>(
      MestingPageRoute(builder: (_) => const PlatformAccountPage()),
    );
    // Completing onboarding does not fabricate a Mesting account/session.
    if (success == true && mounted) _experienceNow();
  }

  Future<void> _showLoginHelp() async {
    await showLiquidGlassBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                title: Text(
                  '登录遇到问题',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                subtitle: Text('手机号登录无需密码，只使用短信验证码'),
              ),
              ListTile(
                leading: const Icon(Icons.phone_forwarded_rounded),
                title: const Text('手机号已更换'),
                subtitle: const Text('请使用新手机号创建账号，原账号可通过已绑定邮箱找回'),
                onTap: () => Navigator.pop(sheetContext),
              ),
              ListTile(
                leading: const Icon(Icons.manage_accounts_outlined),
                title: const Text('找回账号'),
                subtitle: const Text('使用曾绑定的邮箱或手机号确认身份'),
                onTap: () => Navigator.pop(sheetContext),
              ),
              ListTile(
                leading: const Icon(Icons.lock_reset_rounded),
                title: const Text('忘记邮箱密码'),
                subtitle: const Text('通过邮箱验证码重置密码'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  context.push(
                    '/auth/recover?redirect=${Uri.encodeComponent(widget.redirect)}',
                  );
                },
              ),
              const ListTile(
                leading: Icon(Icons.help_outline_rounded),
                title: Text('常见问题'),
                subtitle: Text('验证码可能存在短暂延迟，请勿连续重复发送'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _offerLegacyLibraryImport() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    final preferences = ref.read(sharedPreferencesProvider);
    final marker = 'legacy_library_prompted_${user.uid}';
    if (preferences.getBool(marker) == true) return;
    final repository = ref.read(libraryRepositoryProvider);
    final favoriteCount = await repository.countLegacyFavorites();
    if (favoriteCount == 0 || !mounted) {
      await preferences.setBool(marker, true);
      return;
    }
    final import = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('导入本机收藏？'),
        content: Text(
          '检测到升级前保留的 $favoriteCount 首本机收藏。导入后会归入当前账号，并在云端服务连接后同步到其他设备。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('暂不导入'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('导入收藏'),
          ),
        ],
      ),
    );
    await preferences.setBool(marker, true);
    if (import == true) await repository.importLegacyLibrary();
  }
}

class _TopActions extends StatelessWidget {
  const _TopActions({
    required this.firstLaunch,
    required this.onBack,
    required this.onExperience,
  });

  final bool firstLaunch;
  final VoidCallback onBack;
  final VoidCallback onExperience;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (DistributionChannel.isBeta)
          BetaGlassBackButton(onPressed: onBack)
        else
          IconButton.filledTonal(
            tooltip: firstLaunch ? '暂不登录' : '返回',
            onPressed: onBack,
            icon: Icon(
              firstLaunch ? Icons.close_rounded : Icons.arrow_back_rounded,
            ),
          ),
        const Spacer(),
        TextButton(
          key: const ValueKey('experience-now'),
          onPressed: onExperience,
          child: Text(
            DistributionChannel.isBeta ? '暂不登录，先体验' : '立即体验',
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
      ],
    );
  }
}

class _AuthBrand extends StatelessWidget {
  const _AuthBrand();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 88,
          height: 88,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF8296F2), Color(0xFF3F9FB0)],
            ),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF5268D7).withValues(alpha: .28),
                blurRadius: 32,
                offset: const Offset(0, 15),
              ),
            ],
          ),
          child: const Icon(
            Icons.graphic_eq_rounded,
            color: Colors.white,
            size: 46,
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          'Mesting Music',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w900,
            letterSpacing: -.7,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          '让喜欢的音乐，跟着账号去往每一台设备',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

class _RememberedAccountCard extends StatelessWidget {
  const _RememberedAccountCard({
    required this.session,
    required this.loading,
    required this.onLogin,
    required this.onForget,
  });

  final AuthSession session;
  final bool loading;
  final VoidCallback? onLogin;
  final VoidCallback onForget;

  @override
  Widget build(BuildContext context) {
    final user = session.user;
    final account = user.phoneMasked ?? user.emailMasked ?? '已记住账号';
    return Container(
      key: const ValueKey('remembered-account-card'),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: .72),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: .45),
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 25,
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            child: Text(
              user.nickname.trim().isEmpty
                  ? 'M'
                  : user.nickname.trim().characters.first,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.nickname,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 2),
                Text(
                  account,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            key: const ValueKey('quick-login'),
            onPressed: loading ? null : onLogin,
            child: const Text('快捷登录'),
          ),
          IconButton(
            tooltip: '移除此账号',
            onPressed: onForget,
            icon: const Icon(Icons.close_rounded, size: 19),
          ),
        ],
      ),
    );
  }
}

class _DisclaimerAgreement extends StatelessWidget {
  const _DisclaimerAgreement({
    required this.read,
    required this.accepted,
    required this.shakeAnimation,
    required this.onRead,
    required this.onUnreadCheckboxTap,
    required this.onChanged,
  });

  final bool read;
  final bool accepted;
  final Animation<double> shakeAnimation;
  final VoidCallback onRead;
  final VoidCallback onUnreadCheckboxTap;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        AnimatedBuilder(
          animation: shakeAnimation,
          child: SizedBox.square(
            dimension: 40,
            child: Checkbox(
              key: const ValueKey('disclaimer-checkbox'),
              value: accepted,
              onChanged: read
                  ? (value) => onChanged?.call(value ?? false)
                  : (_) => onUnreadCheckboxTap(),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          builder: (context, child) {
            final progress = shakeAnimation.value;
            final distance =
                math.sin(progress * math.pi * 8) * (1 - progress) * 7;
            return Transform.translate(
              key: const ValueKey('disclaimer-checkbox-shake'),
              offset: Offset(distance, 0),
              child: child,
            );
          },
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text('我已阅读并同意 ', style: TextStyle(fontSize: 12)),
              GestureDetector(
                onTap: onRead,
                child: Text(
                  read ? '《用户协议》《隐私政策》' : '《用户协议》《隐私政策》（需阅读 5 秒）',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EmailModeSwitch extends StatelessWidget {
  const _EmailModeSwitch({
    required this.palette,
    required this.registering,
    required this.onChanged,
  });

  final _AuthPalette palette;
  final bool registering;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('email-mode-switch'),
      height: 45,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: palette.field,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            fit: StackFit.expand,
            children: [
              AnimatedAlign(
                key: const ValueKey('email-mode-indicator-alignment'),
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                alignment: registering
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                child: SizedBox(
                  key: const ValueKey('email-mode-indicator'),
                  width: constraints.maxWidth / 2,
                  height: constraints.maxHeight,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(13),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: .045),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Row(
                children: [
                  _EmailModeButton(
                    key: const ValueKey('email-mode-login'),
                    label: '登录',
                    selected: !registering,
                    onTap: () => onChanged(false),
                  ),
                  _EmailModeButton(
                    key: const ValueKey('email-mode-register'),
                    label: '注册',
                    selected: registering,
                    onTap: () => onChanged(true),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _EmailModeButton extends StatelessWidget {
  const _EmailModeButton({
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: BorderRadius.circular(13),
          splashColor: Theme.of(
            context,
          ).colorScheme.primary.withValues(alpha: .06),
          highlightColor: Theme.of(
            context,
          ).colorScheme.primary.withValues(alpha: .04),
          onTap: onTap,
          child: Center(
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOutCubic,
              style: TextStyle(
                color: selected
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w900,
              ),
              child: Text(label),
            ),
          ),
        ),
      ),
    );
  }
}

class _MessageBanner extends StatelessWidget {
  const _MessageBanner(this.message, {this.error = false});

  final String message;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final color = error
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: .22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            error ? Icons.error_outline_rounded : Icons.info_outline_rounded,
            color: color,
            size: 19,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthBackdrop extends StatelessWidget {
  const _AuthBackdrop({required this.dark});

  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: dark
                  ? const [Color(0xFF171B26), Color(0xFF11121A)]
                  : const [Color(0xFFF1F4FF), Color(0xFFFCFCFD)],
              stops: const [0, .48],
            ),
          ),
          child: const SizedBox.expand(),
        ),
        Positioned(
          left: -80,
          right: -80,
          top: 100,
          height: 310,
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 65, sigmaY: 65),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF5268D7).withValues(alpha: dark ? .18 : .13),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AuthPalette {
  const _AuthPalette({
    required this.background,
    required this.field,
    required this.border,
    required this.secondary,
  });

  factory _AuthPalette.forBrightness(Brightness brightness) {
    if (brightness == Brightness.dark) {
      return const _AuthPalette(
        background: Color(0xFF11121A),
        field: Color(0xB3252A35),
        border: Color(0x3DFFFFFF),
        secondary: Color(0xFFC8D0DE),
      );
    }
    return const _AuthPalette(
      background: Color(0xFFFCFCFD),
      field: Color(0xB3FFFFFF),
      border: Color(0x1F3C4B67),
      secondary: Color(0xFF687181),
    );
  }

  final Color background;
  final Color field;
  final Color border;
  final Color secondary;
}
