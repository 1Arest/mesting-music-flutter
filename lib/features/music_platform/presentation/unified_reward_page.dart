import '../../../core/network/system_music_io_client.dart';
import '../../../shared/widgets/beta_content_insets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/diagnostics/diagnostic_activity.dart';
import '../../../shared/widgets/beta_glass_controls.dart';
import '../../../shared/widgets/beta_secondary_music_layout.dart';
import '../../../shared/widgets/beta_swipe_pages.dart';
import '../music_platform_providers.dart';
import '../retained_kugou_scope.dart';
import '../platform_backend_providers.dart';
import '../netease/netease_api.dart';
import '../netease/netease_features_repository.dart';
import '../netease/netease_music_repository.dart';
import '../netease/netease_providers.dart';
import 'platform_reward_calendar.dart';

/// This private jar permits a retained NetEase sign-in while Kugou is playing.
/// It never reconfigures the shared playback API or changes the queue owner.
final retainedNeteaseRewardProvider =
    FutureProvider<NeteaseFeaturesRepository?>((ref) async {
      ref.watch(retainedNeteaseEpochProvider);
      ref.watch(
        platformAccountProvider.select(
          (a) => (a.value?.ownerId, a.value?.token),
        ),
      );
      final session = await ref
          .watch(neteaseSessionStoreProvider)
          .read()
          .timeout(const Duration(seconds: 5));
      if (!ref.mounted || session == null) return null;
      final client = SystemMusicIoClient();
      final api = NeteaseApi(client)..configure(session);
      ref.onDispose(() {
        api.configure(null);
        client.close();
      });
      return NeteaseFeaturesRepository(NeteaseMusicRepository(api));
    }, retry: (_, _) => null);

/// Both tabs are production reward views. TabBarView preserves independent
/// scroll state and supports gestures without switching the music platform.
class UnifiedRewardPage extends ConsumerWidget {
  const UnifiedRewardPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      BetaSecondaryMusicLayout.wrap(
        context,
        DefaultTabController(
          length: 2,
          initialIndex: ref.read(usesNeteaseProvider) ? 0 : 1,
          child: Scaffold(
            key: const ValueKey('unified-reward-page'),
            appBar: AppBar(
              title: const Text('签到与会员'),
              bottom: const TabBar(
                tabs: [
                  Tab(text: '网易云'),
                  Tab(text: '酷狗'),
                ],
              ),
            ),
            body: TabBarView(
              children: [
                _activeRewardPage(0, const _NeteaseRewardTab()),
                _activeRewardPage(
                  1,
                  const PlatformRewardCalendar(embedded: true),
                ),
              ],
            ),
          ),
        ),
      );
}

/// TabBarView adds a viewport depth. Forward only the selected page's scroll
/// to the common bar, so retained hidden pages cannot take over its capsule.
Widget _activeRewardPage(int index, Widget child) => Builder(
  builder: (context) => NotificationListener<ScrollNotification>(
    onNotification: (scroll) {
      if (scroll.metrics.axis == Axis.vertical &&
          scroll.depth == 0 &&
          DefaultTabController.of(context).index == index) {
        BetaActivePageScrollNotification(scroll).dispatch(context);
      }
      return scroll.metrics.axis == Axis.vertical;
    },
    child: child,
  ),
);

class _NeteaseRewardTab extends ConsumerStatefulWidget {
  const _NeteaseRewardTab();
  @override
  ConsumerState<_NeteaseRewardTab> createState() => _NeteaseRewardTabState();
}

class _NeteaseRewardTabState extends ConsumerState<_NeteaseRewardTab> {
  bool _busy = false;
  String? _message;
  int? _ownerEpoch;
  Future<void> _sign(NeteaseFeaturesRepository service) async {
    if (_busy || ref.read(diagnosticActivityProvider)) return;
    final epoch = ref.read(retainedNeteaseEpochProvider);
    bool current() =>
        mounted &&
        epoch == ref.read(retainedNeteaseEpochProvider) &&
        ref.read(retainedNeteaseRewardProvider).value == service;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final message = await service.signIn();
      if (current()) {
        setState(() => _message = message);
      }
    } catch (_) {
      if (current()) setState(() => _message = '网易云签到未完成，请检查登录与网络后重试');
    } finally {
      if (current()) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final epoch = ref.watch(retainedNeteaseEpochProvider);
    if (_ownerEpoch != epoch) {
      _ownerEpoch = epoch;
      _message = null;
      _busy = false;
    }
    return ref
        .watch(retainedNeteaseRewardProvider)
        .when(
          loading: () => const Center(child: Text('正在读取网易云登录…')),
          error: (_, _) => Center(
            child: BetaGlassButton(
              onPressed: () => ref.invalidate(retainedNeteaseRewardProvider),
              child: const Text('登录读取失败，点击重试'),
            ),
          ),
          data: (service) => service == null
              ? const Center(child: Text('请先登录网易云账号；已保存的酷狗登录可继续用于签到'))
              : ListView(
                  key: const PageStorageKey('netease-reward-scroll'),
                  padding: BetaContentInsets.musicPaddingOf(
                    context,
                    EdgeInsets.fromLTRB(22, 22, 22, 180),
                  ),
                  children: [
                    const Text(
                      '网易云每日签到',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text('使用本机保存的网易云账号，平台确认后显示签到结果。'),
                    const SizedBox(height: 24),
                    BetaGlassButton(
                      onPressed: _busy || ref.watch(diagnosticActivityProvider)
                          ? null
                          : () => _sign(service),
                      child: Text(_busy ? '正在签到…' : '网易云每日签到'),
                    ),
                    if (_message != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 18),
                        child: Text(_message!),
                      ),
                  ],
                ),
        );
  }
}
