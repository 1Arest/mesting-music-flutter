import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/core/security/retained_secure_read.dart';
import 'package:mesting_music/features/music_platform/data/kugou_account_store.dart';

class _StalledStorage extends FlutterSecureStorage {
  int reads = 0;
  bool stalled = true;
  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) {
    reads++;
    if (stalled) return Completer<String?>().future;
    return Future.value('{"version":2,"accounts":[],"selected":null}');
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
  }) async => throw StateError('must not erase');
}

void main() {
  testWidgets(
    'hung encrypted read releases the serialized account queue for explicit recovery',
    (tester) async {
      final storage = _StalledStorage();
      final store = SecureKugouAccountStore(storage: storage);
      final failed = expectLater(
        store.read(),
        throwsA(isA<TimeoutException>()),
      );
      for (var i = 0; i < 55; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await failed;
      expect(storage.reads, 3);
      storage.stalled = false;
      expect(await store.read(), null);
      expect(storage.reads, 4);
    },
  );
  testWidgets('read retries do not delete credentials on platform failure', (
    tester,
  ) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const channel = MethodChannel(
      'plugins.it_nomads.com/flutter_secure_storage',
    );
    final methods = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      methods.add(call.method);
      throw PlatformException(code: 'fixture_keystore_unavailable');
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final operation = expectLater(
      readRetainedSecureValue(const FlutterSecureStorage(), 'fixture'),
      throwsA(isA<PlatformException>()),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await operation;
    expect(methods, ['read', 'read', 'read']);
  });
}
