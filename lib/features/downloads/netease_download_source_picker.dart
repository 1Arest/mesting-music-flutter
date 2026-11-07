import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/widgets/beta_glass_controls.dart';
import '../../shared/widgets/liquid_glass_sheet.dart';
import '../music_platform/domain/platform_audio_quality.dart';
import '../music_platform/music_platform_providers.dart';
import '../music_platform/netease/netease_fallback.dart';
import '../music_platform/netease/netease_track_sources.dart';
import 'audio_downloads.dart';

typedef DownloadSourceAvailability =
    Future<bool> Function(
      AudioDownloadTask task,
      NeteaseTrackSource source,
      bool Function() current,
      Future<void> abort,
    );

final downloadSourceAvailabilityProvider = Provider<DownloadSourceAvailability>(
  (ref) => (task, source, current, abort) async {
    if (task.requestedQuality?.neteaseOnly == true) return false;
    final media = await ref
        .read(neteaseFallbackResolverProvider)
        .resolve(
          task.track.copyWith(
            playbackQuality:
                (task.requestedQuality ?? PlatformAudioQuality.high).code,
          ),
          current: current,
          onlySource: source.adapter,
          requiredQuality: task.requestedQuality?.code,
          abortTrigger: abort,
        );
    return media != null && media.isPlayable && !media.isPreview;
  },
);

Future<NeteaseTrackSource?> chooseNeteaseDownloadSource(
  BuildContext context,
  AudioDownloadTask task,
) => showLiquidGlassBottomSheet<NeteaseTrackSource>(
  context: context,
  useRootNavigator: true,
  useSafeArea: true,
  isScrollControlled: true,
  builder: (_) => NeteaseDownloadSourcePicker(task: task),
);

/// Availability is recording + requested-quality specific. A source responding
/// to a homepage probe is never enough to enable its download button.
class NeteaseDownloadSourcePicker extends ConsumerStatefulWidget {
  const NeteaseDownloadSourcePicker({required this.task, super.key});
  final AudioDownloadTask task;
  @override
  ConsumerState<NeteaseDownloadSourcePicker> createState() =>
      _DownloadSourcePickerState();
}

class _DownloadSourcePickerState
    extends ConsumerState<NeteaseDownloadSourcePicker> {
  final _results = <NeteaseTrackSource, bool>{};
  final _abort = Completer<void>();
  final _sources = NeteaseTrackSource.values
      .where((s) => s.adapter != null)
      .toList();
  String? _token;
  int _generation = 0;
  bool get _current =>
      mounted &&
      !_abort.isCompleted &&
      ref.read(platformAccountProvider).value?.ownerId == widget.task.owner &&
      ref.read(platformAccountProvider).value?.token == _token &&
      ref.read(audioDownloadManagerProvider).taskById(widget.task.id)?.phase ==
          AudioDownloadPhase.awaitingSource;

  @override
  void initState() {
    super.initState();
    _token = ref.read(platformAccountProvider).value?.token;
    Future.microtask(_detect);
  }

  @override
  void dispose() {
    if (!_abort.isCompleted) _abort.complete();
    super.dispose();
  }

  Future<void> _detect() async {
    final generation = ++_generation;
    if (!_current) return;
    setState(_results.clear);
    var cursor = 0;
    Future<void> worker() async {
      while (_current &&
          generation == _generation &&
          cursor < _sources.length) {
        final source = _sources[cursor++];
        var available = false;
        try {
          available = await ref.read(downloadSourceAvailabilityProvider)(
            widget.task,
            source,
            () => _current && generation == _generation,
            _abort.future,
          );
        } catch (_) {
          /* Retry remains explicit. */
        }
        if (_current && generation == _generation) {
          setState(() => _results[source] = available);
        }
      }
    }

    await Future.wait([worker(), worker()]);
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(platformAccountProvider);
    final active = _current;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .8,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('选择下载音源', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              widget.task.track.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Text(
              active
                  ? '${widget.task.downloadSource?.label ?? '官方'}暂不可下载${widget.task.requestedQuality == null ? '' : ' · ${widget.task.requestedQuality!.neteaseLabel}'}'
                  : '账号或下载任务已变化，请关闭后重新操作。',
            ),
            if (active) ...[
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      for (final source in _sources)
                        ListTile(
                          key: ValueKey('download-source-${source.name}'),
                          contentPadding: EdgeInsets.zero,
                          title: Text(source.label),
                          enabled: _results[source] == true,
                          subtitle: Text(
                            !_results.containsKey(source)
                                ? '正在检测完整下载音频…'
                                : _results[source] == true
                                ? '可下载 · ${widget.task.requestedQuality?.neteaseLabel ?? '实际音质以文件为准'}'
                                : '暂不可下载或不支持所选音质',
                          ),
                          trailing: !_results.containsKey(source)
                              ? const BetaActivityIndicator(radius: 8)
                              : _results[source] == true
                              ? const Icon(Icons.download_rounded)
                              : null,
                          onTap: _results[source] == true
                              ? () => Navigator.pop(context, source)
                              : null,
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              BetaGlassButton(
                onPressed: _results.length == _sources.length ? _detect : null,
                child: const Text('重新检测'),
              ),
            ],
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('稍后选择'),
            ),
          ],
        ),
      ),
    );
  }
}
