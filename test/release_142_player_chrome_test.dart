import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mesting_music/core/audio/mesting_audio_handler.dart';
import 'package:mesting_music/core/audio/playback_providers.dart';
import 'package:mesting_music/features/experience/presentation/beta_now_playing_page.dart';
import 'package:mesting_music/features/experience/presentation/beta_music_shell.dart';
import 'package:mesting_music/features/experience/presentation/player_chrome_reveal.dart';
import 'package:mesting_music/features/experience/presentation/player_pull_to_dismiss.dart';
import 'package:mesting_music/features/music_platform/netease/together/netease_together_controller.dart';
import 'package:mesting_music/features/music_platform/netease/messages/netease_messages_repository.dart';
import 'package:mesting_music/features/music_platform/platform_backend_providers.dart';
import 'package:mesting_music/features/music_platform/retained_kugou_scope.dart';
import 'package:mesting_music/features/themes/app_theme.dart';
import 'package:mesting_music/features/themes/music_theme_preset.dart';
import 'package:mesting_music/shared/models/track.dart';
import 'package:mesting_music/shared/widgets/beta_music_chrome_scope.dart';
import 'package:mesting_music/shared/widgets/beta_page_route_observer.dart';

import 'support/deterministic_audio_player.dart';
import 'support/personal_profile_fixture.dart';
import 'netease_v114_workflows_test.dart' show FakeTogetherPlayer;

const _capture = bool.fromEnvironment('CAPTURE_V142_PLAYER');
const _captureKey = ValueKey('player142-capture');

void main() {
  setUpAll(() async {
    await LiquidGlassWidgets.initialize();
    if (!_capture) return;
    for (final family in [
      'V142QA',
      'Roboto',
      'CupertinoSystemText',
      'CupertinoSystemDisplay',
      'sans-serif',
    ]) {
      await (FontLoader(family)..addFont(
            File(
              'C:/Windows/Fonts/msyh.ttc',
            ).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
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

  testWidgets('a player stays covered while its popup is visible', (
    tester,
  ) async {
    final chrome = BetaMusicChromeController();
    final navigation = GlobalKey<NavigatorState>();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      chrome.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: BetaMusicChromeScope(
          controller: chrome,
          child: Navigator(
            key: navigation,
            observers: [BetaPageRouteObserver()],
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (_) => const ColoredBox(color: Colors.white),
            ),
          ),
        ),
      ),
    );
    unawaited(
      navigation.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const BetaMusicChromeCover(
            player: true,
            child: SizedBox.expand(key: ValueKey('player-surface')),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(chrome.covered, true);
    unawaited(
      showModalBottomSheet<void>(
        context: tester.element(find.byKey(const ValueKey('player-surface'))),
        builder: (_) => const SizedBox(height: 100, child: Text('Player menu')),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(
      chrome.covered,
      true,
      reason: 'A popup leaves the fullscreen player visible beneath it.',
    );
    navigation.currentState!.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(chrome.covered, true);
    unawaited(
      navigation.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Text('Next ordinary page'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(
      chrome.covered,
      false,
      reason: 'Another full page owns whether its own chrome is visible.',
    );
    navigation.currentState!.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(chrome.covered, true);
  });

  for (final source in [TrackSource.netease, TrackSource.kugou]) {
    testWidgets('a departed player cannot reveal the next player ${source.name}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final dependencies = (await tester.runAsync(() async {
        final handler = MestingAudioHandler(
          tracks: [],
          player: DeterministicAudioPlayer(),
        );
        final fixture = await PersonalProfileFixture.create(
          audioHandler: handler,
          extraOverrides: [
            savedKugouSessionProvider.overrideWith((ref) async => null),
            currentTrackProvider.overrideWithValue(
              Track(
                id: '${source.name}_17',
                platformSongId: '17',
                source: source,
                title: '合成播放器样本',
                artist: '合成测试',
                album: '合成数据',
                duration: const Duration(minutes: 4),
                coverAsset: profileFixtureCover,
                audioAsset: '',
                lyricsAsset: '',
              ),
            ),
            currentMediaItemProvider.overrideWith(
              (ref) => Stream.value(
                MediaItem(
                  id: '${source.name}_17',
                  title: '合成播放器样本',
                  artist: '合成测试',
                ),
              ),
            ),
            neteaseTogetherControllerProvider.overrideWith((ref) {
              if (source != TrackSource.netease) return null;
              final music = ref.read(neteaseMusicRepositoryProvider);
              final roomPlayer = FakeTogetherPlayer();
              final controller =
                  NeteaseTogetherController(
                      music: music,
                      player: roomPlayer,
                      messages: NeteaseMessagesRepository(music),
                      isCurrent: () => true,
                      automaticTimer: false,
                    )
                    ..roomId = 'synthetic-player-room'
                    ..members = const [
                      NeteasePerson('7001', '合成测试本人', profileFixtureCover),
                      NeteasePerson('7002', '合成测试好友', profileFixtureCover),
                    ];
              ref.onDispose(() {
                controller.dispose();
                unawaited(roomPlayer.close());
              });
              return controller;
            }),
          ],
        );
        return (handler, fixture);
      }))!;
      final (handler, fixture) = dependencies;
      final navigation = GlobalKey<NavigatorState>();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(() async {
          await fixture.dispose();
          await handler.debugDispose();
        });
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: fixture.container,
          child: MaterialApp(
            theme: buildMestingTheme(musicThemePresetById('classic')),
            home: RepaintBoundary(
              key: _captureKey,
              child: BetaMusicShell(
                location: '/profile',
                child: Navigator(
                  key: navigation,
                  observers: [BetaPageRouteObserver()],
                  onGenerateRoute: (_) => MaterialPageRoute<void>(
                    builder: (_) => const Text('Feature entry'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      unawaited(
        navigation.currentState!.push(
          MaterialPageRoute<void>(builder: (_) => const BetaNowPlayingPage()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      final oldProgress = tester
          .widget<PlayerPullToDismiss>(find.byType(PlayerPullToDismiss))
          .onProgress!;
      unawaited(
        navigation.currentState!.push(
          MaterialPageRoute<void>(builder: (_) => const BetaNowPlayingPage()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      final currentProgress = tester
          .widget<PlayerPullToDismiss>(find.byType(PlayerPullToDismiss))
          .onProgress!;
      final signal = fixture.container.read(playerChromeRevealProvider);
      expect(signal.value, 0);
      // Model the late final callback of a previously dragged/dismissing page.
      // The mounted production page supplied both callbacks, not a mock signal.
      oldProgress(1);
      await tester.pump();
      expect(
        signal.value,
        0,
        reason: 'Only the current player may expose the shared glass bars.',
      );
      if (_capture) {
        await tester.runAsync(
          () => precacheImage(
            const AssetImage(profileFixtureCover),
            tester.element(find.byType(BetaNowPlayingPage)),
          ),
        );
        await tester.pump();
        await tester.runAsync(() async {
          final image = await tester
              .renderObject<RenderRepaintBoundary>(find.byKey(_captureKey))
              .toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File(
            '.codex-artifacts/2026-11-02-release142-record-duration/ui/player-${source.name}-after-stale-callback.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      currentProgress(.4);
      await tester.pump();
      expect(signal.value, .4);
      navigation.currentState!.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      oldProgress(.2);
      await tester.pump();
      expect(
        signal.value,
        .2,
        reason: 'Returning restores the previous player animation owner.',
      );
      expect(tester.takeException(), isNull);
    });
  }
}
