import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/audio/playback_providers.dart';
import '../../music_platform/presentation/platform_feedback.dart';
import '../lyric_timing.dart';

/// Compact controls leave the playing lyrics visible while adjusting timing.
class LyricTimingTools extends ConsumerStatefulWidget {
  const LyricTimingTools({required this.child, super.key});
  final Widget child;

  @override
  ConsumerState<LyricTimingTools> createState() => _LyricTimingToolsState();
}

class _LyricTimingToolsState extends ConsumerState<LyricTimingTools> {
  bool _open = false;
  bool _saving = false;
  String? _song;

  Future<void> _adjust(String song, int? delta) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final controller = ref.read(lyricTimingProvider(song).notifier);
      if (delta == null) {
        await controller.reset();
      } else {
        await controller.adjust(delta);
      }
    } on Object catch (error) {
      if (mounted) showPlatformFailure(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final song = lyricTimingKey(ref.watch(currentTrackProvider));
    if (_song != song) {
      _song = song;
      _open = false;
    }
    final offset = ref.watch(lyricTimingProvider(song));
    final synced =
        ref.watch(currentTimedLyricsProvider).value?.isSynced == true;
    final milliseconds = offset.value ?? 0;
    final label =
        '${milliseconds > 0 ? '+' : ''}${(milliseconds / 1000).toStringAsFixed(1)} 秒';
    final ready = !_saving && offset.hasValue;
    return Stack(
      children: [
        Positioned.fill(child: widget.child),
        if (synced)
          Positioned(
            right: 0,
            top: 0,
            child: IconButton(
              tooltip: '歌词时间调整',
              onPressed: () => setState(() => _open = !_open),
              icon: const Icon(Icons.more_horiz_rounded, color: Colors.white70),
            ),
          ),
        if (_open && synced)
          Positioned(
            right: 4,
            top: 46,
            bottom: 4,
            child: Center(
              child: Material(
                color: const Color(0xE6222228),
                borderRadius: BorderRadius.circular(16),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                      TextButton(
                        onPressed: ready ? () => _adjust(song, -500) : null,
                        child: const Text('−0.5 秒'),
                      ),
                      TextButton(
                        onPressed: ready && milliseconds != 0
                            ? () => _adjust(song, null)
                            : null,
                        child: const Text('还原'),
                      ),
                      TextButton(
                        onPressed: ready ? () => _adjust(song, 500) : null,
                        child: const Text('＋0.5 秒'),
                      ),
                      IconButton(
                        tooltip: '关闭歌词时间调整',
                        color: Colors.white,
                        onPressed: () => setState(() => _open = false),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
