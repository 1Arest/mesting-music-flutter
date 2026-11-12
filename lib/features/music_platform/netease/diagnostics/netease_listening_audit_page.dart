import '../../../../shared/widgets/music_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../shared/widgets/beta_choice_field.dart';
import '../../../../shared/widgets/beta_content_insets.dart';
import '../../../../shared/widgets/beta_glass_controls.dart';
import '../../music_platform_providers.dart';
import '../../platform_backend_providers.dart';
import '../../presentation/platform_design.dart';
import 'netease_listening_audit.dart';
import 'netease_listening_audit_provider.dart';
import '../../../themes/music_typography.dart';

String _duration(Object? value) {
  final seconds = (value as int? ?? 0) ~/ 1000;
  return '${seconds ~/ 60} 分钟 ${seconds % 60} 秒';
}

class NeteaseListeningAuditPage extends ConsumerStatefulWidget {
  const NeteaseListeningAuditPage({this.initialMonth, super.key});
  final String? initialMonth;
  @override
  ConsumerState<NeteaseListeningAuditPage> createState() => _AuditPageState();
}

class _AuditPageState extends ConsumerState<NeteaseListeningAuditPage> {
  late String _month;
  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month =
        widget.initialMonth ?? auditMonth(DateTime(now.year, now.month - 1));
  }

  bool _current(NeteaseListeningAudit report) =>
      mounted &&
      ref.read(usesNeteaseProvider) &&
      report.belongsTo(ref.read(platformAccountProvider).value?.ownerId ?? '');

  Future<void> _preview(NeteaseListeningAudit report) async {
    if (!_current(report)) return;
    final text = report.json;
    final copy = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text('$_month 脱敏诊断'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '仅包含日期、时长、发送状态和匿名编号，不包含账号、歌曲名称或凭据。复制后由你决定是否分享，不会自动上传。',
                ),
                const SizedBox(height: 12),
                SelectableText(
                  text.length > 16000
                      ? '${text.substring(0, 16000)}\n…预览已截短，复制包含全部导出内容。'
                      : text,
                  style: const TextStyle(fontSize: MusicTypography.captionSize),
                ),
              ],
            ),
          ),
        ),
        actions: [
          BetaGlassButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('取消'),
          ),
          BetaGlassButton(
            key: const ValueKey('audit-copy'),
            blue: true,
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('复制诊断'),
          ),
        ],
      ),
    );
    if (copy != true || !_current(report)) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted || !_current(report)) return;
    showMusicNotice(
      context,
      icon: Icons.check_rounded,
      title: '已复制本月脱敏诊断',
      message: '',
    );
  }

  Widget _fact(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Text('$label：$value'),
  );
  @override
  Widget build(BuildContext context) {
    final account = ref.watch(platformAccountProvider).value;
    final netease = ref.watch(usesNeteaseProvider);
    final state = netease && account != null
        ? ref.watch(neteaseListeningAuditProvider(_month))
        : null;
    final ready = state?.asData?.value;
    final months = ready != null && ready.belongsTo(account?.ownerId ?? '')
        ? ready.months
        : <String>{
            _month,
            auditMonth(DateTime.now()),
            auditMonth(DateTime(DateTime.now().year, DateTime.now().month - 1)),
          }.toList();
    return PlatformPageFrame(
      title: '听歌上报诊断',
      child: !netease || account == null
          ? const Center(child: Text('账号已变化，请返回后重新打开'))
          : Column(
              children: [
                // Keep the selector mounted while the local snapshot reloads or
                // its menu temporarily covers the route. A pending read must not
                // dispose the FormField that will deliver the selected month.
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 12, 22, 0),
                  child: BetaChoiceField<String>(
                    key: const ValueKey('audit-month'),
                    initialValue: _month,
                    decoration: const InputDecoration(labelText: '统计月份'),
                    items: [
                      for (final month in months)
                        DropdownMenuItem(value: month, child: Text(month)),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _month = value);
                    },
                  ),
                ),
                Expanded(
                  child: state!.when(
                    loading: () => const Center(
                      child: PlatformFeedbackState(loading: true),
                    ),
                    error: (_, _) => PlatformFeedbackState(
                      message: '本机记录暂时无法读取',
                      retry: () =>
                          ref.invalidate(neteaseListeningAuditProvider(_month)),
                    ),
                    skipLoadingOnRefresh: false,
                    data: (report) {
                      if (!report.belongsTo(account.ownerId)) {
                        return const Center(child: Text('账号已变化，请重新读取'));
                      }
                      final local = report.local,
                          events = report.duration,
                          fields = report.fields;
                      final states = events['states'] as Map<String, Object?>;
                      return ListView(
                        padding: BetaContentInsets.musicPaddingOf(
                          context,
                          const EdgeInsets.fromLTRB(22, 12, 22, 190),
                        ),
                        children: [
                          const Text(
                            '只读取当前网易云账号的本机记录。页面是读取时的快照，可刷新更新；诊断不修改统计、不补发、不联网核验。',
                          ),
                          const SizedBox(height: 16),
                          BetaGlassButton(
                            key: const ValueKey('audit-refresh'),
                            onPressed: () => ref.invalidate(
                              neteaseListeningAuditProvider(_month),
                            ),
                            child: const Text('重新读取本机记录'),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            '本机每日统计',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          _fact(
                            '全部歌曲真实收听',
                            _duration(local['allTracksActualMs']),
                          ),
                          _fact(
                            '其中网易云歌曲',
                            _duration(local['neteaseSongsActualMs']),
                          ),
                          _fact(
                            '其他来源',
                            _duration(local['otherTracksActualMs']),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '逐次时长上报',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          _fact(
                            '时长记录',
                            '${events['events']} 条，已知真实收听 ${_duration(events['knownActualMs'])}',
                          ),
                          _fact(
                            '真实时长无法从记录确定',
                            '${events['unknownActualEvents']} 条',
                          ),
                          for (final state in <String, String>{
                            'queued': '待发送',
                            'open': '未结束',
                            'accepted': '接口已接收',
                            'dispatched': '已发出未确认',
                            'unknown': '请求结果不明',
                            'rejected': '接口已拒绝',
                            'verified': '有独立核验标记',
                            'interrupted': '已中断',
                            'coalesced': '已归并',
                          }.entries)
                            if (((states[state.key] as Map)['events'] as int) >
                                0)
                              _fact(
                                state.value,
                                '${(states[state.key] as Map)['events']} 条，已知 ${_duration((states[state.key] as Map)['knownActualMs'])}',
                              ),
                          _fact(
                            '开始播放记录',
                            '${report.starts['events']} 条，最近播放匹配 ${report.starts['recentPlayConfirmed']} 条',
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '历史字段检查',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          _fact(
                            '缺少真实秒数字段 realtime',
                            '${fields['durationMissingRealtime']} 条时长记录',
                          ),
                          _fact(
                            '缺少原始时间字段 startlogtime',
                            '${fields['durationMissingStartlogtime']} 条时长记录',
                          ),
                          _fact(
                            '旧版或无版本标记',
                            '${fields['durationLegacyProtocol']} 条时长记录',
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            '本机按收听日统计，逐次记录按可确定的开始日期归月，跨午夜时不能直接相减。旧版缺少字段仅说明保存的记录不完整；接口接收和最近播放匹配都不能证明已计入云村足迹。',
                          ),
                          if (report.data['detailTruncated'] == true)
                            const Text('记录较多，导出明细已截取前5000条，汇总仍包含全部记录。'),
                          const SizedBox(height: 16),
                          BetaGlassButton(
                            key: const ValueKey('audit-export'),
                            onPressed: () => _preview(report),
                            child: const Text('预览并复制脱敏 JSON'),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
