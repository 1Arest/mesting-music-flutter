import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/audio/playback_providers.dart';
import '../../../shared/utils/duration_format.dart';
import '../music_platform_providers.dart';
import '../presentation/platform_feedback.dart';

/// Cover and lyrics share the existing player's real media timeline. Catalog
/// duration is deliberately not a fallback: an official preview can be much
/// shorter, and dragging must never promise unavailable full-track positions.
class QishuiPlaybackProgress extends ConsumerStatefulWidget {
  const QishuiPlaybackProgress({super.key});

  @override
  ConsumerState<QishuiPlaybackProgress> createState() =>
      _QishuiPlaybackProgressState();
}

class _QishuiPlaybackProgressState
    extends ConsumerState<QishuiPlaybackProgress> {
  double? _scrub;
  String? _trackIdentity;
  String? _scrubIdentity;
  (String?, String?)? _accountIdentity;
  (String?, String?)? _scrubAccount;
  Duration _duration = Duration.zero;
  int _intent = 0;

  String _identity() {
    final track = ref.read(currentTrackProvider);
    return '${track.source.name}:${track.id}:${track.platformSongId}';
  }

  Future<void> _seek(double milliseconds) async {
    final identity = _scrubIdentity;
    if (identity == null || identity != _identity()) return;
    final owner = ref.read(platformAccountProvider).value;
    final account = (owner?.ownerId, owner?.token);
    if (account != _scrubAccount) return;
    final intent = ++_intent;
    final maximum = _duration.inMilliseconds.toDouble();
    if (maximum <= 0) return;
    final target = milliseconds.clamp(0.0, maximum);
    bool current() =>
        mounted &&
        intent == _intent &&
        identity == _identity() &&
        ref.read(platformAccountProvider).value?.ownerId == owner?.ownerId &&
        ref.read(platformAccountProvider).value?.token == owner?.token;
    setState(() => _scrub = target);
    try {
      await ref
          .read(audioHandlerProvider)
          .seek(Duration(milliseconds: target.round()), togetherGuard: current);
    } on Object catch (error) {
      if (!mounted || !current()) return;
      showPlatformFailure(context, error);
    } finally {
      if (mounted && intent == _intent) {
        setState(() {
          _scrub = null;
          _scrubIdentity = null;
          _scrubAccount = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final track = ref.watch(currentTrackProvider);
    final identity = '${track.source.name}:${track.id}:${track.platformSongId}';
    final account = ref.watch(
      platformAccountProvider.select((v) => (v.value?.ownerId, v.value?.token)),
    );
    final duration = ref.watch(durationProvider).value ?? Duration.zero;
    final position = ref.watch(positionProvider).value ?? Duration.zero;
    final processing = ref.watch(
      playbackStateProvider.select((v) => v.value?.processingState),
    );
    // A changed song or media length invalidates an in-flight drag/seek. This
    // also covers replacing a short preview with newly resolved full media.
    if (_trackIdentity != identity ||
        _duration != duration ||
        _accountIdentity != account) {
      _trackIdentity = identity;
      _duration = duration;
      _accountIdentity = account;
      _scrub = null;
      _scrubIdentity = null;
      _scrubAccount = null;
      ++_intent;
    }
    final canSeek =
        duration > Duration.zero &&
        processing != AudioProcessingState.loading &&
        processing != AudioProcessingState.error;
    final maximum = duration.inMilliseconds > 0
        ? duration.inMilliseconds.toDouble()
        : 1.0;
    final value = (_scrub ?? position.inMilliseconds.toDouble()).clamp(
      0.0,
      duration > Duration.zero ? maximum : 0.0,
    );
    final foreground = Theme.of(context).colorScheme.onSurface;
    final labelStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Column(
      key: const ValueKey('qishui-playback-progress'),
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 44,
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              activeTrackColor: foreground,
              inactiveTrackColor: foreground.withValues(alpha: .2),
              thumbColor: foreground,
              thumbShape: RoundSliderThumbShape(
                enabledThumbRadius: _scrub == null ? 4 : 6,
              ),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
              padding: EdgeInsets.zero,
            ),
            child: Semantics(
              label: '播放进度',
              child: Slider(
                key: const ValueKey('qishui-playback-slider'),
                value: value,
                max: maximum,
                semanticFormatterCallback: (next) =>
                    formatDuration(Duration(milliseconds: next.round())),
                onChangeStart: canSeek
                    ? (next) => setState(() {
                        ++_intent;
                        _scrubIdentity = identity;
                        _scrubAccount = account;
                        _scrub = next;
                      })
                    : null,
                onChanged: canSeek
                    ? (next) {
                        if (_scrubIdentity != identity) return;
                        setState(() => _scrub = next.clamp(0.0, maximum));
                      }
                    : null,
                onChangeEnd: canSeek ? _seek : null,
              ),
            ),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              formatDuration(Duration(milliseconds: value.round())),
              key: const ValueKey('qishui-playback-elapsed'),
              style: labelStyle,
            ),
            Text(
              duration > Duration.zero ? formatDuration(duration) : '--:--',
              key: const ValueKey('qishui-playback-duration'),
              style: labelStyle,
            ),
          ],
        ),
      ],
    );
  }
}
