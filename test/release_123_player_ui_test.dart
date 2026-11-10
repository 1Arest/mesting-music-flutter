import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mesting_music/core/audio/mesting_audio_handler.dart';
import 'package:mesting_music/core/audio/playback_providers.dart';
import 'package:mesting_music/features/experience/presentation/beta_now_playing_page.dart';
import 'package:mesting_music/features/player/player_visual_style.dart';
import 'package:mesting_music/features/themes/app_theme.dart';
import 'package:mesting_music/features/themes/music_theme_preset.dart';
import 'package:mesting_music/features/music_platform/netease/netease_api.dart';
import 'package:mesting_music/features/music_platform/netease/netease_session.dart';
import 'package:mesting_music/features/music_platform/netease/netease_music_repository.dart';
import 'package:mesting_music/features/music_platform/netease/messages/netease_messages_repository.dart';
import 'package:mesting_music/features/music_platform/netease/together/netease_together_controller.dart';
import 'package:mesting_music/features/music_platform/netease/together/together_presence.dart';
import 'package:mesting_music/shared/models/track.dart';
import 'netease_v114_workflows_test.dart' show FakeTogetherPlayer;
import 'support/personal_profile_fixture.dart';
import 'support/deterministic_audio_player.dart';

class _Location extends TogetherLocationGateway {
  const _Location();
  @override
  Future<TogetherLocationFix> requestFix() async =>
      const TogetherLocationFix(30, 120, 100);
}

void main() {
  setUpAll(() async {
    await LiquidGlassWidgets.initialize();
    if (const bool.fromEnvironment('CAPTURE_TOGETHER123')) {
      for (final family in [
        'Roboto',
        'CupertinoSystemText',
        'CupertinoSystemDisplay',
        'Microsoft YaHei',
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
              'D:/flutter/mesting-beta5/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
            ).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
      await (FontLoader('packages/cupertino_icons/CupertinoIcons')..addFont(
            rootBundle.load(
              'packages/cupertino_icons/assets/CupertinoIcons.ttf',
            ),
          ))
          .load();
    }
  });

  for (final style in PlayerVisualStyle.values) {
    for (final narrow in [false, true]) {
      testWidgets('together in real player ${style.id} narrow=$narrow', (
        tester,
      ) async {
        const track = Track(
          id: 'netease_17',
          platformSongId: '17',
          source: TrackSource.netease,
          title: '晴天慢慢',
          artist: '固定测试艺人',
          album: '合成测试数据',
          duration: Duration(minutes: 4),
          coverAsset: profileFixtureCover,
          audioAsset: 'assets/fixture.mp3',
          lyricsAsset: '',
        );
        final dependencies = (await tester.runAsync(() async {
          final handler = MestingAudioHandler(
            tracks: [],
            player: DeterministicAudioPlayer(),
          );
          final player = FakeTogetherPlayer();
          final api =
              NeteaseApi(
                MockClient(
                  (r) async => http.Response(
                    jsonEncode({
                      'code': 200,
                      'data': r.url.path.endsWith('/status/get')
                          ? {
                              'inRoom': true,
                              'roomInfo': {
                                'roomId': 'fixture-room',
                                'roomUsers': [
                                  {
                                    'user': {
                                      'userId': 7,
                                      'nickname': '沐白',
                                      'avatar': profileFixtureCover,
                                    },
                                  },
                                  {
                                    'user': {
                                      'userId': 8,
                                      'nickname': '小满',
                                      'avatar': profileFixtureCover,
                                    },
                                  },
                                ],
                              },
                            }
                          : r.url.path.contains('statistics')
                          ? {'totalConnectionTime': 7260}
                          : r.url.path.endsWith('/distance/get')
                          ? {'distance': 12.34}
                          : {},
                    }),
                    200,
                    headers: {
                      'content-type': 'application/json; charset=utf-8',
                    },
                  ),
                ),
              )..configure(
                const NeteaseSession(
                  userId: '7',
                  cookies: {'MUSIC_U': 'fixture'},
                  deviceId: 'fixture',
                ),
              );
          final music = NeteaseMusicRepository(api);
          final controller = NeteaseTogetherController(
            music: music,
            player: player,
            messages: NeteaseMessagesRepository(music),
            isCurrent: () => true,
            automaticTimer: false,
            locationGateway: const _Location(),
          );
          await controller.restore();
          await controller.enableLocation();
          final fixture = await PersonalProfileFixture.create(
            audioHandler: handler,
            extraOverrides: [
              neteaseTogetherControllerProvider.overrideWithValue(controller),
              currentTrackProvider.overrideWithValue(track),
            ],
          );
          await fixture.container
              .read(playerVisualStyleProvider.notifier)
              .select(style);
          return (handler, player, controller, fixture);
        }))!;
        final (handler, player, controller, fixture) = dependencies;
        tester.view.devicePixelRatio = 2;
        tester.view.physicalSize = narrow
            ? const Size(640, 1300)
            : const Size(780, 1688);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: fixture.container,
            child: MaterialApp(
              theme: buildMestingTheme(musicThemePresetById('classic')),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(narrow ? 1.3 : 1)),
                child: child!,
              ),
              home: const RepaintBoundary(
                key: ValueKey('capture-player123'),
                child: BetaNowPlayingPage(),
              ),
            ),
          ),
        );
        await tester.runAsync(
          () => precacheImage(
            const AssetImage(profileFixtureCover),
            tester.element(find.byType(BetaNowPlayingPage)),
          ),
        );
        await tester.pump(const Duration(milliseconds: 800));
        await tester.pump(const Duration(milliseconds: 800));
        expect(
          find.byKey(const ValueKey('player-together-header')),
          findsOneWidget,
        );
        expect(find.text('相距约 12.34 公里'), findsOneWidget);
        expect(find.text('一起听了 2 小时 1 分钟'), findsOneWidget);
        expect(tester.takeException(), isNull);
        if (style == PlayerVisualStyle.cover && !narrow) {
          await tester.tap(find.byTooltip('更多操作'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          expect(find.text('退出一起听'), findsOneWidget);
          // The new share entry must coexist with Together and the narrow
          // menu; existing actions keep their original close-before-open flow.
          expect(find.text('分享歌曲'), findsOneWidget);
          await tester.tap(find.text('退出一起听'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          // The menu intentionally waits for route.completed before opening
          // a business dialog; paint its first frame after that completion.
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          expect(find.text('退出一起听？'), findsOneWidget);
          await tester.tap(find.text('取消'));
          await tester.pump(const Duration(milliseconds: 500));
          expect(controller.active, isTrue);
          expect(
            find.byKey(const ValueKey('player-together-header')),
            findsOneWidget,
          );
        }
        if (const bool.fromEnvironment('CAPTURE_TOGETHER123')) {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('capture-player123')),
          );
          await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 2);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            image.dispose();
            final dir = Directory('.codex-artifacts/2026-10-30-release123/ui')
              ..createSync(recursive: true);
            await File(
              '${dir.path}/${style.id}-${narrow ? 'narrow' : 'phone'}.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
          });
        }
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(() async {
          controller.dispose();
          await fixture.dispose();
          await player.close();
          await handler.debugDispose();
        });
      });
    }
  }
}
