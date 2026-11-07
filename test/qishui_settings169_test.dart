import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_api.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_request_signer.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_signer_settings.dart';

import 'qishui_signer168_test.dart' show token168, MemorySignerStore168;

class _FailedRead extends MemorySignerStore168 {
  final Completer<QishuiSignerConfig?>? pending;
  _FailedRead({this.pending});
  @override
  Future<QishuiSignerConfig?> read() {
    reads++;
    return pending?.future ??
        Future.error(const QishuiSignerSettingsFailure('fixture rejected'));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late String nativePrefix;
  final records = <String, String>{};
  final methods = <String>[];
  bool rejectReopen = false;

  setUpAll(() {
    // Read the owning Java boundary, rather than letting an unconstrained
    // memory repository silently accept the invalid key that shipped in 68.
    final source = File(
      'third_party/flutter_secure_storage/package/android/src/main/java/com/it_nomads/fluttersecurestorage/FlutterSecureStoragePlugin.java',
    ).readAsStringSync();
    nativePrefix = RegExp(
      r'!key\.startsWith\("([^"]+)"\)',
    ).firstMatch(source)!.group(1)!;
  });
  setUp(() {
    records.clear();
    methods.clear();
    rejectReopen = false;
    records['legacy:account'] = 'fixture-account-ciphertext';
    messenger.setMockMethodCallHandler(channel, (call) async {
      methods.add(call.method);
      final arguments = Map<String, dynamic>.from(call.arguments as Map);
      final key = arguments['key'] as String;
      final options = Map<String, dynamic>.from(
        arguments['options'] as Map? ?? {},
      );
      if (call.method.startsWith('mesting')) {
        if (!key.startsWith(nativePrefix)) {
          throw PlatformException(
            code: 'mesting_storage',
            details: {'family': 'unknown'},
          );
        }
        expect(call.method, 'mestingVerifyReopen');
        expect(options['storageNamespace'], 'mesting_qishui_signer_v1');
        if (rejectReopen) {
          throw PlatformException(
            code: 'mesting_storage',
            details: {'family': 'keyInvalidated'},
          );
        }
        expect(
          records['${options['storageNamespace']}:$key'],
          arguments['value'],
        );
        return null;
      }
      expect(options['storageNamespace'], 'mesting_qishui_signer_v1');
      expect(options['resetOnError'], 'false');
      final recordKey = '${options['storageNamespace']}:$key';
      switch (call.method) {
        case 'read':
          return records[recordKey];
        case 'write':
          records[recordKey] = arguments['value'] as String;
          return null;
        default:
          fail(
            'No account archive or destructive storage method expected: ${call.method}',
          );
      }
    });
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test(
    '68 recovery-read key is rejected by the actual native prefix contract',
    () async {
      await expectLater(
        channel.invokeMethod<String>('mestingArchiveRead', {
          'key': 'mesting_qishui_signer_settings_v1',
        }),
        throwsA(isA<PlatformException>()),
      );
    },
  );
  test(
    'empty independent settings read needs no account recovery archive',
    () async {
      const store = SecureQishuiSignerSettingsStore(android: true);
      expect(await store.read(), isNull);
      expect(methods, ['read']);
      expect(records['legacy:account'], 'fixture-account-ciphertext');
    },
  );
  test(
    'save uses isolated ciphertext and independently reopens after a cold store',
    () async {
      const store = SecureQishuiSignerSettingsStore(android: true);
      final config = QishuiSignerConfig.parse(
        qishuiSelfHostedSignerAddress,
        token168,
      );
      await store.write(config);
      final fresh = SecureQishuiSignerSettingsStore(
        android: true,
        storage: FlutterSecureStorage(
          aOptions: qishuiSignerSecureStorage.aOptions,
        ),
      );
      expect(await fresh.read(), config);
      expect(methods, ['write', 'read', 'mestingVerifyReopen', 'read']);
      expect(records['legacy:account'], 'fixture-account-ciphertext');
    },
  );
  test(
    'reopen failure is surfaced without deleting a namespace or account',
    () async {
      rejectReopen = true;
      const store = SecureQishuiSignerSettingsStore(android: true);
      await expectLater(
        store.write(
          QishuiSignerConfig.parse(qishuiSelfHostedSignerAddress, token168),
        ),
        throwsA(isA<QishuiSignerSettingsFailure>()),
      );
      expect(methods.any((method) => method.contains('delete')), isFalse);
      expect(records['legacy:account'], 'fixture-account-ciphertext');
    },
  );
  test(
    'unconfigured production signer never contacts NAS or public services',
    () async {
      var requests = 0;
      final signer = ConfiguredQishuiRequestSigner(
        MockClient((_) async {
          requests++;
          fail('A token must be saved first');
        }),
        () async => null,
      );
      await expectLater(
        signer.identity(Completer<void>().future),
        throwsA(
          isA<QishuiException>().having(
            (e) => e.message,
            'manual configuration',
            contains('访问令牌'),
          ),
        ),
      );
      expect(requests, 0);
    },
  );
  testWidgets(
    'native rejection is one visible failure, not automatic retries',
    (tester) async {
      final store = _FailedRead();
      final container = ProviderContainer(
        overrides: [qishuiSignerSettingsStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        qishuiSignerSettingsProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);
      await tester.pump();
      expect(container.read(qishuiSignerSettingsProvider).hasError, isTrue);
      await tester.pump(const Duration(minutes: 1));
      expect(store.reads, 1);
      expect(container.read(qishuiSignerSettingsProvider).isLoading, isFalse);
    },
  );
  testWidgets('an unresponsive read leaves loading within nine seconds', (
    tester,
  ) async {
    final pending = Completer<QishuiSignerConfig?>();
    final store = _FailedRead(pending: pending);
    final container = ProviderContainer(
      overrides: [qishuiSignerSettingsStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      qishuiSignerSettingsProvider,
      (_, _) {},
    );
    addTearDown(subscription.close);
    await tester.pump();
    await tester.pump(const Duration(seconds: 10));
    expect(container.read(qishuiSignerSettingsProvider).hasError, isTrue);
    await tester.pump(const Duration(minutes: 1));
    expect(store.reads, 1);
    pending.complete(null);
    await tester.pump();
    expect(container.read(qishuiSignerSettingsProvider).hasError, isTrue);
  });
}
