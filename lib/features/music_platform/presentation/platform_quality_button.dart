import '../../../shared/widgets/beta_glass_popover.dart';
import '../../../shared/widgets/beta_content_reveal.dart';
import 'package:flutter/cupertino.dart';
import '../../../core/haptics/app_haptics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/audio/playback_providers.dart';
import '../../../shared/models/track.dart';
import '../../../shared/widgets/music_notice.dart';
import '../../themes/beta_appearance.dart';
import '../domain/platform_audio_quality.dart';
import '../platform_quality_providers.dart';
import 'platform_feedback.dart';
import '../data/playback_quality_catalog.dart';
import '../../themes/music_typography.dart';

class _QualitySelection {
  const _QualitySelection(this.trackId, this.tier, this.catalog);
  final String trackId;
  final PlatformAudioQuality tier;
  final VerifiedPlaybackQualities catalog;
}

/// A retry must refresh resource metadata as well as the verified stream list;
/// otherwise rebuilding the outer provider can reuse its dependency's error.
void _reloadQualities(WidgetRef ref, Track track) {
  ref.invalidate(platformSongQualitiesProvider(track.id));
  ref.invalidate(platformPlaybackQualitiesProvider(track));
}

/// The live dialog follows song changes. A returned selection is bound to its
/// recording, so closing it cannot accidentally change a newly playing song.
Future<void> showPlatformQualityPicker(
  BuildContext context,
  WidgetRef ref,
) async {
  final selected = await showBetaGlassDialog<_QualitySelection>(
    context: context,
    builder: (_) => const _QualityDialog(),
  );
  if (selected == null ||
      !context.mounted ||
      ref.read(currentTrackProvider).id != selected.trackId) {
    return;
  }
  try {
    final applied = await ref
        .read(platformQualityProvider.notifier)
        .select(selected.tier, catalog: selected.catalog);
    if (!context.mounted) return;
    final handler = ref.read(audioHandlerProvider);
    final updated = handler.trackForId(handler.mediaItem.value?.id ?? '');
    if (updated == null) return;
    final actual = PlatformAudioQuality.fromCode(updated.playbackQuality);
    showMusicNotice(
      context,
      icon: CupertinoIcons.waveform,
      title: !applied
          ? '本次切换已取消，请重试'
          : updated.isPreview
          ? '平台当前提供试听片段'
          : actual == null
          ? '已切换音源，音质待平台确认'
          : '已切换为${playbackAudioOrigin(updated)?.isNetease == true ? actual.neteaseLabel : actual.label}',
      message: '',
    );
  } catch (error) {
    if (context.mounted) showPlatformFailure(context, error);
  }
}

