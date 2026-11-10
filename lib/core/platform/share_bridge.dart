import 'package:flutter/services.dart';

class ShareBridge {
  const ShareBridge._();

  static const _channel = MethodChannel('com.mesting.music/share');

  /// Opens WeChat's recipient picker; the user still confirms the final send.
  /// Share only the public catalogue URL, never a resolved audio transport.
  static Future<void> shareToWeChat(String url) async {
    await _channel.invokeMethod<void>('shareToWeChat', {'url': url});
  }

  static Future<void> shareText(String text, {String? title}) async {
    await _channel.invokeMethod<void>('shareText', {
      'text': text,
      'title': ?title,
    });
  }
}
