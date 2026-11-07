import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../audio/playback_providers.dart';
import '../audio/mesting_audio_handler.dart';
import '../persistence/app_preferences.dart';

class LyricsOverlaySettings {
  const LyricsOverlaySettings({
    this.visible = false,
    this.permissionGranted = false,
    this.notificationPermissionGranted = false,
    this.locked = false,
    this.fontSize = 17,
    this.textColor = '#FFFFFFFF',
  });

  final bool visible;
  final bool permissionGranted;
  final bool notificationPermissionGranted;
  final bool locked;
  final double fontSize;
  final String textColor;

  LyricsOverlaySettings copyWith({
    bool? visible,
    bool? permissionGranted,
    bool? notificationPermissionGranted,
    bool? locked,
    double? fontSize,
    String? textColor,
  }) => LyricsOverlaySettings(
    visible: visible ?? this.visible,
    permissionGranted: permissionGranted ?? this.permissionGranted,
    notificationPermissionGranted:
        notificationPermissionGranted ?? this.notificationPermissionGranted,
    locked: locked ?? this.locked,
    fontSize: fontSize ?? this.fontSize,
    textColor: textColor ?? this.textColor,
  );
}

class LyricsOverlayBridge {
  LyricsOverlayBridge();

  static const _channel = MethodChannel('com.mesting.music/lyrics_overlay');
  static const _systemChannel = MethodChannel('com.mesting.music/system_media');
  ValueChanged<Map<String, Object?>>? onAction;

  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  void startListening() {
    if (!supported) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'overlayAction') return;
      final args = call.arguments as Map<dynamic, dynamic>?;
      if (args == null) return;
      onAction?.call(args.map((key, value) => MapEntry(key.toString(), value)));
    });
  }

  Future<bool> canDrawOverlays() async {
    if (!supported) return false;
    return await _invoke<bool>(_channel, 'canDrawOverlays') ?? false;
  }

  Future<void> requestPermission() async {
    if (supported) await _invoke<void>(_channel, 'requestPermission');
  }

  Future<bool> show(Map<String, Object> payload) async {
    if (!supported) return false;
    return await _invoke<bool>(_channel, 'show', payload) ?? false;
  }

  Future<void> hide() async {
    if (supported) await _invoke<void>(_channel, 'hide');
  }

  Future<void> update(Map<String, Object> payload) async {
    if (supported) await _invoke<void>(_channel, 'update', payload);
  }

  Future<bool> notificationPermissionGranted() async {
    if (!supported) return false;
    return await _invoke<bool>(
          _systemChannel,
          'notificationPermissionGranted',
        ) ??
        false;
  }

  Future<void> requestNotificationPermission() async {
    if (supported) {
      await _invoke<void>(_systemChannel, 'requestNotificationPermission');
    }
  }

  Future<void> bringAppToFront() async {
    if (supported) await _invoke<void>(_systemChannel, 'bringAppToFront');
  }

  Future<T?> _invoke<T>(
    MethodChannel channel,
    String method, [
    Object? arguments,
  ]) async {
    try {
      return await channel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}

final lyricsOverlayBridgeProvider = Provider<LyricsOverlayBridge>((ref) {
  final bridge = LyricsOverlayBridge()..startListening();
  return bridge;
});

class LyricsOverlayController extends Notifier<LyricsOverlaySettings> {
  static const _lockKey = 'lyrics_overlay_locked';
  static const _fontKey = 'lyrics_overlay_font_size';
  static const _colorKey = 'lyrics_overlay_text_color';
  bool _pendingShowAfterPermission = false;
  String _pendingCurrent = 'Mesting 音乐';
  String _pendingNext = '歌词准备中';
  bool _pendingPlaying = false;
  bool _pendingFavorite = false;
  String _lastCurrent = 'Mesting 音乐';
  String _lastNext = '歌词准备中';
  bool _lastPlaying = false;
  bool _lastFavorite = false;

  @override
  LyricsOverlaySettings build() {
    final preferences = ref.watch(sharedPreferencesProvider);
    final settings = LyricsOverlaySettings(
      locked: preferences.getBool(_lockKey) ?? false,
      fontSize: preferences.getDouble(_fontKey) ?? 17,
      textColor: preferences.getString(_colorKey) ?? '#FFFFFFFF',
    );
    final bridge = ref.watch(lyricsOverlayBridgeProvider);
    bridge.onAction = _handleNativeAction;
    Future.microtask(refreshPermissions);
    return settings;
  }

  Future<void> refreshPermissions() async {
    final bridge = ref.read(lyricsOverlayBridgeProvider);
    final overlay = await bridge.canDrawOverlays();
    final notifications = await bridge.notificationPermissionGranted();
    state = state.copyWith(
      permissionGranted: overlay,
      notificationPermissionGranted: notifications,
    );
    if (overlay && _pendingShowAfterPermission) {
      _pendingShowAfterPermission = false;
      await show(
        current: _pendingCurrent,
        next: _pendingNext,
        playing: _pendingPlaying,
        favorite: _pendingFavorite,
      );
    }
  }

  Future<void> show({
    String current = 'Mesting 音乐',
    String next = '歌词准备中',
    bool playing = false,
    bool favorite = false,
  }) async {
    _rememberSnapshot(
      current: current,
      next: next,
      playing: playing,
      favorite: favorite,
    );
    final bridge = ref.read(lyricsOverlayBridgeProvider);
    final permitted = await bridge.canDrawOverlays();
    if (!permitted) {
      prepareShowAfterPermission(
        current: current,
        next: next,
        playing: playing,
        favorite: favorite,
      );
      await bridge.requestPermission();
      return;
    }
    final shown = await bridge.show(
      _payload(
        current: current,
        next: next,
        playing: playing,
        favorite: favorite,
      ),
    );
    state = state.copyWith(visible: shown, permissionGranted: true);
  }

  void prepareShowAfterPermission({
    required String current,
    required String next,
    required bool playing,
    bool favorite = false,
  }) {
    _rememberSnapshot(
      current: current,
      next: next,
      playing: playing,
      favorite: favorite,
    );
    _pendingShowAfterPermission = true;
    _pendingCurrent = current;
    _pendingNext = next;
    _pendingPlaying = playing;
    _pendingFavorite = favorite;
    state = state.copyWith(permissionGranted: false);
  }

  Future<void> hide() async {
    await ref.read(lyricsOverlayBridgeProvider).hide();
    state = state.copyWith(visible: false);
  }

  Future<void> toggle({
    String current = 'Mesting 音乐',
    String next = '歌词准备中',
    bool playing = false,
    bool favorite = false,
  }) => state.visible
      ? hide()
      : show(
          current: current,
          next: next,
          playing: playing,
          favorite: favorite,
        );

  Future<void> setLocked(bool value) async {
    state = state.copyWith(locked: value);
    await ref.read(sharedPreferencesProvider).setBool(_lockKey, value);
    await update(current: _lastCurrent, next: _lastNext, playing: _lastPlaying);
  }

  Future<void> setFontSize(double value) async {
    state = state.copyWith(fontSize: value);
    await ref.read(sharedPreferencesProvider).setDouble(_fontKey, value);
    await update(current: _lastCurrent, next: _lastNext, playing: _lastPlaying);
  }

  Future<void> setTextColor(String value) async {
    state = state.copyWith(textColor: value);
    await ref.read(sharedPreferencesProvider).setString(_colorKey, value);
    await update(current: _lastCurrent, next: _lastNext, playing: _lastPlaying);
  }

  Future<void> requestNotificationPermission() async {
    await ref.read(lyricsOverlayBridgeProvider).requestNotificationPermission();
  }

  Future<void> update({
    required String current,
    required String next,
    bool? playing,
    bool? favorite,
  }) async {
    if (!state.visible) return;
    _rememberSnapshot(
      current: current,
      next: next,
      playing: playing ?? _lastPlaying,
      favorite: favorite ?? _lastFavorite,
    );
    await ref
        .read(lyricsOverlayBridgeProvider)
        .update(
          _payload(
            current: current,
            next: next,
            playing: playing,
            favorite: favorite,
          ),
        );
  }

  void _rememberSnapshot({
    required String current,
    required String next,
    required bool playing,
    required bool favorite,
  }) {
    _lastCurrent = current;
    _lastNext = next;
    _lastPlaying = playing;
    _lastFavorite = favorite;
  }

  Map<String, Object> _payload({
    required String current,
    required String next,
    bool? playing,
    bool? favorite,
  }) => {
    'current': current,
    'next': next,
    'playing': playing ?? false,
    'favorite': favorite ?? _lastFavorite,
    'locked': state.locked,
    'fontSize': state.fontSize,
    'textColor': state.textColor,
  };

  void _handleNativeAction(Map<String, Object?> event) {
    final action = event['action'] as String?;
    if (action == null) return;
    if (action == 'settingsChanged') {
      _applyNativeSettings(event);
      return;
    }
    if (action == 'notificationPermissionResult') {
      unawaited(refreshPermissions());
      return;
    }
    final handler = ref.read(audioHandlerProvider);
    switch (action) {
      case 'previous':
        handler.skipToPrevious();
      case 'playPause':
        handler.togglePlayPause();
      case 'next':
        handler.skipToNext();
      case 'toggleFavorite':
        handler.customAction(
          MestingAudioHandler.notificationToggleFavoriteAction,
        );
      case 'close':
        state = state.copyWith(visible: false);
      case 'locked':
        setLocked(true);
      case 'unlocked':
        setLocked(false);
    }
  }

  void _applyNativeSettings(Map<String, Object?> event) {
    final nextLocked = event['locked'] as bool? ?? state.locked;
    final nextFontSize =
        (event['fontSize'] as num?)?.toDouble() ?? state.fontSize;
    final nextTextColor = event['textColor'] as String? ?? state.textColor;
    state = state.copyWith(
      locked: nextLocked,
      fontSize: nextFontSize.clamp(14, 34),
      textColor: nextTextColor,
    );
    final preferences = ref.read(sharedPreferencesProvider);
    preferences.setBool(_lockKey, state.locked);
    preferences.setDouble(_fontKey, state.fontSize);
    preferences.setString(_colorKey, state.textColor);
  }
}

final lyricsOverlayProvider =
    NotifierProvider<LyricsOverlayController, LyricsOverlaySettings>(
      LyricsOverlayController.new,
    );
