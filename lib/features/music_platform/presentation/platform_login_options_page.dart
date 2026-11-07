import '../qishui/qishui_login_page.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/beta_glass_controls.dart';
import '../../../shared/widgets/beta_glass_scroll_body.dart';
import '../../../shared/widgets/beta_music_chrome_scope.dart';
import '../../../core/security/credential_failure.dart';
import '../../auth/presentation/beta_welcome_page.dart';
import '../domain/platform_session.dart';
import '../music_platform_providers.dart';
import '../netease/netease_login.dart';
import 'platform_account_page.dart';

/// Platform selection owns navigation only. Forms, glass controls and page
/// movement are the same components used by the existing Kugou login.
class PlatformLoginOptionsPage extends StatelessWidget {
  const PlatformLoginOptionsPage({required this.platform, super.key});
  final MusicPlatform platform;

  Future<void> _open(BuildContext context, Widget page) async {
    final result = await Navigator.of(context).push<bool>(betaEntryRoute(page));
    if (result == true && context.mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) => _AccountChoiceFrame(
    title: '${platform.label}登录',
    children: [
      if (platform == MusicPlatform.qishui)
        BetaGlassButton(
          onPressed: () => _open(context, const QishuiLoginPage()),
          child: const Text('手机号登录'),
        )
      else if (platform == MusicPlatform.kugou)
        for (final item in const [
          (PlatformLoginMethod.phone, '手机号登录'),
          (PlatformLoginMethod.kugouQr, '酷狗扫码登录'),
          (PlatformLoginMethod.wechatQr, '微信扫码登录'),
          (PlatformLoginMethod.qqQr, 'QQ 扫码登录'),
        ]) ...[
          BetaGlassButton(
            onPressed: () => _open(
              context,
              PlatformAccountPage(initialMethod: item.$1, loginOnly: true),
            ),
            child: Text(item.$2),
          ),
          const SizedBox(height: 14),
        ]
      else
        for (final method in NeteaseLoginMethod.values) ...[
          BetaGlassButton(
            onPressed: () => _open(
              context,
              PlatformAccountPage(
                platform: platform,
                neteaseMethod: method,
                loginOnly: true,
              ),
            ),
            child: Text(method.label),
          ),
          const SizedBox(height: 14),
        ],
    ],
  );
}

/// One explicit switch boundary; errors leave the current account selected.
/// Reading a retained credential never publishes it or starts music playback.
class MusicPlatformSwitchPage extends ConsumerStatefulWidget {
  const MusicPlatformSwitchPage({super.key});
  @override
  ConsumerState<MusicPlatformSwitchPage> createState() =>
      _MusicPlatformSwitchPageState();
}

class _MusicPlatformSwitchPageState
    extends ConsumerState<MusicPlatformSwitchPage> {
  bool _busy = false;
  MusicPlatform? _target;
  MusicPlatform? _unreadableTarget;
  String? _error;

  Future<void> _select(MusicPlatform platform) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _target = platform;
      _error = null;
      _unreadableTarget = null;
    });
    try {
      final controller = ref.read(platformAccountProvider.notifier);
      final saved = await controller.retainedIdentity(platform);
      if (!mounted) return;
      if (saved == null) {
        final success = await Navigator.of(context).push<bool>(
          betaEntryRoute(PlatformLoginOptionsPage(platform: platform)),
        );
        if (success != true) return;
      } else {
        await controller.switchPlatform(platform);
      }
      if (mounted) Navigator.of(context).pop(true);
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          if (error is CredentialStoreException || error is TimeoutException) {
            // A broken TARGET credential must not strand a healthy CURRENT
            // account. Only a subsequent, user-requested login may replace it.
            _unreadableTarget = platform;
            _error = error is CredentialStoreException
                ? error.message
                : '该平台登录资料仍在处理中，可重试或重新登录；原资料已保留';
          } else {
            _error = '切换未完成，请重试；原账号数据已保留。';
          }
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reauthenticate(MusicPlatform platform) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _target = platform;
    });
    try {
      final success = await Navigator.of(context).push<bool>(
        betaEntryRoute(PlatformLoginOptionsPage(platform: platform)),
      );
      // Cancelling the form leaves the selected account and both stores alone.
      // The existing controller owns authentication, durable save and publish.
      if (mounted && success == true) Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _platformButton(MusicPlatform platform, MusicPlatform? active) {
    final caption =
        '${platform.label}音乐'
        '${platform == active ? ' · 当前平台' : ''}';
    return LayoutBuilder(
      builder: (context, constraints) {
        // The current-platform suffix can wrap at large accessibility sizes.
        // Measure the same inherited type style instead of clipping two lines
        // inside the shared button's normal 52dp height or shrinking the text.
        final painter =
            TextPainter(
              text: TextSpan(
                text: caption,
                style: DefaultTextStyle.of(context).style.merge(
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
              textScaler: MediaQuery.textScalerOf(context),
              textDirection: Directionality.of(context),
            )..layout(
              maxWidth: (constraints.maxWidth - 36).clamp(1, double.infinity),
            );
        final height = painter.height + 24;
        painter.dispose();
        return BetaGlassButton(
          height: height > 52 ? height : 52,
          loading: _busy && _target == platform,
          onPressed: _busy || platform == active
              ? null
              : () => _select(platform),
          child: Text(caption, textAlign: TextAlign.center),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final active = ref.watch(platformAccountProvider).value?.platform;
    return _AccountChoiceFrame(
      title: '切换音乐平台',
      children: [
        for (final platform in MusicPlatform.values) ...[
          _platformButton(platform, active),
          const SizedBox(height: 14),
        ],
        if (_error != null)
          Text(
            _error!,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        if (_unreadableTarget != null) ...[
          const SizedBox(height: 16),
          BetaGlassButton(
            key: const ValueKey('platform-switch-reauthenticate'),
            loading: _busy,
            onPressed: _busy ? null : () => _reauthenticate(_unreadableTarget!),
            child: Text('重新登录${_unreadableTarget?.label}'),
          ),
        ],
      ],
    );
  }
}

class _AccountChoiceFrame extends StatelessWidget {
  const _AccountChoiceFrame({required this.title, required this.children});
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => BetaMusicChromeCover(
    child: Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
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
                          style: const TextStyle(
                            fontSize: 25,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: BetaGlassScrollBody(
                    padding: const EdgeInsets.fromLTRB(24, 30, 24, 32),
                    children: children,
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
