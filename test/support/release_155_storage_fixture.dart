import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Synthetic persistent bytes shared by fresh repository instances. Failures
/// apply per key, so one unreadable platform cannot stand in for a broken app.
class Storage155 extends FlutterSecureStorage {
  Storage155([Map<String, String>? values]) : values = values ?? {};
  final Map<String, String> values;
  final Map<String, String> readFailures = {};
  bool failWrites = false;
  int reads = 0, writes = 0, deletes = 0;

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    reads++;
    final family = readFailures[key];
    if (family != null) {
      throw PlatformException(
        code: 'mesting_storage',
        details: {'family': family},
      );
    }
    return values[key];
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    writes++;
    if (failWrites) {
      throw PlatformException(
        code: 'mesting_storage',
        details: {'family': 'io'},
      );
    }
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    deletes++;
    values.remove(key);
  }
}
