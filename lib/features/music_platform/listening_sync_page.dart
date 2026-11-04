import '../../shared/widgets/music_notice.dart';
import '../../shared/widgets/beta_content_insets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/widgets/beta_glass_controls.dart';
import 'listening_sync/listening_sync_providers.dart';
import 'presentation/platform_design.dart';

/// Acknowledged transport and confirmed official entries remain visibly
/// different, especially after a timeout that must not be blindly repeated.
class ListeningSyncPage extends ConsumerWidget {
  const ListeningSyncPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(platformListeningSyncEnabledProvider);
    final summary = ref.watch(platformListeningSyncSummaryProvider);
    return PlatformPageFrame(
      title: '酷狗播放同步',
      child: ListView(
        padding: BetaContentInsets.musicPaddingOf(
          context,
          EdgeInsets.fromLTRB(24, 20, 24, 210),
        ),
        children: [
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('同步播放历史与听歌时长'),
            subtitle: const Text('使用当前登录的酷狗账号'),
            value: enabled,
            onChanged: (value) async {
              try {
                await ref
                    .read(platformListeningSyncEnabledProvider.notifier)
                    .setEnabled(value);
              } on Object {
                if (context.mounted) {
                  showMusicNotice(
                    context,
                    icon: Icons.error_outline_rounded,
                    title: '设置暂未保存，请重试',
                    message: '',
                  );
                }
              }
            },
          ),
          const SizedBox(height: 24),
          const Text(
            '新播放记录在后台同步，暂停、缓冲和拖动进度不计入收听时长。已有歌曲历史按可还原的信息补传；升级前的累计时长完整保留在本地听歌回顾中。',
          ),
          const SizedBox(height: 24),
          summary.when(
            loading: () => const Text('正在读取同步状态…'),
            error: (_, _) => const Text('同步状态暂未读取，请重新打开此页面'),
            data: (state) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('已由酷狗读回确认：${state.verified} 项'),
                const SizedBox(height: 10),
                Text('平台已接收，等待确认：${state.accepted} 项'),
                const SizedBox(height: 10),
                Text('等待发送：${state.queued} 项'),
                const SizedBox(height: 10),
                Text('结果待核对：${state.uncertain} 项'),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            '请求已接收不代表官方时长已经入账。网络中断时，应用会保留结果待核对的记录，避免重复上报；最终以酷狗实际记录为准。',
          ),
          const SizedBox(height: 24),
          BetaGlassButton(
            onPressed: () async {
              await ref.read(platformListeningSyncProvider).verifyPending();
              ref.invalidate(platformListeningSyncSummaryProvider);
            },
            child: const Text('刷新同步状态'),
          ),
        ],
      ),
    );
  }
}
