import '../../../shared/widgets/beta_content_insets.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../../core/diagnostics/diagnostic_activity.dart';
import '../../../core/diagnostics/diagnostic_run.dart';
import '../../../core/performance/frame_timing_probe.dart';
import '../../../shared/widgets/beta_glass_controls.dart';
import '../../../shared/widgets/beta_page_motion.dart';
import '../../music_platform/domain/platform_session.dart';
import '../../auth/beta_account_choice.dart';
import '../../music_platform/music_platform_providers.dart';
import '../../music_platform/presentation/platform_design.dart';
import 'production_diagnostic_driver.dart';
import '../../themes/music_typography.dart';

/// This provider survives real route changes. Reading a crash checkpoint alone
/// must not activate the process-local automatic-sign-in suppression latch.
final diagnosticControllerProvider = FutureProvider<DiagnosticRunController>((
  ref,
) async {
  final controller = DiagnosticRunController(await DiagnosticRunStore.open());
  await controller.load();
  ref.onDispose(controller.dispose);
  return controller;
});

class FrameDiagnosticsPage extends ConsumerStatefulWidget {
  const FrameDiagnosticsPage({super.key});
  @override
  ConsumerState<FrameDiagnosticsPage> createState() =>
      _FrameDiagnosticsPageState();
}

class _FrameDiagnosticsPageState extends ConsumerState<FrameDiagnosticsPage> {
  bool _copied = false;
  String? _exportState;

