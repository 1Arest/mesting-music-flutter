import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../features/themes/startup_style.dart';
import 'branded_launch_screen.dart';

/// One foreground playback of bundled startup media. This widget owns only the
/// film; bootstrap owns readiness and account/audio restoration starts later.
/// Preview uses a separate instance, never the process's completed startup gate.
class StartupVideoSurface extends StatefulWidget {
  const StartupVideoSurface({
    required this.style,
    required this.onFinished,
    super.key,
  });
  final StartupStyle style;
  final VoidCallback onFinished;

  @override
  State<StartupVideoSurface> createState() => _StartupVideoSurfaceState();
}

class _StartupVideoSurfaceState extends State<StartupVideoSurface>
    with WidgetsBindingObserver {
  late final VideoPlayerController _controller;
  final _activePlayback = Stopwatch();
  Timer? _watchdog;
  Timer? _fallbackTimer;
  bool _ready = false;
  bool _fallback = false;
  bool _finished = false;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _controller = VideoPlayerController.asset(widget.style.videoAsset!)
      ..addListener(_onVideo);
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      await _controller.initialize().timeout(const Duration(seconds: 3));
      if (!mounted || _finished || _fallback) return;
      if (_controller.value.duration <= Duration.zero) {
        _useClassic();
        return;
      }
      await _controller.setLooping(false);
      // Original soundtrack, at the user's existing system media volume.
      await _controller.setVolume(1);
      if (!mounted || _finished || _fallback) return;
      setState(() => _ready = true);
      _watchdog = Timer.periodic(const Duration(milliseconds: 250), (_) {
        // A stalled decoder cannot hold startup forever. Background time does
        // not consume the deadline, and resume never seeks back to the start.
        if (_activePlayback.elapsed >
            _controller.value.duration + const Duration(seconds: 3)) {
          _useClassic();
        }
      });
      if (_foreground) await _play();
    } on Object {
      _useClassic();
    }
  }

  Future<void> _play() async {
    if (!_ready || _finished || _fallback || !_foreground) return;
    try {
      _activePlayback.start();
      await _controller.play();
    } on Object {
      _useClassic();
    }
  }

  void _onVideo() {
    if (!mounted || _finished || _fallback) return;
    final value = _controller.value;
    if (value.hasError) {
      _useClassic();
    } else if (value.isCompleted ||
        (value.isInitialized &&
            value.duration > Duration.zero &&
            value.position >= value.duration)) {
      unawaited(_finish());
    }
  }

  void _useClassic() {
    if (!mounted || _finished || _fallback) return;
    _watchdog?.cancel();
    _activePlayback.stop();
    unawaited(_controller.pause().catchError((Object _) {}));
    setState(() => _fallback = true);
    _fallbackTimer = Timer(const Duration(milliseconds: 720), _finish);
  }

  Future<void> _finish() async {
    if (!mounted || _finished) return;
    _finished = true;
    _watchdog?.cancel();
    _fallbackTimer?.cancel();
    _activePlayback.stop();
    // Release video audio focus before bootstrap mounts the music/account app.
    // Its outgoing fade may keep this surface alive for another 280 ms.
    try {
      await _controller.pause();
    } on Object {
      // A failed decoder has nothing left to pause; readiness still advances.
    }
    if (mounted) widget.onFinished();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_finished || _fallback) return;
    if (_foreground) {
      unawaited(_play());
    } else {
      _activePlayback.stop();
      unawaited(_controller.pause().catchError((Object _) {}));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _watchdog?.cancel();
    _fallbackTimer?.cancel();
    _controller.removeListener(_onVideo);
    unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_fallback) {
      return const MestingBrandedLaunchScreen(forceCoral: true);
    }
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarContrastEnforced: false,
        systemStatusBarContrastEnforced: false,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: ColoredBox(
        key: const ValueKey('startup-video-surface'),
        color: mestingBrandCoral,
        // Contain preserves both characters and the wordmark on every ratio;
        // the matching coral canvas absorbs any extra width/height.
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_ready)
              Positioned.fill(
                child: ClipRect(
                  child: ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                    child: FittedBox(
                      fit: BoxFit.fill,
                      child: SizedBox(
                        width: _controller.value.size.width,
                        height: _controller.value.size.height,
                        child: VideoPlayer(_controller),
                      ),
                    ),
                  ),
                ),
              ),
            Center(
              child: _ready
                  ? AspectRatio(
                      aspectRatio: _controller.value.aspectRatio,
                      child: VideoPlayer(_controller),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}
