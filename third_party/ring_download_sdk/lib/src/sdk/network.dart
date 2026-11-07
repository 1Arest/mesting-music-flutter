import 'package:flutter/services.dart';
import '../core/services/app_upgrade_p2p_protocol.dart';

/// Plugin-owned channels; host applications do not copy Kotlin/Java handlers.
class RingNetwork {
  static const _method = MethodChannel('ring_download_sdk/network');
  static const _events = EventChannel('ring_download_sdk/network_events');
  static Stream<dynamic>? _stream;

  static Future<AppUpgradeP2PNetwork> read() async {
    try {
      return AppUpgradeP2PNetwork.fromNative(
        await _method
            .invokeMethod<String>('getNetworkType')
            .timeout(const Duration(seconds: 1)),
      );
    } catch (_) {
      // Missing permission/plugin must never enable uploads or block HTTPS.
      return AppUpgradeP2PNetwork.unknown;
    }
  }

  static Stream<dynamic> get events =>
      _stream ??= _events.receiveBroadcastStream();
}
