import 'dart:async';
import 'dart:ui' show lerpDouble;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Orientation and route lifetime belong to the full-screen presentation, not
/// to the video controller. The caller retains the same decoder and position.
Future<void> showMusicMvFullscreen({
  required BuildContext context,
  required Rect origin,
  required Widget video,
}) async {
  final viewport = MediaQuery.sizeOf(context);
  final reduced = MediaQuery.disableAnimationsOf(context);
  final route = PageRouteBuilder<void>(
    opaque: false,
    transitionDuration: reduced
        ? Duration.zero
        : const Duration(milliseconds: 360),
    reverseTransitionDuration: reduced
        ? Duration.zero
        : const Duration(milliseconds: 280),
    pageBuilder: (_, animation, _) => _MvFullscreen(
      origin: origin,
      originalViewport: viewport,
      animation: animation,
      video: video,
    ),
    transitionsBuilder: (_, _, _, child) => child,
  );
  try {
    await Navigator.of(context, rootNavigator: true).push(route);
    // push completes at pop, before the reverse animation has finished.
    await route.completed;
  } finally {
    // Also cover route removal/disposal and failure to enter full screen.
    await restoreMusicMvPortrait();
  }
}

Future<void> restoreMusicMvPortrait() async {
  try {
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  } finally {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }
}

class _MvFullscreen extends StatefulWidget {
  const _MvFullscreen({
    required this.origin,
    required this.originalViewport,
    required this.animation,
    required this.video,
  });
  final Rect origin;
  final Size originalViewport;
  final Animation<double> animation;
  final Widget video;
  @override
  State<_MvFullscreen> createState() => _MvFullscreenState();
}

class _MvFullscreenState extends State<_MvFullscreen> {
  bool _canPop = false, _leaving = false;
  late final Future<void> _enter;

  @override
  void initState() {
    super.initState();
    _enter = _configure();
  }

  Future<void> _configure() async {
    try {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      if (!mounted || _leaving) return;
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } on Object {
      // Systems may decline orientation requests (e.g. large-screen policy).
      // Keep a usable route and a working Back action rather than losing video.
    }
  }

  Future<void> _exit() async {
    if (_leaving) return;
    _leaving = true;
    await _enter;
    await restoreMusicMvPortrait();
    if (!mounted) return;
    setState(() => _canPop = true);
    // Apply PopScope before requesting pop; repeated Back/exit stays guarded.
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => PopScope<void>(
    canPop: _canPop,
    onPopInvokedWithResult: (popped, _) {
      if (!popped) unawaited(_exit());
    },
    child: Material(
      type: MaterialType.transparency,
      child: AnimatedBuilder(
        animation: widget.animation,
        child: widget.video,
        builder: (context, video) {
          final size = MediaQuery.sizeOf(context);
          final progress = MediaQuery.disableAnimationsOf(context)
              ? 1.0
              : Curves.easeInOutCubic.transform(widget.animation.value);
          // Reproject the portrait origin when Android reports a rotated
          // viewport mid-flight; no fixed pixel dimensions survive rotation.
          final from = Rect.fromLTWH(
            widget.origin.left / widget.originalViewport.width * size.width,
            widget.origin.top / widget.originalViewport.height * size.height,
            widget.origin.width / widget.originalViewport.width * size.width,
            widget.origin.height / widget.originalViewport.height * size.height,
          );
          final rect = Rect.lerp(from, Offset.zero & size, progress)!;
          return Stack(
            children: [
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: progress),
                ),
              ),
              Positioned.fromRect(
                rect: rect,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(
                    lerpDouble(18, 0, progress)!,
                  ),
                  child: ColoredBox(color: Colors.black, child: video),
                ),
              ),
              Positioned(
                right: 12 + MediaQuery.paddingOf(context).right,
                top: 12 + MediaQuery.paddingOf(context).top,
                child: FadeTransition(
                  opacity: widget.animation,
                  child: IconButton(
                    key: const ValueKey('music-mv-exit-fullscreen'),
                    tooltip: '退出全屏',
                    onPressed: _exit,
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0x66000000),
                      minimumSize: const Size(48, 48),
                    ),
                    icon: const Icon(
                      CupertinoIcons.arrow_down_right_arrow_up_left,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}
