import 'package:flutter/services.dart';

/// Short, bundled, original UI feedback. Android SoundPool mixes with media;
/// it never creates an audio_service owner or requests music audio focus.
class LoginSuccessSound {
  static const _channel = MethodChannel('com.mesting.music/ui_sound');
  static Future<void> play() async {
    try {
      await _channel.invokeMethod<void>('loginSuccess');
    } on MissingPluginException {
      // Desktop/widget hosts have no Android output device.
    } on PlatformException {
      // Optional feedback must never prevent a completed login or the guide.
    }
  }
}
