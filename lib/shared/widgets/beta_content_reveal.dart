import 'package:flutter/material.dart';

/// Foreground-only arrival motion. Never wrap an entire glass surface in this
/// widget: its backdrop must stay in the scene pass. A stable key retains the
/// completed reveal when pagination adds rows or a parent changes selection.
class BetaContentReveal extends StatelessWidget {
  const BetaContentReveal({
    required this.child,
    this.animate = true,
    super.key,
  });
  final Widget child;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    if (!animate || MediaQuery.disableAnimationsOf(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      child: child,
      builder: (_, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 7 * (1 - value)),
          child: child,
        ),
      ),
    );
  }
}
