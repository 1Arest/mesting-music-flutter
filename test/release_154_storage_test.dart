import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesting_music/core/network/music_network_diagnostics.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/core/security/credential_failure.dart';
import 'package:mesting_music/core/security/retained_secure_read.dart';
import 'package:mesting_music/features/auth/beta_account_choice.dart';
import 'package:mesting_music/features/music_platform/data/embedded_music_server.dart';
import 'package:mesting_music/features/music_platform/data/kugou_account_store.dart';
import 'package:mesting_music/features/music_platform/data/music_platform_api.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/music_platform/netease/netease_api.dart';
import 'package:mesting_music/features/music_platform/netease/netease_providers.dart';
import 'package:mesting_music/features/music_platform/netease/netease_session.dart';

/// Two storage instances can share persisted bytes, but no Dart vault/cache.
/// These are protocol/storage-transaction fixtures, never real account data.
class _Disk extends FlutterSecureStorage {
  _Disk([Map<String, String>? disk]) : disk = disk ?? {};
  final Map<String, String> disk;
  bool brokenRead = false, brokenWrite = false;
  Completer<String?>? gate;
  int reads = 0, writes = 0;
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
    if (brokenRead) {
      throw PlatformException(
        code: 'mesting_storage',
        message: 'fixture-secret-must-not-export',
        details: {'family': 'decrypt'},
      );
    }
    if (gate != null) return gate!.future;
    return disk[key];
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
    if (brokenWrite) {
      throw PlatformException(
        code: 'mesting_storage',
        details: {'family': 'io'},
      );
    }
    if (value == null) {
      disk.remove(key);
    } else {
      disk[key] = value;
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
    disk.remove(key);
  }
}

