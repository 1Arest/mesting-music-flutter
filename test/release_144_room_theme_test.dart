import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/core/audio/playback_providers.dart';
import 'package:mesting_music/features/experience/presentation/music_functions_page.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/music_platform/netease/netease_login.dart';
import 'package:mesting_music/features/music_platform/netease/netease_music_repository.dart';
import 'package:mesting_music/features/music_platform/netease/messages/netease_messages_repository.dart';
import 'package:mesting_music/features/music_platform/netease/together/netease_together_controller.dart';
import 'package:mesting_music/features/music_platform/netease/together/netease_together_panel.dart';
import 'package:mesting_music/features/music_platform/netease/together/together_room_members.dart';
import 'package:mesting_music/features/music_platform/presentation/platform_account_page.dart';
import 'package:mesting_music/features/themes/beta_appearance.dart';
import 'package:mesting_music/features/themes/music_application_theme.dart';
import 'package:mesting_music/features/themes/music_theme_tokens.dart';
import 'package:mesting_music/shared/models/track.dart';
import 'package:mesting_music/shared/widgets/beta_glass_controls.dart';

import 'support/personal_profile_fixture.dart';
import 'support/release_144_qa.dart';

class _Music extends Fake implements NeteaseMusicRepository {}

class _Player extends Fake implements NeteaseTogetherPlayer {}

class _Messages extends Fake implements NeteaseMessagesRepository {
  @override
  Future<List<NeteasePerson>> friends([int offset = 0]) async => const [
    NeteasePerson('friend', '合成好友', profileFixtureCover),
    NeteasePerson('other', '另一位好友', profileFixtureCover),
  ];
}

class _Room extends NeteaseTogetherController {
  _Room()
    : super(
        music: _Music(),
        player: _Player(),
        messages: _Messages(),
        isCurrent: () => true,
        automaticTimer: false,
      );
  @override
  NeteasePerson get self =>
      const NeteasePerson('me', '合成测试账号', profileFixtureCover);
  @override
  Future<void> restore() async {}
  void show({bool paired = true}) {
    roomId = 'synthetic-room';
    members = [
      self,
      if (paired) const NeteasePerson('friend', '合成好友', profileFixtureCover),
    ];
    notifyListeners();
  }
}

