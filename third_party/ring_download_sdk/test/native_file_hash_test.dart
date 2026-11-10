import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ring_download_sdk/src/core/services/app_upgrade_native_hash.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/file_hash');
  const hash = AppUpgradeNativeFileHash(channel: channel, enabled: true);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final digest = 'a' * 64;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'new IDs and native reads for every invocation, including same path',
    () async {
      final ids = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'hashFile');
        expect(call.arguments['path'], '/owned/file');
        ids.add(call.arguments['id'] as String);
        return {
          'code': 'ok',
          'sha256': ids.length == 1 ? digest : 'b' * 64,
          'bytes': 7,
        };
      });
      expect(await hash.tryHash('/owned/file', expectedBytes: 7), digest);
      expect(await hash.tryHash('/owned/file', expectedBytes: 7), 'b' * 64);
      expect(ids.toSet().length, 2);
      expect(ids.every((id) => RegExp(r'^[a-f0-9]{32}$').hasMatch(id)), true);
    },
  );

  test(
    'unsupported worker and missing plugin explicitly permit fresh fallback',
    () async {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => {'code': 'unavailable'},
      );
      expect(await hash.tryHash('/outside/file', expectedBytes: 7), isNull);
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => throw MissingPluginException(),
      );
      expect(await hash.tryHash('/owned/file', expectedBytes: 7), isNull);
    },
  );

  test(
    'bad status, digest, byte count or platform error never become a receipt',
    () async {
      for (final value in [
        null,
        {'code': 'error'},
        {'code': 'ok', 'sha256': digest, 'bytes': 8},
        {'code': 'ok', 'sha256': digest, 'bytes': 7.0},
        {'code': 'ok', 'sha256': 'BAD', 'bytes': 7},
      ]) {
        messenger.setMockMethodCallHandler(channel, (_) async => value);
        await expectLater(
          hash.tryHash('/owned/file', expectedBytes: 7),
          throwsA(isA<FileSystemException>()),
        );
      }
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => throw PlatformException(code: 'error'),
      );
      await expectLater(
        hash.tryHash('/owned/file', expectedBytes: 7),
        throwsA(isA<FileSystemException>()),
      );
    },
  );

  test(
    'cancel marking is insufficient: completion waits for the closed-reader receipt',
    () async {
      final running = Completer<Map<String, Object>>();
      final begun = Completer<void>(),
          marked = Completer<void>(),
          signal = Completer<void>();
      String? id;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'hashFile') {
          id = call.arguments['id'] as String;
          begun.complete();
          return running.future;
        }
        expect(call.method, 'cancelFileHash');
        expect(call.arguments['id'], id);
        marked.complete();
        return true;
      });
      var completed = false;
      final request = hash.tryHash(
        '/owned/file',
        expectedBytes: 7,
        cancelSignal: signal.future,
      );
      final rejection = expectLater(
        request.whenComplete(() => completed = true),
        throwsA(isA<FileSystemException>()),
      );
      await begun.future;
      signal.complete();
      await marked.future;
      expect(completed, false);
      running.complete({'code': 'cancelled'});
      await rejection;
      expect(completed, true);
    },
  );

  test('late cancellation from old call never cancels the new owner', () async {
    final oldSignal = Completer<void>();
    var cancels = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'cancelFileHash') {
        cancels++;
        return false;
      }
      return {'code': 'ok', 'sha256': digest, 'bytes': 7};
    });
    await hash.tryHash(
      '/owned/file',
      expectedBytes: 7,
      cancelSignal: oldSignal.future,
    );
    oldSignal.complete();
    expect(await hash.tryHash('/owned/file', expectedBytes: 7), digest);
    expect(cancels, 0);
  });

  test('already cancelled request never starts a native reader', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls++;
      return {'code': 'ok', 'sha256': digest, 'bytes': 7};
    });
    await expectLater(
      hash.tryHash(
        '/owned/file',
        expectedBytes: 7,
        cancelSignal: Future<void>.value(),
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(calls, 0);
  });

  test('disabled platform or oversized file performs no method call', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => fail('unexpected native call'),
    );
    expect(
      await const AppUpgradeNativeFileHash(
        channel: channel,
        enabled: false,
      ).tryHash('/owned/file', expectedBytes: 7),
      isNull,
    );
    expect(
      await hash.tryHash('/owned/file', expectedBytes: 1024 * 1024 * 1024 + 1),
      isNull,
    );
  });
}
