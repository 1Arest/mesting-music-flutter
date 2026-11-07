import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import '../../../../core/audio/playback_interruption.dart';
import '../../../../core/audio/playback_providers.dart';
import '../../../../shared/widgets/beta_glass_controls.dart';
import '../../music_platform_providers.dart';
import '../netease_media_uri.dart';

/// Video shares the existing music interruption owner. A music command or an
/// account change wins over video; closing a stale video cannot resume music.
class NeteaseVideoView extends ConsumerStatefulWidget {
  const NeteaseVideoView({
    required this.url,
    required this.isCurrent,
    super.key,
  });
  final String url;
  final bool Function() isCurrent;
  @override
  ConsumerState<NeteaseVideoView> createState() => _NeteaseVideoViewState();
}

class _NeteaseVideoViewState extends ConsumerState<NeteaseVideoView>
    with WidgetsBindingObserver {
  VideoPlayerController? _video;
  MusicPlaybackInterruption? _music;
  StreamSubscription<String>? _commands;
  bool _loading = true, _ownPause = false;
  bool _authorized = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final account = ref.read(platformAccountProvider).value;
    ref.listenManual(platformAccountProvider, (_, next) {
      if (next.value?.ownerId != account?.ownerId ||
          next.value?.token != account?.token) {
        _authorized = false;
        unawaited(_video?.pause());
      }
    });
    _load();
  }

  Future<void> _load() async {
    final uri = neteaseMediaUri(widget.url);
    if (uri == null ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.userInfo.isNotEmpty) {
      setState(() {
        _error = '视频地址无效';
        _loading = false;
      });
      return;
    }
    final video = VideoPlayerController.networkUrl(uri);
    try {
      await video.initialize().timeout(const Duration(seconds: 20));
      if (!mounted || !widget.isCurrent()) {
        await video.dispose();
        return;
      }
      final handler = ref.read(audioHandlerProvider);
      _music = MusicPlaybackInterruption(
        mediaId: () => handler.mediaItem.value?.id,
        revision: () => handler.transportRevision,
        playing: () => handler.playbackState.value.playing,
        pause: handler.pause,
        play: handler.play,
      );
      _commands = handler.userCommandStream.listen((_) {
        if (!_ownPause) unawaited(video.pause());
      });
      video.addListener(_redraw);
      setState(() {
        _video = video;
        _loading = false;
      });
    } catch (_) {
      await video.dispose();
      if (mounted) {
        setState(() {
          _error = '视频暂未加载成功，请返回后重试';
          _loading = false;
        });
      }
    }
  }

  void _redraw() {
    if (mounted) setState(() {});
  }

  Future<void> _toggle() async {
    final video = _video;
    if (video == null || !widget.isCurrent()) return;
    if (video.value.isPlaying) {
      await video.pause();
      return;
    }
    _ownPause = true;
    try {
      await _music?.acquire();
      if (mounted && widget.isCurrent()) await video.play();
    } finally {
      _ownPause = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(_video?.pause());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_commands?.cancel());
    _video?.removeListener(_redraw);
    unawaited(_video?.dispose());
    if (_authorized) unawaited(_music?.release());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 20),
    child: Column(
      children: [
        if (_loading) const Center(child: BetaActivityIndicator()),
        if (_error != null) Text(_error!),
        if (_video != null) ...[
          AspectRatio(
            aspectRatio: _video!.value.aspectRatio,
            child: VideoPlayer(_video!),
          ),
          const SizedBox(height: 12),
          VideoProgressIndicator(_video!, allowScrubbing: true),
          const SizedBox(height: 12),
          BetaGlassButton(
            onPressed: _toggle,
            child: Text(_video!.value.isPlaying ? '暂停视频' : '播放视频'),
          ),
        ],
      ],
    ),
  );
}

String? neteaseVideoUrl(Object? value) {
  if (value is Map) {
    final url = value['url'];
    if (url is String && url.isNotEmpty) {
      final uri = Uri.tryParse(url);
      if (uri != null &&
          {'http', 'https'}.contains(uri.scheme) &&
          uri.userInfo.isEmpty) {
        return url;
      }
    }
    for (final v in value.values) {
      if (v is Map || v is List) {
        final found = neteaseVideoUrl(v);
        if (found != null) return found;
      }
    }
  } else if (value is List) {
    for (final v in value) {
      final found = neteaseVideoUrl(v);
      if (found != null) return found;
    }
  }
  return null;
}
