import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/widgets/beta_content_insets.dart';
import '../../../shared/widgets/beta_glass_controls.dart';
import '../../../shared/widgets/music_activity_indicator.dart';
import '../../../shared/widgets/music_feature_page.dart';
import '../../../shared/widgets/beta_secondary_music_layout.dart';
import 'qishui_api.dart';
import 'qishui_listening_providers.dart';
import 'qishui_page_scope.dart';

/// Official totals are always read from Soda. Locally observed and submitted
/// intervals are useful to the user but must never be added to that total.
class QishuiListeningPage extends ConsumerStatefulWidget {
  const QishuiListeningPage({super.key});
  @override
  ConsumerState<QishuiListeningPage> createState() =>
      _QishuiListeningPageState();
}

class _QishuiListeningPageState extends ConsumerState<QishuiListeningPage>
    with QishuiOwnedPage<QishuiListeningPage> {
  Future<void> _refresh() async {
    ref.invalidate(qishuiOfficialListeningProvider);
    ref.invalidate(qishuiListeningLedgerProvider);
    try {
      await ref.read(qishuiOfficialListeningProvider.future);
    } on Object {
      /* Visible error below. */
    }
  }

  Widget _value(String name, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Wrap(
      spacing: 16,
      runSpacing: 6,
      children: [Text(name), Text(value)],
    ),
  );
  @override
  Widget build(BuildContext context) {
    if (!watchOwner()) return changedAccount();
    final officialState = ref.watch(qishuiOfficialListeningProvider);
    final official = officialState.isReloading ? null : officialState.value;
    final localState = ref.watch(qishuiListeningLedgerProvider);
    final local = localState.isReloading ? null : localState.value;
    final status = ref.watch(qishuiListeningStatusProvider);
    final title = Theme.of(context).textTheme.titleLarge;
    return BetaSecondaryMusicLayout.wrap(
      context,
      MusicFeaturePage(
        title: '汽水听歌时长',
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              24,
              16,
              24,
              BetaContentInsets.musicBottomOf(context),
            ),
            children: [
              Text('官方累计', style: title),
              if (officialState.isLoading && official == null)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: MusicActivityIndicator()),
                ),
              _value('听歌总时长', qishuiListeningLabel(official?.totalSeconds)),
              _value('本周听歌', qishuiListeningLabel(official?.weekSeconds)),
              if (official != null)
                Text(
                  '读取时间：${official.fetchedAt.toLocal().toString().split('.').first}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              if (officialState.hasError)
                Semantics(
                  liveRegion: true,
                  child: Text(
                    officialState.error is QishuiException
                        ? (officialState.error as QishuiException).message
                        : '官方听歌时长暂未取得，请重试。',
                  ),
                ),
              const SizedBox(height: 12),
              BetaGlassButton(onPressed: _refresh, child: const Text('刷新官方时长')),
              const SizedBox(height: 28),
              Text('本次打开后的实际收听', style: title),
              _value(
                '已收听',
                qishuiListeningLabel(status.heardMilliseconds ~/ 1000),
              ),
              _value(
                '已提交，待官版核对',
                qishuiListeningLabel(
                  status.transportAcceptedMilliseconds ~/ 1000,
                ),
              ),
              _value(
                '提交尚未确认',
                qishuiListeningLabel(status.unconfirmedMilliseconds ~/ 1000),
              ),
              if (status.message.isNotEmpty)
                Semantics(liveRegion: true, child: Text(status.message)),
              const SizedBox(height: 28),
              Text('Mesting 本机记录', style: title),
              _value(
                '累计实际收听',
                qishuiListeningLabel(
                  local?.heardMilliseconds == null
                      ? null
                      : local!.heardMilliseconds ~/ 1000,
                ),
              ),
              _value(
                '已提交，待官版核对',
                qishuiListeningLabel(
                  local?.transportAcceptedMilliseconds == null
                      ? null
                      : local!.transportAcceptedMilliseconds ~/ 1000,
                ),
              ),
              _value(
                '尚未确认',
                qishuiListeningLabel(
                  local?.unconfirmedMilliseconds == null
                      ? null
                      : local!.unconfirmedMilliseconds ~/ 1000,
                ),
              ),
              if (localState.hasError) const Text('本机记录暂未读取成功，下拉可重试。'),
              const SizedBox(height: 12),
              const Text('本机记录从本版开始按汽水账号保存。仅统计实际播放，暂停、缓冲和拖动进度不会增加时长。'),
              const SizedBox(height: 12),
              const Text(
                '官方累计以刷新读回的数值为准。请求被接收仍需核对官版入账；本机记录不会直接加到官方数值上，也不会重发结果未确认的旧记录。',
              ),
            ],
          ),
        ),
      ),
      selectedIndex: 3,
    );
  }
}
