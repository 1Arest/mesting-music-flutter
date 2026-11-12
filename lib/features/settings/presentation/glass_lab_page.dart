import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/diagnostics/diagnostic_activity.dart';
import '../../../core/diagnostics/glass_lab_run.dart';
import '../../../core/diagnostics/glass_lab_store.dart';
import '../../../shared/widgets/beta_music_chrome_scope.dart';
import 'glass_lab_scene.dart';

/// Synthetic render experiments live on their own opaque route. Production
/// chrome is covered, while its normal state and the selected account survive.
class GlassLabPage extends ConsumerStatefulWidget {
  const GlassLabPage({
    required this.environment,
    required this.displayHz,
    this.recorder,
    this.store,
    super.key,
  });
  final Map<String, Object> environment;
  final double displayHz;
  final GlassLabRecorder? recorder;
  final GlassLabReportStore? store;
  @override
  ConsumerState<GlassLabPage> createState() => _GlassLabPageState();
}

class _GlassLabPageState extends ConsumerState<GlassLabPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver
    implements GlassLabDriver {
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 340),
    reverseDuration: const Duration(milliseconds: 310),
  );
  final _scroll = ScrollController();
  late final GlassLabReportStore _store = widget.store ?? GlassLabReportStore();
  late final GlassLabRunController _run;
  GlassLabScenario _selected = GlassLabScenario.scrollSingle;
  late Widget _scene = _sceneFor(_selected);
  String? _exportMessage;
  bool _foreground = true;
  bool _exporting = false;
  bool _uiDisposed = false;

  Widget _sceneFor(GlassLabScenario scenario) => GlassLabScene(
    key: ValueKey('glass-lab-${scenario.name}'),
    scenario: scenario,
    scroll: _scroll,
    motion: _motion,
  );

  @override
  void initState() {
    super.initState();
    final activity = ref.read(diagnosticActivityProvider.notifier);
    _run = GlassLabRunController(
      recorder: widget.recorder ?? FrameProbeGlassLabRecorder(),
      sink: _store,
      setActive: activity.setRunning,
      isOtherDiagnosticActive: () => diagnosticRunActive.value,
    )..addListener(_changed);
    WidgetsBinding.instance.addObserver(this);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _check(GlassLabTicket ticket) {
    if (!mounted || !_foreground) ticket.cancel();
    ticket.check();
  }

  @override
  Future<void> prepare(GlassLabScenario scenario, GlassLabTicket ticket) async {
    _check(ticket);
    _motion.value = 0;
    setState(() {
      _selected = scenario;
      _scene = _sceneFor(scenario);
    });
    await ticket.wait(WidgetsBinding.instance.endOfFrame);
    _check(ticket);
    if (_scroll.hasClients) _scroll.jumpTo(1000);
    await ticket.wait(Future<void>.delayed(const Duration(milliseconds: 600)));
    _check(ticket);
  }

  @override
  Future<void> exercise(
    GlassLabScenario scenario,
    GlassLabTicket ticket,
  ) async {
    for (var i = 0; i < 6; i++) {
      _check(ticket);
      if (scenario == GlassLabScenario.menuMorph ||
          scenario == GlassLabScenario.pageSlide) {
        await ticket.wait(_motion.forward().orCancel);
        _check(ticket);
        await ticket.wait(_motion.reverse().orCancel);
      } else if (scenario != GlassLabScenario.staticSingle &&
          _scroll.hasClients) {
        final initial = _scroll.offset;
        await ticket.wait(
          _scroll.animateTo(
            initial + 340,
            duration: const Duration(milliseconds: 250),
            curve: Curves.linear,
          ),
        );
        _check(ticket);
        await ticket.wait(
          _scroll.animateTo(
            initial,
            duration: const Duration(milliseconds: 250),
            curve: Curves.linear,
          ),
        );
      } else {
        await ticket.wait(
          Future<void>.delayed(const Duration(milliseconds: 500)),
        );
      }
    }
    _check(ticket);
  }

  @override
  void stopMotion() {
    if (_uiDisposed) return;
    _motion.stop();
    if (_scroll.hasClients) _scroll.jumpTo(_scroll.offset);
  }

  Future<void> _start({required bool all}) async {
    _exportMessage = null;
    await _run.run(
      all ? GlassLabScenario.values : [_selected],
      driver: this,
      displayHz: widget.displayHz,
      environment: {
        ...widget.environment,
        'reduceMotion': MediaQuery.disableAnimationsOf(context),
      },
    );
  }

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      final file = await _store.reportFile();
      await const MethodChannel(
        'com.mesting.music/share',
      ).invokeMethod<void>('shareGlassLabDiagnosticJson', {'path': file.path});
      if (mounted) setState(() => _exportMessage = '已打开系统分享，可保存实验报告');
    } on Object {
      if (mounted) setState(() => _exportMessage = '导出未完成，请重试');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) _run.cancel();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _run.removeListener(_changed);
    _run.dispose();
    _uiDisposed = true;
    _motion.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final records = _run.records;
    final enabled = !_run.running && !_exporting;
    return BetaMusicChromeCover(
      child: PopScope(
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) _run.cancel();
        },
        child: Scaffold(
          // The laboratory route must remain opaque even when the music shell
          // uses a transparent scaffold over its shared wallpaper.
          backgroundColor: Theme.of(context).colorScheme.surface,
          appBar: AppBar(title: const Text('八场景渲染实验室')),
          body: SafeArea(
            top: false,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text(
                    ui.ImageFilter.isShaderFilterSupported
                        ? '固定合成内容，用于比较绘制开销。建议先手动暂停音乐；本实验不操作账号或播放歌曲。'
                        : '当前后端不支持完整玻璃，仅作结构验证，不能代表手机绘制性能。',
                    key: const ValueKey('glass-lab-backend-status'),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: DropdownButton<GlassLabScenario>(
                    isExpanded: true,
                    value: _selected,
                    items: [
                      for (final s in GlassLabScenario.values)
                        DropdownMenuItem(value: s, child: Text(s.label)),
                    ],
                    onChanged: enabled
                        ? (s) {
                            if (s != null) {
                              setState(() {
                                _selected = s;
                                _scene = _sceneFor(s);
                              });
                            }
                          }
                        : null,
                  ),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  alignment: WrapAlignment.center,
                  children: [
                    FilledButton(
                      onPressed: enabled
                          ? () => unawaited(_start(all: false))
                          : null,
                      child: const Text('运行当前场景'),
                    ),
                    OutlinedButton(
                      onPressed: enabled
                          ? () => unawaited(_start(all: true))
                          : null,
                      child: const Text('依次运行八场景'),
                    ),
                    TextButton(
                      onPressed: _run.running ? _run.cancel : null,
                      child: const Text('停止'),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.all(6),
                  child: Text(
                    '${_run.phase} · 已记录 ${records.length} 段',
                    key: const ValueKey('glass-lab-progress'),
                  ),
                ),
                Expanded(child: _scene),
                if (_run.savingFailed)
                  const Padding(
                    padding: EdgeInsets.all(6),
                    child: Text('部分报告未保存，需重新采集后导出'),
                  ),
                if (records.isNotEmpty && !_run.running)
                  Padding(
                    padding: const EdgeInsets.all(6),
                    child: Text('运行完成不代表性能达标，仍需结合真实设备、渲染后端和实际页面对照。'),
                  ),
                TextButton.icon(
                  onPressed: enabled && records.isNotEmpty && !_run.savingFailed
                      ? _export
                      : null,
                  icon: const Icon(Icons.ios_share),
                  label: const Text('导出本轮 JSON 报告'),
                ),
                if (_exportMessage != null)
                  Padding(
                    padding: const EdgeInsets.all(6),
                    child: Text(_exportMessage!),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
