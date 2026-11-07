import 'dart:ui';

import 'package:flutter/material.dart';

import '../../features/themes/music_theme_tokens.dart';
import '../layout/adaptive_layout.dart';

const liquidGlassSheetSurfaceKey = ValueKey<String>(
  'liquid-glass-sheet-surface',
);
const liquidGlassSidePanelSurfaceKey = ValueKey<String>(
  'liquid-glass-side-panel-surface',
);
const liquidGlassSurfaceBodyKey = ValueKey<String>('liquid-glass-surface-body');

Future<T?> showLiquidGlassBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool useRootNavigator = false,
  bool isScrollControlled = false,
  bool useSafeArea = false,
  bool isDismissible = true,
  bool enableDrag = true,
  bool? showDragHandle,
  bool showTopHighlight = true,
  bool showShadow = true,
  bool showDecorativeGlow = true,
  double blurSigma = 24,
  BorderRadius? borderRadius,
  Color? surfaceColor,
  Color Function(BuildContext context)? surfaceColorBuilder,
  Color? barrierColor,
  ThemeData Function(BuildContext context)? themeBuilder,
  AnimationStyle? sheetAnimationStyle,
}) {
  assert(surfaceColor == null || surfaceColorBuilder == null);
  final dark = Theme.of(context).brightness == Brightness.dark;
  final viewportWidth = MediaQuery.sizeOf(context).width;
  final wideSheet = viewportWidth >= MestingAdaptiveBreakpoints.medium
      ? BoxConstraints(
          maxWidth: (viewportWidth - 48).clamp(0.0, 720.0).toDouble(),
        )
      : null;
  return showModalBottomSheet<T>(
    context: context,
    useRootNavigator: useRootNavigator,
    isScrollControlled: isScrollControlled,
    useSafeArea: useSafeArea,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    showDragHandle: false,
    backgroundColor: Colors.transparent,
    elevation: 0,
    constraints: wideSheet,
    barrierColor:
        barrierColor ?? Colors.black.withValues(alpha: dark ? 0.56 : 0.42),
    sheetAnimationStyle:
        sheetAnimationStyle ??
        const AnimationStyle(
          duration: Duration(milliseconds: 320),
          reverseDuration: Duration(milliseconds: 240),
        ),
    builder: (sheetContext) {
      final surface = LiquidGlassSurface(
        key: liquidGlassSheetSurfaceKey,
        borderRadius:
            borderRadius ??
            const BorderRadius.only(
              topLeft: Radius.circular(30),
              topRight: Radius.circular(30),
            ),
        showDragHandle: showDragHandle ?? false,
        showTopHighlight: showTopHighlight,
        showShadow: showShadow,
        showDecorativeGlow: showDecorativeGlow,
        blurSigma: blurSigma,
        surfaceColor: surfaceColor,
        surfaceColorBuilder: surfaceColorBuilder,
        child: builder(sheetContext),
      );
      // Application-owned sheets can opt out of a captured player palette.
      // Resolve inside the route so a system appearance change also updates
      // the glass surface, not just its foreground content.
      return themeBuilder == null
          ? surface
          : Theme(data: themeBuilder(sheetContext), child: surface);
    },
  );
}

class LiquidGlassSurface extends StatelessWidget {
  const LiquidGlassSurface({
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(30)),
    this.showDragHandle = false,
    this.showTopHighlight = true,
    this.showShadow = true,
    this.showDecorativeGlow = true,
    this.blurSigma = 24,
    this.surfaceColor,
    this.surfaceColorBuilder,
    super.key,
  }) : assert(surfaceColor == null || surfaceColorBuilder == null);

  final Widget child;
  final BorderRadius borderRadius;
  final bool showDragHandle;
  final bool showTopHighlight;
  final bool showShadow;
  final bool showDecorativeGlow;
  final double blurSigma;
  final Color? surfaceColor;
  final Color Function(BuildContext context)? surfaceColorBuilder;

  @override
  Widget build(BuildContext context) {
    final tokens = context.musicThemeTokens;
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final resolvedSurfaceColor =
        surfaceColorBuilder?.call(context) ?? surfaceColor;

    final content = showDragHandle
        ? Padding(padding: const EdgeInsets.only(top: 18), child: child)
        : child;

    return RepaintBoundary(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          boxShadow: showShadow
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: dark ? 0.42 : 0.18),
                    blurRadius: 38,
                    offset: const Offset(0, -8),
                  ),
                  BoxShadow(
                    color: scheme.primary.withValues(alpha: dark ? 0.08 : 0.06),
                    blurRadius: 54,
                    spreadRadius: -12,
                    offset: const Offset(0, -14),
                  ),
                ]
              : null,
        ),
        child: ClipRRect(
          borderRadius: borderRadius,
          child: blurSigma > 0
              ? BackdropFilter(
                  filter: ImageFilter.blur(
                    sigmaX: blurSigma,
                    sigmaY: blurSigma,
                    tileMode: TileMode.decal,
                  ),
                  child: _LiquidGlassSurfaceBody(
                    borderRadius: borderRadius,
                    showDragHandle: showDragHandle,
                    showTopHighlight: showTopHighlight,
                    showDecorativeGlow: showDecorativeGlow,
                    content: content,
                    tokens: tokens,
                    scheme: scheme,
                    dark: dark,
                    surfaceColor: resolvedSurfaceColor,
                  ),
                )
              : _LiquidGlassSurfaceBody(
                  borderRadius: borderRadius,
                  showDragHandle: showDragHandle,
                  showTopHighlight: showTopHighlight,
                  showDecorativeGlow: showDecorativeGlow,
                  content: content,
                  tokens: tokens,
                  scheme: scheme,
                  dark: dark,
                  surfaceColor: resolvedSurfaceColor,
                ),
        ),
      ),
    );
  }
}

