import '../../../shared/widgets/music_feature_page.dart';
import 'qishui_page_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/widgets/beta_glass_controls.dart';
import '../../../shared/widgets/music_activity_indicator.dart';
import 'qishui_effects.dart';
import 'qishui_providers.dart';

class QishuiEffectsPage extends ConsumerStatefulWidget {
  const QishuiEffectsPage({super.key});
  @override
  ConsumerState<QishuiEffectsPage> createState() => _QishuiEffectsPageState();
}

class _QishuiEffectsPageState extends ConsumerState<QishuiEffectsPage>
    with QishuiOwnedPage<QishuiEffectsPage> {
  late Future<List<QishuiEffect>> _catalog = _load();
  Future<List<QishuiEffect>> _load() async {
    final music = ref.read(qishuiRepositoryProvider);
    final effects = await loadQishuiEffects();
    final commerce = await music.commerce();
    if (!music.current) return const [];
    // Device compensation/Douyin defaults are internal presets, not fourteen
    // interchangeable manual buttons in the official sound-effect panel.
    return effects
        .where(
          (effect) =>
              !{
                'speaker',
                'headset',
                'headset2',
                'headset3',
                'voice_clean_v2',
              }.contains(effect.key) &&
              qishuiEffectGrant(commerce, effect.key) != null,
        )
        .toList();
  }

  bool _busy = false;
  String? _message;
  Future<void> _select(QishuiEffect? effect) async {
    if (_busy || !ownerCurrent) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final controller = ref.read(qishuiEffectsProvider);
      if (effect == null) {
        await controller.off();
      } else {
        await controller.select(effect, ref.read(qishuiRepositoryProvider));
      }
      if (mounted) {
        setState(
          () => _message = effect == null ? '官版音效已关闭' : '已设置${effect.name}',
        );
      }
    } on Object catch (error) {
      if (mounted) setState(() => _message = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!watchOwner()) return changedAccount();
    return MusicFeaturePage(
      title: '汽水官版音效',
      child: FutureBuilder<List<QishuiEffect>>(
        future: _catalog,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('音效目录未能读取，请返回后重试'));
          }
          if (!snapshot.hasData) {
            return const Center(child: MusicActivityIndicator());
          }
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Text('选择时将核对汽水账号权益。此官版引擎仅支持 ARM64；部分配置可能不适用于当前设备或账号。'),
              const SizedBox(height: 20),
              if (snapshot.data!.isEmpty) const Text('当前账号未返回可用的官版音效。'),
              const SizedBox(height: 12),
              BetaGlassButton(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                        _catalog = _load();
                      }),
                child: const Text('刷新可用音效'),
              ),
              const SizedBox(height: 20),
              BetaGlassButton(
                onPressed: _busy ? null : () => _select(null),
                child: const Text('关闭官版音效'),
              ),
              if (_message != null) ...[
                const SizedBox(height: 20),
                Semantics(liveRegion: true, child: Text(_message!)),
              ],
              const SizedBox(height: 20),
              for (final effect in snapshot.data!)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(effect.name),
                  trailing:
                      ref.watch(qishuiEffectsProvider).selectedKey == effect.key
                      ? const Icon(Icons.check)
                      : null,
                  enabled: !_busy,
                  onTap: () => _select(effect),
                ),
            ],
          );
        },
      ),
    );
  }
}