class _QualityDialog extends ConsumerWidget {
  const _QualityDialog();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = ref.watch(currentTrackProvider);
    final switching = ref.watch(
      platformQualityProvider.select((s) => s.switching),
    );
    final supported =
        !track.hasLocalAudio &&
        ((track.source == TrackSource.kugou && track.id.startsWith('kugou_')) ||
            (track.source == TrackSource.netease &&
                track.id.startsWith('netease_')));
    final actual = PlatformAudioQuality.fromCode(track.playbackQuality);
    final origin = playbackAudioOrigin(track);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ink = dark ? Colors.white : const Color(0xFF202024);
    final accent = BetaAppearance.accent(Theme.of(context).brightness);
    final qualities = supported
        ? ref.watch(platformPlaybackQualitiesProvider(track))
        : null;
    return Dialog(
      key: const ValueKey('apple-quality-picker'),
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: BetaGlassMenuSurface(
          radius: 30,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '音质选择',
                  style: TextStyle(
                    color: ink,
                    fontSize: MusicTypography.sectionTitleSize,
                    fontWeight: MusicTypography.titleWeight,
                  ),
                ),
                const SizedBox(height: 18),
                if (origin != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      '${origin.adapter} · 仅显示当前歌曲与账号已确认可用的音质',
                      style: TextStyle(
                        color: ink,
                        fontSize: MusicTypography.captionSize,
                      ),
                    ),
                  ),
                if (qualities != null)
                  AnimatedSize(
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 280),
                    alignment: Alignment.topCenter,
                    child: qualities.when(
                      loading: () => const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CupertinoActivityIndicator()),
                      ),
                      error: (_, _) => Column(
                        children: [
                          Text('暂未获取到歌曲音质信息', style: TextStyle(color: ink)),
                          TextButton(
                            onPressed: () => _reloadQualities(ref, track),
                            child: const Text('重新加载'),
                          ),
                        ],
                      ),
                      data: (available) => BetaContentReveal(
                        key: ValueKey('quality-catalog-${track.id}'),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final quality
                                in (origin?.isNetease == true
                                        ? PlatformAudioQuality.neteaseOrder
                                        : PlatformAudioQuality.values.where(
                                            (q) => !q.neteaseOnly,
                                          ))
                                    .where(available.values.containsKey))
                              Padding(
                                padding: const EdgeInsets.only(bottom: 5),
                                child: Material(
                                  color: actual == quality
                                      ? accent.withValues(alpha: .18)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(17),
                                  clipBehavior: Clip.antiAlias,
                                  child: ListTile(
                                    key: ValueKey(
                                      'quality-option-${quality.code}',
                                    ),
                                    minVerticalPadding: 10,
                                    title: Text(
                                      origin?.isNetease == true
                                          ? quality.neteaseLabel
                                          : quality.label,
                                      style: TextStyle(
                                        color: actual == quality ? accent : ink,
                                        fontSize: MusicTypography.bodySize,
                                        fontWeight: actual == quality
                                            ? MusicTypography.titleWeight
                                            : MusicTypography.bodyWeight,
                                      ),
                                    ),
                                    trailing: actual == quality
                                        ? Icon(
                                            CupertinoIcons.check_mark,
                                            color: accent,
                                            size: 20,
                                          )
                                        : null,
                                    onTap: switching
                                        ? null
                                        : () => Navigator.pop(
                                            context,
                                            _QualitySelection(
                                              track.id,
                                              quality,
                                              available,
                                            ),
                                          ),
                                  ),
                                ),
                              ),
                            if (available.values.isEmpty)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                child: Text(
                                  '当前音源暂无已确认可切换的档位',
                                  style: TextStyle(color: ink),
                                ),
                              ),
                            TextButton(
                              onPressed: switching
                                  ? null
                                  : () => _reloadQualities(ref, track),
                              child: const Text('重新检测可用音质'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (!supported) ...[
                  const SizedBox(height: 12),
                  Text(
                    '当前音源不支持在线音质切换',
                    style: TextStyle(
                      color: ink.withValues(alpha: .65),
                      fontSize: MusicTypography.captionSize,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class PlatformQualityButton extends ConsumerWidget {
  const PlatformQualityButton({this.inline = false, super.key});
  final bool inline;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = ref.watch(currentTrackProvider);
    final state = ref.watch(platformQualityProvider);
    final actual = PlatformAudioQuality.fromCode(track.playbackQuality);
    final label = state.switching
        ? '切换中'
        : track.isPreview
        ? '试听'
        : (playbackAudioOrigin(track)?.isNetease == true
                  ? actual?.neteaseLabel
                  : actual?.label) ??
              '音质';
    return CupertinoButton(
      key: const ValueKey('player-quality-button'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      minimumSize: const Size(64, 48),
      onPressed: state.switching
          ? null
          : () {
              appHaptic(context, AppHapticEvent.selection);
              showPlatformQualityPicker(context, ref);
            },
      child: inline
          ? Semantics(
              label: '音质，$label',
              child: const Icon(
                CupertinoIcons.hifispeaker_fill,
                size: 25,
                color: Colors.white70,
              ),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  CupertinoIcons.music_note,
                  size: 18,
                  color: Colors.white,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: MusicTypography.subheadlineSize,
                  ),
                ),
              ],
            ),
    );
  }
}
