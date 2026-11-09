import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/music_diagnostic_clipboard.dart';
import '../../../../shared/widgets/beta_content_insets.dart';
import '../../../../shared/widgets/beta_glass_controls.dart';
import '../../../../shared/widgets/music_feature_page.dart';
import 'netease_ad_probe_export.dart';
import 'netease_ad_probe_provider.dart';
import 'netease_ad_probe_report.dart';
import 'netease_ad_probe_repository.dart';

/// An explicit, foreground diagnostic surface. Opening it never requests an
/// ad; leaving/pausing cancels an active read, and old account reports are hidden.
class NeteaseAdProbePage extends ConsumerStatefulWidget {
  const NeteaseAdProbePage({this.exporter, super.key});
  final NeteaseAdProbeExport? exporter;

  @override
  ConsumerState<NeteaseAdProbePage> createState() => _NeteaseAdProbePageState();
}

class _NeteaseAdProbePageState extends ConsumerState<NeteaseAdProbePage> {
  NeteaseAdProbeReport? _report;
  NeteaseAdProbeService? _reportService;
  Completer<void>? _cancel;
  late final _exporter = widget.exporter ?? NeteaseAdProbeExport();
  late final AppLifecycleListener _lifecycle;
  bool _reading = false, _exporting = false;
  int _ticket = 0;
  String _status = '点击“读取广告配置”开始一次只读诊断。';

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onPause: _stop);
  }

  void _abort() {
    _ticket++;
    if (_cancel?.isCompleted == false) _cancel!.complete();
    _cancel = null;
  }

  void _stop() {
    if (!_reading) return;
    _abort();
    if (!mounted) return;
    setState(() {
      _reading = false;
      _status = '本次读取已停止。';
    });
  }

  bool _current(NeteaseAdProbeService service) {
    if (!mounted) return false;
    final value = ref.read(neteaseAdProbeServiceProvider);
    return !value.isLoading &&
        !value.hasError &&
        identical(value.value, service) &&
        service.isCurrent;
  }

  Future<void> _read(NeteaseAdProbeService service) async {
    if (_reading || _exporting || !_current(service)) return;
    _abort();
    final ticket = _ticket;
    final cancelled = Completer<void>();
    _cancel = cancelled;
    setState(() {
      _reading = true;
      _report = null;
      _reportService = null;
      _status = '正在读取任务入口与广告配置…';
    });
    try {
      final report = await service.inspect(cancelled: cancelled.future);
      if (!mounted || ticket != _ticket || !_current(service)) return;
      setState(() {
        _report = report;
        _reportService = service;
        _status = report.outcome.label;
      });
    } on Object {
      if (mounted && ticket == _ticket) {
        setState(() => _status = '读取未完成，请重试。');
      }
    } finally {
      if (!cancelled.isCompleted) cancelled.complete();
      if (mounted && ticket == _ticket) setState(() => _reading = false);
    }
  }

  bool get _reportCurrent =>
      _report != null && _reportService != null && _current(_reportService!);

  Future<void> _copy() async {
    if (_exporting || _reading || !_reportCurrent) return;
    final service = _reportService!;
    final snapshot = _report!.compactJson;
    setState(() => _exporting = true);
    final copied = await MusicDiagnosticClipboard.copy(snapshot);
    if (!mounted) return;
    setState(() {
      _exporting = false;
      if (!_current(service)) return;
      _status = switch (copied) {
        MusicDiagnosticCopyResult.verified => '已复制并核对，可粘贴发送。',
        MusicDiagnosticCopyResult.mismatch => '剪贴板核对不一致，请导出 JSON 文件。',
        MusicDiagnosticCopyResult.unavailable => '剪贴板未能核对，请导出 JSON 文件。',
      };
    });
  }

  Future<void> _export() async {
    if (_exporting || _reading || !_reportCurrent) return;
    final report = _report!, service = _reportService!;
    setState(() => _exporting = true);
    try {
      await _exporter.share(report, isCurrent: () => _current(service));
      if (mounted && _current(service)) {
        setState(() => _status = '已打开系统分享，可保存或发送 JSON 文件。');
      }
    } on Object {
      if (mounted && _current(service)) {
        setState(() => _status = '文件暂未导出，请重试或复制诊断。');
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  void dispose() {
    _abort();
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(neteaseAdProbeServiceProvider, (previous, next) {
      if (previous == next) return;
      _abort();
      setState(() {
        _reading = false;
        _report = null;
        _reportService = null;
        _status = '账号状态已更新，请重新读取。';
      });
    });
    final value = ref.watch(neteaseAdProbeServiceProvider);
    final service = value.isLoading || value.hasError ? null : value.value;
    final report = _reportCurrent ? _report : null;
    final status = value.isLoading
        ? '正在读取已保存的登录…'
        : value.hasError
        ? '登录读取失败，请返回后重试。'
        : service == null
        ? '请先登录网易云账号。'
        : _status;
    final height = (MediaQuery.textScalerOf(context).scale(17) * 1.45 + 24)
        .clamp(52.0, double.infinity);
    return MusicFeaturePage(
      title: '网易云广告配置诊断',
      child: ListView(
        key: const ValueKey('netease-ad-probe-page'),
        padding: EdgeInsets.fromLTRB(
          22,
          20,
          22,
          BetaContentInsets.musicBottomOf(context, 40),
        ),
        children: [
          const Text('读取当前账号的广告配置，核对是否可在Mesting内展示。'),
          const SizedBox(height: 10),
          const Text('此验证版不展示广告、不提交观看或领奖；不会打开官版网易云。'),
          const SizedBox(height: 10),
          const Text('导出仅含字段结构、素材链接类别和任务规则，不含账号凭据或完整广告地址。'),
          const SizedBox(height: 24),
          BetaGlassButton(
            key: const ValueKey('netease-ad-probe-read'),
            height: height,
            onPressed: service == null || _reading || _exporting
                ? null
                : () => _read(service),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_reading) ...[
                  const CupertinoActivityIndicator(radius: 9),
                  const SizedBox(width: 10),
                ],
                Text(_reading ? '读取中…' : '读取广告配置'),
              ],
            ),
          ),
          if (_reading) ...[
            const SizedBox(height: 12),
            BetaGlassButton(
              key: const ValueKey('netease-ad-probe-stop'),
              height: height,
              onPressed: _stop,
              child: const Text('停止读取'),
            ),
          ],
          const SizedBox(height: 16),
          Semantics(liveRegion: true, child: Text(status)),
          const SizedBox(height: 24),
          BetaGlassButton(
            key: const ValueKey('netease-ad-probe-copy'),
            height: height,
            onPressed: report == null || _exporting || _reading ? null : _copy,
            child: const Text('复制精简诊断'),
          ),
          const SizedBox(height: 12),
          BetaGlassButton(
            key: const ValueKey('netease-ad-probe-export'),
            height: height,
            onPressed: report == null || _exporting || _reading
                ? null
                : _export,
            child: const Text('导出 JSON 文件'),
          ),
          if (report != null) ...[
            const SizedBox(height: 20),
            ExpansionTile(
              title: const Text('查看脱敏结构'),
              tilePadding: EdgeInsets.zero,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: SelectableText(
                    report.json,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
