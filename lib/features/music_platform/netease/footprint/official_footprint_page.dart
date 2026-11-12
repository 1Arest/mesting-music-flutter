import 'lifetime_duration_check.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../shared/widgets/beta_choice_field.dart';
import '../../../../shared/widgets/beta_content_insets.dart';
import '../../../../shared/widgets/beta_glass_controls.dart';
import '../../presentation/platform_design.dart';
import '../../music_platform_providers.dart';
import '../diagnostics/netease_listening_audit_provider.dart';
import 'official_footprint.dart';
import 'official_footprint_reader.dart';
import 'official_footprint_providers.dart';

class OfficialFootprintPage extends ConsumerStatefulWidget {
  const OfficialFootprintPage({super.key});
  @override
  ConsumerState<OfficialFootprintPage> createState() => _FootprintPageState();
}

class _FootprintPageState extends ConsumerState<OfficialFootprintPage>
    with WidgetsBindingObserver {
  OfficialFootprintReader? _bound;
  Timer? _calendar;
  bool _active = true;
  String? _selectedMonth;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // This only detects a civil-date change. It does not poll account data or
    // upload playback every minute while the user listens.
    _calendar = Timer.periodic(const Duration(minutes: 1), (_) {
      if (_active &&
          mounted &&
          ModalRoute.of(context)?.isCurrent == true &&
          _bound?.calendarChanged == true) {
        unawaited(_bound!.refresh());
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    if (_active && mounted && ModalRoute.of(context)?.isCurrent == true) {
      unawaited(_bound?.refresh() ?? Future.value());
    }
  }

  @override
  void dispose() {
    _calendar?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  String _time(DateTime? value) {
    if (value == null) return '';
    final t = footprintDate(value);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${footprintDay(value)} ${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  Widget _reading(String title, FootprintReading<int> item, String expected) {
    final value = item.value;
    final oldPeriod = value != null && item.key != expected;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            value == null
                ? '暂未获取'
                : '${oldPeriod ? '上次记录 ${item.key}：' : ''}${officialDuration(value)}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          if (item.readAt != null) Text('读取于 ${_time(item.readAt)}（北京时间）'),
          if (item.loading) const Text('正在读取官方数据…'),
          if (item.failed)
            Text(value == null ? '读取失败，可点击刷新重试' : '刷新失败，保留上次成功读取值'),
          if (oldPeriod) const Text('日期已变化，上次记录不代表当前日期的数据'),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final reader = ref.watch(officialFootprintReaderProvider);
    if (_bound != reader) {
      _bound = reader;
      // Defer state notifications until after this provider/widget build. The
      // identity check prevents the previous account's queued callback running.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && reader != null && identical(reader, _bound)) {
          unawaited(reader.refresh());
        }
      });
    }
    return PlatformPageFrame(
      title: '云村听歌足迹',
      child: reader == null
          ? const Center(child: Text('请返回并选择网易云账号'))
          : AnimatedBuilder(
              animation: reader,
              builder: (context, _) {
                final now = footprintDate(reader.now());
                final day = footprintDay(reader.now());
                final month = day.substring(0, 7);
                final months = [
                  for (var i = 1; i <= 36; i++)
                    '${DateTime.utc(now.year, now.month - i).year}-${DateTime.utc(now.year, now.month - i).month.toString().padLeft(2, '0')}',
                ];
                final selected = _selectedMonth ?? months.first;
                // A selected month stays selectable after the calendar rolls over.
                if (!months.contains(selected)) months.add(selected);
                final history = reader.history;
                return ListView(
                  key: const ValueKey('official-footprint-list'),
                  padding: BetaContentInsets.musicPaddingOf(
                    context,
                    const EdgeInsets.fromLTRB(22, 12, 22, 190),
                  ),
                  children: [
                    const Text('以下为网易云官方返回的统计，包含账号多端数据；不会把本机分钟数加到官方读数中。'),
                    const SizedBox(height: 16),
                    BetaGlassButton(
                      key: const ValueKey('footprint-refresh'),
                      loading: reader.loading,
                      onPressed: () => reader.refresh(),
                      child: const Text('刷新官方数据'),
                    ),
                    _reading('今日收听 · $day', reader.today, day),
                    const Divider(),
                    _reading('当前月收听 · $month', reader.month, month),
                    const Divider(),
                    _reading('历史总时长', reader.total, day),
                    const LifetimeDurationCheck(),
                    const Text(
                      '今日统计可能延迟 1～2 分钟；历史总时长按天更新，具体时刻由网易云处理。周日下午 15 点前后更新的是周报。',
                    ),
                    const SizedBox(height: 28),
                    Text(
                      '历史月报核对',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    BetaChoiceField<String>(
                      key: const ValueKey('footprint-month'),
                      initialValue: selected,
                      decoration: const InputDecoration(labelText: '选择历史月份'),
                      items: [
                        for (final value in months)
                          DropdownMenuItem(value: value, child: Text(value)),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => _selectedMonth = value);
                        reader.selectMonth();
                      },
                    ),
                    const SizedBox(height: 12),
                    BetaGlassButton(
                      key: const ValueKey('footprint-history'),
                      loading: history.loading,
                      onPressed: () => reader.readHistory(selected),
                      child: const Text('读取月报并核对'),
                    ),
                    if (history.value != null && history.key == selected) ...[
                      const SizedBox(height: 16),
                      Text(
                        '$selected 官方月报：${officialDuration(history.value!.seconds)}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text('读取于 ${_time(history.readAt)}（北京时间）'),
                      _LocalComparison(month: selected),
                    ],
                    if (history.failed)
                      const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: Text(
                          '官方月报读取失败或尚未开放所选月份，请重试；会员查看范围也可能影响读取。有上次成功值时继续保留。',
                        ),
                      ),
                    const SizedBox(height: 12),
                    const Text(
                      '官方包含多端、播客及有声书，并有收听门槛；本机按收听日汇总，逐次记录按开始日归月。三种统计不能直接相减作为缺失分钟。读取月报不会补发或修改旧记录，不能据此承诺追回十月时长。',
                    ),
                  ],
                );
              },
            ),
    );
  }
}

class _LocalComparison extends ConsumerWidget {
  const _LocalComparison({required this.month});
  final String month;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final owner = ref.watch(platformAccountProvider).value?.ownerId;
    return ref
        .watch(neteaseListeningAuditProvider(month))
        .when(
          data: (audit) => !audit.belongsTo(owner ?? '')
              ? const Text('账号已变化，请重新读取本机记录')
              : Text(
                  '本机网易云歌曲：${officialDuration((audit.local['neteaseSongsActualMs'] as int) ~/ 1000)}\n'
                  '本机逐次记录：${audit.duration['events']} 条，已知真实收听 ${officialDuration((audit.duration['knownActualMs'] as int) ~/ 1000)}',
                ),
          error: (_, _) => const Text('本机记录暂时无法读取，官方月报值保留'),
          loading: () => const Text('正在读取本机记录…'),
        );
  }
}
