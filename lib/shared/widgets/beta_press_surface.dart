import 'package:flutter/material.dart';

/// A quiet, rounded press response for setting rows; no rectangular ink splash.
/// Persistence/selection remain with the caller, independently of pointer state.
class BetaPressSurface extends StatefulWidget {
  const BetaPressSurface({required this.child, required this.onTap, super.key});
  final Widget child;
  final VoidCallback? onTap;
  @override
  State<BetaPressSurface> createState() => _BetaPressSurfaceState();
}

class _BetaPressSurfaceState extends State<BetaPressSurface> {
  bool _pressed = false;
  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: widget.onTap,
    onTapDown: widget.onTap == null
        ? null
        : (_) => setState(() => _pressed = true),
    onTapUp: (_) => setState(() => _pressed = false),
    onTapCancel: () => setState(() => _pressed = false),
    child: AnimatedScale(
      scale: _pressed ? .977 : 1,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: Theme.of(
            context,
          ).colorScheme.onSurface.withValues(alpha: _pressed ? .055 : 0),
        ),
        child: widget.child,
      ),
    ),
  );
}
