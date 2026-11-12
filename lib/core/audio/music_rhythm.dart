import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/widgets/beta_music_chrome_scope.dart';
import '../../shared/widgets/beta_root_tab_viewport.dart';
import 'playback_providers.dart';

/// PCM loudness and frequency bands for the audio sink's current position.
@immutable
class MusicRhythmFrame {
  const MusicRhythmFrame({
    this.level = 0,
    this.peak = 0,
    this.bands = const [],
    this.pulse = 0,
    this.onset = 0,
    this.frameId = 0,
    this.available = false,
  });
  static const bandCount = 12;
  final double level, peak, pulse;
  final List<double> bands;
  final int frameId, onset;
  final bool available;

  double get bass => bands.take(3).fold(0.0, math.max);

  double bandAt(double fraction) {
    if (bands.isEmpty) return 0;
    final position = fraction.clamp(0.0, 1.0) * (bands.length - 1);
    final left = position.floor();
    final right = position.ceil();
    return bands[left] + (bands[right] - bands[left]) * (position - left);
  }

  factory MusicRhythmFrame.parse(Map<String, Object?> data) {
    double level(Object? value) {
      final v = value is num ? value.toDouble() : 0.0;
      if (!v.isFinite || v <= .0001) return 0;
      // A decibel scale keeps quiet passages visible without flattening a beat.
      return ((20 * math.log(v.clamp(.0001, 1)) / math.ln10 + 54) / 48).clamp(
        0.0,
        1.0,
      );
    }

    if (data['available'] != true) return const MusicRhythmFrame();
    final rawBands = data['bands'];
    return MusicRhythmFrame(
      level: level(data['rms']),
      peak: level(data['peak']),
      bands: rawBands is List
          ? List<double>.unmodifiable(rawBands.take(bandCount).map(level))
          : const [],
      frameId: (data['frameId'] as num?)?.toInt() ?? 0,
      available: true,
    );
  }
}

typedef RhythmRead = Future<Map<String, Object?>> Function(bool enabled);

/// Visible surfaces lease one shared, bounded sampler. Native calls are serial;
/// disposing a lease cannot race an older read into re-enabling capture.
class MusicRhythmSampler extends ValueNotifier<MusicRhythmFrame> {
  MusicRhythmSampler(this.read) : super(const MusicRhythmFrame());
  final RhythmRead read;
  final _owners = <Object>{};
  Timer? _timer;
  Future<void> _tail = Future.value();
  bool _closed = false;
  int _leaseEpoch = 0;
  int _onset = 0;
  MusicRhythmFrame _raw = const MusicRhythmFrame();
  final _clock = Stopwatch()..start();
  int _lastOnsetMs = -1000;
  void lease(Object owner, bool enabled) {
    if (_closed) return;
    enabled ? _owners.add(owner) : _owners.remove(owner);
    if (_owners.isNotEmpty && _timer == null) {
      _timer = Timer.periodic(const Duration(milliseconds: 50), (_) => _poll());
      _poll();
    } else if (_owners.isEmpty && _timer != null) {
      _timer?.cancel();
      _timer = null;
      _leaseEpoch++;
      _raw = const MusicRhythmFrame();
      value = const MusicRhythmFrame();
      _tail = _tail
          .then((_) async {
            if (_owners.isEmpty) await read(false);
          })
          .catchError((Object _) {});
    }
  }

  bool _busy = false;
  void _poll() {
    if (_busy || _closed || _owners.isEmpty) return;
    _busy = true;
    final epoch = _leaseEpoch;
    _tail = _tail
        .then((_) async {
          if (_closed || _owners.isEmpty) return;
          final frame = MusicRhythmFrame.parse(await read(true));
          if (!_closed && _owners.isNotEmpty && epoch == _leaseEpoch) {
            _publish(frame);
          }
        })
        .catchError((Object _) {
          if (!_closed) value = const MusicRhythmFrame();
        })
        .whenComplete(() => _busy = false);
  }

  void _publish(MusicRhythmFrame frame) {
    if (!frame.available) {
      _raw = const MusicRhythmFrame();
      value = frame;
      return;
    }
    double follow(double before, double after) =>
        before + (after - before) * (after > before ? .84 : .42);

    // Notes are emitted only on a new measured rise. Holding the last sample
    // across two polls cannot generate a second note or keep a pulse alive.
    final now = _clock.elapsedMilliseconds;
    final newFrame = frame.frameId != 0 && frame.frameId != _raw.frameId;
    final rise = math.max(frame.level - _raw.level, frame.bass - _raw.bass);
    var pulse = value.pulse * .48;
    if (newFrame &&
        rise > .085 &&
        frame.level > .14 &&
        now - _lastOnsetMs >= 190) {
      _lastOnsetMs = now;
      _onset++;
      pulse = (rise * 3.8).clamp(0.0, 1.0);
    }
    _raw = frame;
    value = MusicRhythmFrame(
      level: follow(value.level, frame.level),
      peak: follow(value.peak, frame.peak),
      bands: List<double>.unmodifiable([
        for (var i = 0; i < frame.bands.length; i++)
          follow(i < value.bands.length ? value.bands[i] : 0, frame.bands[i]),
      ]),
      pulse: pulse,
      onset: _onset,
      frameId: frame.frameId,
      available: true,
    );
  }