class _Server implements MusicServer {
  @override
  Future<Uri> start() async => Uri.parse('http://127.0.0.1:1');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => MusicNetworkDiagnostics.shared.clear());
  const fresh = PlatformSession(userId: '123', token: 'synthetic-new-token');

  Future<ProviderContainer> containerFor(
    SecureKugouAccountStore kugou,
    SecureNeteaseSessionStore netease,
    String choice,
  ) async {
    SharedPreferences.setMockInitialValues({
      BetaAccountChoiceController.preferenceKey: choice,
    });
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(
          await SharedPreferences.getInstance(),
        ),
        platformSessionStoreProvider.overrideWithValue(kugou),
        neteaseSessionStoreProvider.overrideWithValue(netease),
        musicPlatformApiProvider.overrideWithValue(
          MusicPlatformApi(
            server: _Server(),
            client: MockClient((_) async => http.Response('{}', 200)),
          ),
        ),
        neteaseApiProvider.overrideWithValue(
          NeteaseApi(MockClient((_) async => http.Response('{}', 200))),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  testWidgets(
    'timed-out callers reuse one native read and receive its late completion',
    (tester) async {
      final storage = _Disk()..gate = Completer<String?>();
      final first = expectLater(
        readRetainedSecureValue(storage, 'fixture'),
        throwsA(isA<TimeoutException>()),
      );
      await tester.pump(const Duration(seconds: 9));
      await first;
      final retry = readRetainedSecureValue(storage, 'fixture');
      await tester.pump();
      expect(
        storage.reads,
        1,
        reason: 'a UI deadline cannot cancel native work',
      );
      storage.gate!.complete('late-valid-result');
      await tester.pump();
      expect(await retry, 'late-valid-result');
      storage.gate = null;
      expect(await readRetainedSecureValue(storage, 'fixture'), isNull);
      expect(storage.reads, 2, reason: 'settled calls release the slot');
    },
  );

  test(
    'failed Kugou cold restore -> verified login -> new-store restore, without touching old bytes',
    () async {
      final primary = _Disk({
        SecureKugouAccountStore.key: 'retained-opaque-legacy',
      })..brokenRead = true;
      final recoveryDisk = <String, String>{};
      final recovery = _Disk(recoveryDisk);
      final store = SecureKugouAccountStore(
        storage: primary,
        recoveryStorage: recovery,
      );
      final container = await containerFor(
        store,
        SecureNeteaseSessionStore(storage: _Disk()),
        'kugou',
      );
      await expectLater(
        container.read(platformAccountProvider.future),
        throwsA(isA<CredentialStoreException>()),
      );
      await container
          .read(platformAccountProvider.notifier)
          .accept(fresh.toJson(), loginMethod: 'phone');
      expect(
        container.read(platformAccountProvider).value?.userId,
        fresh.userId,
      );
      expect(
        primary.disk[SecureKugouAccountStore.key],
        'retained-opaque-legacy',
      );
      expect(primary.writes, 0);
      final restarted = SecureKugouAccountStore(
        storage: _Disk(primary.disk)..brokenRead = true,
        recoveryStorage: _Disk(recoveryDisk),
      );
      expect((await restarted.read())?.token, fresh.token);
      expect((await restarted.snapshot()).accounts.single.loginMethod, 'phone');
      final exported = MusicNetworkDiagnostics.shared.export();
      expect(exported, contains('"family": "decrypt"'));
      expect(exported, isNot(contains('fixture-secret')));
      expect(exported, isNot(contains(fresh.token)));
    },
  );

  test(
    'malformed legacy snapshot is retained and only explicit verified login writes recovery',
    () async {
      final primary = _Disk({
        SecureKugouAccountStore.key: '{"version":2,"accounts":[null]}',
      });
      final recovery = _Disk();
      final store = SecureKugouAccountStore(
        storage: primary,
        recoveryStorage: recovery,
      );
      final before = Map.of(primary.disk);
      await expectLater(store.read(), throwsA(isA<CredentialStoreException>()));
      expect(recovery.writes, 0);
      final receipt = await store.recoverVerifiedLogin(fresh);
      expect((await store.read())?.userId, fresh.userId);
      await receipt.rollback();
      expect(primary.disk, before);
      expect(recovery.disk, isEmpty);
      await expectLater(store.read(), throwsA(isA<CredentialStoreException>()));
    },
  );

  test(
    'failed recovery write cannot publish a login or reset the old namespace',
    () async {
      final primary = _Disk({SecureKugouAccountStore.key: 'retained'})
        ..brokenRead = true;
      final recovery = _Disk()..brokenWrite = true;
      final store = SecureKugouAccountStore(
        storage: primary,
        recoveryStorage: recovery,
      );
      final container = await containerFor(
        store,
        SecureNeteaseSessionStore(storage: _Disk()),
        'kugou',
      );
      await expectLater(
        container.read(platformAccountProvider.future),
        throwsA(isA<CredentialStoreException>()),
      );
      await expectLater(
        container.read(platformAccountProvider.notifier).accept(fresh.toJson()),
        throwsA(isA<CredentialStoreException>()),
      );
      expect(container.read(platformAccountProvider).hasError, isTrue);
      expect(container.read(musicPlatformApiProvider).session, isNull);
      expect(primary.writes, 0);
      expect(primary.disk.values.single, 'retained');
    },
  );

  test(
    'incomplete HTTP-success credentials report remote validation, not local storage',
    () async {
      final primary = _Disk();
      final store = SecureKugouAccountStore(storage: primary);
      final container = await containerFor(
        store,
        SecureNeteaseSessionStore(storage: _Disk()),
        'kugou',
      );
      await container.read(platformAccountProvider.future);
      final before = Map.of(primary.disk);
      await expectLater(
        container.read(platformAccountProvider.notifier).accept({
          'userid': '123',
        }),
        throwsA(isA<MusicPlatformException>()),
      );
      expect(primary.disk, before);
      expect(
        MusicNetworkDiagnostics.shared.rows.last['phase'],
        'credentialValidate',
      );
      expect(
        MusicNetworkDiagnostics.shared.rows.last['family'],
        'credentialIncomplete',
      );
    },
  );

  test(
    'NetEase recovery survives new-store creation and logout tombstone prevents old-login resurrection',
    () async {
      final primary = _Disk({SecureNeteaseSessionStore.key: 'retained-old'})
        ..brokenRead = true;
      final recoveryDisk = <String, String>{};
      final netease = SecureNeteaseSessionStore(
        storage: primary,
        recoveryStorage: _Disk(recoveryDisk),
      );
      final container = await containerFor(
        SecureKugouAccountStore(storage: _Disk()),
        netease,
        'netease',
      );
      await expectLater(
        container.read(platformAccountProvider.future),
        throwsA(isA<CredentialStoreException>()),
      );
      const session = NeteaseSession(
        userId: '456',
        deviceId: 'synthetic-device',
        cookies: {'MUSIC_U': 'synthetic-cookie'},
      );
      await container
          .read(platformAccountProvider.notifier)
          .acceptNetease(session);
      expect(
        container.read(platformAccountProvider).value?.platform,
        MusicPlatform.netease,
      );
      final restarted = SecureNeteaseSessionStore(
        storage: _Disk(primary.disk)..brokenRead = true,
        recoveryStorage: _Disk(recoveryDisk),
      );
      expect((await restarted.read())?.cookies['MUSIC_U'], 'synthetic-cookie');
      await restarted.clear();
      final afterLogout = SecureNeteaseSessionStore(
        storage: _Disk(primary.disk),
        recoveryStorage: _Disk(recoveryDisk),
      );
      expect(await afterLogout.read(), isNull);
      expect(primary.disk.values.single, 'retained-old');
      expect(jsonDecode(recoveryDisk.values.single)['value'], isNull);
    },
  );
}
