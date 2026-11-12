import 'package:flutter/material.dart';

/// Compact icon feedback without Material's large circular state overlay.
/// IconButton retains keyboard activation, tooltip, focus and 48dp hit target;
/// only the glyph scales/fades, including cancellation and reduced motion.
class BetaIconButton extends StatefulWidget {
  const BetaIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.backgroundColor = Colors.transparent,
    super.key,
  });
  final Widget icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color backgroundColor;
  @override
  State<BetaIconButton> createState() => _BetaIconButtonState();
}

class _BetaIconButtonState extends State<BetaIconButton> {
  bool _pressed = false;
  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: widget.onPressed == null
        ? null
        : (_) => setState(() => _pressed = true),
    onPointerUp: (_) => setState(() => _pressed = false),
    onPointerCancel: (_) => setState(() => _pressed = false),
    child: IconButton(
      tooltip: widget.tooltip,
      onPressed: widget.onPressed,
      style: ButtonStyle(
        backgroundColor: WidgetStatePropertyAll(widget.backgroundColor),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        side: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.focused) &&
                  FocusManager.instance.highlightMode ==
                      FocusHighlightMode.traditional
              ? BorderSide(
                  color: Theme.of(context).colorScheme.primary,
                  width: 1.5,
                )
              : BorderSide.none,
        ),
        splashFactory: NoSplash.splashFactory,
        minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
      ),
      icon: AnimatedScale(
        scale: _pressed ? .9 : 1,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 140),
        child: AnimatedOpacity(
          opacity: _pressed ? .66 : 1,
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 140),
          child: widget.icon,
        ),
      ),
    ),
  );
}