  Future<Map<String, Object>> _environment() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return {};
    final view = View.of(context);
    return {
      'appVersion': info.version,
      'buildNumber': info.buildNumber,
      'theme': Theme.of(context).brightness.name,
      'physicalWidth': view.physicalSize.width,
      'physicalHeight': view.physicalSize.height,
      'devicePixelRatio': view.devicePixelRatio,
      'shaderFilterSupported': ui.ImageFilter.isShaderFilterSupported,
    };
  }

  Future<void> _start(
    DiagnosticRunController controller, {
    bool resume = false,
  }) async {
    if (controller.running ||
        FrameTimingProbe.recording.value ||
        FrameTimingProbe.draining.value) {
      return;
    }
    final environment = await _environment();
    if (!mounted) return;
    final container = ProviderScope.containerOf(context, listen: false);
    final navigator = Navigator.of(context);
    final router = GoRouter.of(context);
    final hz = View.of(context).display.refreshRate;
    final savedOriginal = resume
        ? controller.checkpoint['originalPlatform'] as String?
        : null;
    // A null original platform is meaningful: a guest may have crashed after
    // visiting a retained login. Resume must restore that guest, not whichever
    // platform was left selected at the interrupted step.
    final original = resume
        ? (savedOriginal == null
              ? null
              : MusicPlatform.values.byName(savedOriginal))
        : container.read(platformAccountProvider).value?.platform;
    final activity = container.read(diagnosticActivityProvider.notifier);
    final savedChoice = resume
        ? controller.checkpoint['originalAccountChoice'] as String?
        : null;
    final originalChoice = resume
        ? (savedChoice == null
              ? BetaAccountChoice.guest
              : BetaAccountChoice.values.byName(savedChoice))
        : container.read(betaAccountChoiceProvider) ?? BetaAccountChoice.guest;
    final entry = OverlayEntry(
      builder: (context) => _RunProgress(controller: controller),
    );
    Overlay.of(context, rootOverlay: true).insert(entry);
    navigator.pop();
    final driver = ProductionDiagnosticDriver(
      container: container,
      router: router,
      navigator: navigator,
      originalPlatform: original,
      originalAccountChoice: originalChoice,
    );
    try {
      await controller.run(
        driver,
        displayHz: hz,
        environment: environment,
        originalPlatform: original?.name,
        originalAccountChoice: originalChoice.name,
        setActive: activity.setRunning,
        resume: resume,
      );
    } finally {
      entry.remove();
      entry.dispose();
      if (navigator.mounted) {
        unawaited(
          navigator.push(betaContentRoute<void>(const FrameDiagnosticsPage())),
        );
      }
    }
  }

  Future<void> _export(DiagnosticRunController controller) async {
    try {
      final file = await controller.store.export(controller.checkpoint);
      await const MethodChannel(
        'com.mesting.music/share',
      ).invokeMethod<void>('shareDiagnosticJson', {'path': file.path});
      if (mounted) setState(() => _exportState = '已打开系统分享，可保存 JSON 文件');
    } on Object {
      if (mounted) setState(() => _exportState = '文件导出未完成，可重试或复制汇总');
    }
  }

  @override
  Widget build(BuildContext context) => PlatformPageFrame(
    title: '流畅度诊断',
    child: ref
        .watch(diagnosticControllerProvider)
        .when(
          loading: () => const Center(child: Text('正在读取本机诊断记录…')),
          error: (_, _) => Center(
            child: BetaGlassButton(
              onPressed: () => ref.invalidate(diagnosticControllerProvider),
              child: const Text('读取失败，重试'),
            ),
          ),
          data: (controller) => AnimatedBuilder(
            animation: Listenable.merge([
              controller,
              FrameTimingProbe.recording,
              FrameTimingProbe.draining,
            ]),
            builder: (context, _) {
              final busy =
                  controller.running ||
                  FrameTimingProbe.recording.value ||
                  FrameTimingProbe.draining.value;
              final records = controller.records;
              final passed = records
                  .where((r) => r['status'] == 'passed')
                  .length;
              final failed = records
                  .where((r) => r['status'] == 'failed')
                  .length;
              final skipped = records
                  .where((r) => r['status'] == 'skipped')
                  .length;
              return ListView(
                padding: BetaContentInsets.musicPaddingOf(
                  context,
                  EdgeInsets.fromLTRB(24, 24, 24, 210),
                ),
                children: [
                  Text(
                    '双平台连续巡检',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '当前显示刷新率：${View.of(context).display.refreshRate.toStringAsFixed(0)} Hz',
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '一键运行网易云、酷狗与公共页面的正常滚动、超快速反向滚动、页面左右滑动及主 Tab 快速切换。使用真实页面和本机已有数据，未登录或缺少数据会记录跳过；单页失败后继续。',
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '运行时暂停自动签到，不执行签到、领取、发送、付费或删除。切换平台会暂停并保存播放，结束恢复原平台，不自动重新播放。每段单独保存；若应用退出，重新进入这里可续跑。',
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '报告记录逐帧耗时、慢帧、玻璃绘制计数与固定页面名称，不包含账号、歌曲、私信内容或凭据。帧耗时用于定位卡顿，不能证明屏幕持续 120 FPS 或永不闪退。',
                  ),
                  const SizedBox(height: 24),
                  BetaGlassButton(
                    blue: true,
                    onPressed: busy ? null : () => _start(controller),
                    child: const Text('一键连续测试全部页面'),
                  ),
                  if (controller.resumable) ...[
                    const SizedBox(height: 12),
                    BetaGlassButton(
                      onPressed: busy
                          ? null
                          : () => _start(controller, resume: true),
                      child: const Text('从已保存断点继续'),
                    ),
                  ],
                  if (controller.checkpoint.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Text('上次记录：${_runStatus(controller.checkpoint['status'])}'),
                    Text('通过 $passed 段 · 失败 $failed 段 · 跳过 $skipped 段'),
                    Text('开始：${controller.checkpoint['startedAt']}'),
                    if (controller.checkpoint['updatedAt'] != null)
                      Text('最近保存：${controller.checkpoint['updatedAt']}'),
                    if (controller.checkpoint['platformRestored'] == false)
                      const Text('原平台未恢复，请通过账号切换页手动恢复。'),
                    if (controller.checkpoint['persistenceError'] == true)
                      const Text('部分记录未能保存，本次结果不完整。'),
                    const SizedBox(height: 14),
                    BetaGlassButton(
                      onPressed: busy ? null : () => _export(controller),
                      child: const Text('导出完整 JSON 文件'),
                    ),
                    const SizedBox(height: 12),
                    BetaGlassButton(
                      onPressed: busy
                          ? null
                          : () async {
                              await Clipboard.setData(
                                ClipboardData(
                                  text: _readableSummary(controller),
                                ),
                              );
                              if (mounted) setState(() => _copied = true);
                            },
                      child: Text(_copied ? '汇总已复制' : '复制可读汇总'),
                    ),
                    if (_exportState != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(_exportState!),
                      ),
                    for (final row in records)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${row['label']} · ${_phaseLabel(row['phase'])}',
                              style: const TextStyle(
                                fontWeight: MusicTypography.titleWeight,
                              ),
                            ),
                            Text(
                              '${_resultStatus(row['status'])}${row['reason'] == null ? '' : ' · ${_reasonLabel(row['reason'])}'}',
                            ),
                            if (row['timing'] is Map)
                              Text(
                                _timingLabel(row['timing'] as Map),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                          ],
                        ),
                      ),
                  ],
                  const SizedBox(height: 30),
                  ExpansionTile(
                    initiallyExpanded: true,
                    title: const Text('手动采集（每次最多 90 秒）'),
                    children: [
                      const Text('开始后返回应用操作，再回此处停止。停止会等待 1.2 秒收齐末批帧。'),
                      BetaGlassButton(
                        onPressed:
                            controller.running ||
                                FrameTimingProbe.draining.value
                            ? null
                            : () async {
                                if (FrameTimingProbe.recording.value) {
                                  await FrameTimingProbe.stopSession();
                                } else {
                                  final env = await _environment();
                                  if (!context.mounted) return;
                                  FrameTimingProbe.beginSession(
                                    View.of(context).display.refreshRate,
                                    environment: env,
                                  );
                                }
                              },
                        child: Text(
                          FrameTimingProbe.recording.value
                              ? '停止采集'
                              : FrameTimingProbe.draining.value
                              ? '正在收齐报告…'
                              : '开始采集',
                        ),
                      ),
                      BetaGlassButton(
                        onPressed: busy
                            ? null
                            : () async {
                                await Clipboard.setData(
                                  ClipboardData(
                                    text: jsonEncode(
                                      FrameTimingProbe.sessionReport(),
                                    ),
                                  ),
                                );
                              },
                        child: const Text('复制诊断报告'),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
  );
}

class _RunProgress extends StatelessWidget {
  const _RunProgress({required this.controller});
  final DiagnosticRunController controller;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => Stack(
      children: [
        // Prevent accidental business gestures. Controller-driven scroll actions do
        // not pass through hit testing, while this explicit stop remains available.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {},
            onPanStart: (_) {},
          ),
        ),
        Positioned(
          top: MediaQuery.paddingOf(context).top + 8,
          left: 12,
          right: 12,
          child: Material(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(18),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '诊断中 · 已保存 ${controller.records.length} 段\n${controller.current}',
                      maxLines: 3,
                    ),
                  ),
                  BetaGlassButton(
                    onPressed: controller.stopRequested
                        ? null
                        : controller.stop,
                    child: Text(controller.stopRequested ? '正在停止…' : '停止'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

String _runStatus(Object? value) => switch (value) {
  'completed' => '已完成',
  'stopped' => '已停止，可续跑',
  'interrupted' => '记录中断，可续跑',
  _ => '上次运行中断，可续跑',
};
String _resultStatus(Object? value) => switch (value) {
  'passed' => '已完成采样',
  'failed' => '失败',
  _ => '已跳过',
};
String _phaseLabel(Object? value) => switch (value) {
  'normal' => '正常滚动',
  'fastReverse' => '超快与反向滚动',
  'pages' => '分页切换',
  'transition' => '进出与返回',
  _ => '打开页面',
};
String _reasonLabel(Object? value) => switch (value) {
  'platform_not_logged_in' => '此平台未登录',
  'no_current_song' => '暂无当前歌曲',
  'queue_empty' => '播放队列为空',
  'no_existing_conversation' => '暂无已有会话',
  'no_scrollable_content' => '此页无可滚动内容',
  'no_paged_navigation' => '此页无分页导航',
  'dedicated_tab_stage' => '仅执行主 Tab 切换阶段',
  'page_timeout' => '页面加载超时',
  'stage_timeout' => '本阶段超时',
  'no_frame_timings' => '未收到有效帧数据',
  'page_error' => '页面加载或导航失败',
  'stage_error' => '阶段操作失败',
  'page_close_failed' => '返回页面失败，已继续下一项',
  'stage_cancelled' => '超时操作已失效',
  'no_current_platform_song' => '此平台暂无当前歌曲',
  'no_real_detail_seed' => '平台暂无可进入的详情数据',
  'page_not_available' => '此页没有该标签',
  'unsupported_page' => '此页面不支持自动浏览',
  'excluded_interactive_operation' => '需用户主动操作，未自动执行',
  _ => '本阶段未完成',
};

// Readable text and JSON are separate exports: humans need labelled units,
// whereas automated comparisons need the raw frame samples and schema fields.
String _timingLabel(Map timing) {
  String ms(String key) => ((timing[key] as num?) ?? 0).toStringAsFixed(2);
  return '${timing['frames']} 帧 · 构建 P99 ${ms('buildP99Ms')} ms · '
      '栅格 P99 ${ms('rasterP99Ms')} ms\n'
      '超过显示帧预算 ${timing['rasterOverDisplayBudget'] ?? 0} 帧 · '
      '超过 16.67 ms ${timing['rasterOver16_67Ms'] ?? 0} 帧';
}

String _readableSummary(DiagnosticRunController controller) {
  final text = StringBuffer('Mesting Music 流畅度诊断\n');
  text.writeln('开始：${controller.checkpoint['startedAt']}');
  text.writeln('状态：${_runStatus(controller.checkpoint['status'])}');
  text.writeln(
    '原平台恢复：${controller.checkpoint['platformRestored'] == true ? '是' : '待检查'}',
  );
  for (final record in controller.records) {
    text.writeln(
      '\n${record['label']} · ${_phaseLabel(record['phase'])} · ${_resultStatus(record['status'])}',
    );
    if (record['reason'] != null) text.writeln(_reasonLabel(record['reason']));
    if (record['timing'] is Map) {
      text.writeln(_timingLabel(record['timing'] as Map));
    }
  }
  return text.toString();
}
