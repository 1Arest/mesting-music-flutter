import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mesting_music/core/audio/mesting_audio_handler.dart';
import 'package:mesting_music/features/app_update/presentation/apple_download_progress.dart';
import 'package:mesting_music/features/downloads/audio_downloads.dart';
import 'package:mesting_music/features/experience/presentation/beta_bottom_bar.dart';
import 'package:mesting_music/features/music_platform/data/platform_effects_repository.dart';
import 'package:mesting_music/features/themes/app_theme.dart';
import 'package:mesting_music/features/themes/music_theme_preset.dart';
import 'package:mesting_music/shared/utils/media_uri.dart';
import 'package:mesting_music/shared/widgets/beta_bottom_search.dart';
import 'package:mesting_music/shared/widgets/beta_glass_scroll_body.dart';
import 'package:mesting_music/shared/widgets/beta_page_search_layout.dart';
import 'package:mesting_music/shared/widgets/beta_swipe_pages.dart';
import 'package:mesting_music/shared/widgets/music_feature_page.dart';
import 'netease_v112_fallback_download_test.dart' show recording, until;
import 'support/deterministic_audio_player.dart';
import 'support/personal_profile_fixture.dart';
import 'support/test_tracks.dart';

void main() {
  setUpAll(() async {
    await LiquidGlassWidgets.initialize();
  });
  test(
    'effects preserve the official HTTP-only image host without TLS bypass',
    () {
      const cover =
          'http://mobileservice.bssdl.kugou.com/2ec70100c63055ac63f4e6b4c1a4165c.png';
      expect(normalizeArtworkUri(cover), cover);
      expect(
        normalizeArtworkUri('http://imge.kugou.com/cover.jpg'),
        'https://imge.kugou.com/cover.jpg',
      );
      expect(
        normalizeArtworkUri('http://mobileservice.bssdl.kugou.com.evil.test/a'),
        'http://mobileservice.bssdl.kugou.com.evil.test/a',
      );
      final community = MusicSoundEffect.parse({
        'id': 2431,
        'name': '通用耳机',
        'sound': 'https://cdn.example/sound.irs',
        'icon_url': cover,
      });
      expect(community!.cover, cover);
      final headphone = MusicSoundEffect.parse({
        'model_id': 1799,
        'model': '通用耳机',
        'model_icon': cover,
        'sound': {
          'id': 2431,
          'name': '通用耳机',
          'sound': 'https://cdn.example/free.irs',
        },
      });
      expect(headphone!.cover, cover);
      final artist = MusicSoundEffect.parse({
        'id': 7739,
        'name': '艺人定制',
        'sound': 'https://cdn.example/free.irs',
        'icon_url': 'image-id',
        'playlist_v20_icon': cover,
      });
      expect(artist!.cover, cover);
    },
  );

  test(
    'resolving is separate, cancellation and immediate retry reject the old attempt',
    () async {
      final root = await Directory.systemTemp.createTemp('music124-download');
      addTearDown(() => root.delete(recursive: true));
      final first = Completer<String>();
      var resolutions = 0, requests = 0, publishes = 0;
      final manager = AudioDownloadManager(
        client: MockClient((_) async {
          requests++;
          return http.Response.bytes([73, 68, 51, ...List.filled(20, 0)], 200);
        }),
        resolve: (_) {
          resolutions++;
          return resolutions == 1
              ? first.future
              : Future.value('https://cdn.example/new');
        },
        publish: (_, _, _, _) async {
          publishes++;
          return 'content://downloads/one';
        },
        currentOwner: () => 'netease:7',
        directory: () async => root,
        persist: (_) async {},
      );
      addTearDown(manager.dispose);
      manager.enqueue(recording());
      expect(manager.tasks.single.phase, AudioDownloadPhase.resolving);
      final id = manager.tasks.single.id;
      manager.cancel(id);
      manager.retry(id);
      first.complete('https://cdn.example/old');
      await until(
        () => manager.tasks.single.phase == AudioDownloadPhase.completed,
      );
      expect(resolutions, 2);
      expect(requests, 1);
      expect(publishes, 1);
      expect(manager.tasks.single.received, 23);
      await until(() => root.listSync().isEmpty);
    },
  );

  test(
    '100 percent bytes remains saving until publish and account invalidation rejects late save',
    () async {
      final root = await Directory.systemTemp.createTemp('music124-saving');
      addTearDown(() => root.delete(recursive: true));
      final saved = Completer<String>();
      final manager = AudioDownloadManager(
        client: MockClient(
          (_) async =>
              http.Response.bytes([73, 68, 51, ...List.filled(20, 0)], 200),
        ),
        resolve: (_) async => 'https://cdn.example/song',
        publish: (_, _, _, _) => saved.future,
        currentOwner: () => 'netease:7',
        directory: () async => root,
        persist: (_) async {},
      );
      addTearDown(manager.dispose);
      manager.enqueue(recording());
      await until(
        () => manager.tasks.single.phase == AudioDownloadPhase.saving,
      );
      expect(manager.tasks.single.received, manager.tasks.single.total);
      manager.cancelPending();
      saved.complete('content://downloads/late');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(manager.tasks.single.phase, AudioDownloadPhase.failed);
    },
  );

  testWidgets(
    'shared progress reports measured KB, MB and unknown total honestly',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppleDownloadProgress(
              receivedBytes: 512,
              totalBytes: 0,
              semanticLabel: '音频下载进度',
            ),
          ),
        ),
      );
      expect(find.text('总大小未知'), findsOneWidget);
      expect(find.text('已下载 0.5 KB'), findsOneWidget);
      expect(find.text('0%'), findsNothing);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppleDownloadProgress(
              receivedBytes: 1048576,
              totalBytes: 2097152,
              semanticLabel: '音频下载进度',
            ),
          ),
        ),
      );
      expect(find.text('1.0 MB / 2.0 MB'), findsOneWidget);
      expect(find.text('50%'), findsOneWidget);
    },
  );

  testWidgets(
    'swiping and clicking share index and retain independent vertical positions',
    (tester) async {
      var index = 0;
      final scrolls = [ScrollController(), ScrollController()];
      addTearDown(() {
        for (final scroll in scrolls) {
          scroll.dispose();
        }
      });
      var activeNotifications = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, update) => Column(
                children: [
                  TextButton(
                    onPressed: () => update(() => index = 1 - index),
                    child: const Text('切换'),
                  ),
                  Expanded(
                    child:
                        NotificationListener<BetaActivePageScrollNotification>(
                          onNotification: (_) {
                            activeNotifications++;
                            return true;
                          },
                          child: BetaSwipePages(
                            index: index,
                            length: 2,
                            onChanged: (value) => update(() => index = value),
                            itemBuilder: (_, page) => ListView.builder(
                              controller: scrolls[page],
                              itemExtent: 60,
                              itemCount: 100,
                              itemBuilder: (_, row) => Text('$page/$row'),
                            ),
                          ),
                        ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      scrolls[0].jumpTo(420);
      await tester.pump();
      expect(activeNotifications, greaterThan(0));
      // A first click must work before any swipe has reported a page index.
      await tester.tap(find.text('切换'));
      await tester.pumpAndSettle();
      expect(index, 1);
      await tester.tap(find.text('切换'));
      await tester.pumpAndSettle();
      expect(index, 0);
      await tester.drag(find.byType(PageView), const Offset(-650, 0));
      await tester.pumpAndSettle();
      expect(index, 1);
      scrolls[1].jumpTo(780);
      await tester.pump();
      await tester.tap(find.text('切换'));
      await tester.pumpAndSettle();
      expect(index, 0);
      expect(scrolls[0].offset, 420);
      expect(scrolls[1].offset, 780);
      final before = activeNotifications;
      scrolls[1].jumpTo(900);
      await tester.pump();
      expect(
        activeNotifications,
        before,
        reason: 'hidden page must not claim glass chrome',
      );
    },
  );

  for (final dark in [false, true]) {
    for (final narrow in [false, true]) {
      testWidgets(
        'secondary music glass keyboard restoration dark=$dark narrow=$narrow',
        (tester) async {
          final dependencies = (await tester.runAsync(() async {
            final player = DeterministicAudioPlayer();
            final handler = MestingAudioHandler(
              tracks: testTracks,
              player: player,
            );
            await handler.replaceQueue(testTracks, autoplay: false);
            final fixture = await PersonalProfileFixture.create(
              audioHandler: handler,
            );
            return (handler, fixture);
          }))!;
          final (handler, fixture) = dependencies;
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = narrow
              ? const Size(320, 700)
              : const Size(390, 844);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetViewInsets);
          final search = BetaPageSearchController(
            hintText: '筛选音效',
            onSubmitted: (_) {},
            onCleared: () {},
            onChanged: (_) {},
          );
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: fixture.container,
              child: MaterialApp(
                theme: buildMestingTheme(
                  musicThemePresetById(dark ? 'classic-dark' : 'classic'),
                ),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(narrow ? 1.3 : 1)),
                  child: child!,
                ),
                home: BetaPageSearchLayout(
                  controller: search,
                  child: const MusicFeaturePage(
                    title: '音效',
                    child: BetaGlassScrollBody(children: [Text('正式页面内容')]),
                  ),
                ),
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 500));
          expect(find.byType(BetaMusicBottomBar), findsOneWidget);
          search.setActive(true);
          search.changed('人声');
          search.focus.requestFocus();
          tester.view.viewInsets = const FakeViewPadding(bottom: 280);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          expect(
            tester
                .widget<BetaMusicBottomBar>(find.byType(BetaMusicBottomBar))
                .accessoryEnabled,
            isFalse,
          );
          tester.view.viewInsets = FakeViewPadding.zero;
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          expect(search.active, isTrue);
          expect(search.hasResults, isTrue);
          expect(
            tester
                .widget<BetaMusicBottomBar>(find.byType(BetaMusicBottomBar))
                .accessoryEnabled,
            isTrue,
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          search.dispose();
          await tester.runAsync(() async {
            await fixture.dispose();
            await handler.debugDispose();
          });
        },
      );
    }
  }
}
