import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SensitiveScreen extends StatefulWidget {
  const SensitiveScreen({required this.child, super.key});

  final Widget child;

  @override
  State<SensitiveScreen> createState() => _SensitiveScreenState();
}

class _SensitiveScreenState extends State<SensitiveScreen> {
  static const _channel = MethodChannel('com.mesting.music/system_media');

  @override
  void initState() {
    super.initState();
    unawaited(_setSecure(true));
  }

  @override
  void dispose() {
    unawaited(_setSecure(false));
    super.dispose();
  }

  Future<void> _setSecure(bool enabled) async {
    try {
      await _channel.invokeMethod<void>(
        enabled ? 'enterSecureScreen' : 'exitSecureScreen',
      );
    } on MissingPluginException {
      // Widget tests and unsupported hosts intentionally have no Android host.
    } on PlatformException {
      // Privacy hardening must not make an authentication page unusable.
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
