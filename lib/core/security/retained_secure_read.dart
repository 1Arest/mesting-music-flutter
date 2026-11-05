import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// A hung read must not hold a serialized account store forever. This bounds
/// reads only: no deletion/reset or timed-out write replay is permitted here.
Future<String?> readRetainedSecureValue(
  FlutterSecureStorage storage,
  String key,
) async {
  for (var attempt = 0; ; attempt++) {
    try {
      return await storage
          .read(key: key)
          .timeout(const Duration(milliseconds: 1500));
    } on Object catch (error) {
      if (attempt >= 2 ||
          error is! PlatformException && error is! TimeoutException) {
        rethrow;
      }
      await Future<void>.delayed(Duration(milliseconds: 100 * (attempt + 1)));
    }
  }
}
