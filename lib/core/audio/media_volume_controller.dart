import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

@immutable
class MediaVolumeState {
  const MediaVolumeState({this.value = .5, this.available = false});
  final double value;
  final bool available;
}

/// Controls Android STREAM_MUSIC, never a second AudioPlayer's gain. Native
/// volume events include hardware-key changes; foreground refresh covers events
/// missed while the activity was suspended. Unsupported hosts stay disabled.
class MediaVolumeController extends Notifier<MediaVolumeState>
    with WidgetsBindingObserver {
  static const methods = MethodChannel('com.mesting.music/media_volume');
  static const events = EventChannel('com.mesting.music/media_volume_events');
  StreamSubscription<Object?>? _subscription;
  bool _disposed = false;
  Future<void>? _write;
  double? _pendingVolume;

  @override
  MediaVolumeState build() {
    _disposed = false;
    WidgetsBinding.instance.addObserver(this);
    ref.onDispose(() {
      _disposed = true;
      _pendingVolume = null;
      WidgetsBinding.instance.removeObserver(this);
      _subscription?.cancel();
    });
    unawaited(Future<void>.microtask(_attach));
    return const MediaVolumeState();
  }

  Future<void> _attach() async {
    // Probe the method channel before opening events. EventChannel reports a
    // missing host plugin globally even with an onError stream listener.
    try {
      final value = await methods.invokeMethod<double>('getVolume');
      if (_disposed || value == null) return;
      _accept(value);
      _subscription = events.receiveBroadcastStream().listen(
        _accept,
        onError: (Object _) {},
      );
    } on MissingPluginException {
      // Unsupported desktop/test hosts keep a truthful disabled volume rail.
    } on PlatformException {
      // Foreground refresh can recover a temporarily unavailable audio service.
    }
  }

  void _accept(Object? value) {
    if (!_disposed && value is num) {
      final normalized = value.toDouble().clamp(0, 1).toDouble();
      if (state.available && (state.value - normalized).abs() < .00001) return;
      state = MediaVolumeState(value: normalized, available: true);
    }
  }

  Future<void> refresh() async {
    try {
      _accept(await methods.invokeMethod<double>('getVolume'));
    } on MissingPluginException {
      // Widget tests and desktop builds have no Android system-volume bridge.
    } on PlatformException {
      // A transient system service failure must not interrupt playback.
    }
  }

  Future<void> setVolume(double value) {
    if (_disposed || !state.available) return Future.value();
    _pendingVolume = value.clamp(0, 1);
    // One in-flight native write, with the newest drag sample retained. This
    // prevents out-of-order responses and bounds platform work without adding
    // delay to the slider's local, every-frame visual feedback.
    return _write ??= _flushVolume().whenComplete(() => _write = null);
  }

  Future<void> _flushVolume() async {
    while (!_disposed && _pendingVolume != null) {
      final requested = _pendingVolume!;
      _pendingVolume = null;
      try {
        final actual = await methods.invokeMethod<double>('setVolume', {
          'value': requested,
        });
        if (_pendingVolume == null) _accept(actual);
      } on PlatformException {
        if (_pendingVolume == null) await refresh();
      } on MissingPluginException {
        _pendingVolume = null;
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(refresh());
  }
}

final mediaVolumeProvider =
    NotifierProvider<MediaVolumeController, MediaVolumeState>(
      MediaVolumeController.new,
    );
