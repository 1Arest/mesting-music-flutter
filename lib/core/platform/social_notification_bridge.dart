import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Minimal Android notification bridge for social updates.
///
/// Keeping this bridge native avoids introducing a second notification plugin
/// beside the existing media-notification integration.
class SocialNotificationBridge {
  SocialNotificationBridge({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const _channelName = 'com.mesting.music/system_media';

  final MethodChannel _channel;

  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<bool> permissionGranted() async {
    if (!supported) return false;
    return await _invoke<bool>('notificationPermissionGranted') ?? false;
  }

  Future<void> requestPermission() async {
    if (supported) await _invoke<void>('requestNotificationPermission');
  }

  Future<bool> show({
    required int id,
    required String title,
    required String body,
  }) async {
    if (!supported || title.trim().isEmpty || body.trim().isEmpty) {
      return false;
    }
    return await _invoke<bool>('showSocialNotification', {
          'id': id,
          'title': title.trim(),
          'body': body.trim(),
        }) ??
        false;
  }

  Future<T?> _invoke<T>(String method, [Object? arguments]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}
