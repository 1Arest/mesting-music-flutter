import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'credential_failure.dart';
import '../network/music_network_diagnostics.dart';

final _inFlight = Expando<Map<String, Future<String?>>>();

/// The UI may stop waiting, but Future.timeout cannot cancel a platform call.
/// Reuse that call until it settles; never enqueue three more native reads just
/// because a screen retried. Completed transient failures may still retry.
Future<String?> readRetainedSecureValue(
  FlutterSecureStorage storage,
  String key,
) async {
  final pending = _inFlight[storage] ??= {};
  var operation = pending[key];
  if (operation == null) {
    operation = () async {
      for (var attempt = 0; ; attempt++) {
        try {
          return await storage.read(key: key);
        } on PlatformException catch (error) {
          final family = credentialFailureFamily(error);
          if (attempt >= 2 ||
              family == MusicFailureFamily.decrypt ||
              family == MusicFailureFamily.keyInvalidated) {
            rethrow;
          }
          await Future<void>.delayed(
            Duration(milliseconds: 100 * (attempt + 1)),
          );
        }
      }
    }();
    pending[key] = operation;
    final current = operation;
    // Consume both completion branches without creating an unhandled future.
    unawaited(
      operation.then<void>(
        (_) {
          if (identical(pending[key], current)) pending.remove(key);
        },
        onError: (Object _, StackTrace stack) {
          if (identical(pending[key], current)) pending.remove(key);
        },
      ),
    );
  }
  return operation.timeout(const Duration(seconds: 8));
}
