import 'dart:convert';
import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/features/auth/beta_account_choice.dart';
import 'package:mesting_music/features/music_platform/data/embedded_music_server.dart';
import 'package:mesting_music/features/music_platform/data/kugou_account_store.dart';
import 'package:mesting_music/features/music_platform/data/music_platform_api.dart';
import 'package:mesting_music/features/music_platform/data/platform_session_store.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/music_platform/netease/netease_api.dart';
import 'package:mesting_music/features/music_platform/netease/netease_providers.dart';
import 'package:mesting_music/features/music_platform/retained_kugou_scope.dart';

const _a = PlatformSession(userId: '1', token: 'fixture-a', nickname: '甲');
const _b = PlatformSession(userId: '2', token: 'fixture-b', nickname: '乙');

class _Storage extends FlutterSecureStorage {
  final values = <String, String>{};
  int writes = 0;
  bool failAfterWrite = false;
  Completer<void>? nextWriteBarrier;
  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => values[key];
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
    final barrier = nextWriteBarrier;
    nextWriteBarrier = null;
    await barrier?.future;
    writes++;
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
    if (failAfterWrite) {
      failAfterWrite = false;
      throw StateError('fixture write ACK failed');
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
    values.remove(key);
  }
}

class _Server implements MusicServer {
  @override
  Future<Uri> start() async => Uri.parse('http://127.0.0.1:12400');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Storage storage;
  late SecureKugouAccountStore store;
  setUp(() {
    storage = _Storage();
    store = SecureKugouAccountStore(storage: storage);
  });
  test('legacy login migrates only after a durable new snapshot', () async {
    storage.values[SecurePlatformSessionStore.key] = jsonEncode(_a.toJson());
    expect((await store.read())?.token, _a.token);
    expect(storage.values[SecurePlatformSessionStore.key], isNull);
    expect(storage.values[SecureKugouAccountStore.key], isNotNull);
    await store.select(_b, loginMethod: 'phone');
    final restarted = SecureKugouAccountStore(storage: storage);
    expect((await restarted.read())?.userId, '2');
    expect((await restarted.snapshot()).accounts.map((a) => a.userId), [
      '1',
      '2',
    ]);
    expect((await restarted.snapshot()).accounts.last.methodLabel, '手机号登录');
  });
  test('ambiguous migration write never deletes the old login', () async {
    storage.values[SecurePlatformSessionStore.key] = jsonEncode(_a.toJson());
    storage.failAfterWrite = true;
    await expectLater(store.read(), throwsStateError);
    expect(
      storage.values[SecurePlatformSessionStore.key],
      jsonEncode(_a.toJson()),
    );
    expect((await store.read())?.userId, '1');
  });
  test(
    'same UID reauthentication replaces secrets and keeps its login method',
    () async {
      await store.select(_a, loginMethod: 'qqQr');
      await store.select(_b, loginMethod: 'wechatQr');
      await store.select(
        const PlatformSession(userId: '1', token: 'fixture-new'),
      );
      final snapshot = await store.snapshot();
      expect(snapshot.accounts.length, 2);
      expect(snapshot.accounts.last.methodLabel, 'QQ 扫码登录');
      expect(snapshot.selected?.token, 'fixture-new');
      expect((await store.account('2'))?.token, _b.token);
      expect(snapshot.accounts.toString(), isNot(contains('fixture-')));
    },
  );
  test(
    'sign out removes current credential and never resurrects legacy login',
    () async {
      storage.values[SecurePlatformSessionStore.key] = jsonEncode(_a.toJson());
      await store.read();
      await store.select(_b);
      await store.clear();
      final restarted = SecureKugouAccountStore(storage: storage);
      expect(await restarted.read(), isNull);
      expect((await restarted.snapshot()).accounts.map((a) => a.userId), ['1']);
      expect((await restarted.account('1'))?.token, _a.token);
      await restarted.remove('1');
      expect((await restarted.snapshot()).accounts, isEmpty);
      expect(await SecureKugouAccountStore(storage: storage).read(), isNull);
    },
  );
  test(
    'malformed encrypted snapshot is not treated as an empty list',
    () async {
      storage.values[SecureKugouAccountStore.key] = '{bad';
      await expectLater(store.select(_a), throwsFormatException);
      expect(storage.writes, 0);
      expect(storage.values[SecureKugouAccountStore.key], '{bad');
    },
  );
  test('failed change restores exact previous encrypted snapshot', () async {
    await store.select(_a);
    final raw = storage.values[SecureKugouAccountStore.key];
    storage.failAfterWrite = true;
    await expectLater(store.select(_b), throwsStateError);
    expect(storage.values[SecureKugouAccountStore.key], raw);
    expect((await store.read())?.userId, '1');
    expect(await store.account('2'), isNull);
  });
  test(
    'concurrent additions and removal serialize without losing another UID',
    () async {
      await Future.wait([store.select(_a), store.select(_b)]);
      await Future.wait([
        store.remove('1'),
        store.select(_b, loginMethod: 'phone'),
      ]);
      expect((await store.snapshot()).accounts.map((a) => a.userId), ['2']);
      expect((await store.read())?.token, _b.token);
    },
  );

