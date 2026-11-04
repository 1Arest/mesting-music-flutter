import 'package:qr_flutter/qr_flutter.dart';
import '../domain/platform_session.dart';
import '../netease/netease_login.dart';
import '../netease/netease_providers.dart';
import '../../../shared/widgets/beta_text_editing.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/liquid_glass_sheet.dart';
import '../../../shared/widgets/beta_glass_controls.dart';
import '../../../shared/widgets/beta_glass_scroll_body.dart';
import '../../../shared/widgets/music_notice.dart';
import '../data/music_platform_api.dart';
import '../music_platform_providers.dart';
import '../../auth/auth_providers.dart';
import '../platform_profile_provider.dart';
import 'platform_avatar.dart';

/// Uses Mesting's inherited theme, with account state owned entirely outside
/// CloudBase. Closing this route cancels scans without affecting either login.
class PlatformAccountPage extends ConsumerStatefulWidget {
  const PlatformAccountPage({
    this.initialMethod = PlatformLoginMethod.phone,
    this.platform = MusicPlatform.kugou,
    this.neteaseMethod = NeteaseLoginMethod.qr,
    this.loginOnly = false,
    super.key,
  });
  final PlatformLoginMethod initialMethod;
  final MusicPlatform platform;
  final NeteaseLoginMethod neteaseMethod;

  /// Adding the other platform must not turn its form into the active account's
  /// management screen. Its credential is committed only on successful login.
  final bool loginOnly;

  @override
  ConsumerState<PlatformAccountPage> createState() =>
      _PlatformAccountPageState();
}

