import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../presentation/platform_design.dart';
import '../retained_kugou_scope.dart';

const neteaseAutomaticSourceOrder = '网易云官方 → 酷狗概念版账号 → 其他备用音源 → BugPk';

/// Reports the independently retained Kugou identity without switching the
/// active platform, probing account entitlements, or changing resolver policy.
class NeteaseAccountSourceInfo extends ConsumerWidget {
  const NeteaseAccountSourceInfo({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(retainedKugouSessionProvider);
    final saved = ref.watch(savedKugouSessionProvider);
    final String status;
    if (account != null) {
      final name = account.nickname.trim();
      status = '已保存登录 · ${name.isEmpty ? '酷狗账号' : name}';
    } else if (saved.isLoading) {
      status = '正在读取账号状态…';
    } else if (saved.hasError) {
      status = '账号状态读取失败，请在账号管理中重试';
    } else {
      status = '尚未登录酷狗账号';
    }
    return PlatformPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(CupertinoIcons.music_note_2, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '酷狗概念版账号',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(status, key: const ValueKey('kugou-account-source-status')),
          const SizedBox(height: 8),
          Text(
            '网易云原曲不可播放或仅可试听时，使用已保存的酷狗账号尝试匹配同一录音。实际可用音质以账号权益与返回音频为准。',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
