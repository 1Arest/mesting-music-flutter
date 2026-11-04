import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/beta_glass_controls.dart';
import '../../../shared/widgets/beta_glass_scroll_body.dart';
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
    title: platform == MusicPlatform.kugou ? '酷狗登录' : '网易云登录',
    children: [
      if (platform == MusicPlatform.kugou)
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
  String? _error;

  Future<void> _select(MusicPlatform platform) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _target = platform;
      _error = null;
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
    } catch (_) {
      if (mounted) setState(() => _error = '切换未完成，请重试；原账号数据已保留。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = ref.watch(platformAccountProvider).value?.platform;
    return _AccountChoiceFrame(
      title: '切换音乐平台',
      children: [
        for (final platform in MusicPlatform.values) ...[
          BetaGlassButton(
            loading: _busy && _target == platform,
            onPressed: _busy || platform == active
                ? null
                : () => _select(platform),
            child: Text(
              '${platform == MusicPlatform.kugou ? '酷狗音乐' : '网易云音乐'}'
              '${platform == active ? ' · 当前平台' : ''}',
            ),
          ),
          const SizedBox(height: 14),
        ],
        if (_error != null)
          Text(
            _error!,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}

class _AccountChoiceFrame extends StatelessWidget {
  const _AccountChoiceFrame({required this.title, required this.children});
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Scaffold(
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
  );
}
