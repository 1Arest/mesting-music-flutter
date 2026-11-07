import 'package:flutter/material.dart';

/// An inset optical press highlight shared by menu rows. Business callbacks
/// remain with callers; InkWell supplies cancellation, keyboard and focus.
/// Only this row animates, never the enclosing premium glass surface.
class BetaGlassMenuItem extends StatefulWidget {
  const BetaGlassMenuItem({
    required this.child,
    required this.onTap,
    super.key,
  });
  final Widget child;
  final VoidCallback? onTap;
  @override
  State<BetaGlassMenuItem> createState() => _BetaGlassMenuItemState();
}

class _BetaGlassMenuItemState extends State<BetaGlassMenuItem> {
  bool _pressed = false, _focused = false, _hovered = false;
  bool _scrolling = false;
  ScrollPosition? _position;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = Scrollable.maybeOf(context)?.position;
    if (identical(next, _position)) return;
    _position?.isScrollingNotifier.removeListener(_scrollChanged);
    _position = next;
    _scrolling = next?.isScrollingNotifier.value ?? false;
    next?.isScrollingNotifier.addListener(_scrollChanged);
  }

  void _scrollChanged() {
    if (!mounted) return;
    setState(() {
      _scrolling = _position?.isScrollingNotifier.value ?? false;
      // Touch focus is not a selected menu value. A scroll must clear its
      // transient highlight even while the finger remains on the screen.
      if (_scrolling) _pressed = false;
    });
  }

  @override
  void dispose() {
    _position?.isScrollingNotifier.removeListener(_scrollChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final keyboardFocus =
        _focused &&
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    final active =
        widget.onTap != null &&
        !_scrolling &&
        (_pressed || keyboardFocus || _hovered);
    final tint = dark ? Colors.white : const Color(0xFF007AFF);
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 130);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      child: AnimatedScale(
        scale: _pressed && !_scrolling ? .985 : 1,
        duration: duration,
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: duration,
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                tint.withValues(alpha: active ? (dark ? .14 : .09) : 0),
                tint.withValues(alpha: active ? (dark ? .05 : .025) : 0),
              ],
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            splashFactory: NoSplash.splashFactory,
            overlayColor: const WidgetStatePropertyAll(Colors.transparent),
            canRequestFocus: widget.onTap != null,
            onHighlightChanged: (value) =>
                setState(() => _pressed = value && !_scrolling),
            onFocusChange: (value) => setState(() => _focused = value),
            onHover: (value) => setState(() => _hovered = value),
            onTap: widget.onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}
