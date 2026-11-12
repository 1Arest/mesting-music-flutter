import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mesting_music/features/music_platform/domain/membership_badge.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/music_platform/membership_badge_provider.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/music_platform/netease/netease_playback_options.dart';
import 'package:mesting_music/features/music_platform/presentation/beta_personal_profile.dart';
import 'package:mesting_music/features/player/sharing/song_share.dart';
import 'package:mesting_music/features/player/sharing/song_share_sheet.dart';
import 'package:mesting_music/features/profile/presentation/vip_profile_effects.dart';
import 'package:mesting_music/shared/models/track.dart';
import 'package:mesting_music/shared/widgets/beta_music_chrome_scope.dart';
import 'package:mesting_music/shared/widgets/beta_root_tab_viewport.dart';
import 'support/personal_profile_fixture.dart';
import 'support/pump_artwork_ready.dart';

const _capture = bool.fromEnvironment('CAPTURE_UI190');
const _boundary = ValueKey('pr190-render');

class _Account extends PlatformAccountController {
  _Account(this.platform);
  final MusicPlatform platform;
  @override
  Future<PlatformSession?> build() async => PlatformSession(
    userId: '7001',
    token: 'fixture-only',
    nickname: '固定测试账号',
    platform: platform,
  );
}

Future<void> _capturePage(WidgetTester tester, String name) async {
  if (!_capture) return;
  await tester.runAsync(() async {
    final render = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_boundary),
    );
    final image = await render.toImage();
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('.codex-artifacts/2026-11-10-ui190/ui-final/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(png!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await LiquidGlassWidgets.initialize();
    if (!_capture) return;
    // Host QA aliases are loaded only by the capture define, never the app.
    final bytes = await File('C:/Windows/Fonts/msyh.ttc').readAsBytes();
    for (final family in [
      'MestingQA',
      'Ahem',
      'Roboto',
      'sans-serif',
      'CupertinoSystemText',
      'CupertinoSystemDisplay',
    ]) {
      await (FontLoader(
        family,
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    }
    await (FontLoader('MaterialIcons')..addFont(
          File(
            'D:/CodexCache/flutter-3.41.9/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
          ).readAsBytes().then(ByteData.sublistView),
        ))
        .load();
    await (FontLoader('packages/cupertino_icons/CupertinoIcons')..addFont(
          rootBundle.load('packages/cupertino_icons/assets/CupertinoIcons.ttf'),
        ))
        .load();
  });

  test(
    'refreshing official facts never reuses the previous account tier',
    () async {
      var request = Completer<MembershipBadgeTier?>();
      final container = ProviderContainer(
        overrides: [
          officialMembershipBadgeProvider.overrideWith((ref) => request.future),
          neteaseLocalSvipProvider.overrideWithValue(false),
        ],
      );
      addTearDown(container.dispose);
      expect(container.read(membershipPresentationTierProvider), isNull);
      request.complete(MembershipBadgeTier.svip);
      await container.read(officialMembershipBadgeProvider.future);
      expect(
        container.read(membershipPresentationTierProvider),
        MembershipBadgeTier.svip,
      );
      request = Completer<MembershipBadgeTier?>();
      container.invalidate(officialMembershipBadgeProvider);
      expect(container.read(membershipPresentationTierProvider), isNull);
      request.complete(null);
      await container.read(officialMembershipBadgeProvider.future);
      expect(container.read(membershipPresentationTierProvider), isNull);
    },
  );

  for (final large in [false, true]) {
    for (final platform in [MusicPlatform.netease, MusicPlatform.kugou]) {
      for (final official in [
        MembershipBadgeTier.vip,
        MembershipBadgeTier.svip,
        null,
      ]) {
        testWidgets(
          'profile ${platform.name} official=$official large=$large keeps unified badge',
          (tester) async {
            tester.view.physicalSize = Size(large ? 320 : 390, 844);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);
            final local = platform == MusicPlatform.netease;
            final fixture = await PersonalProfileFixture.create(
              accountFactory: () => _Account(platform),
              extraOverrides: [
                officialMembershipBadgeProvider.overrideWith(
                  (ref) async => official,
                ),
                neteaseLocalSvipProvider.overrideWithValue(local),
              ],
            );
            addTearDown(() async {
              await tester.pumpWidget(const SizedBox());
              await fixture.dispose();
            });
            final base = ThemeData(
              brightness: large ? Brightness.dark : Brightness.light,
            );
            await tester.pumpWidget(
              UncontrolledProviderScope(
                container: fixture.container,
                child: RepaintBoundary(
                  key: _boundary,
                  child: MaterialApp(
                    debugShowCheckedModeBanner: false,
                    theme: _capture
                        ? base.copyWith(
                            textTheme: base.textTheme.apply(
                              fontFamily: 'MestingQA',
                            ),
                          )
                        : base,
                    builder: (context, child) => MediaQuery(
                      data: MediaQuery.of(context).copyWith(
                        textScaler: TextScaler.linear(large ? 2 : 1),
                        disableAnimations: !_capture,
                      ),
                      child: child!,
                    ),
                    home: const Scaffold(body: BetaPersonalProfile()),
                  ),
                ),
              ),
            );
            await pumpArtworkReady(tester);
            await tester.pump(const Duration(milliseconds: 600));
            final tier =
                official ?? (local ? MembershipBadgeTier.supreme : null);
            expect(
              fixture.container.read(membershipPresentationTierProvider),
              tier,
            );
            final label = switch (tier) {
              MembershipBadgeTier.vip => 'VIP',
              MembershipBadgeTier.svip => 'SVIP',
              MembershipBadgeTier.supreme => '至尊SVIP',
              null => null,
            };
            expect(find.text('本地 SVIP · 至尊'), findsNothing);
            if (label != null) {
              expect(find.text(label), findsOneWidget);
              expect(find.text('ID 7001'), findsOneWidget);
              expect(find.byType(VipGoldText), findsNWidgets(2));
            } else {
              expect(find.byType(VipGoldText), findsNothing);
              expect(find.text('ID 7001'), findsNothing);
            }
            expect(tester.takeException(), isNull);
            await _capturePage(
              tester,
              'profile-${platform.name}-${label ?? 'none'}-${large ? '320-dark-2x' : '390-light'}',
            );
            if (_capture &&
                platform == MusicPlatform.netease &&
                official == MembershipBadgeTier.svip &&
                !large) {
              await tester.pump(const Duration(milliseconds: 1800));
              await _capturePage(tester, 'profile-netease-SVIP-phase2');
            }
          },
        );
      }
    }
    testWidgets('share sheet uses live production controls large=$large', (
      tester,
    ) async {
      tester.view.physicalSize = Size(large ? 320 : 390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final theme = ThemeData(
        brightness: large ? Brightness.dark : Brightness.light,
      );
      final track = Track(
        id: 'netease_123',
        title: '一起听这首歌',
        artist: '合成歌手',
        album: '',
        duration: Duration.zero,
        source: TrackSource.netease,
        audioAsset: '',
        coverAsset: profileFixtureCover,
        lyricsAsset: '',
      );
      await tester.pumpWidget(
        RepaintBoundary(
          key: _boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: _capture
                ? theme.copyWith(
                    textTheme: theme.textTheme.apply(fontFamily: 'MestingQA'),
                  )
                : theme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(large ? 2 : 1)),
              child: child!,
            ),
            home: Scaffold(
              body: Builder(
                builder: (context) => Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.asset(profileFixtureCover, fit: BoxFit.cover),
                    Center(
                      child: TextButton(
                        onPressed: () => showSongShareSheet(context, track),
                        child: const Text('打开分享'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开分享'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('分享链接给微信好友'), findsOneWidget);
      await _capturePage(
        tester,
        'share-sheet-${large ? '320-dark-2x' : '390-light'}',
      );
      if (_capture) {
        final png = await tester.runAsync(
          () => generateSongPoster(track, fontFamily: 'MestingQA'),
        );
        final file = File(
          '.codex-artifacts/2026-11-10-ui190/ui-final/song-poster-${large ? 'dark-host' : 'light-host'}.png',
        );
        // File IO must leave the widget fake-async zone as well as decoding;
        // otherwise a screenshot-only run can wait forever on its file close.
        await tester.runAsync(() => file.writeAsBytes(png!));
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
    'profile effects pause for shared chrome cover and retained hidden tab',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final chrome = BetaMusicChromeController();
      addTearDown(chrome.dispose);
      final avatar = VipEffectAnchorHandle();
      final owner = Object();
      Widget host(bool visible) => ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: MaterialApp(
          home: BetaMusicChromeScope(
            controller: chrome,
            child: BetaTabVisibility(
              visible: visible,
              child: Scaffold(
                body: VipProfileEffects(
                  enabled: true,
                  avatarKey: avatar,
                  child: Center(
                    child: VipEffectAnchor(
                      handle: avatar,
                      child: const SizedBox(width: 104, height: 104),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(host(true));
      await tester.pump();
      expect(tester.hasRunningAnimations, isTrue);
      chrome.cover(owner, player: true);
      await tester.pump();
      expect(tester.hasRunningAnimations, isFalse);
      chrome.uncover(owner);
      await tester.pump();
      expect(tester.hasRunningAnimations, isTrue);
      await tester.pumpWidget(host(false));
      await tester.pump();
      expect(tester.hasRunningAnimations, isFalse);
      await tester.pumpWidget(host(true));
      await tester.pump();
      expect(tester.hasRunningAnimations, isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
