import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/features/music_platform/data/embedded_music_server.dart';
import 'package:mesting_music/features/music_platform/data/music_platform_api.dart';
import 'package:mesting_music/features/music_platform/data/platform_session_store.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/music_platform/netease/netease_providers.dart';
import 'package:mesting_music/features/music_platform/netease/netease_session.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_api.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_providers.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_session.dart';
import 'qishui_protocol_test.dart'
    show sodaSession, fixtureContext, fixtureJson;

class MemorySodaStore implements QishuiSessionStore {
  QishuiSession? value;
  bool failWrite = false;
  int writes = 0, clears = 0;
  @override
  Future<QishuiSession?> read() async => value;
  @override
  Future<void> write(QishuiSession session) async {
    if (failWrite) throw StateError('fixture storage refusal');
    writes++;
    value = session;
  }

  @override
  Future<void> clear() async {
    clears++;
    value = null;
  }
}

class MemoryKugouStore implements PlatformSessionStore {
  PlatformSession? value;
  @override
  Future<PlatformSession?> read() async => value;
  @override
  Future<void> write(PlatformSession session) async {
    value = session;
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}

class MemoryNeteaseStore implements NeteaseSessionStore {
  NeteaseSession? value;
  @override
  Future<NeteaseSession?> read() async => value;
  @override
  Future<void> write(NeteaseSession session) async {
    value = session;
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}

class FixtureServer implements MusicServer {
  int starts = 0;
  @override
  Future<Uri> start() async {
    starts++;
    return Uri.parse('http://127.0.0.1:12345');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences preferences;
  late MemorySodaStore soda;
  late MemoryKugouStore kugou;
  late MemoryNeteaseStore netease;
  late QishuiApi api;
  late MusicPlatformApi kugouApi;
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'beta_active_account_v2': 'qishui',
    });
    preferences = await SharedPreferences.getInstance();
    soda = MemorySodaStore()..value = sodaSession();
    kugou = MemoryKugouStore()
      ..value = const PlatformSession(
        userId: 'fixture-kugou',
        token: 'fixture-kugou-token',
      );
    netease = MemoryNeteaseStore()
      ..value = const NeteaseSession(
        userId: 'fixture-netease',
        cookies: {'MUSIC_U': 'fixture-cookie'},
        deviceId: 'fixture-device',
      );
    api = QishuiApi(
      MockClient((_) async => fixtureJson({'status_code': 0})),
      context: fixtureContext,
    );
    kugouApi = MusicPlatformApi(
      server: FixtureServer(),
      client: MockClient((_) async => http.Response('{"status":1}', 200)),
    );
  });
  ProviderContainer container() => ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(preferences),
      qishuiSessionStoreProvider.overrideWithValue(soda),
      qishuiApiProvider.overrideWithValue(api),
      platformSessionStoreProvider.overrideWithValue(kugou),
      neteaseSessionStoreProvider.overrideWithValue(netease),
      musicPlatformApiProvider.overrideWithValue(kugouApi),
    ],
  );

  test(
    'switching among all three accounts keeps stores isolated and playback owners explicit',
    () async {
      final c = container();
      addTearDown(c.dispose);
      await c.read(platformAccountProvider.future);
      final controller = c.read(platformAccountProvider.notifier);
      final owners = <String>[];
      controller.preparePlatformSwitch = (owner) async {
        owners.add(owner);
      };
      await controller.switchPlatform(MusicPlatform.kugou);
      expect(api.session, isNull);
      expect(kugouApi.session?.userId, 'fixture-kugou');
      await controller.switchPlatform(MusicPlatform.netease);
      expect(kugouApi.session, isNull);
      await controller.switchPlatform(MusicPlatform.qishui);
      expect(
        c.read(platformAccountProvider).value?.ownerId,
        'qishui:fixture-user',
      );
      expect(owners, [
        'kugou:fixture-kugou',
        'netease:fixture-netease',
        'qishui:fixture-user',
      ]);
      expect(soda.clears, 0);
    },
  );
  test(
    'logout clears only the active Soda login and persists guest choice',
    () async {
      final c = container();
      addTearDown(c.dispose);
      await c.read(platformAccountProvider.future);
      await c.read(platformAccountProvider.notifier).signOut();
      expect(soda.value, isNull);
      expect(soda.clears, 1);
      expect(kugou.value, isNotNull);
      expect(netease.value, isNotNull);
      expect(preferences.getString('beta_active_account_v2'), 'guest');
      expect(api.session, isNull);
      expect(c.read(platformAccountProvider).value, isNull);
    },
  );
  test(
    'failed Soda save preserves the active Kugou login and retained Soda bytes',
    () async {
      await preferences.setString('beta_active_account_v2', 'kugou');
      final c = container();
      addTearDown(c.dispose);
      await c.read(platformAccountProvider.future);
      final original = soda.value;
      soda.failWrite = true;
      await expectLater(
        c
            .read(platformAccountProvider.notifier)
            .acceptQishui(sodaSession('new')),
        throwsStateError,
      );
      expect(
        c.read(platformAccountProvider).value?.platform,
        MusicPlatform.kugou,
      );
      expect(preferences.getString('beta_active_account_v2'), 'kugou');
      expect(identical(soda.value, original), isTrue);
      expect(kugouApi.session?.userId, 'fixture-kugou');
    },
  );
  test(
    'cancelled verified login cannot publish or change the selected account',
    () async {
      final c = container();
      addTearDown(c.dispose);
      final original = await c.read(platformAccountProvider.future);
      await expectLater(
        c
            .read(platformAccountProvider.notifier)
            .acceptQishui(sodaSession('new'), isCurrent: () => false),
        throwsA(isA<MusicPlatformException>()),
      );
      expect(
        identical(c.read(platformAccountProvider).value, original),
        isTrue,
      );
      expect(soda.writes, 0);
    },
  );
  test(
    'late token refresh after logout cannot recreate a credential',
    () async {
      final c = container();
      addTearDown(c.dispose);
      await c.read(platformAccountProvider.future);
      final previous = soda.value!;
      await c.read(platformAccountProvider.notifier).signOut();
      await c
          .read(platformAccountProvider.notifier)
          .persistQishuiRefresh(previous, previous.withProfile(name: 'late'));
      expect(soda.value, isNull);
      expect(soda.writes, 0);
    },
  );
  test(
    'Soda route guard blocks old anonymous HTTP before starting the Kugou server',
    () async {
      final server = FixtureServer();
      var requests = 0;
      final guarded = MusicPlatformApi(
        server: server,
        client: MockClient((_) async {
          requests++;
          return fixtureJson({});
        }),
        routeAllowed: (_) => false,
      );
      await expectLater(
        guarded.get('/search'),
        throwsA(isA<MusicPlatformException>()),
      );
      expect(requests, 0);
      expect(server.starts, 0);
    },
  );
  test(
    'refreshed secret bytes retain one login epoch across encrypted serialization',
    () {
      final original = sodaSession();
      final updated = QishuiSession(
        userId: original.userId,
        cookies: [
          {...original.cookies.single, 'value': 'fixture-rotated'},
        ],
        loginId: original.credentialId,
      );
      final restored = QishuiSession.fromJson(updated.toJson());
      expect(restored.credentialId, original.credentialId);
      expect(restored.cookies.single['value'], 'fixture-rotated');
    },
  );
}
