import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesting_music/core/network/music_network_diagnostics.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/core/security/credential_failure.dart';
import 'package:mesting_music/features/auth/beta_account_choice.dart';
import 'package:mesting_music/features/music_platform/data/embedded_music_server.dart';
import 'package:mesting_music/features/music_platform/data/kugou_account_store.dart';
import 'package:mesting_music/features/music_platform/data/music_platform_api.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/music_platform/netease/netease_api.dart';
import 'package:mesting_music/features/music_platform/netease/netease_providers.dart';
import 'package:mesting_music/features/music_platform/netease/netease_session.dart';

import 'support/release_155_storage_fixture.dart';

const kugou155 = PlatformSession(userId: '1551', token: 'synthetic-kugou');
const netease155 = NeteaseSession(
  userId: '1552',
  deviceId: 'synthetic-device',
  cookies: {'MUSIC_U': 'synthetic-netease'},
);

class _Server155 implements MusicServer {
  @override
  Future<Uri> start() async => Uri.parse('http://127.0.0.1:1');
}

/// Actual account controllers/stores, with synthetic disk and no remote login.
Future<ProviderContainer> accounts155(
  Storage155 primary,
  Storage155 recovery, {
  String choice = 'kugou',
}) async {
  SharedPreferences.setMockInitialValues({
    BetaAccountChoiceController.preferenceKey: choice,
  });
  final mock = MockClient((_) async => http.Response('{}', 200));
  final scope = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(
        await SharedPreferences.getInstance(),
      ),
      platformSessionStoreProvider.overrideWithValue(
        SecureKugouAccountStore(storage: primary, recoveryStorage: recovery),
      ),
      neteaseSessionStoreProvider.overrideWithValue(
        SecureNeteaseSessionStore(storage: primary, recoveryStorage: recovery),
      ),
      musicPlatformApiProvider.overrideWithValue(
        MusicPlatformApi(server: _Server155(), client: mock),
      ),
      neteaseApiProvider.overrideWithValue(NeteaseApi(mock)),
    ],
  );
  addTearDown(scope.dispose);
  return scope;
}