void main() {
  setUpAll(initialize144QA);

  Future<PersonalProfileFixture> fixture(
    WidgetTester tester,
    _Room room,
  ) async {
    final result = (await tester.runAsync(
      () => PersonalProfileFixture.create(
        extraOverrides: [
          neteaseTogetherControllerProvider.overrideWithValue(room),
          neteaseMessagesRepositoryProvider.overrideWithValue(_Messages()),
          currentTrackProvider.overrideWithValue(
            const Track(
              id: 'local_qa',
              title: '本机合成歌曲',
              artist: '合成艺术家',
              album: '',
              duration: Duration(minutes: 3),
              audioAsset: '',
              lyricsAsset: '',
              coverAsset: '',
            ),
          ),
        ],
      ),
    ))!;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(result.dispose);
      room.dispose();
    });
    return result;
  }

  Future<void> mount(
    WidgetTester tester,
    PersonalProfileFixture data,
    Widget page, {
    bool dark = false,
    Size size = const Size(390, 844),
    double scale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: data.container,
        child: MaterialApp(
          theme: theme144(dark),
          builder: (context, child) => MusicApplicationTheme(
            data: Theme.of(context),
            child: MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: capture144Builder(context, child),
            ),
          ),
          home: page,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 650));
  }

  for (final dark in [false, true]) {
    testWidgets(
      'room sheet follows app appearance under dark player, dark=$dark',
      (tester) async {
        final room = _Room()..show();
        final data = await fixture(tester, room);
        await mount(
          tester,
          data,
          Theme(
            data: theme144(true),
            child: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => showNeteaseTogetherPanel(context),
                    child: const Text('管理一起听'),
                  ),
                ),
              ),
            ),
          ),
          dark: dark,
        );
        await tester.tap(find.text('管理一起听'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 650));
        final members = find.byType(TogetherRoomMembers);
        expect(members, findsOneWidget);
        final scheme = Theme.of(tester.element(members)).colorScheme;
        expect(scheme.brightness, dark ? Brightness.dark : Brightness.light);
        expect(find.text('邀请好友'), findsNothing);
        expect(find.text('复制邀请链接'), findsNothing);
        final first = tester.getRect(
          find.byKey(const ValueKey('together-room-self-avatar')),
        );
        final second = tester.getRect(
          find.byKey(const ValueKey('together-room-peer-avatar')),
        );
        expect(first.overlaps(second), isTrue);
        expect(first.top, second.top);
        final names = tester.widget<Text>(find.text('合成测试账号 · 合成好友'));
        expect(names.style!.color, scheme.onSurface);
        expect(tester.takeException(), isNull);
        await capture144UI(
          tester,
          'together-paired-${dark ? 'dark' : 'light'}',
        );
        // The same mounted room must restore invitation controls when the peer
        // leaves. No refresh, close/reopen or second controller is involved.
        room.show(paired: false);
        await tester.pump();
        expect(find.text('邀请好友'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('together-room-peer-avatar')),
          findsNothing,
        );
        room.show();
        await tester.pump();
        expect(find.text('邀请好友'), findsNothing);
      },
    );
  }

  testWidgets(
    'retained functions follow the complete application palette across switches',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final room = _Room();
      final data = await fixture(tester, room);
      final appearance = ValueNotifier(theme144(false));
      addTearDown(appearance.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: data.container,
          child: ValueListenableBuilder(
            valueListenable: appearance,
            builder: (context, theme, _) => MaterialApp(
              theme: theme,
              builder: (context, child) => MusicApplicationTheme(
                data: Theme.of(context),
                child: capture144Builder(context, child),
              ),
              home: Theme(
                data: theme144(true),
                child: const Scaffold(body: MusicFunctionsPage()),
              ),
            ),
          ),
        ),
      );
      for (final dark in [false, true, false]) {
        appearance.value = theme144(dark);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 650));
        final tile = tester.widget<CupertinoButton>(
          find.byKey(const ValueKey('function-私人 FM')),
        );
        expect(
          tile.color,
          BetaAppearance.panel(dark ? Brightness.dark : Brightness.light),
        );
        final label = tester.widget<Text>(find.text('私人 FM'));
        expect(
          label.style!.color,
          theme144(dark).extension<MusicThemeTokens>()!.textPrimary,
        );
        expect(tester.takeException(), isNull);
        await capture144UI(tester, 'functions-${dark ? 'dark' : 'light'}');
      }
    },
  );

  testWidgets('compact large-text members retain both names without overflow', (
    tester,
  ) async {
    final room = _Room()..show();
    final data = await fixture(tester, room);
    await mount(
      tester,
      data,
      const NeteaseTogetherPanel(),
      size: const Size(320, 700),
      scale: 1.5,
    );
    expect(find.text('合成测试账号 · 合成好友'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await capture144UI(tester, 'together-light-large-text');
  });

  testWidgets(
    'current-account buttons have independent separated touch bounds',
    (tester) async {
      final room = _Room();
      final data = await fixture(tester, room);
      await mount(
        tester,
        data,
        const PlatformAccountPage(
          platform: MusicPlatform.netease,
          neteaseMethod: NeteaseLoginMethod.sms,
        ),
      );
      final refresh = find.widgetWithText(BetaGlassButton, '刷新网易云登录状态');
      final logout = find.widgetWithText(BetaGlassButton, '退出登录');
      expect(refresh, findsOneWidget);
      expect(
        tester.getTopLeft(logout).dy - tester.getBottomLeft(refresh).dy,
        greaterThanOrEqualTo(16),
      );
      expect(tester.takeException(), isNull);
      await capture144UI(tester, 'account-light-spacing');
    },
  );

  test('full room blocks an invitation from any entry point', () async {
    final room = _Room()..show();
    addTearDown(room.dispose);
    // The fake repository deliberately has no send implementation. Reaching
    // it would fail this test rather than silently accepting a synthetic send.
    await room.invite(const NeteasePerson('other', '其他好友', ''));
    expect(room.notice, '已有好友正在一起听');
  });
}
