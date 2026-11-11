import 'dart:async';
import 'equalizer_preset_picker.dart';
import 'equalizer_band_control.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/audio/music_equalizer.dart';
import '../../../core/audio/music_equalizer_providers.dart';
import '../../../shared/widgets/beta_glass_controls.dart';
import '../../../shared/widgets/beta_glass_scroll_body.dart';
import '../../../shared/widgets/music_feature_page.dart';
import '../../auth/presentation/beta_welcome_page.dart';
import '../../music_platform/presentation/music_effects_page.dart';
import '../../music_platform/platform_backend_providers.dart';
import '../../themes/music_typography.dart';

class MusicEqualizerPage extends ConsumerStatefulWidget {
  const MusicEqualizerPage({super.key});
  @override
  ConsumerState<MusicEqualizerPage> createState() => _MusicEqualizerPageState();
}

class _MusicEqualizerPageState extends ConsumerState<MusicEqualizerPage> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) ref.read(musicEqualizerProvider).bind();
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(musicEqualizerProvider);
    final scheme = Theme.of(context).colorScheme;
    return MusicFeaturePage(
      title: ref.watch(usesNeteaseProvider) ? '本地均衡器' : '均衡器',
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final state = controller.state;
          final interactive = state.enabled && state.bound && !state.binding;
          return BetaGlassScrollBody(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 40),
            children: [
              if (ref.watch(usesNeteaseProvider))
                const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: Text('音效由 Mesting Music 在本机处理，当前未接入网易云官方音效。'),
                ),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Row(
                  children: [
                    Icon(
                      CupertinoIcons.slider_horizontal_3,
                      color: scheme.primary,
                      size: 28,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '音乐均衡',
                            style: TextStyle(
                              fontSize: MusicTypography.bodySize,
                              fontWeight: MusicTypography.titleWeight,
                            ),
                          ),
                          const SizedBox(height: 5),
                          _EqualizerStatusLabel(
                            message: state.binding
                                ? '正在连接音频会话'
                                : !state.enabled
                                ? '已关闭'
                                : state.bound
                                ? '已生效 · ${state.preset}'
                                : '已开启 · 等待音乐播放',
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontSize: MusicTypography.footnoteSize,
                            ),
                          ),
                        ],
                      ),
                    ),
                    CupertinoSwitch(
                      key: const ValueKey('music-equalizer-enabled'),
                      activeTrackColor: scheme.primary,
                      value: state.enabled,
                      onChanged: state.binding
                          ? null
                          : (v) => controller.setEnabled(v),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      '频段增益',
                      style: TextStyle(
                        fontSize: MusicTypography.bodySize,
                        fontWeight: MusicTypography.titleWeight,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed:
                        state.binding || state.levels.every((v) => v == 0)
                        ? null
                        : controller.clearEffect,
                    child: const Text('重置'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 125,
                child: CustomPaint(
                  key: const ValueKey('music-equalizer-curve'),
                  painter: _EqualizerCurve(
                    state.levels,
                    state.minimum,
                    state.maximum,
                    interactive ? scheme.primary : scheme.onSurfaceVariant,
                    scheme.outlineVariant,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                '预设',
                style: TextStyle(
                  fontSize: MusicTypography.subheadlineSize,
                  fontWeight: MusicTypography.bodyWeight,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              EqualizerPresetPicker(
                names: musicEqualizerPresets.keys,
                selected: state.preset,
                onSelected: state.binding ? null : controller.selectPreset,
              ),
              const SizedBox(height: 28),
              for (var i = 0; i < state.frequencies.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: EqualizerBandControl(
                    index: i,
                    frequency: _frequency(state.frequencies[i]),
                    value: state.levels[i],
                    minimum: state.minimum,
                    maximum: state.maximum,
                    onChanged: interactive
                        ? (v) => controller.previewBand(i, v)
                        : null,
                    onChangeEnd: interactive
                        ? (_) => unawaited(controller.commitBands())
                        : null,
                  ),
                ),
              if (state.message != null) ...[
                Text(
                  state.message!,
                  style: TextStyle(color: scheme.onSurfaceVariant, height: 1.5),
                ),
                const SizedBox(height: 12),
                if (!state.bound)
                  BetaGlassButton(
                    onPressed: state.binding ? null : controller.bind,
                    accent: true,
                    child: const Text('重试连接'),
                  ),
              ],
              const SizedBox(height: 24),
              if (!ref.watch(usesNeteaseProvider))
                CupertinoButton(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  onPressed: () => Navigator.of(
                    context,
                    rootNavigator: true,
                  ).push(betaEntryRoute<void>(const MusicEffectsPage())),
                  child: Row(
                    children: [
                      const Icon(CupertinoIcons.waveform),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          state.effectName ?? '浏览音效',
                          style: const TextStyle(
                            fontSize: MusicTypography.calloutSize,
                          ),
                        ),
                      ),
                      const Icon(CupertinoIcons.chevron_forward, size: 17),
                    ],
                  ),
                ),
              Text(
                '设置会自动保存。频段范围由设备提供；音效仅作用于 Mesting Music 的音乐播放。',
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: MusicTypography.footnoteSize,
                  height: 1.6,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _frequency(int milliHz) {
    final hz = milliHz / 1000;
    return hz >= 1000
        ? '${(hz / 1000).toStringAsFixed(hz % 1000 == 0 ? 0 : 1)} kHz'
        : '${hz.round()} Hz';
  }
}

/// A view of selected band gains, not a measured acoustic response. Repaints
/// only this small graph while a slider moves; it does not sample the audio.
class _EqualizerCurve extends CustomPainter {
  _EqualizerCurve(this.levels, this.minimum, this.maximum, this.ink, this.grid);
  final List<double> levels;
  final double minimum, maximum;
  final Color ink, grid;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = grid
      ..strokeWidth = .5;
    for (final value in [minimum, 0.0, maximum]) {
      final y = (1 - (value - minimum) / (maximum - minimum)) * size.height;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
    if (levels.isEmpty) return;
    final path = Path();
    for (var i = 0; i < levels.length; i++) {
      final point = Offset(
        levels.length == 1
            ? size.width / 2
            : i * size.width / (levels.length - 1),
        (1 - (levels[i] - minimum) / (maximum - minimum)) * size.height,
      );
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawCircle(point, 3, Paint()..color = ink);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_EqualizerCurve old) =>
      old.levels != levels ||
      old.ink != ink ||
      old.minimum != minimum ||
      old.maximum != maximum;
}

/// Reserve the tallest supported status at the current text scale and width.
/// Long preset names or a temporary binding message must not move the controls.
class _EqualizerStatusLabel extends StatelessWidget {
  const _EqualizerStatusLabel({required this.message, required this.style});
  final String message;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final effectiveStyle = DefaultTextStyle.of(context).style.merge(style);
      var height = 0.0;
      for (final text in [
        message,
        '正在连接音频会话',
        '已开启 · 等待音乐播放',
        for (final preset in musicEqualizerPresets.keys) '已生效 · $preset',
      ]) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: effectiveStyle),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: bounds.maxWidth);
        if (painter.height > height) height = painter.height;
        painter.dispose();
      }
      return SizedBox(
        height: height,
        child: Text(message, style: style),
      );
    },
  );
}
