import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/features/auth/beta_account_choice.dart';
import 'package:mesting_music/features/music_platform/data/platform_session_store.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/music_platform/netease/netease_api.dart';
import 'package:mesting_music/features/music_platform/netease/netease_session.dart';
import 'package:mesting_music/features/music_platform/netease/netease_providers.dart';
import 'package:mesting_music/features/music_platform/retained_kugou_scope.dart';

const net = NeteaseSession(
  userId: 'net',
  cookies: {'MUSIC_U': 'fake-cookie'},
  deviceId: 'fake-device',
);

class _UI extends PlatformAccountController {
  @override
  Future<PlatformSession?> build() async => net.identity;
}

class _KGStore implements PlatformSessionStore {
  PlatformSession? value;
  @override
  Future<PlatformSession?> read() async => value;
  @override
  Future<void> write(PlatformSession s) async {
    value = s;
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}

class _NEStore implements NeteaseSessionStore {
  NeteaseSession? value;
  @override
  Future<NeteaseSession?> read() async => value;
  @override
  Future<void> write(NeteaseSession s) async {
    value = s;
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'supplementary Kugou login preserves active NetEase choice, identity and player namespace',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = _KGStore();
      var prepared = 0;
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(
            await SharedPreferences.getInstance(),
          ),
          platformAccountProvider.overrideWith(_UI.new),
          platformSessionStoreProvider.overrideWithValue(store),
        ],
      );
      addTearDown(container.dispose);
      await container.read(platformAccountProvider.future);
      await container
          .read(betaAccountChoiceProvider.notifier)
          .select(BetaAccountChoice.netease);
      final c = container.read(platformAccountProvider.notifier)
        ..preparePlatformSwitch = ((_) async {
          prepared++;
        });
      await c.accept({
        'userid': 'kg',
        'token': 'fake-kugou',
      }, retainCurrentPlatform: true);
      expect(store.value!.userId, 'kg');
      expect(
        container.read(platformAccountProvider).value!.ownerId,
        net.identity.ownerId,
      );
      expect(
        container.read(platformAccountProvider).value!.token,
        net.identity.token,
      );
      expect(
        container.read(betaAccountChoiceProvider),
        BetaAccountChoice.netease,
      );
      expect(container.read(retainedKugouSessionProvider)!.userId, 'kg');
      expect(prepared, 0);
    },
  );
  test(
    'supplementary NetEase login saves own cookie and epoch without configuring the active client',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = _NEStore();
      final api = NeteaseApi(
        MockClient((_) async => throw StateError('No live requests')),
      );
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(
            await SharedPreferences.getInstance(),
          ),
          platformAccountProvider.overrideWith(_KGUI.new),
          neteaseSessionStoreProvider.overrideWithValue(store),
          neteaseApiProvider.overrideWithValue(api),
        ],
      );
      addTearDown(container.dispose);
      await container.read(platformAccountProvider.future);
      await container
          .read(betaAccountChoiceProvider.notifier)
          .select(BetaAccountChoice.kugou);
      var prepared = 0;
      container
          .read(platformAccountProvider.notifier)
          .preparePlatformSwitch = (_) async {
        prepared++;
      };
      await container
          .read(platformAccountProvider.notifier)
          .acceptNetease(net, retainCurrentPlatform: true);
      expect(store.value, net);
      expect(api.session, isNull);
      expect(container.read(retainedNeteaseEpochProvider), 1);
      expect(
        container.read(platformAccountProvider).value!.platform,
        MusicPlatform.kugou,
      );
      expect(
        container.read(betaAccountChoiceProvider),
        BetaAccountChoice.kugou,
      );
      expect(prepared, 0);
    },
  );
}

class _KGUI extends PlatformAccountController {
  @override
  Future<PlatformSession?> build() async =>
      const PlatformSession(userId: 'kg', token: 'fake-kugou');
}
