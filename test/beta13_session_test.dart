import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/core/platform/distribution_channel.dart';
import 'package:mesting_music/features/auth/beta_account_choice.dart';
import 'package:mesting_music/features/auth/beta_entry_flow.dart';
import 'package:mesting_music/features/music_platform/data/platform_session_store.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/themes/startup_style.dart';

const _session = PlatformSession(
  userId: 'fixture-user',
  token: 'fixture-token',
  nickname: '音乐旅行者',
);
const _storageChannel = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);

class _Store implements PlatformSessionStore {
  PlatformSession? value = _session;
  final Completer<void>? wait;
  _Store([this.wait]);
  @override
  Future<PlatformSession?> read() async {
    await wait?.future;
    return value;
  }

  @override
  Future<void> write(PlatformSession session) async {
    value = session;
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}

class _BrokenStore extends _Store {
  bool broken = true;
  int deletes = 0;
  @override
  Future<PlatformSession?> read() async {
    if (broken) throw const FormatException('fixture malformed session');
    return value;
  }

  @override
  Future<void> write(PlatformSession session) async {
    value = session;
    broken = false;
  }

  @override
  Future<void> clear() async {
    deletes++;
    value = null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_storageChannel, null),
  );

  test(
    'temporary Android keystore attach failure retries without deleting the session',
    () async {
      var reads = 0, deletes = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_storageChannel, (call) async {
            expect((call.arguments as Map)['options']['resetOnError'], 'false');
            if (call.method == 'delete') {
              deletes++;
              return null;
            }
            if (++reads < 3) throw PlatformException(code: 'engine_attaching');
            return jsonEncode(_session.toJson());
          });
      final restored = await const SecurePlatformSessionStore().read();
      expect(restored?.userId, _session.userId);
      expect(reads, 3);
      expect(deletes, 0);
    },
  );
  test(
    'persistent restoration failure can be replaced only by a confirmed fresh login',
    () async {
      SharedPreferences.setMockInitialValues({
        BetaAccountChoiceController.preferenceKey: 'kugou',
      });
      final prefs = await SharedPreferences.getInstance();
      final store = _BrokenStore();
      final c = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          platformSessionStoreProvider.overrideWithValue(store),
        ],
      );
      await expectLater(
        c.read(platformAccountProvider.future),
        throwsFormatException,
      );
      await c.read(betaEntryFlowProvider.notifier).welcome();
      await c.read(platformAccountProvider.notifier).readyForInteractiveLogin();
      expect(store.value, same(_session));
      expect(store.deletes, 0);
      await c
          .read(platformAccountProvider.notifier)
          .accept(
            const PlatformSession(
              userId: 'new-fixture',
              token: 'new-fixture-token',
            ).toJson(),
          );
      expect(c.read(platformAccountProvider).value?.userId, 'new-fixture');
      expect(store.deletes, 0);
      expect(c.read(betaEntryFlowProvider), BetaEntryStage.success);
      c.dispose();
    },
    skip: !DistributionChannel.isBeta,
  );
  test(
    'a temporary missing read retries; malformed JSON never erases encrypted data',
    () async {
      var reads = 0, deletes = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_storageChannel, (call) async {
            if (call.method == 'delete') {
              deletes++;
              return null;
            }
            return ++reads == 1 ? null : '{broken-json';
          });
      await expectLater(
        const SecurePlatformSessionStore().read(),
        throwsFormatException,
      );
      expect(reads, 2);
      expect(deletes, 0);
    },
  );
  test(
    'persistent read failure is reported, rather than returned as a logged-out identity',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            _storageChannel,
            (_) async => throw PlatformException(code: 'read_failed'),
          );
      await expectLater(
        const SecurePlatformSessionStore().read(),
        throwsA(isA<PlatformException>()),
      );
    },
  );
  test(
    'a write ACK with no durable read-back cannot report login success',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_storageChannel, (_) async => null);
      await expectLater(
        const SecurePlatformSessionStore().write(_session),
        throwsStateError,
      );
    },
  );
  for (final style in StartupStyle.values) {
    test(
      'changing ${style.id} preserves durable phone identity across a fresh container',
      () async {
        SharedPreferences.setMockInitialValues({
          BetaAccountChoiceController.preferenceKey: 'kugou',
        });
        final prefs = await SharedPreferences.getInstance();
        final store = _Store();
        ProviderContainer create() => ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            platformSessionStoreProvider.overrideWithValue(store),
          ],
        );
        final first = create();
        expect(
          (await first.read(platformAccountProvider.future))?.userId,
          _session.userId,
        );
        await first.read(startupStyleProvider.notifier).select(style);
        first.dispose();
        final cold = create();
        expect(savedStartupStyle(prefs), style);
        expect(
          (await cold.read(platformAccountProvider.future))?.userId,
          _session.userId,
        );
        expect(cold.read(betaEntryFlowProvider), BetaEntryStage.idle);
        await cold.read(platformAccountProvider.notifier).signOut();
        cold.dispose();
        final afterLogout = create();
        expect(await afterLogout.read(platformAccountProvider.future), isNull);
        afterLogout.dispose();
      },
      skip: !DistributionChannel.isBeta,
    );
  }
  test(
    'delayed restoration cannot overwrite a guest choice made while its read was pending',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final gate = Completer<void>();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          platformSessionStoreProvider.overrideWithValue(_Store(gate)),
        ],
      );
      final restoring = container.read(platformAccountProvider.future);
      await container
          .read(betaAccountChoiceProvider.notifier)
          .select(BetaAccountChoice.guest);
      gate.complete();
      expect(await restoring, isNull);
      container.dispose();
    },
    skip: !DistributionChannel.isBeta,
  );
}
