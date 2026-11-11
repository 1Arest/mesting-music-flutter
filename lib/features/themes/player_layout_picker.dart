import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/widgets/music_notice.dart';
import 'theme_controller.dart';
import 'music_theme_tokens.dart';

/// Static miniatures share the gallery's rounded cards and selected border.
/// No animations, platform players or extra image downloads run in the gallery.
class PlayerLayoutPicker extends ConsumerStatefulWidget {
  const PlayerLayoutPicker({super.key});
  @override
  ConsumerState<PlayerLayoutPicker> createState() => _PlayerLayoutPickerState();
}

class _PlayerLayoutPickerState extends ConsumerState<PlayerLayoutPicker> {
  bool _saving = false;
  Future<void> _select(PlayerPageLayout layout) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(themeVisualSettingsProvider.notifier)
          .setPlayerLayout(layout);
    } on Object {
      if (mounted) {
        showMusicNotice(
          context,
          icon: Icons.error_outline_rounded,
          title: '排版暂未保存',
          message: '请稍后重试',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(
      themeVisualSettingsProvider.select((s) => s.playerLayout),
    );
    final tokens = context.musicThemeTokens;
    final accent = Theme.of(context).colorScheme.primary;
    final extra = (MediaQuery.textScalerOf(context).scale(12) - 12).clamp(
      0.0,
      40.0,
    );
    return LayoutBuilder(
      builder: (context, box) {
        final cardWidth = ((box.maxWidth - 10) / 2).clamp(110.0, 190.0);
        return SizedBox(
          height: 226 + extra * 4,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final layout in PlayerPageLayout.values)
                  Padding(
                    padding: EdgeInsets.only(
                      right: layout == PlayerPageLayout.values.last ? 0 : 10,
                    ),
                    child: Semantics(
                      button: true,
                      selected: selected == layout,
                      enabled: !_saving,
                      label: '${layout.label}，${layout.description}',
                      child: SizedBox(
                        width: cardWidth,
                        child: Material(
                          color: selected == layout
                              ? accent.withValues(alpha: .12)
                              : tokens.glassSubtle,
                          borderRadius: BorderRadius.circular(20),
                          child: InkWell(
                            key: ValueKey('player-layout-${layout.name}'),
                            onTap: _saving ? null : () => _select(layout),
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: selected == layout
                                      ? accent
                                      : tokens.border,
                                  width: selected == layout ? 1.5 : 1,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: SizedBox.expand(
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(15),
                                        child: CustomPaint(
                                          key: ValueKey(
                                            'player-layout-preview-${layout.name}',
                                          ),
                                          painter: _LayoutPreview(
                                            layout,
                                            Theme.of(
                                              context,
                                            ).textTheme.bodyMedium?.fontFamily,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          layout.label,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: tokens.textPrimary,
                                          ),
                                        ),
                                      ),
                                      if (selected == layout)
                                        Icon(
                                          Icons.check_circle_rounded,
                                          color: accent,
                                          size: 16,
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    layout.description,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11,
                                      height: 1.3,
                                      color: tokens.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _LayoutPreview extends CustomPainter {
  const _LayoutPreview(this.layout, this.fontFamily);
  final PlayerPageLayout layout;
  final String? fontFamily;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF242427),
    );
    final scale = math.min(size.width / 90, size.height / 150);
    canvas.save();
    canvas.translate(
      (size.width - 90 * scale) / 2,
      (size.height - 150 * scale) / 2,
    );
    canvas.scale(scale);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(6, 0, 78, 150),
        const Radius.circular(8),
      ),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF615957), Color(0xFF27282D)],
        ).createShader(const Rect.fromLTWH(6, 0, 78, 150)),
    );
    void text(String value, double x, double y, double font, double opacity) {
      final p = TextPainter(
        text: TextSpan(
          text: value,
          style: TextStyle(
            fontSize: font,
            fontFamily: fontFamily,
            color: Colors.white.withValues(alpha: opacity),
            height: 1,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      p.paint(canvas, Offset(x, y));
      p.dispose();
    }

    void line(double x, double y, double width, double opacity) =>
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x, y, width, 1.3),
            const Radius.circular(1),
          ),
          Paint()..color = Colors.white.withValues(alpha: opacity),
        );
    final original = layout == PlayerPageLayout.original;
    canvas.drawPath(
      Path()
        ..moveTo(12, 7)
        ..lineTo(15, 10)
        ..lineTo(18, 7),
      Paint()
        ..color = Colors.white70
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    line(30, 9, 25, .65);
    line(35, 14, 15, .3);
    final count = original ? 4 : 6;
    final font = original ? 9.5 : 6.1;
    final step = original ? 17.0 : 11.0;
    for (var i = 0; i < count; i++) {
      text(
        original ? '让心事随风去' : '让心事随晚风散去',
        original ? 13 : 45 - font * 4,
        29 + i * step,
        font,
        i == count ~/ 2 ? 1 : .32,
      );
    }
    line(13, 108, 64, .3);
    line(13, 108, 24, .9);
    text('0:37', 13, 113, 4, .55);
    text('4:19', 67, 113, 4, .55);
    final white = Paint()..color = Colors.white;
    canvas.drawPath(
      Path()
        ..moveTo(31, 121)
        ..lineTo(25, 126)
        ..lineTo(31, 131)
        ..close(),
      white,
    );
    canvas.drawRect(const Rect.fromLTWH(23, 121, 1.4, 10), white);
    canvas.drawRect(const Rect.fromLTWH(42, 121, 2.6, 10), white);
    canvas.drawRect(const Rect.fromLTWH(47, 121, 2.6, 10), white);
    canvas.drawPath(
      Path()
        ..moveTo(60, 121)
        ..lineTo(66, 126)
        ..lineTo(60, 131)
        ..close(),
      white,
    );
    canvas.drawRect(const Rect.fromLTWH(67, 121, 1.4, 10), white);
    if (original) {
      line(18, 137, 54, .28);
      line(18, 137, 26, .7);
    } else {
      line(21, 142, 4, .45);
      line(43, 142, 4, .45);
      line(65, 142, 4, .45);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LayoutPreview old) =>
      old.layout != layout || old.fontFamily != fontFamily;
}
