import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

/// Internal optional accelerator. A status receipt is emitted only after the
/// native reader closes. No timeout races a still-live native reader with Dart.
class AppUpgradeNativeFileHash {
  const AppUpgradeNativeFileHash({MethodChannel? channel, bool? enabled})
    : _channel = channel ?? const MethodChannel('ring_download_sdk/network'),
      _enabled = enabled;

  final MethodChannel _channel;
  final bool? _enabled;

  Future<String?> tryHash(
    String path, {
    required int expectedBytes,
    Future<Object?>? cancelSignal,
  }) async {
    if (!(_enabled ?? Platform.isAndroid) ||
        expectedBytes < 0 ||
        expectedBytes > 1024 * 1024 * 1024) {
      return null;
    }
    final id = const Uuid().v4().replaceAll('-', '');
    var finished = false, cancelled = false, begun = false;
    cancelSignal?.then((_) {
      cancelled = true;
      if (!finished && begun) {
        unawaited(
          _channel
              .invokeMethod<Object?>('cancelFileHash', {'id': id})
              .catchError((Object _) => null),
        );
      }
    }, onError: (Object _) {});
    try {
      await Future<void>.value();
      if (cancelled) throw const FileSystemException('file_hash_cancelled');
      begun = true;
      final value = await _channel.invokeMapMethod<String, Object?>(
        'hashFile',
        {'id': id, 'path': path},
      );
      if (cancelled || value?['code'] == 'cancelled') {
        throw const FileSystemException('file_hash_cancelled');
      }
      if (value?['code'] == 'unavailable') return null;
      if (value?['code'] != 'ok' ||
          value?['bytes'] is! int ||
          value?['bytes'] != expectedBytes ||
          value?['sha256'] is! String ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(value!['sha256'] as String)) {
        throw const FileSystemException('file_hash_failed');
      }
      return value['sha256'] as String;
    } on MissingPluginException {
      if (cancelled) throw const FileSystemException('file_hash_cancelled');
      return null;
    } on PlatformException {
      throw const FileSystemException('file_hash_failed');
    } finally {
      finished = true;
    }
  }
}
