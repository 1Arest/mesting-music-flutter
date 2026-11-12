import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'dart:io';

/// Native owns permission, scheduling, durable cursors and the delivery lease.
/// Dart owns source protocols and parsing. Neither side stores raw credentials
/// in notification preferences or Intent extras.
class MusicNotificationBridge {
  const MusicNotificationBridge();
  static const channel = MethodChannel('com.mesting.music/notifications');
  bool get supported => !kIsWeb && Platform.isAndroid;

  Future<T?> call<T>(String method, [Map<String, Object?>? arguments]) async {
    if (!supported) return null;
    try {
      return await channel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      return null;
    }
  }

  Future<Map<String, dynamic>> state() async =>
      Map<String, dynamic>.from(await call<Map>('state') ?? const {});
}
