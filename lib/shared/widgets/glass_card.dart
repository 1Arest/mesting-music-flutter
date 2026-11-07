import 'package:flutter/material.dart';

import '../../features/themes/music_theme_tokens.dart';

class GlassCard extends StatelessWidget {
  const GlassCard({
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.borderRadius = 24,
    this.color,
    this.borderColor,
    this.shadows,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final Color? color;
  final Color? borderColor;
  final List<BoxShadow>? shadows;

  @override
  Widget build(BuildContext context) {
    final tokens = context.musicThemeTokens;
    final radius = BorderRadius.circular(borderRadius);
    final surfaceColor = color ?? tokens.glass;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow:
            shadows ??
            [
              BoxShadow(
                color: tokens.shadow,
                blurRadius: 34,
                offset: const Offset(0, 16),
              ),
            ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: radius,
            border: Border.all(color: borderColor ?? tokens.border),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: radius,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: dark ? .055 : .22),
                  Colors.white.withValues(alpha: 0),
                  Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: dark ? .025 : .018),
                ],
                stops: const [0, .46, 1],
              ),
            ),
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}
