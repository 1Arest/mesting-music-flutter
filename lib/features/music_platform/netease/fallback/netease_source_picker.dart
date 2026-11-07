import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/audio/playback_providers.dart';
import '../../../../shared/models/track.dart';
import '../../../../shared/widgets/beta_glass_controls.dart';
import '../../../../shared/widgets/liquid_glass_sheet.dart';
import '../../platform_backend_providers.dart';
import '../../platform_quality_providers.dart';
import '../../presentation/platform_feedback.dart';
import '../../../player/presentation/beta_playback_actions.dart';
import '../netease_fallback.dart';
import '../netease_track_sources.dart';
import '../../retained_kugou_scope.dart';

typedef NeteaseSourceAvailability =
    Future<bool> Function(
      Track track,
      NeteaseTrackSource source,
      bool Function() current,
      Future<void> abort,
    );

/// Detection is a transport concern, separate from sheet state and selection.
/// It uses the same full-recording validation as actual playback.
final neteaseSourceAvailabilityProvider = Provider<NeteaseSourceAvailability>(
  (ref) => (track, source, current, abort) async {
    final song = await resolveNeteaseTrack(
      music: ref.read(neteaseMusicRepositoryProvider),
      fallback: ref.read(neteaseFallbackResolverProvider),
      allowFallback: true,
      current: current,
      track: track,
      quality: ref.read(platformQualityProvider).preferred,
      selectedSource: source,
      // A successful automatic rescue is not proof that this source works.
      fallbackOnSelectedFailure: false,
      abortTrigger: abort,
    );
    return song.isPlayable && !song.isPreview;
  },
);

Future<void> showNeteaseTrackSources(
  BuildContext context,
  WidgetRef ref,
  Track track,
) async {
  final owner = ref.read(neteaseMusicRepositoryProvider).credential;
  final kugou = ref.read(retainedKugouScopeProvider);
  final previous =
      ref.read(neteaseTrackSourcesProvider)[track.id] ??
      NeteaseTrackSource.automatic;
  final choice = await showLiquidGlassBottomSheet<NeteaseTrackSource>(
    context: context,
    useRootNavigator: true,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (_) => NeteaseSourcePicker(track),
  );
  if (!context.mounted ||
      choice == null ||
      !identical(ref.read(retainedKugouScopeProvider), kugou) ||
      ref.read(neteaseMusicRepositoryProvider).credential != owner) {
    return;
  }
  ref.read(neteaseTrackSourcesProvider.notifier).select(track.id, choice);
  try {
    if (ref.read(currentTrackProvider).id == track.id) {
      await ref.read(audioHandlerProvider).refreshCurrentSource();
    } else {
      await playBetaSelection(context, ref, track);
    }
  } catch (error) {
    if (!context.mounted) return;
    if (ref.read(neteaseMusicRepositoryProvider).credential == owner) {
      ref.read(neteaseTrackSourcesProvider.notifier).select(track.id, previous);
    }
    if (context.mounted) showPlatformFailure(context, error);
  }
}

class NeteaseSourcePicker extends ConsumerStatefulWidget {
  const NeteaseSourcePicker(this.track, {super.key});
  final Track track;
  @override
  ConsumerState<NeteaseSourcePicker> createState() =>
      _NeteaseSourcePickerState();
}

class _NeteaseSourcePickerState extends ConsumerState<NeteaseSourcePicker> {
  final _results = <NeteaseTrackSource, bool>{
    NeteaseTrackSource.automatic: true,
  };
  final _abort = Completer<void>();
  int _revision = 0;
  late final String? _credential;
  late final RetainedKugouScope? _kugou;
  bool get _current =>
      mounted &&
      !_abort.isCompleted &&
      identical(ref.read(retainedKugouScopeProvider), _kugou) &&
      ref.read(neteaseMusicRepositoryProvider).credential == _credential;
  @override
  void initState() {
    super.initState();
    _credential = ref.read(neteaseMusicRepositoryProvider).credential;
    _kugou = ref.read(retainedKugouScopeProvider);
    Future.microtask(_detect);
  }

  @override
  void dispose() {
    if (!_abort.isCompleted) _abort.complete();
    super.dispose();
  }

  Future<void> _detect() async {
    final revision = ++_revision;
    setState(() {
      _results.clear();
      _results[NeteaseTrackSource.automatic] = true;
    });
    var cursor = 0;
    final choices = NeteaseTrackSource.values.skip(1).toList();
    Future<void> worker() async {
      while (_current && revision == _revision && cursor < choices.length) {
        final source = choices[cursor++];
        var available = false;
        try {
          available = await ref.read(neteaseSourceAvailabilityProvider)(
            widget.track,
            source,
            () => _current && revision == _revision,
            _abort.future,
          );
        } catch (_) {
          /* Transient errors remain retryable, never advertised as supported. */
        }
        if (_current && revision == _revision) {
          setState(() => _results[source] = available);
        }
      }
    }

    await Future.wait([worker(), worker()]);
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(neteaseMusicRepositoryProvider);
    ref.watch(retainedKugouScopeProvider);
    if (!_current) {
      return const Padding(
        padding: EdgeInsets.all(28),
        child: Text('账号已变化，请关闭后重新打开音乐来源'),
      );
    }
    final selected =
        ref.watch(neteaseTrackSourcesProvider)[widget.track.id] ??
        NeteaseTrackSource.automatic;
    final scheme = Theme.of(context).colorScheme;
    final detecting = _results.length < NeteaseTrackSource.values.length;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .8,
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 18, 12, 30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text(
                  '选择音乐来源',
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  widget.track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              for (final source in NeteaseTrackSource.values)
                ListTile(
                  key: ValueKey('song-source-${source.name}'),
                  enabled: _current && _results[source] == true,
                  title: Text(
                    source.label,
                    style: TextStyle(
                      color: _results[source] == true
                          ? scheme.onSurface
                          : scheme.onSurfaceVariant.withValues(alpha: .55),
                    ),
                  ),
                  subtitle: Text(
                    source == NeteaseTrackSource.automatic
                        ? '保留自动补源'
                        : !_results.containsKey(source)
                        ? '正在检测完整音频…'
                        : _results[source] == true
                        ? '可用 · 同一录音完整音频'
                        : '暂不可用或未找到同一录音，可重新检测',
                  ),
                  trailing: !_results.containsKey(source)
                      ? const BetaActivityIndicator(radius: 8)
                      : selected == source
                      ? const Icon(CupertinoIcons.check_mark, size: 18)
                      : null,
                  onTap: _current && _results[source] == true
                      ? () => Navigator.pop(context, source)
                      : null,
                ),
              const SizedBox(height: 12),
              BetaGlassButton(
                onPressed: detecting ? null : _detect,
                loading: detecting,
                child: const Text('重新检测'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
