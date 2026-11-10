import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/features/music_platform/discovery_startup_cache.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/music_platform/presentation/platform_home_visit.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_pages.dart';
import 'package:mesting_music/features/auth/beta_account_choice.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Accounts extends PlatformAccountController {
  @override
  Future<PlatformSession?> build() async => const PlatformSession(
    userId: 'synthetic',
    token: 'synthetic',
    platform: MusicPlatform.netease,
  );
  void selectForTest() => state = const AsyncData(
    PlatformSession(
      userId: 'other-synthetic',
      token: 'synthetic',
      platform: MusicPlatform.kugou,
    ),
  );
}

class _Mount extends StatefulWidget {
  const _Mount(this.onMount);
  final VoidCallback onMount;
  @override
  State<_Mount> createState() => _MountState();
}

class _MountState extends State<_Mount> {
  @override
  void initState() {
    super.initState();
    widget.onMount();
  }

  @override
  Widget build(BuildContext context) => const Text('prepared catalog');
}

void main() {
  testWidgets(
    'covered catalog mounts once after owner and visit are prepared',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        BetaAccountChoiceController.preferenceKey: 'netease',
      });
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          platformAccountProvider.overrideWith(_Accounts.new),
        ],
      );
      var mounts = 0;
      await container.read(platformAccountProvider.future);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: QishuiRootSwitch(
              root: QishuiRoot.discover,
              child: _Mount(() => mounts++),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(mounts, 1);
      final gate = container.read(platformPresentationSwitchProvider.notifier);
      gate.hold();
      await tester.pump();
      (container.read(platformAccountProvider.notifier) as _Accounts)
          .selectForTest();
      await tester.pump();
      container
          .read(platformHomeVisitProvider.notifier)
          .begin(DiscoveryStartupCache());
      await tester.pump();
      expect(
        mounts,
        1,
        reason: 'Neither publication nor visit may build a hidden new catalog',
      );
      gate.release();
      await tester.pumpAndSettle();
      expect(mounts, 2);
      expect(find.text('prepared catalog'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      container.dispose();
    },
  );
}
