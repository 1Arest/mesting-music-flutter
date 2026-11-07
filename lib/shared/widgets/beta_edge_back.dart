import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// A two-edge fallback for in-app pages and embedded search states. Android's
/// system Back continues through PopScope; this recognizer only owns a narrow
/// edge strip, leaving sliders and horizontal shelves inside the page alone.
class BetaEdgeBack extends StatelessWidget {
  const BetaEdgeBack({
    required this.child,
    this.onBack,
    this.enabled = true,
    super.key,
  });
  final Widget child;
  final VoidCallback? onBack;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final navigator = Navigator.maybeOf(context);
    final active =
        enabled && (onBack != null || (navigator?.canPop() ?? false));
    // A popup changes Navigator.canPop even when this underlying page stays
    // visible. Keep its content at the same element position: swapping the
    // Scaffold with a LayoutBuilder used to dispose menus/editors mid-open,
    // losing selection results and restoring focus to a replacement editor.
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          fit: StackFit.expand,
          children: [
            child,
            if (active)
              for (final left in [true, false])
                Positioned(
                  left: left ? 0 : null,
                  right: left ? null : 0,
                  top: 0,
                  bottom: 0,
                  width: 32,
                  child: _EdgeRecognizer(
                    left: left,
                    onBack: () {
                      FocusManager.instance.primaryFocus?.unfocus();
                      if (onBack != null) {
                        onBack!();
                      } else {
                        unawaited(navigator!.maybePop());
                      }
                    },
                  ),
                ),
          ],
        );
      },
    );
  }
}

class _EdgeRecognizer extends StatefulWidget {
  const _EdgeRecognizer({required this.left, required this.onBack});
  final bool left;
  final VoidCallback onBack;
  @override
  State<_EdgeRecognizer> createState() => _EdgeRecognizerState();
}

class _EdgeRecognizerState extends State<_EdgeRecognizer> {
  double distance = 0;
  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.translucent,
    dragStartBehavior: DragStartBehavior.down,
    onHorizontalDragStart: (_) => distance = 0,
    onHorizontalDragUpdate: (details) =>
        distance += details.delta.dx * (widget.left ? 1 : -1),
    onHorizontalDragEnd: (details) {
      final speed = (details.primaryVelocity ?? 0) * (widget.left ? 1 : -1);
      if (distance > 64 || (distance > 12 && speed > 500)) widget.onBack();
      distance = 0;
    },
    child: const SizedBox.expand(),
  );
}
