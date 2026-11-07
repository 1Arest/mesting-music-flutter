import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../features/themes/startup_style.dart';

/// Presentation only: no timer, audio, navigation or dependency gate.
/// Keep the user's complete original artwork, including its typography. The
/// Notify the bootstrap after the first decoded image has actually painted.
class StartupImageSurface extends StatefulWidget {
  const StartupImageSurface({
    required this.style,
    this.onPresented,
    this.onFailed,
    super.key,
  }) : assert(
         style == StartupStyle.staticOne || style == StartupStyle.staticTwo,
       );
  final StartupStyle style;
  final VoidCallback? onPresented;
  final VoidCallback? onFailed;

  @override
  State<StartupImageSurface> createState() => _StartupImageSurfaceState();
}

class _StartupImageSurfaceState extends State<StartupImageSurface> {
  bool _notified = false;

  @override
  void didUpdateWidget(covariant StartupImageSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.style != oldWidget.style) _notified = false;
  }

  void _decodedFrame({bool failed = false}) {
    if (_notified) return;
    _notified = true;
    final style = widget.style;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.style == style) {
        failed ? widget.onFailed?.call() : widget.onPresented?.call();
      }
    });
  }

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: SystemUiOverlayStyle.light.copyWith(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarContrastEnforced: false,
      systemStatusBarContrastEnforced: false,
    ),
    child: IgnorePointer(
      child: ColoredBox(
        color: widget.style == StartupStyle.staticOne
            ? const Color(0xFFEC4B43)
            : const Color(0xFFE55449),
        child: SizedBox.expand(
          child: Image.asset(
            widget.style.posterAsset!,
            frameBuilder: (context, child, frame, _) {
              if (frame != null) _decodedFrame();
              return child;
            },
            errorBuilder: (context, error, stack) {
              // A missing/undecodable image must not hold dependency-ready
              // navigation forever. The bootstrap chooses its normal fallback.
              _decodedFrame(failed: true);
              return const SizedBox.expand();
            },
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
            excludeFromSemantics: true,
          ),
        ),
      ),
    ),
  );
}