class _PlatformAccountPageState extends ConsumerState<PlatformAccountPage> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  final _password = TextEditingController();
  NeteaseLoginService? _neteaseLogin;
  NeteaseQrChallenge? _neteaseChallenge;
  bool get _isNetease => widget.platform == MusicPlatform.netease;
  NeteaseLoginService get _netLogin =>
      _neteaseLogin ??= NeteaseLoginService(ref.read(neteaseApiProvider));
  PlatformLoginMethod _method = PlatformLoginMethod.phone;
  PlatformQrChallenge? _challenge;
  String? _message;
  bool _busy = false;
  String? _busyAction;
  bool _polling = false;
  int _generation = 0;
  int _countdown = 0;
  Timer? _countdownTimer;

  PlatformLoginService get _login =>
      PlatformLoginService(ref.read(musicPlatformApiProvider));

  @override
  void initState() {
    super.initState();
    _method = _isNetease
        ? (widget.neteaseMethod == NeteaseLoginMethod.qr
              ? PlatformLoginMethod.kugouQr
              : PlatformLoginMethod.phone)
        : widget.initialMethod;
    if (_method != PlatformLoginMethod.phone) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _select(_method);
      });
    }
  }

  @override
  void dispose() {
    ++_generation;
    _countdownTimer?.cancel();
    _phone.dispose();
    _code.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _select(PlatformLoginMethod method) async {
    final generation = ++_generation;
    setState(() {
      _method = method;
      _polling = false;
      _busyAction = 'qr';
      _challenge = null;
      _neteaseChallenge = null;
      _message = null;
      _busy = method != PlatformLoginMethod.phone;
    });
    if (method == PlatformLoginMethod.phone) return;
    try {
      await ref
          .read(platformAccountProvider.notifier)
          .readyForInteractiveLogin();
      if (_isNetease) {
        final challenge = await _netLogin.createQr();
        if (!mounted || generation != _generation) return;
        setState(() {
          _neteaseChallenge = challenge;
          _busy = false;
          _polling = true;
          _message = '请使用网易云音乐扫描二维码并确认';
        });
        unawaited(_pollNetease(challenge, generation));
        return;
      }
      final challenge = await _login.createQr(method);
      if (!mounted || generation != _generation) return;
      setState(() {
        _challenge = challenge;
        _polling = true;
        _busy = false;
        _message = '请使用${_label(method)}完成扫码并确认';
      });
      unawaited(_poll(challenge, generation));
    } on Object catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _busy = false;
          _message = _error(error);
        });
      }
    }
  }

  Future<void> _poll(PlatformQrChallenge challenge, int generation) async {
    // Sequential bounded polling prevents overlapping requests; every await
    // is followed by a generation guard before a credential can be persisted.
    final expires = DateTime.now().add(const Duration(minutes: 3));
    while (mounted &&
        generation == _generation &&
        DateTime.now().isBefore(expires)) {
      await Future<void>.delayed(const Duration(seconds: 2));
      if (!mounted || generation != _generation) return;
      try {
        final result = await _login.poll(challenge);
        if (!mounted || generation != _generation) return;
        if (result != null) {
          await ref.read(platformAccountProvider.notifier).accept(result);
          if (!mounted || generation != _generation) return;
          Navigator.of(context).pop(true);
          return;
        }
      } on Object catch (error) {
        if (mounted && generation == _generation) {
          setState(() {
            _message = _error(error);
            _polling = false;
          });
        }
        return;
      }
    }
    if (mounted && generation == _generation) {
      setState(() {
        _message = '二维码已过期，请刷新';
        _polling = false;
      });
    }
  }

  Future<void> _sendCode() async {
    if (_busy || _countdown > 0) return;
    _busyAction = 'code';
    if (!RegExp(r'^1\d{10}$').hasMatch(_phone.text.trim())) {
      setState(() => _message = '请输入正确的 11 位手机号');
      return;
    }
    final generation = _generation;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await ref
          .read(platformAccountProvider.notifier)
          .readyForInteractiveLogin();
      if (_isNetease) {
        await _netLogin.sendCode(_phone.text.trim(), '86');
      } else {
        await _login.sendCode(_phone.text.trim());
      }
      if (!mounted || generation != _generation) return;
      setState(() {
        _countdown = 60;
        _message = null;
      });
      showMusicNotice(
        context,
        icon: Icons.check_rounded,
        title: '验证码已发送',
        message: '',
      );
      _countdownTimer?.cancel();
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted || _countdown <= 1) {
          timer.cancel();
          if (mounted) setState(() => _countdown = 0);
        } else {
          setState(() => --_countdown);
        }
      });
    } on Object catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _message = _error(error));
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _phoneLogin() async {
    if (_busy) return;
    if (_isNetease) return _loginNetease();
    _busyAction = 'login';
    final phone = _phone.text.trim();
    final code = _code.text.trim();
    if (!RegExp(r'^1\d{10}$').hasMatch(phone) ||
        !RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() => _message = '请填写正确的手机号和 6 位验证码');
      return;
    }
    final generation = _generation;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await ref
          .read(platformAccountProvider.notifier)
          .readyForInteractiveLogin();
      var result = await _login.phoneLogin(phone, code);
      if (!mounted || generation != _generation) return;
      var data = MusicPlatformApi.objectMap(result['data']);
      if ('${result['error_code']}' == '34175') {
        final rows = data['info_list'];
        if (rows is! List || rows.isEmpty) {
          throw const MusicPlatformException('此手机号的账号列表暂时不可用');
        }
        final selected = await showLiquidGlassBottomSheet<String>(
          context: context,
          showDragHandle: true,
          builder: (context) => SafeArea(
            child: ListView(
              shrinkWrap: true,
              children: [
                const ListTile(title: Text('选择音乐平台账号')),
                for (final row in rows.whereType<Map>())
                  ListTile(
                    title: Text(
                      '${row['nickname'] ?? row['userid'] ?? '酷狗账号'}',
                    ),
                    onTap: () =>
                        Navigator.pop(context, '${row['userid'] ?? ''}'),
                  ),
              ],
            ),
          ),
        );
        if (!mounted ||
            generation != _generation ||
            selected == null ||
            selected.isEmpty) {
          return;
        }
        result = await _login.phoneLogin(phone, code, userId: selected);
        data = MusicPlatformApi.objectMap(result['data']);
      }
      if (!mounted || generation != _generation) return;
      if ('${result['status']}' != '1') {
        throw const MusicPlatformException('登录未成功，请核对验证码或稍后重试');
      }
      await ref.read(platformAccountProvider.notifier).accept(data);
      if (mounted && generation == _generation) Navigator.of(context).pop(true);
    } on Object catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _message = _error(error));
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _loginNetease() async {
    final generation = _generation;
    setState(() {
      _busy = true;
      _busyAction = 'login';
      _message = null;
    });
    try {
      final result = await _netLogin.login(
        widget.neteaseMethod,
        _phone.text.trim(),
        widget.neteaseMethod == NeteaseLoginMethod.sms
            ? _code.text.trim()
            : _password.text,
      );
      if (!mounted || generation != _generation) return;
      await ref.read(platformAccountProvider.notifier).acceptNetease(result);
      if (mounted && generation == _generation) Navigator.of(context).pop(true);
    } on Object catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _message = _error(error));
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _pollNetease(
    NeteaseQrChallenge challenge,
    int generation,
  ) async {
    final expiry = DateTime.now().add(const Duration(minutes: 3));
    while (mounted &&
        generation == _generation &&
        DateTime.now().isBefore(expiry)) {
      await Future<void>.delayed(const Duration(seconds: 2));
      if (!mounted || generation != _generation) return;
      try {
        final result = await _netLogin.poll(challenge);
        if (!mounted || generation != _generation) return;
        if (result == null) continue;
        await ref.read(platformAccountProvider.notifier).acceptNetease(result);
        if (mounted && generation == _generation) {
          Navigator.of(context).pop(true);
        }
        return;
      } on Object catch (error) {
        if (mounted && generation == _generation) {
          setState(() {
            _message = _error(error);
            _polling = false;
          });
        }
        return;
      }
    }
    if (mounted && generation == _generation) {
      setState(() {
        _message = '二维码已过期，请刷新';
        _polling = false;
      });
    }
  }

  Widget _neteasePasswordFields() => AutofillGroup(
    child: Column(
      children: [
        BetaGlassField(
          child: TextField(
            key: const ValueKey('netease-login-account'),
            controller: _phone,
            contextMenuBuilder: buildBetaEditingMenu,
            selectionControls: mestingTextSelectionControls,
            keyboardType: widget.neteaseMethod == NeteaseLoginMethod.email
                ? TextInputType.emailAddress
                : TextInputType.phone,
            enabled: !_busy,
            autofillHints: const [AutofillHints.username],
            style: const TextStyle(fontSize: 18),
            decoration: InputDecoration(
              labelText: widget.neteaseMethod == NeteaseLoginMethod.email
                  ? '网易邮箱'
                  : '手机号',
            ),
          ),
        ),
        const SizedBox(height: 14),
        BetaGlassField(
          child: TextField(
            key: const ValueKey('netease-login-password'),
            controller: _password,
            contextMenuBuilder: buildBetaEditingMenu,
            selectionControls: mestingTextSelectionControls,
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
            enabled: !_busy,
            autofillHints: const [AutofillHints.password],
            style: const TextStyle(fontSize: 18),
            decoration: const InputDecoration(labelText: '密码'),
            onSubmitted: (_) => _phoneLogin(),
          ),
        ),
      ],
    ),
  );

  String _error(Object error) =>
      error is MusicPlatformException ? error.message : '音乐平台暂时不可用，请重试或返回先体验';

  String _label(PlatformLoginMethod method) => _isNetease
      ? '网易云扫码'
      : switch (method) {
          PlatformLoginMethod.phone => '手机验证码',
          PlatformLoginMethod.kugouQr => '酷狗扫码',
          PlatformLoginMethod.wechatQr => '微信扫码',
          PlatformLoginMethod.qqQr => 'QQ 扫码',
        };

  Future<void> _logout() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _busyAction = 'logout';
      _message = null;
    });
    try {
      if (ref.read(platformAccountProvider).value != null) {
        await ref.read(platformAccountProvider.notifier).signOut();
      } else {
        await ref.read(authControllerProvider.notifier).signOut();
      }
    } catch (_) {
      if (mounted) setState(() => _message = '退出未完成，请重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// A dedicated method page: identity/form/waiting are separate from the
  /// welcome's choice of account. Each field/button retains its own glass layer.
  @override
  Widget build(BuildContext context) {
    final account = ref.watch(platformAccountProvider);
    final session = account.value;
    final user = ref.watch(currentUserProvider);
    final profile = session == null
        ? null
        : ref.watch(platformProfileProvider).value;
    final signedIn = !widget.loginOnly && (session != null || user != null);
    final scheme = Theme.of(context).colorScheme;
    final title = signedIn
        ? '当前账号'
        : _method == PlatformLoginMethod.phone
        ? (_isNetease ? widget.neteaseMethod.label : '手机号登录')
        : '${_label(_method)}登录';
    final codeLabel = _countdown > 0 ? '${_countdown}s 后重试' : '获取验证码';
    return Scaffold(
      key: const ValueKey('platform-account-opaque-page'),
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 14, 22, 8),
                  child: Row(
                    children: [
                      const BetaGlassBackButton(),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontSize: 25,
                            fontWeight: FontWeight.w700,
                            color: scheme.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: BetaGlassScrollBody(
                    padding: const EdgeInsets.fromLTRB(24, 30, 24, 32),
                    children: [
                      if (account.isLoading)
                        const Center(child: BetaActivityIndicator())
                      else if (signedIn) ...[
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: PlatformAvatar(
                            url:
                                profile?.avatarUrl ??
                                session?.avatarUrl ??
                                user?.avatarUrl ??
                                '',
                          ),
                          title: Text(
                            profile?.nickname ??
                                session?.nickname ??
                                user?.nickname ??
                                '当前账号',
                          ),
                          subtitle: Text(
                            session != null
                                ? '${session.platformLabel}账号 · 已登录'
                                : 'Mesting 账号 · 已登录',
                          ),
                        ),
                        const SizedBox(height: 24),
                        if (session?.platform == MusicPlatform.netease)
                          BetaGlassButton(
                            onPressed: _busy
                                ? null
                                : () async {
                                    setState(() => _busy = true);
                                    try {
                                      await ref
                                          .read(
                                            platformAccountProvider.notifier,
                                          )
                                          .refreshNetease();
                                      if (mounted) {
                                        setState(() => _message = '网易云登录状态已刷新');
                                      }
                                    } catch (_) {
                                      if (mounted) {
                                        setState(
                                          () => _message = '刷新未完成，已保留原登录状态',
                                        );
                                      }
                                    } finally {
                                      if (mounted) {
                                        setState(() => _busy = false);
                                      }
                                    }
                                  },
                            child: const Text('刷新网易云登录状态'),
                          ),
                        BetaGlassButton(
                          loading: _busy && _busyAction == 'logout',
                          onPressed: _busy ? null : _logout,
                          child: const Text('退出登录'),
                        ),
                      ] else if (_method == PlatformLoginMethod.phone) ...[
                        Text(
                          _isNetease
                              ? '使用网易云音乐账号，继续你的音乐。'
                              : '使用酷狗账号手机号，继续你的音乐。',
                          style: TextStyle(
                            fontSize: 15,
                            height: 1.6,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 28),
                        if (_isNetease &&
                            widget.neteaseMethod != NeteaseLoginMethod.sms)
                          _neteasePasswordFields()
                        else
                          AutofillGroup(
                            child: Column(
                              children: [
                                BetaGlassField(
                                  child: TextField(
                                    contextMenuBuilder: buildBetaEditingMenu,
                                    selectionControls:
                                        mestingTextSelectionControls,
                                    cursorRadius: const Radius.circular(1),
                                    key: const ValueKey('beta11-phone-field'),
                                    controller: _phone,
                                    keyboardType: TextInputType.phone,
                                    enabled: !_busy,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                      LengthLimitingTextInputFormatter(11),
                                    ],
                                    autofillHints: const [
                                      AutofillHints.telephoneNumberNational,
                                    ],
                                    style: const TextStyle(fontSize: 18),
                                    decoration: const InputDecoration(
                                      hintText: '手机号码',
                                      prefixIcon: Padding(
                                        padding: EdgeInsets.only(
                                          left: 18,
                                          right: 12,
                                        ),
                                        child: Text(
                                          '+86',
                                          style: TextStyle(fontSize: 17),
                                        ),
                                      ),
                                      prefixIconConstraints: BoxConstraints(
                                        minWidth: 66,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                _InlineCodeField(
                                  controller: _code,
                                  enabled: !_busy,
                                  label: codeLabel,
                                  loading: _busy && _busyAction == 'code',
                                  onSend: _busy || _countdown > 0
                                      ? null
                                      : _sendCode,
                                  onSubmitted: (_) => _phoneLogin(),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 18),
                        BetaGlassButton(
                          key: const ValueKey('beta11-phone-submit'),
                          blue: true,
                          loading: _busy && _busyAction == 'login',
                          interactionEnabled: !_busy,
                          onPressed: _phoneLogin,
                          child: const Text('登录'),
                        ),
                      ] else ...[
                        Text(
                          '使用${_label(_method).replaceAll('扫码', '')}扫描二维码并确认登录。',
                          style: TextStyle(
                            fontSize: 15,
                            height: 1.6,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 32),
                        if (_busy)
                          const Center(
                            child: BetaActivityIndicator(label: '正在获取二维码'),
                          ),
                        if (_neteaseChallenge != null)
                          Center(
                            child: Container(
                              color: Colors.white,
                              padding: const EdgeInsets.all(12),
                              child: QrImageView(
                                data: _neteaseChallenge!.url,
                                size: 220,
                                backgroundColor: Colors.white,
                                semanticsLabel: '网易云扫码登录二维码',
                              ),
                            ),
                          ),
                        if (_challenge != null)
                          Center(
                            child: Container(
                              color: Colors.white,
                              padding: const EdgeInsets.all(12),
                              child: Image.memory(
                                base64Decode(_challenge!.imageBase64),
                                width: 220,
                                height: 220,
                                semanticLabel: '${_label(_method)}登录二维码',
                                errorBuilder: (_, _, _) =>
                                    const Text('二维码无法显示，请刷新'),
                              ),
                            ),
                          ),
                        const SizedBox(height: 24),
                        BetaGlassButton(
                          onPressed: _busy ? null : () => _select(_method),
                          child: const Text('刷新二维码'),
                        ),
                        if (_polling)
                          const Padding(
                            padding: EdgeInsets.only(top: 20),
                            child: Center(
                              child: BetaActivityIndicator(label: '等待扫码确认'),
                            ),
                          ),
                      ],
                      if (_message != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 20),
                          child: Semantics(
                            liveRegion: true,
                            child: Text(
                              _message!,
                              style: TextStyle(
                                color: scheme.onSurfaceVariant,
                                height: 1.6,
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
        ),
      ),
    );
  }
}

/// Only layout lives here; sending, countdown and credentials remain owned by
/// the method page. Narrow/large-text layouts keep the identifier above the
/// field and wrap the suffix, reserving room for a complete six-digit code.
class _InlineCodeField extends StatelessWidget {
  const _InlineCodeField({
    required this.controller,
    required this.enabled,
    required this.label,
    required this.loading,
    required this.onSend,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final bool enabled, loading;
  final String label;
  final VoidCallback? onSend;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scaler = MediaQuery.textScalerOf(context);
      final textStyle = DefaultTextStyle.of(context).style;
      double measure(String text, double fontSize, {bool bold = false}) {
        final painter = TextPainter(
          text: TextSpan(
            text: text,
            style: textStyle.copyWith(
              fontSize: fontSize,
              fontWeight: bold ? FontWeight.w700 : FontWeight.normal,
            ),
          ),
          textDirection: Directionality.of(context),
          textScaler: scaler,
        )..layout();
        final width = painter.width;
        painter.dispose();
        return width;
      }

      // Stable width across pending/countdown/retry avoids moving the caret.
      final fullAction =
          math.max(
            measure('获取验证码', 13, bold: true),
            measure('60s 后重试', 13, bold: true),
          ) +
          36;
      final compact =
          constraints.maxWidth < fullAction + measure('000000', 18) + 54;
      final actionWidth = compact
          ? math.max(
                  measure('验证码', 13, bold: true),
                  measure('60s', 13, bold: true),
                ) +
                24
          : fullAction;
      final actionHeight = compact
          ? math.max(44.0, scaler.scale(13) * 2.6 + 14)
          : 44.0;
      final actionLabel = compact
          ? label == '获取验证码'
                ? '获取\n验证码'
                : label.replaceFirst(' ', '\n')
          : label;
      final fieldSize = compact ? 16.0 : 18.0;
      final fieldHeight = math.max(
        actionHeight + 12,
        scaler.scale(fieldSize) * 1.4 + 34,
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (compact) ...[
            Padding(
              padding: const EdgeInsets.only(left: 16, bottom: 8),
              child: Text(
                '验证码',
                key: const ValueKey('beta11-code-label'),
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
          // Independent sibling glass layers retain premium refraction even
          // though the action is visually placed inside the field's outline.
          Stack(
            alignment: Alignment.centerRight,
            children: [
              BetaGlassField(
                child: SizedBox(
                  height: fieldHeight,
                  child: Center(
                    child: Semantics(
                      label: compact ? '验证码' : null,
                      child: TextField(
                        contextMenuBuilder: buildBetaEditingMenu,
                        selectionControls: mestingTextSelectionControls,
                        cursorRadius: const Radius.circular(1),
                        key: const ValueKey('beta11-code-field'),
                        controller: controller,
                        keyboardType: TextInputType.number,
                        enabled: enabled,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(6),
                        ],
                        autofillHints: const [AutofillHints.oneTimeCode],
                        style: TextStyle(fontSize: fieldSize),
                        onSubmitted: onSubmitted,
                        decoration: InputDecoration(
                          contentPadding: EdgeInsets.fromLTRB(
                            compact ? 8 : 20,
                            17,
                            actionWidth + (compact ? 10 : 14),
                            17,
                          ),
                          hintText: compact ? null : '验证码',
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 7,
                top: 0,
                bottom: 0,
                width: actionWidth,
                child: Center(
                  child: BetaGlassButton(
                    key: const ValueKey('beta11-send-code'),
                    label: label,
                    width: actionWidth,
                    height: actionHeight,
                    fontSize: 13,
                    horizontalPadding: compact ? 12 : 18,
                    loading: loading,
                    onPressed: onSend,
                    child: Text(actionLabel, textAlign: TextAlign.center),
                  ),
                ),
              ),
            ],
          ),
        ],
      );
    },
  );
}
