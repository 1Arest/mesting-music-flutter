import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../shared/widgets/beta_content_insets.dart';
import '../../../../shared/widgets/beta_glass_controls.dart';
import '../../presentation/platform_design.dart';
import 'netease_together_controller.dart';
import 'together_background_binding.dart';

/// A local, manual export surface. It deliberately owns no room subscription,
/// restore/poll action, permission request, upload, file or persistent timer.
class TogetherSyncDiagnosticsPage extends StatefulWidget {
  const TogetherSyncDiagnosticsPage({required this.controller, super.key});

  final NeteaseTogetherController controller;

  @override
  State<TogetherSyncDiagnosticsPage> createState() =>
      _TogetherSyncDiagnosticsPageState();
}

class _TogetherSyncDiagnosticsPageState
    extends State<TogetherSyncDiagnosticsPage> {
  String? _report, _notice;
  bool _reading = false;

  @override
  void initState() {
    super.initState();
    unawaited(_read());
  }

  Future<void> _read() async {
    if (_reading) return;
    setState(() {
      _reading = true;
      _notice = null;
    });
    final report = await TogetherBackgroundBinding.captureDiagnostics(
      synchronization: widget.controller.synchronizationDiagnostics,
      journal: widget.controller.diagnostics,
    );
    if (!mounted) return;
    setState(() {
      _reading = false;
      _report = const JsonEncoder.withIndent('  ').convert(report);
      _notice = '已读取本机诊断';
    });
  }

  Future<void> _copy() async {
    final report = _report;
    if (report == null || _reading) return;
    try {
      await Clipboard.setData(ClipboardData(text: report));
      if (mounted) setState(() => _notice = '脱敏报告已复制');
    } on PlatformException {
      if (mounted) setState(() => _notice = '复制暂未完成，请重试');
    }
  }

  @override
  Widget build(BuildContext context) => PlatformPageFrame(
    title: '一起听同步诊断',
    child: ListView(
      padding: BetaContentInsets.musicPaddingOf(
        context,
        const EdgeInsets.fromLTRB(24, 18, 24, 210),
      ),
      children: [
        Text(
          '复现后台不同步后，返回这里读取并复制报告。',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 12),
        const Text(
          '报告仅含本次进程最近的阶段、计数和时间，不含账号、好友、房间、歌曲或登录信息。读取报告不会请求平台，也不会改变播放。',
        ),
        const SizedBox(height: 22),
        BetaGlassButton(
          loading: _reading,
          onPressed: _reading ? null : _read,
          child: const Text('读取本机诊断'),
        ),
        const SizedBox(height: 12),
        BetaGlassButton(
          onPressed: _report == null || _reading ? null : _copy,
          child: const Text('复制脱敏报告'),
        ),
        if (_notice != null) ...[
          const SizedBox(height: 14),
          Semantics(liveRegion: true, child: Text(_notice!)),
        ],
        const SizedBox(height: 22),
        Text('报告预览', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        PlatformPanel(
          child: SelectableText(
            _report ?? '正在读取本机诊断…',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              height: 1.5,
            ),
          ),
        ),
      ],
    ),
  );
}
