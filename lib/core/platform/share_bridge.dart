import 'package:flutter/services.dart';

class ShareBridge {
  const ShareBridge._();

  static const _channel = MethodChannel('com.mesting.music/share');

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