class _LiquidGlassSurfaceBody extends StatelessWidget {
  const _LiquidGlassSurfaceBody({
    required this.borderRadius,
    required this.showDragHandle,
    required this.showTopHighlight,
    required this.showDecorativeGlow,
    required this.content,
    required this.tokens,
    required this.scheme,
    required this.dark,
    required this.surfaceColor,
  });

  final BorderRadius borderRadius;
  final bool showDragHandle;
  final bool showTopHighlight;
  final bool showDecorativeGlow;
  final Widget content;
  final MusicThemeTokens tokens;
  final ColorScheme scheme;
  final bool dark;
  final Color? surfaceColor;

  @override
  Widget build(BuildContext context) {
    final body = Stack(
      children: [
        content,
        if (showDragHandle)
          Positioned(
            top: 8,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: tokens.textMuted.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(99),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.white.withValues(
                          alpha: dark ? 0.09 : 0.34,
                        ),
                        blurRadius: 5,
                        offset: const Offset(0, -1),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );

    return DecoratedBox(
      key: liquidGlassSurfaceBodyKey,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        color: surfaceColor,
        // A bright top edge reads as an unintended white bar against the
        // dark app surfaces. Keep the subtle outline on the other edges,
        // while letting the sheet/card blend into its dark backdrop above.
        border: dark
            ? Border(
                left: BorderSide(
                  color: Colors.white.withValues(alpha: 0.15),
                  width: 0.8,
                ),
                right: BorderSide(
                  color: Colors.white.withValues(alpha: 0.15),
                  width: 0.8,
                ),
                bottom: BorderSide(
                  color: Colors.white.withValues(alpha: 0.15),
                  width: 0.8,
                ),
              )
            : Border.all(
                color: Colors.white.withValues(alpha: 0.48),
                width: 0.8,
              ),
        gradient: surfaceColor == null
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.alphaBlend(
                    Colors.white.withValues(alpha: dark ? 0.07 : 0.28),
                    tokens.glassStrong.withValues(alpha: dark ? 0.84 : 0.76),
                  ),
                  tokens.glass.withValues(alpha: dark ? 0.78 : 0.68),
                  Color.alphaBlend(
                    scheme.primary.withValues(alpha: dark ? 0.08 : 0.045),
                    tokens.glassStrong.withValues(alpha: dark ? 0.82 : 0.74),
                  ),
                ],
                stops: const [0, 0.52, 1],
              )
            : null,
      ),
      child: showDecorativeGlow
          ? CustomPaint(
              foregroundPainter: _LiquidGlassSheetPainter(
                borderRadius: borderRadius,
                accent: scheme.primary,
                dark: dark,
                // The light-only top gleam preserves the clean separation on
                // white sheets without leaving a white stripe in dark mode.
                showTopHighlight: showTopHighlight && !dark,
              ),
              child: body,
            )
          : body,
    );
  }
}

class _LiquidGlassSheetPainter extends CustomPainter {
  const _LiquidGlassSheetPainter({
    required this.borderRadius,
    required this.accent,
    required this.dark,
    required this.showTopHighlight,
  });

  final BorderRadius borderRadius;
  final Color accent;
  final bool dark;
  final bool showTopHighlight;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final bounds = Offset.zero & size;
    final clipPath = Path()
      ..addRRect(borderRadius.resolve(TextDirection.ltr).toRRect(bounds));
    canvas.save();
    canvas.clipPath(clipPath);

    final glow = Paint()
      ..shader =
          RadialGradient(
            colors: [
              accent.withValues(alpha: dark ? 0.1 : 0.075),
              accent.withValues(alpha: 0),
            ],
          ).createShader(
            Rect.fromCircle(
              center: Offset(size.width * 0.83, size.height * 0.12),
              radius: size.width * 0.44,
            ),
          );
    canvas.drawCircle(
      Offset(size.width * 0.83, size.height * 0.12),
      size.width * 0.44,
      glow,
    );

    if (showTopHighlight) {
      final topHighlight = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..shader = LinearGradient(
          colors: [
            Colors.white.withValues(alpha: dark ? 0.34 : 0.82),
            Colors.white.withValues(alpha: dark ? 0.08 : 0.22),
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width, 34));
      final topPath = Path()
        ..moveTo(30, 1)
        ..cubicTo(
          size.width * 0.28,
          0,
          size.width * 0.68,
          2.5,
          size.width - 24,
          0.8,
        );
      canvas.drawPath(topPath, topHighlight);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _LiquidGlassSheetPainter oldDelegate) =>
      oldDelegate.borderRadius != borderRadius ||
      oldDelegate.accent != accent ||
      oldDelegate.dark != dark ||
      oldDelegate.showTopHighlight != showTopHighlight;
}
