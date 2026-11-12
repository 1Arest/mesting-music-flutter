import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../core/network/music_diagnostic_clipboard.dart';
import '../../../shared/widgets/beta_glass_controls.dart';
import '../../../shared/widgets/beta_content_insets.dart';
import '../../../shared/widgets/beta_secondary_music_layout.dart';
import '../../../shared/widgets/music_feature_page.dart';
import 'qishui_diagnostic_export.dart';
import 'qishui_diagnostics.dart';

/// A passive view of already-recorded observations. Filtering, copying and
/// sharing never open a music endpoint or change the user's account state.
class QishuiDiagnosticsPage extends StatefulWidget {
  const QishuiDiagnosticsPage({this.diagnostics, this.exporter, super.key});
  final QishuiDiagnostics? diagnostics;
  final QishuiDiagnosticExport? exporter;

  @override
  State<QishuiDiagnosticsPage> createState() => _QishuiDiagnosticsPageState();
}

class _QishuiDiagnosticsPageState extends State<QishuiDiagnosticsPage> {
  late final _diagnostics = widget.diagnostics ?? QishuiDiagnostics.shared;
  late final _exporter = widget.exporter ?? QishuiDiagnosticExport();
  QishuiDiagnosticGroup _group = QishuiDiagnosticGroup.all;
  bool _busy = false;
  String _status = '';

  Future<void> _copy({required bool compact}) async {
    if (_busy) return;
    final snapshot = compact
        ? _diagnostics.exportCompact(group: _group)
        : _diagnostics.export(group: _group);
    setState(() {
      _busy = true;
      _status = '正在复制并核对…';
    });
    final result = await MusicDiagnosticClipboard.copy(snapshot);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = switch (result) {
        MusicDiagnosticCopyResult.verified => '已复制并核对，可粘贴发送。',
        MusicDiagnosticCopyResult.mismatch => '剪贴板核对不一致，请改用导出 JSON 文件。',
        MusicDiagnosticCopyResult.unavailable => '剪贴板暂不能核对，可改用导出 JSON 文件。',
      };
    });
  }

  Future<void> _export() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = '正在生成诊断文件…';
    });
    try {
      await _exporter.share(diagnostics: _diagnostics, group: _group);
      if (mounted) {
        setState(() => _status = '已打开系统分享，可保存或发送 JSON 文件。');
      }
    } on Object {
      if (mounted) {
        // File paths and platform exceptions stay outside the diagnostic UI.
        setState(() => _status = '文件暂未导出，请重试或复制精简记录。');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => BetaSecondaryMusicLayout.wrap(
    context,
    MusicFeaturePage(
      title: '汽水诊断',
      child: ListenableBuilder(
        listenable: _diagnostics,
        builder: (context, _) {
          final rows = _diagnostics.select(_group).reversed.toList();
          final buttonHeight =
              (MediaQuery.textScalerOf(context).scale(17) * 1.45 + 28).clamp(
                52.0,
                double.infinity,
              );
          return ListView(
            padding: EdgeInsets.fromLTRB(
              20,
              16,
              20,
              BetaContentInsets.musicBottomOf(context, 40),
            ),
            children: [
              const Text('只记录本次打开的汽水操作。复现问题后，选择分组并复制或导出。'),
              const SizedBox(height: 12),
              const Text('仅含阶段、状态码和结构摘要，不含账号凭据、图片或歌曲内容。'),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final group in QishuiDiagnosticGroup.values)
                    ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 48),
                      child: ChoiceChip(
                        label: Text(group.label),
                        selected: _group == group,
                        onSelected: _busy
                            ? null
                            : (_) => setState(() {
                                _group = group;
                                _status = '';
                              }),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text('本组 ${rows.length} 条记录'),
              const SizedBox(height: 12),
              BetaGlassButton(
                height: buttonHeight,
                label: '复制精简记录',
                onPressed: _busy || rows.isEmpty
                    ? null
                    : () => _copy(compact: true),
                child: const Text('复制精简记录', textAlign: TextAlign.center),
              ),
              const SizedBox(height: 12),
              BetaGlassButton(
                height: buttonHeight,
                label: '导出 JSON 文件',
                onPressed: _busy || rows.isEmpty ? null : _export,
                child: const Text('导出 JSON 文件', textAlign: TextAlign.center),
              ),
              const SizedBox(height: 12),
              BetaGlassButton(
                height: buttonHeight,
                label: '复制完整记录',
                onPressed: _busy || rows.isEmpty
                    ? null
                    : () => _copy(compact: false),
                child: const Text('复制完整记录', textAlign: TextAlign.center),
              ),
              const SizedBox(height: 8),
              // Keep the live region mounted before its first status update.
              Semantics(liveRegion: true, child: Text(_status)),
              const SizedBox(height: 12),
              if (rows.isEmpty) const Text('本组暂无记录，请返回汽水页面复现一次问题。'),
              for (final row in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_feature(row['feature'])} · ${_stage(row['stage'])}',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      Text(
                        '${_outcome(row['outcome'])}'
                        '${row['httpStatus'] == null ? '' : ' · HTTP ${row['httpStatus']}'}'
                        '${row['businessCode'] == null ? '' : ' · 业务码 ${row['businessCode']}'}',
                      ),
                      if (row['serviceCode'] != null)
                        Text('服务错误码：${row['serviceCode']}'),
                      if (row['reason'] != null) Text('分类：${row['reason']}'),
                      Text(
                        '${row['at']}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (row['shape'] != null)
                        ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          title: const Text('查看结构摘要'),
                          children: [
                            Align(
                              alignment: Alignment.centerLeft,
                              child: SelectableText(
                                const JsonEncoder.withIndent(
                                  '  ',
                                ).convert(row['shape']),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    ),
    selectedIndex: 3,
  );

  static String _feature(Object? value) => switch (value) {
    'socialStats' => '官方社交数值',
    'following' => '关注列表',
    'followers' => '粉丝列表',
    'userInfo' => '用户资料',
    'userFollow' => '关注操作',
    'userUnfollow' => '取消关注',
    'artistCollection' => '歌手关注',
    'officialListening' => '官方累计时长',
    'listeningReport' => '实际收听上报',
    'coverUpload' => '封面上传',
    'playlistCover' => '歌单封面保存',
    _ => '汽水资料',
  };

  static String _stage(Object? value) => switch (value) {
    'prepare' => '准备',
    'helper' => '应用签名',
    'request' => '发送请求',
    'response' => '接收响应',
    'parse' => '解析资料',
    'identity' => '核对上报身份',
    'submit' => '提交上报',
    'receipt' => '核对回执',
    'grant' => '读取上传授权',
    'apply' => '申请上传地址',
    'storage' => '上传图片内容',
    'commit' => '提交图片',
    'readback' => '云端读回',
    'ledger' => '本机时长记录',
    _ => '处理资料',
  };

  static String _outcome(Object? value) => switch (value) {
    'success' => '本阶段完成',
    'http' => 'HTTP 响应异常',
    'business' => '平台未接受',
    'format' => '资料格式异常',
    'unconfirmed' => '结果未确认',
    'localOnly' => '仅本机记录',
    'cancelled' => '已取消',
    'network' => '连接未完成',
    'refused' => '请求未接受',
    _ => '状态待核对',
  };
}
