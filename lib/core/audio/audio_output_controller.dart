import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

@immutable
class AudioOutputRoute {
  const AudioOutputRoute({
    required this.id,
    required this.name,
    this.headphones = false,
    this.selected = false,
    this.selectable = false,
    this.local = false,
  });
  final String id, name;
  final bool headphones, selected, selectable, local;
  factory AudioOutputRoute.fromMap(Map<Object?, Object?> raw) =>
      AudioOutputRoute(
        id: raw['id'] as String? ?? '',
        name: raw['kind'] == 'phone' ? '本机' : raw['name'] as String? ?? '音频设备',
        local: raw['kind'] == 'phone',
        headphones: raw['kind'] == 'headphones',
        selected: raw['selected'] == true,
        selectable: raw['selectable'] == true,
      );
}

@immutable
class AudioOutput {
  const AudioOutput({
    this.name = '本机扬声器',
    this.headphones = false,
    this.available = false,
    this.id = '',
    this.routes = const [],
    this.local = false,
    this.pendingId = '',
  });
  final String name;
  final String id;
  final String pendingId;
  final List<AudioOutputRoute> routes;
  final bool headphones, available, local;
  static AudioOutput fromMap(Map<Object?, Object?> value) => AudioOutput(
    name: value['kind'] == 'phone'
        ? '本机'
        : (value['name'] as String?)?.trim().isNotEmpty == true
        ? value['name'] as String
        : '本机扬声器',
    headphones: value['kind'] == 'headphones',
    local: value['kind'] == 'phone',
    pendingId: value['pendingId'] as String? ?? '',
    available: value['available'] == true,
    id: value['id'] as String? ?? '',
    routes: (value['routes'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (route) => AudioOutputRoute.fromMap(route.cast<Object?, Object?>()),
        )
        .toList(growable: false),
  );
}

/// One lifecycle-scoped subscription, independent of playback position ticks.
/// Device names are native metadata; never infer an AirPods brand or codec.
class AudioOutputController extends Notifier<AudioOutput>
    with WidgetsBindingObserver {
  static const methods = MethodChannel('com.mesting.music/audio_output');
  static const events = EventChannel('com.mesting.music/audio_output_events');
  StreamSubscription<Object?>? _events;
  bool _disposed = false;
  @override
  AudioOutput build() {
    _disposed = false;
    WidgetsBinding.instance.addObserver(this);
    ref.onDispose(() {
      _disposed = true;
      WidgetsBinding.instance.removeObserver(this);
      _events?.cancel();
    });
    unawaited(Future<void>.microtask(_attach));
    return const AudioOutput();
  }

  void _accept(Object? raw) {
    if (_disposed || raw is! Map) return;
    final next = AudioOutput.fromMap(raw.cast<Object?, Object?>());
    if (state.name != next.name ||
        state.headphones != next.headphones ||
        state.available != next.available ||
        state.id != next.id ||
        state.pendingId != next.pendingId ||
        state.local != next.local ||
        _routeSignature(state) != _routeSignature(next)) {
      state = next;
    }
  }

  String _routeSignature(AudioOutput value) => value.routes
      .map(
        (route) =>
            '${route.id}:${route.name}:${route.headphones}:${route.local}:${route.selected}:${route.selectable}',
      )
      .join('|');

  /// Native exposes connected media sinks and the app player's real route.
  /// An accepted paused preference is distinct from a confirmed active output.
  Future<void> refreshRoutes() async {
    _accept(await methods.invokeMapMethod<Object?, Object?>('routes'));
  }

  Future<bool> transfer(String routeId) async {
    if (!state.routes.any((route) => route.id == routeId && route.selectable)) {
      return false;
    }
    final confirmed = await methods.invokeMethod<bool>('transfer', {
      'id': routeId,
    });
    await refresh();
    return confirmed == true &&
        (state.id == routeId || state.pendingId == routeId);
  }

  Future<void> refresh() async {
    try {
      _accept(await methods.invokeMapMethod<Object?, Object?>('current'));
    } on MissingPluginException {
      /* Host rendering has no Android route service. */
    } on PlatformException {
      /* A later foreground refresh can recover. */
    }
  }

  Future<void> _attach() async {
    await refresh();
    if (_disposed || !state.available || _events != null) return;
    _events = events.receiveBroadcastStream().listen(
      _accept,
      onError: (Object _) {},
    );
  }

  Future<void> choose() async {
    if (!state.available) return;
    await methods.invokeMethod<bool>('choose');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_attach());
  }
}

final audioOutputProvider =
    NotifierProvider<AudioOutputController, AudioOutput>(
      AudioOutputController.new,
    );
