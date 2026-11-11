import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/audio/playback_providers.dart';
import '../../../core/errors/user_facing_error.dart';
import '../../../shared/utils/duration_format.dart';
import '../../../shared/widgets/music_notice.dart';

/// Follows touch, wheel and fling events independently of playback scrolling.
class LyricScrollPreview {
  LyricScrollPreview(this.onChanged);

  final VoidCallback onChanged;
  Timer? _resume;
  int? _index;
  bool _scrolling = false;
  bool _seeking = false;

  int? get index => _index;
  bool get seeking => _seeking;

  bool handleScroll(
    ScrollNotification notification, {
    required int lineCount,
    required double topPadding,
    required int Function(double offset) lineAtOffset,
  }) {
    if (notification.depth != 0 || lineCount == 0) return false;

    final userScroll =
        notification is ScrollStartNotification &&
            notification.dragDetails != null ||
        notification is UserScrollNotification &&
            notification.direction != ScrollDirection.idle ||
        notification is ScrollUpdateNotification &&
            (notification.dragDetails != null || _scrolling);
    if (userScroll) {
      _resume?.cancel();
      _scrolling = true;
      final metrics = notification.metrics;
      final offset =
          metrics.pixels + metrics.viewportDimension / 2 - topPadding;
      final int next;
      if (metrics.pixels <= metrics.minScrollExtent) {
        next = 0;
      } else if (metrics.pixels >= metrics.maxScrollExtent) {
        next = lineCount - 1;
      } else {
        next = lineAtOffset(offset).clamp(0, lineCount - 1);
      }
      if (_index != next) {
        _index = next;
        onChanged();
      }
    } else if (notification is ScrollEndNotification && _scrolling) {
      _scrolling = false;
      _scheduleResume();
    }
    return false;
  }

  void _scheduleResume() {
    _resume?.cancel();
    if (!_seeking && _index != null) {
      _resume = Timer(const Duration(seconds: 5), () => clear());
    }
  }

  void clear({bool notify = true}) {
    _resume?.cancel();
    _scrolling = false;
    final wasBrowsing = _index != null;
    _index = null;
    if (notify && wasBrowsing) onChanged();
  }

  Future<void> playFrom(
    BuildContext context,
    WidgetRef ref,
    Duration time,
  ) async {
    if (_seeking || _index == null) return;
    final track = ref.read(currentTrackProvider);
    bool current() {
      final now = ref.read(currentTrackProvider);
      return now.id == track.id &&
          now.resolvedLyricsAsset == track.resolvedLyricsAsset;
    }

    _seeking = true;
    _resume?.cancel();
    onChanged();
    try {
      final handler = ref.read(audioHandlerProvider);
      final pendingSeek = handler.seek(time);
      final revision = handler.transportRevision;
      await pendingSeek;
      if (!context.mounted ||
          !current() ||
          handler.transportRevision != revision) {
        return;
      }
      await handler.play();
      if (context.mounted && current() && !_scrolling) clear(notify: false);
    } on Object catch (error) {
      if (context.mounted && current()) {
        showMusicNotice(
          context,
          icon: Icons.error_outline_rounded,
          title: '歌词定位未完成',
          message: userFacingErrorMessage(error, fallback: '暂时无法从这句播放，请重试'),
        );
      }
    } finally {
      _seeking = false;
      if (context.mounted) {
        if (!_scrolling) _scheduleResume();
        onChanged();
      }
    }
  }
}

/// Offsets include zero and the total height at the end of the last row.
int lyricLineAtOffset(List<double> offsets, double offset) {
  var first = 0;
  var last = offsets.length - 2;
  while (first < last) {
    final middle = (first + last + 1) ~/ 2;
    if (offsets[middle] <= offset) {
      first = middle;
    } else {
      last = middle - 1;
    }
  }
  return first;
}

class LyricSeekRow extends StatelessWidget {
  const LyricSeekRow({
    required this.time,
    required this.foreground,
    required this.onPlay,
    required this.child,
    this.alignment = Alignment.center,
    super.key,
  });

  final Duration time;
  final Color foreground;
  final VoidCallback? onPlay;
  final Widget child;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final label = formatDuration(time).padLeft(5, '0');
    return Material(
      color: foreground.withValues(alpha: .10),
      borderRadius: BorderRadius.circular(12),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: foreground,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => FittedBox(
                alignment: alignment,
                fit: BoxFit.scaleDown,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                  child: child,
                ),
              ),
            ),
          ),
          SizedBox(
            width: 48,
            child: IconButton(
              tooltip: '从 $label 播放',
              onPressed: onPlay,
              color: foreground,
              icon: const Icon(Icons.play_arrow_rounded),
            ),
          ),
        ],
      ),
    );
  }
}