Future<void> seed155(Storage155 primary) async {
  await SecureKugouAccountStore(storage: primary).write(kugou155);
  await SecureNeteaseSessionStore(storage: primary).write(netease155);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => MusicNetworkDiagnostics.shared.clear());
  for (final choice in ['kugou', 'netease']) {
    test(
      'readable pre-upgrade $choice credentials restore and switch without login or replacement',
      () async {
        final oldDisk = Storage155();
        await seed155(oldDisk);
        final primary = Storage155(Map.of(oldDisk.values));
        final before = Map.of(primary.values);
        final scope = await accounts155(primary, Storage155(), choice: choice);
        final session = await scope.read(platformAccountProvider.future);
        expect(session?.platform.name, choice);
        await scope
            .read(platformAccountProvider.notifier)
            .switchPlatform(
              choice == 'kugou' ? MusicPlatform.netease : MusicPlatform.kugou,
            );
        expect(primary.values, before);
        expect(primary.writes, 0);
        expect(primary.deletes, 0);
      },
    );
  }

  test(
    'invalid old NetEase key leaves Kugou selected; verified recovery survives a new store',
    () async {
      final primary = Storage155();
      await seed155(primary);
      final before = Map.of(primary.values);
      primary.readFailures[SecureNeteaseSessionStore.key] = 'keyInvalidated';
      final recovery = Storage155();
      final scope = await accounts155(primary, recovery);
      await scope.read(platformAccountProvider.future);
      final controller = scope.read(platformAccountProvider.notifier);
      await expectLater(
        controller.retainedIdentity(MusicPlatform.netease),
        throwsA(
          isA<CredentialStoreException>().having(
            (e) => e.requiresReauthentication,
            'needs reauthentication',
            true,
          ),
        ),
      );
      expect(
        scope.read(platformAccountProvider).value?.ownerId,
        kugou155.ownerId,
      );
      expect(scope.read(betaAccountChoiceProvider), BetaAccountChoice.kugou);
      expect(recovery.values, isEmpty);
      await controller.acceptNetease(netease155);
      expect(
        scope.read(platformAccountProvider).value?.ownerId,
        netease155.identity.ownerId,
      );
      expect(primary.values, before);
      final restarted = await accounts155(
        Storage155(primary.values)
          ..readFailures[SecureNeteaseSessionStore.key] = 'keyInvalidated',
        Storage155(recovery.values),
        choice: 'netease',
      );
      expect(
        (await restarted.read(platformAccountProvider.future))?.ownerId,
        netease155.identity.ownerId,
      );
      await restarted
          .read(platformAccountProvider.notifier)
          .switchPlatform(MusicPlatform.kugou);
      expect(
        restarted.read(platformAccountProvider).value?.ownerId,
        kugou155.ownerId,
      );
      expect(primary.values, before);
    },
  );

  test(
    'invalid Kugou target can be reauthenticated while NetEase remains usable',
    () async {
      final primary = Storage155();
      await seed155(primary);
      primary.readFailures[SecureKugouAccountStore.key] = 'keyInvalidated';
      final before = Map.of(primary.values);
      final recovery = Storage155();
      final scope = await accounts155(primary, recovery, choice: 'netease');
      await scope.read(platformAccountProvider.future);
      final controller = scope.read(platformAccountProvider.notifier);
      await expectLater(
        controller.switchPlatform(MusicPlatform.kugou),
        throwsA(isA<CredentialStoreException>()),
      );
      expect(
        scope.read(platformAccountProvider).value?.platform,
        MusicPlatform.netease,
      );
      await controller.accept(kugou155.toJson(), loginMethod: 'phone');
      expect(
        scope.read(platformAccountProvider).value?.ownerId,
        kugou155.ownerId,
      );
      expect(primary.values, before);
      expect(
        (await SecureKugouAccountStore(
          storage: primary,
          recoveryStorage: Storage155(recovery.values),
        ).read())?.token,
        kugou155.token,
      );
      expect(
        (await SecureNeteaseSessionStore(storage: primary).read())?.userId,
        netease155.userId,
      );
    },
  );

  test(
    'failed recovery save cannot replace the healthy active platform',
    () async {
      final primary = Storage155();
      await seed155(primary);
      primary.readFailures[SecureNeteaseSessionStore.key] = 'keyInvalidated';
      final recovery = Storage155()..failWrites = true;
      final scope = await accounts155(primary, recovery);
      await scope.read(platformAccountProvider.future);
      final before = Map.of(primary.values);
      await expectLater(
        scope.read(platformAccountProvider.notifier).acceptNetease(netease155),
        throwsA(isA<CredentialStoreException>()),
      );
      expect(
        scope.read(platformAccountProvider).value?.ownerId,
        kugou155.ownerId,
      );
      expect(scope.read(betaAccountChoiceProvider), BetaAccountChoice.kugou);
      expect(primary.values, before);
      expect(recovery.values, isEmpty);
    },
  );

  test(
    'incomplete fresh authentication cannot open a recovery overlay',
    () async {
      final primary = Storage155();
      await seed155(primary);
      primary.readFailures[SecureNeteaseSessionStore.key] = 'keyInvalidated';
      final recovery = Storage155();
      final scope = await accounts155(primary, recovery);
      await scope.read(platformAccountProvider.future);
      await expectLater(
        scope
            .read(platformAccountProvider.notifier)
            .acceptNetease(
              const NeteaseSession(
                userId: '1552',
                deviceId: 'synthetic-device',
                cookies: {},
              ),
            ),
        throwsA(isA<MusicPlatformException>()),
      );
      expect(recovery.values, isEmpty);
      expect(
        scope.read(platformAccountProvider).value?.ownerId,
        kugou155.ownerId,
      );
    },
  );

  test(
    'recovered platform logout tombstone does not resurrect old credentials or remove the other platform',
    () async {
      final primary = Storage155();
      await seed155(primary);
      final before = Map.of(primary.values);
      primary.readFailures[SecureNeteaseSessionStore.key] = 'keyInvalidated';
      final recovery = Storage155();
      final store = SecureNeteaseSessionStore(
        storage: primary,
        recoveryStorage: recovery,
      );
      await store.recoverVerifiedLogin(netease155);
      await store.clear();
      // Simulate the legacy key becoming readable: logout still wins.
      final restarted = SecureNeteaseSessionStore(
        storage: Storage155(primary.values),
        recoveryStorage: Storage155(recovery.values),
      );
      expect(await restarted.read(), isNull);
      expect(primary.values, before);
      expect(
        jsonDecode(recovery.values[SecureNeteaseSessionStore.key]!)['value'],
        isNull,
      );
      expect(
        (await SecureKugouAccountStore(storage: primary).read())?.token,
        kugou155.token,
      );
    },
  );
}
