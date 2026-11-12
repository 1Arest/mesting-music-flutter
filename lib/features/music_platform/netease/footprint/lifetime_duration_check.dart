import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/persistence/app_preferences.dart';
import '../../../../shared/widgets/beta_glass_controls.dart';
import '../../music_platform_providers.dart';
import 'official_footprint.dart';
import 'official_footprint_providers.dart';

/// Two genuine server reads provide a durable, account-scoped comparison.
/// This tool never turns accepted playback logs into claimed lifetime credit.
class LifetimeDurationCheck extends ConsumerStatefulWidget {
  const LifetimeDurationCheck({super.key});
  @override
  ConsumerState<LifetimeDurationCheck> createState() =>
      _LifetimeDurationCheckState();
}

class _LifetimeDurationCheckState extends ConsumerState<LifetimeDurationCheck> {
  bool _busy = false;
  String? _message, _messageOwner;
  Future<void> _read(bool saveBaseline) async {
    if (_busy) return;
    final account = ref.read(platformAccountProvider).value;
    final reader = ref.read(officialFootprintReaderProvider);
    if (account == null || reader == null) return;
    final owner = account.ownerId, token = account.token;
    final prefs = ref.read(sharedPreferencesProvider);
    final key = 'netease_official_total_baseline_v1_$owner';
    setState(() => _busy = true);
    try {
      await reader.refreshTotalOnly();
      if (!mounted ||
          ref.read(platformAccountProvider).value?.ownerId != owner ||
          ref.read(platformAccountProvider).value?.token != token) {
        return;
      }
      final total = reader.total;
      if (total.failed || total.value == null || total.readAt == null) {
        throw StateError('官方读数不可用');
      }
      if (saveBaseline) {
        final saved = await prefs.setString(
          key,
          jsonEncode({
            'seconds': total.value,
            'at': total.readAt!.toIso8601String(),
          }),
        );
        if (!saved) throw StateError('基线未保存');
        if (mounted) {
          setState(() {
            _messageOwner = owner;
            _message =
                '已保存官方基线：${officialDuration(total.value!)}。实际听歌后，待官方按天更新再回读核对。';
          });
        }
      } else {
        final raw = jsonDecode(prefs.getString(key) ?? '{}');
        if (raw is! Map || raw['seconds'] is! int || raw['at'] is! String) {
          throw StateError('请先保存基线');
        }
        final delta = total.value! - (raw['seconds'] as int);
        final baselineDay = footprintDay(DateTime.parse(raw['at'] as String));
        if (mounted) {
          setState(() {
            _messageOwner = owner;
            _message = delta > 0
                ? '与 $baselineDay 官方基线相比，账号累计增加 ${officialDuration(delta)}（多端汇总）。'
                : delta == 0
                ? '与 $baselineDay 官方基线相同，尚未观察到累计增长。官方历史总时长按天更新。'
                : '官方当前累计低于 $baselineDay 基线，请保留两次读数继续核对。';
          });
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _messageOwner = owner;
          _message = '本次核对未完成，请检查官方读取状态；已有基线保留。';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(platformAccountProvider).value;
    final raw = account == null
        ? null
        : ref
              .read(sharedPreferencesProvider)
              .getString(
                'netease_official_total_baseline_v1_${account.ownerId}',
              );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('官方累计增长核对', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text('保存官方读数作为基线，实际听歌后再回读。播放上报的接收状态和官方累计读数分别核对。'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              BetaGlassButton(
                height: 44,
                onPressed: _busy ? null : () => _read(true),
                child: const Text('保存官方基线'),
              ),
              BetaGlassButton(
                height: 44,
                onPressed: _busy || raw == null ? null : () => _read(false),
                child: const Text('回读并核对'),
              ),
            ],
          ),
          if (_message != null && _messageOwner == account?.ownerId)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_message!),
            ),
        ],
      ),
    );
  }
}
