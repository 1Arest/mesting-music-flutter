import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import '../../../core/audio/playback_interruption.dart';
import '../../../core/audio/playback_providers.dart';
import '../../../shared/models/track.dart';
import '../../../shared/widgets/beta_glass_controls.dart';
import '../../../shared/widgets/beta_glass_scroll_body.dart';
import '../../../shared/widgets/music_feature_page.dart';
import '../data/platform_mv_repository.dart';
import '../platform_mv_providers.dart';
import 'music_mv_fullscreen.dart';
import '../platform_backend_providers.dart';
import '../netease/netease_mv_repository.dart';
import '../netease/netease_features_page.dart';
import '../netease/netease_features_repository.dart';
import '../music_platform_providers.dart';
import '../data/music_platform_api.dart';

class MusicMvPage extends ConsumerStatefulWidget {
  const MusicMvPage({required this.track, this.mvId, super.key});
  final Track track;
  final String? mvId;
  @override
  ConsumerState<MusicMvPage> createState() => _MusicMvPageState();
}

class _MusicMvPageState extends ConsumerState<MusicMvPage>
    with WidgetsBindingObserver {
  late final MusicPlaybackInterruption _music;
  VideoPlayerController? _video;
  StreamSubscription<String>? _commands;
  MusicMv? _mv;
  MusicMvQuality? _quality;
  bool _loading = true,
      _absent = false,
      _resumeVideo = false,
      _pausingForVideo = false;
  String? _error;
  int _generation = 0;
  final _videoAnchor = GlobalKey();
  bool _fullscreenOpen = false;
  late final String? _owner, _credential;
  bool get _current =>
      ref.read(platformAccountProvider).value?.ownerId == _owner &&
      ref.read(platformAccountProvider).value?.token == _credential;
  @override
  void initState() {
    super.initState();
    final account = ref.read(platformAccountProvider).value;
    _owner = account?.ownerId;
    _credential = account?.token;
    WidgetsBinding.instance.addObserver(this);
    final handler = ref.read(audioHandlerProvider);
    _music = MusicPlaybackInterruption(
      mediaId: () => handler.mediaItem.value?.id,
      revision: () => handler.transportRevision,
      playing: () => handler.playbackState.value.playing,
      pause: handler.pause,
      play: handler.play,
    );
    // An explicit music command (including a sleep-timer pause) wins over MV.
    _commands = handler.userCommandStream.listen((_) {
      if (_pausingForVideo) return;
      _resumeVideo = false;
      unawaited(_video?.pause());
    });
    Future.microtask(_load);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _resumeVideo = _video?.value.isPlaying == true;
      unawaited(_video?.pause());
    } else if (state == AppLifecycleState.resumed &&
        _resumeVideo &&
        _music.isCurrent) {
      _resumeVideo = false;
      unawaited(_video?.play());
    }
  }

  Future<void> _load() async {
    if (!_current) return;
    final generation = ++_generation;
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
        _absent = false;
      });
    }
    try {
      await _music.acquire();
      if (!mounted || generation != _generation || !_current) return;
      final repository = ref.read(platformMvRepositoryProvider);
      final mv = widget.mvId != null && repository is NeteaseMvRepository
          ? await repository.byId(
              widget.mvId!,
              fallbackTitle: widget.track.title,
            )
          : await repository.lookup(widget.track);
      if (!mounted || generation != _generation || !_current) return;
      if (mv == null) {
        setState(() {
          _absent = true;
          _loading = false;
        });
        return;
      }
      _mv = mv;
      await _select(mv.qualities.first, autoplay: true);
    } on Object {
      if (mounted && generation == _generation) {
        setState(() {
          _loading = false;
          _error = 'MV 暂时无法加载，请重试。';
        });
      }
    }
  }

  Future<void> _select(MusicMvQuality quality, {bool? autoplay}) async {
    if (!_current) return;
    final generation = ++_generation;
    final previous = _video;
    final position = previous?.value.position ?? Duration.zero;
    final play = autoplay ?? previous?.value.isPlaying ?? false;
    await previous?.pause();
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final urls = await ref.read(platformMvRepositoryProvider).urls(quality);
      if (urls.isEmpty) {
        throw const MusicPlatformException('平台暂未提供此清晰度的 MV 地址，请选择其他清晰度或稍后重试');
      }
      for (final url in urls.take(3)) {
        final candidate = VideoPlayerController.networkUrl(url);
        try {
          await candidate.initialize().timeout(const Duration(seconds: 15));
          if (!mounted || generation != _generation || !_current) {
            await candidate.dispose();
            return;
          }
          if (position > Duration.zero) {
            await candidate.seekTo(
              position < candidate.value.duration ? position : Duration.zero,
            );
          }
          if (play && _music.isCurrent) await candidate.play();
          if (!mounted || generation != _generation || !_current) {
            await candidate.dispose();
            return;
          }
          setState(() {
            _video = candidate;
            _quality = quality;
            _loading = false;
          });
          unawaited(previous?.dispose());
          return;
        } on Object {
          await candidate.dispose();
        }
      }
      throw StateError('Video playback unavailable');
    } on Object catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _loading = false;
          _error = error is MusicPlatformException
              ? error.message
              : '该 MV 暂未加载成功，请重试或选择其他清晰度。';
        });
      }
    }
  }

  Future<void> _fullscreen() async {
    final video = _video;
    if (video == null || _fullscreenOpen || _loading) return;
    final box = _videoAnchor.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final origin = box.localToGlobal(Offset.zero) & box.size;
    setState(() => _fullscreenOpen = true);
    try {
      await showMusicMvFullscreen(
        context: context,
        origin: origin,
        video: _VideoSurface(controller: video, onToggle: _toggleVideo),
      );
    } finally {
      if (mounted) setState(() => _fullscreenOpen = false);
    }
  }

  Future<void> _toggleVideo() async {
    final video = _video;
    if (video == null) return;
    if (video.value.isPlaying) {
      await video.pause();
      return;
    }
    final handler = ref.read(audioHandlerProvider);
    if (handler.playbackState.value.playing) {
      _pausingForVideo = true;
      try {
        await handler.pause();
      } finally {
        _pausingForVideo = false;
      }
    }
    if (mounted && identical(video, _video)) await video.play();
  }

  @override
  void dispose() {
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_commands?.cancel());
    final video = _video;
    unawaited(() async {
      try {
        await video?.pause();
        await video?.dispose();
      } finally {
        await _music.release();
      }
    }());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(platformAccountProvider);
    if (!_current) {
      unawaited(_video?.pause());
      return const MusicFeaturePage(
        title: 'MV',
        child: Center(child: Text('账号已变化，请返回后重新打开')),
      );
    }
    final scheme = Theme.of(context).colorScheme;
    return MusicFeaturePage(
      title: 'MV',
      child: BetaGlassScrollBody(
        padding: const EdgeInsets.fromLTRB(22, 12, 22, 40),
        children: [
          ClipRRect(
            key: _videoAnchor,
            borderRadius: BorderRadius.circular(18),
            child: ColoredBox(
              color: Colors.black,
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: _video == null
                    ? Center(
                        child: _loading
                            ? const BetaActivityIndicator(color: Colors.white)
                            : const Icon(
                                CupertinoIcons.play_rectangle,
                                color: Colors.white54,
                                size: 50,
                              ),
                      )
                    : Stack(
                        fit: StackFit.expand,
                        children: [
                          if (!_fullscreenOpen)
                            _VideoSurface(
                              controller: _video!,
                              onToggle: _toggleVideo,
                            ),
                          if (_loading)
                            const Center(
                              child: BetaActivityIndicator(color: Colors.white),
                            ),
                        ],
                      ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            _mv?.title ?? widget.track.title,
            style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            widget.track.artist,
            style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant),
          ),
          if (_absent)
            const Padding(
              padding: EdgeInsets.only(top: 28),
              child: Text(
                '这首歌曲暂未提供可播放的 MV。',
                style: TextStyle(fontSize: 16, height: 1.6),
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 18),
              child: MusicFeatureMessage(
                message: _error!,
                onRetry: _video == null
                    ? _load
                    : () => _select(
                        _quality ?? _mv!.qualities.first,
                        autoplay: true,
                      ),
              ),
            ),
          if (_mv != null) ...[
            const SizedBox(height: 28),
            const Text(
              '清晰度',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final quality in _mv!.qualities)
                  ChoiceChip(
                    label: Text(quality.label),
                    selected: quality.hash == _quality?.hash,
                    onSelected: _loading ? null : (_) => _select(quality),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            BetaGlassButton(
              key: const ValueKey('music-mv-fullscreen'),
              onPressed: _video == null || _loading || _fullscreenOpen
                  ? null
                  : _fullscreen,
              child: const Text('全屏播放'),
            ),
          ],
          const SizedBox(height: 20),
          if (ref.watch(usesNeteaseProvider) && _mv != null)
            NeteaseResourceActions(
              item: NeteaseItem(
                id: _mv!.id,
                name: _mv!.title,
                kind: NeteaseEntity.mv,
              ),
            ),
          Text(
            'MV 播放期间音乐暂停；返回时按进入前的播放状态恢复。',
            style: TextStyle(
              fontSize: 13,
              height: 1.6,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _VideoSurface extends StatefulWidget {
  const _VideoSurface({required this.controller, required this.onToggle});
  final VideoPlayerController controller;
  final Future<void> Function() onToggle;
  @override
  State<_VideoSurface> createState() => _VideoSurfaceState();
}

class _VideoSurfaceState extends State<_VideoSurface> {
  Timer? _hide;
  bool _visible = true;
  @override
  void initState() {
    super.initState();
    _armHide();
  }

  void _armHide() {
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 3), () {
      if (mounted &&
          widget.controller.value.isPlaying &&
          !MediaQuery.accessibleNavigationOf(context)) {
        setState(() => _visible = false);
      }
    });
  }

  @override
  void dispose() {
    _hide?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<VideoPlayerValue>(
        valueListenable: widget.controller,
        builder: (context, value, _) => Stack(
          alignment: Alignment.center,
          children: [
            if (value.isInitialized)
              Center(
                child: AspectRatio(
                  aspectRatio: value.aspectRatio,
                  child: VideoPlayer(widget.controller),
                ),
              ),
            if (value.hasError)
              const Center(
                child: Text(
                  '播放中断，请返回重试',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  setState(() => _visible = !_visible);
                  _armHide();
                },
                child: const SizedBox.expand(),
              ),
            ),
            IgnorePointer(
              ignoring: !_visible && value.isPlaying,
              child: AnimatedOpacity(
                opacity: _visible || !value.isPlaying ? 1 : 0,
                duration: const Duration(milliseconds: 180),
                child: Center(
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      color: Color(0x66000000),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      tooltip: value.isPlaying ? '暂停 MV' : '播放 MV',
                      iconSize: 48,
                      onPressed: () {
                        widget.onToggle();
                        _armHide();
                      },
                      icon: Icon(
                        value.isPlaying
                            ? CupertinoIcons.pause_circle
                            : CupertinoIcons.play_circle,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 14,
              right: 14,
              bottom: 8,
              child: IgnorePointer(
                ignoring: !_visible && value.isPlaying,
                child: AnimatedOpacity(
                  opacity: _visible || !value.isPlaying ? 1 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x00000000), Color(0xAA000000)],
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 14, 8, 6),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          VideoProgressIndicator(
                            widget.controller,
                            allowScrubbing: true,
                            colors: const VideoProgressColors(
                              playedColor: Colors.white,
                              bufferedColor: Colors.white38,
                              backgroundColor: Colors.white24,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _time(value.position),
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.white,
                                ),
                              ),
                              Text(
                                _time(value.duration),
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
  String _time(Duration duration) =>
      '${duration.inMinutes}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}';
}