  test(
    'standard authorization is retained alongside the same UID Lite login',
    () async {
      await store.select(
        const PlatformSession(
          userId: '1',
          token: 'lite-a',
          kugouStandardToken: 'standard-a',
        ),
      );
      await store.select(
        const PlatformSession(userId: '1', token: 'lite-a-new'),
      );
      final saved = await store.read();
      expect(saved?.token, 'lite-a-new');
      expect(saved?.kugouOfficialToken, 'standard-a');
      expect(saved?.kugouAppId, 1005);
      await store.select(_b);
      expect((await store.read())?.kugouAppId, 3116);
      expect((await store.read())?.kugouStandardToken, isEmpty);
      final restarted = SecureKugouAccountStore(storage: storage);
      expect((await restarted.account('1'))?.kugouStandardToken, 'standard-a');
    },
  );

  Future<ProviderContainer> accountContainer() async {
    await store.select(_b);
    await store.select(_a);
    SharedPreferences.setMockInitialValues({
      BetaAccountChoiceController.preferenceKey: 'kugou',
    });
    final api = MusicPlatformApi(
      server: _Server(),
      client: MockClient((_) async => http.Response('{"status":1}', 200)),
    );
    final container = ProviderContainer(
      overrides: [
        platformSessionStoreProvider.overrideWithValue(store),
        sharedPreferencesProvider.overrideWithValue(
          await SharedPreferences.getInstance(),
        ),
        musicPlatformApiProvider.overrideWithValue(api),
        neteaseApiProvider.overrideWithValue(
          NeteaseApi(MockClient((_) async => http.Response('{}', 200))),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(platformAccountProvider.future);
    return container;
  }

  test(
    'switch pauses and saves departing owner before publishing destination',
    () async {
      final container = await accountContainer();
      final controller = container.read(platformAccountProvider.notifier);
      final order = <String>[];
      controller.preparePlatformSwitch = (owner) async {
        order.add(
          '${container.read(platformAccountProvider).value?.ownerId}->$owner',
        );
        expect((await store.read())?.userId, '1');
      };
      await controller.switchKugouAccount('2');
      expect(order, ['kugou:1->kugou:2']);
      expect(container.read(platformAccountProvider).value?.userId, '2');
      expect(container.read(musicPlatformApiProvider).session?.token, _b.token);
      expect(container.read(retainedKugouSessionProvider)?.token, _b.token);
      expect((await store.account('1'))?.token, _a.token);
      await controller.switchKugouAccount('2');
      expect(order.length, 1, reason: 'selecting current account is a no-op');
    },
  );
  test(
    'same UID standard authorization keeps primary token and does not reset playback',
    () async {
      final container = await accountContainer();
      final controller = container.read(platformAccountProvider.notifier);
      controller.preparePlatformSwitch = (_) async =>
          fail('same owner authorization must not reset playback');
      await controller.acceptKugouStandard({
        'userid': '1',
        'token': 'standard-a',
        'mesting_kugou_appid': 1005,
      }, expected: _a);
      final value = container.read(platformAccountProvider).value!;
      expect(value.token, _a.token);
      expect(value.kugouOfficialToken, 'standard-a');
      expect(value.ownerId, _a.ownerId);
      expect((await store.read())?.kugouStandardToken, 'standard-a');
      await expectLater(
        controller.acceptKugouStandard({
          'userid': '2',
          'token': 'wrong',
          'mesting_kugou_appid': 1005,
        }, expected: _a),
        throwsA(isA<MusicPlatformException>()),
      );
      expect(
        container.read(platformAccountProvider).value?.kugouOfficialToken,
        'standard-a',
      );
    },
  );
  test(
    'late standard login cannot attach to a different selected account',
    () async {
      final container = await accountContainer();
      final controller = container.read(platformAccountProvider.notifier);
      await controller.switchKugouAccount('2');
      await expectLater(
        controller.acceptKugouStandard({
          'userid': '1',
          'token': 'late',
          'mesting_kugou_appid': 1005,
        }, expected: _a),
        throwsA(isA<MusicPlatformException>()),
      );
      expect(container.read(platformAccountProvider).value?.userId, '2');
      expect((await store.account('1'))?.kugouStandardToken, isEmpty);
    },
  );
  test(
    'cancelled standard authorization rolls back a delayed secure write',
    () async {
      final container = await accountContainer();
      final controller = container.read(platformAccountProvider.notifier);
      final blocked = Completer<void>();
      storage.nextWriteBarrier = blocked;
      var current = true;
      final pending = controller.acceptKugouStandard(
        {'userid': '1', 'token': 'new-standard', 'mesting_kugou_appid': 1005},
        expected: _a,
        isCurrent: () => current,
      );
      final outcome = expectLater(
        pending,
        throwsA(isA<MusicPlatformException>()),
      );
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      current = false;
      blocked.complete();
      await outcome;
      expect(
        container.read(platformAccountProvider).value?.kugouStandardToken,
        isEmpty,
      );
      expect((await store.read())?.kugouStandardToken, isEmpty);
    },
  );
  test(
    'failed account persistence keeps live identity and selected login',
    () async {
      final container = await accountContainer();
      storage.failAfterWrite = true;
      await expectLater(
        container
            .read(platformAccountProvider.notifier)
            .switchKugouAccount('2'),
        throwsStateError,
      );
      expect(container.read(platformAccountProvider).value?.userId, '1');
      expect(container.read(musicPlatformApiProvider).session?.token, _a.token);
      expect((await store.read())?.userId, '1');
      expect((await store.snapshot()).accounts.length, 2);
    },
  );
}
