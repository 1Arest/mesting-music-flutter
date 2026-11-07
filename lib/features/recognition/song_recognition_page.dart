import '../../shared/widgets/beta_content_insets.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import '../../core/audio/playback_providers.dart';
import '../../shared/models/track.dart';
import '../../shared/widgets/beta_glass_controls.dart';
import '../../shared/widgets/track_artwork.dart';
import '../experience/presentation/editorial_widgets.dart';
import '../library/presentation/favorite_toggle_button.dart';
import '../music_platform/music_platform_providers.dart';
import '../music_platform/presentation/platform_design.dart';
import 'recognition_repository.dart';
import '../themes/music_typography.dart';

class SongRecognitionPage extends ConsumerStatefulWidget {
  const SongRecognitionPage({super.key});
  @override
  ConsumerState<SongRecognitionPage> createState() =>
      _SongRecognitionPageState();
}

class _SongRecognitionPageState extends ConsumerState<SongRecognitionPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _recorder = AudioRecorder();
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  Completer<void>? _cancel;
  bool _active = false, _matching = false;
  int _epoch = 0, _attempt = 0;
  String? _error;
  List<Track> _results = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      unawaited(_stop());
    }
  }

  Future<void> _stop() async {
    _epoch++;
    if (_cancel?.isCompleted == false) {
      _cancel!.complete();
    }
    _pulse.stop();
    try {
      await _recorder.stop();
    } on Object {
      /* Already stopped/disposed. */
    }
    if (mounted) {
      setState(() {
        _active = false;
        _matching = false;
      });
    }
  }

  Future<void> _start() async {
    if (_active) return;
    final generation = ++_epoch;
    setState(() {
      _active = true;
      _error = null;
      _results = const [];
    });
    final identity = ref.read(platformAccountProvider).value;
    _cancel = Completer<void>();
    final abort = _cancel!.future;
    Directory? runDirectory;
    try {
      if (!await _recorder.hasPermission()) {
        throw const FormatException('请在系统设置中允许麦克风权限后重试');
      }
      if (!mounted || generation != _epoch) return;
      final handler = ref.read(audioHandlerProvider);
      await handler.pause();
      final dir = await getTemporaryDirectory();
      runDirectory = await createRecognitionSessionDirectory(dir);
      final repository = RecognitionRepository(
        ref.read(musicPlatformApiProvider),
      );
      for (var attempt = 1; attempt <= 7 && generation == _epoch; attempt++) {
        final file = File('${runDirectory.path}/segment-$attempt.wav');
        try {
          setState(() {
            _attempt = attempt;
            _matching = false;
          });
          await _recorder.start(
            const RecordConfig(
              encoder: AudioEncoder.wav,
              sampleRate: 44100,
              numChannels: 1,
              autoGain: false,
              echoCancel: false,
              noiseSuppress: false,
            ),
            path: file.path,
          );
          if (generation != _epoch) {
            await _recorder.stop();
            break;
          }
          _pulse.repeat(reverse: true);
          await Future.any([
            Future<void>.delayed(const Duration(seconds: 8)),
            abort,
          ]);
          final path = await _recorder.stop();
          if (!mounted || generation != _epoch) break;
          _pulse.stop();
          setState(() => _matching = true);
          if (path == null) continue;
          final tracks = await repository.identify(
            await File(path).readAsBytes(),
            abort: abort,
            identity: identity,
          );
          if (!mounted || generation != _epoch) break;
          if (tracks.isNotEmpty) {
            setState(() => _results = tracks);
            break;
          }
        } finally {
          if (await file.exists()) await file.delete();
        }
      }
      if (mounted && generation == _epoch && _results.isEmpty) {
        setState(() => _error = '暂未识别到歌曲，请靠近音源后重试');
      }
    } on Object catch (e) {
      if (mounted && generation == _epoch) {
        setState(
          () => _error = e is FormatException ? e.message : '识曲暂时未能完成，请检查网络后重试',
        );
      }
    } finally {
      try {
        if (runDirectory != null && await runDirectory.exists()) {
          await runDirectory.delete(recursive: true);
        }
      } on FileSystemException {
        // Cleanup failure does not replace the recognition result/error.
      }
      if (mounted && generation == _epoch) {
        _pulse.stop();
        setState(() {
          _active = false;
          _matching = false;
        });
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _epoch++;
    if (_cancel?.isCompleted == false) {
      _cancel!.complete();
    }
    _pulse.dispose();
    unawaited(_recorder.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(platformAccountProvider, (before, after) {
      if (_active &&
          (before?.value?.userId != after.value?.userId ||
              before?.value?.token != after.value?.token)) {
        unawaited(_stop());
      }
    });
    final scheme = Theme.of(context).colorScheme;
    return PlatformPageFrame(
      title: '听歌识曲',
      child: ListView(
        padding: BetaContentInsets.musicPaddingOf(
          context,
          EdgeInsets.fromLTRB(24, 30, 24, 210),
        ),
        children: [
          const Text(
            '让音乐告诉你答案',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: MusicTypography.titleSize,
              fontWeight: MusicTypography.titleWeight,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _active
                ? (_matching ? '正在识别第 $_attempt 段录音…' : '正在聆听周围的音乐…')
                : '轻点开始，识别正在播放的歌曲',
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 52),
          Center(
            child: ScaleTransition(
              scale: Tween<double>(begin: 1, end: 1.07).animate(_pulse),
              child: Container(
                width: 142,
                height: 142,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scheme.primary.withValues(alpha: .10),
                ),
                child: Icon(
                  CupertinoIcons.mic,
                  size: 60,
                  color: scheme.primary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 46),
          Center(
            child: BetaGlassButton(
              blue: !_active,
              onPressed: _active
                  ? () => unawaited(_stop())
                  : () => unawaited(_start()),
              child: Text(_active ? '停止识别' : '开始识别'),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 24),
              child: Text(_error!, textAlign: TextAlign.center),
            ),
          if (_results.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.only(top: 38, bottom: 12),
              child: Text(
                '识别结果',
                style: TextStyle(
                  fontSize: MusicTypography.sectionTitleSize,
                  fontWeight: MusicTypography.titleWeight,
                ),
              ),
            ),
            for (final track in _results)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: TrackArtwork(track: track, width: 52, height: 52),
                title: Text(track.title),
                subtitle: Text(track.artist),
                trailing: FavoriteToggleButton(track: track, compact: true),
                onTap: () => playEditorialTrack(context, ref, track, _results),
              ),
          ],
        ],
      ),
    );
  }
}
