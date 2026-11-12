import 'dart:async';
import 'package:flutter/services.dart';

/// Android-only compatibility boundary. Ordinary accounts keep the original
/// 50/51 store and algorithms. The native side reads an archive only when an
/// encrypted entry actually exists, so an empty, broken archive cannot block
/// the original login. Only a platform-verified new login may create a slot.
class AndroidCredentialArchive {
  const AndroidCredentialArchive();

  static const _channel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  static final _pendingReads = <String, Future<String?>>{};

  Future<String?> read(String key) {
    // A UI deadline cannot cancel a platform call. Reuse it until native code
    // settles, just as the retained primary reader does, without queue flooding.
    final pending = _pendingReads.putIfAbsent(key, () {
      final call = _channel.invokeMethod<String>('mestingArchiveRead', {
        'key': key,
      });
      unawaited(
        call.then<void>(
          (_) {
            _pendingReads.remove(key);
          },
          onError: (Object _, StackTrace _) {
            _pendingReads.remove(key);
          },
        ),
      );
      return call;
    });
    return pending.timeout(const Duration(seconds: 8));
  }

  Future<void> write(String key, String envelope) =>
      _channel.invokeMethod<void>('mestingArchiveWrite', {
        'key': key,
        'value': envelope,
      });

  /// The receipt contains opaque slot names only, never account credentials.
  /// Native code commits this pointer only after reopening and decrypting the
  /// newly written value with a fresh cipher instance.
  Future<Map<String, String?>> replace(String key, String envelope) async {
    final result = await _channel.invokeMapMethod<String, String?>(
      'mestingArchiveSave',
      {'key': key, 'value': envelope},
    );
    if (result == null || result['generation'] == null) {
      throw PlatformException(
        code: 'mesting_storage',
        details: const {'family': 'io'},
      );
    }
    return result;
  }

  Future<void> rollback(String key, Map<String, String?> receipt) => _channel
      .invokeMethod<void>('mestingArchiveRollback', {'key': key, ...receipt});

  Future<void> verifyPrimary(
    String key,
    String expected,
    Map<String, String> options,
  ) => _channel
      .invokeMethod<void>('mestingVerifyReopen', {
        'key': key,
        'value': expected,
        'options': options,
      })
      .timeout(const Duration(seconds: 8));
}