  @override
  void dispose() {
    _closed = true;
    _owners.clear();
    _timer?.cancel();
    unawaited(
      _tail
          .then((_) => read(false))
          .catchError((Object _) => <String, Object?>{}),
    );
    super.dispose();
  }
}

final musicRhythmSamplerProvider = Provider<MusicRhythmSampler>((ref) {
  final meter = MusicRhythmSampler(
    ref.watch(audioHandlerProvider).musicRhythmFrame,
  );
  ref.onDispose(meter.dispose);
  return meter;
});

/// All real-time artwork shares the same lifecycle policy. Offscreen profile
/// headers can additionally revoke their lease without rebuilding the list.
class MusicRhythmSurface extends ConsumerStatefulWidget {
  const MusicRhythmSurface({
    required this.builder,
    this.enabled = true,
    this.respectChrome = true,
    super.key,
  });
  final bool enabled, respectChrome;
  final Widget Function(BuildContext, MusicRhythmFrame) builder;
  @override
  ConsumerState<MusicRhythmSurface> createState() => _MusicRhythmSurfaceState();
}

class _MusicRhythmSurfaceState extends ConsumerState<MusicRhythmSurface>
    with WidgetsBindingObserver {
  MusicRhythmSampler? _meter;
  BetaMusicChromeController? _chrome;
  bool _foreground = true;
  ScrollPosition? _scroll;
  bool _visibilityPending = false;
  bool _inViewport = true;
  bool _active = false, _building = false, _rebuildPending = false;
  @override
  void initState() {
    super.initState();
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final chrome = BetaMusicChromeScope.maybeOf(context);
    if (_chrome != chrome) {
      _chrome?.removeListener(_sync);
      _chrome = chrome;
      _chrome?.addListener(_sync);
    }
    final position = Scrollable.maybeOf(context)?.position;
    if (_scroll != position) {
      _scroll?.removeListener(_queueVisibility);
      _scroll = position;
      _scroll?.addListener(_queueVisibility);
    }
    _queueVisibility();
    _sync();
  }

  void _queueVisibility() {
    if (_visibilityPending) return;
    _visibilityPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _visibilityPending = false;
      if (!mounted) return;
      final box = context.findRenderObject();
      if (box is RenderBox && box.hasSize && box.attached) {
        final offset = box.localToGlobal(Offset.zero);
        _inViewport =
            offset.dy + box.size.height > 0 &&
            offset.dy < MediaQuery.sizeOf(context).height;
      }
      _sync();
    });
  }

  @override
  void didUpdateWidget(covariant MusicRhythmSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _sync();
  }

  void _sync() {
    if (!mounted) return;
    final active =
        widget.enabled &&
        _inViewport &&
        _foreground &&
        shouldAnimateVinyl(ref.read(playbackStateProvider).value) &&
        (!widget.respectChrome || _chrome?.covered != true) &&
        BetaTabVisibility.of(context) &&
        (ModalRoute.isCurrentOf(context) ?? true) &&
        TickerMode.valuesOf(context).enabled &&
        !MediaQuery.disableAnimationsOf(context);
    if (active) _meter ??= ref.read(musicRhythmSamplerProvider);
    final changed = active != _active;
    _active = active;
    _meter?.lease(this, active);
    if (changed && !_building) {
      // Chrome/route notifications may arrive while an ancestor is building.
      // Update the lease now, and defer only the surface rebuild in that case.
      if (SchedulerBinding.instance.schedulerPhase ==
          SchedulerPhase.persistentCallbacks) {
        if (!_rebuildPending) {
          _rebuildPending = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _rebuildPending = false;
            if (mounted) setState(() {});
          });
        }
      } else {
        setState(() {});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.enabled) ref.listen(playbackStateProvider, (_, _) => _sync());
    if (widget.enabled) _meter ??= ref.read(musicRhythmSamplerProvider);
    _building = true;
    _sync();
    _building = false;
    // Hidden retained tabs must also detach the repaint listener while another
    // visible avatar owns the shared meter. Revoking capture alone is not enough.
    return !_active || _meter == null
        ? widget.builder(context, const MusicRhythmFrame())
        : ValueListenableBuilder<MusicRhythmFrame>(
            valueListenable: _meter!,
            builder: (c, frame, _) => widget.builder(c, frame),
          );
  }

  @override
  void dispose() {
    _scroll?.removeListener(_queueVisibility);
    WidgetsBinding.instance.removeObserver(this);
    _chrome?.removeListener(_sync);
    _meter?.lease(this, false);
    super.dispose();
  }
}
