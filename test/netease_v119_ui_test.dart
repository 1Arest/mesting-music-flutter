import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/features/downloads/audio_download_quality.dart';
import 'package:mesting_music/features/music_platform/domain/platform_audio_quality.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/music_platform/netease/full/netease_catalog.dart';
import 'package:mesting_music/features/music_platform/netease/full/netease_full_page.dart';
import 'package:mesting_music/features/music_platform/netease/messages/netease_messages_page.dart';
import 'package:mesting_music/features/music_platform/netease/messages/netease_messages_repository.dart';
import 'package:mesting_music/features/music_platform/netease/messages/netease_unread.dart';
import 'package:mesting_music/features/music_platform/netease/netease_api.dart';
import 'package:mesting_music/features/music_platform/netease/netease_music_repository.dart';
import 'package:mesting_music/features/music_platform/netease/netease_session.dart';
import 'package:mesting_music/features/music_platform/platform_backend_providers.dart';
import 'package:mesting_music/features/themes/app_theme.dart';
import 'package:mesting_music/features/themes/music_theme_preset.dart';
import 'package:mesting_music/shared/widgets/beta_glass_controls.dart';
import 'package:mesting_music/shared/widgets/beta_popup_menu_button.dart';
import 'package:mesting_music/shared/widgets/route_settled_content.dart';
import 'package:mesting_music/shared/models/track.dart';
import 'netease_v115_sources_test.dart' show TestAccount;
import 'netease_v112_fallback_download_test.dart' show recording;

void main() {
  setUpAll(() async {
    await LiquidGlassWidgets.initialize();
    if (const bool.fromEnvironment('CAPTURE_V119')) {
      for (final family in [
        'MestingQA',
        'Noto Sans SC',
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
      await (FontLoader('Noto Color Emoji')..addFont(
            File(
              'C:/Windows/Fonts/seguiemj.ttf',
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
  Future<ProviderContainer> mount(
    WidgetTester tester,
    Widget page, {
    bool dark = false,
    bool compact = false,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final api =
        NeteaseApi(
          MockClient(
            (req) async => http.Response(
              jsonEncode({
                'code': 200,
                'more': false,
                'msgs': [
                  {
                    'id': 1,
                    'msg': jsonEncode({'msg': '[便便]'}),
                    'time': 1000,
                    'fromUser': {'userId': 8, 'nickname': '测试朋友'},
                    'toUser': {'userId': 7},
                  },
                  {
                    'id': 2,
                    'msg': jsonEncode({'msg': '你好 🌹'}),
                    'time': 2000,
                    'fromUser': {'userId': 7, 'nickname': '我'},
                    'toUser': {'userId': 8},
                  },
                ],
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            ),
          ),
        )..configure(
          const NeteaseSession(
            userId: '7',
            cookies: {'MUSIC_U': 'fixture'},
            deviceId: 'fixture',
          ),
        );
    final all =
        (jsonDecode(
                  File(
                    'assets/data/netease-full-catalog.json',
                  ).readAsStringSync(),
                )
                as Map)['entries']
            as List;
    final c = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        platformAccountProvider.overrideWith(TestAccount.new),
        neteaseMusicRepositoryProvider.overrideWithValue(
          NeteaseMusicRepository(api),
        ),
        neteaseCatalogProvider.overrideWith(
          (ref) async => all
              .map(
                (e) => NeteaseEndpoint.fromJson(Map<String, dynamic>.from(e)),
              )
              .toList(),
        ),
        neteaseUnreadCountsProvider.overrideWith(
          (ref) => ref.watch(platformAccountProvider).value?.userId == '8'
              ? const Stream.empty()
              : Stream.value({
                  'privateMsgCount': 88,
                  'commentCount': 12,
                  'noticeCount': 1,
                }),
        ),
        downloadSongQualitiesProvider.overrideWith(
          (ref, id) async => {
            PlatformAudioQuality.standard,
            PlatformAudioQuality.higher,
            PlatformAudioQuality.high,
            PlatformAudioQuality.lossless,
          },
        ),
      ],
    );
    addTearDown(c.dispose);
    await c.read(platformAccountProvider.future);
    await c.read(neteaseCatalogProvider.future);
    tester.view.physicalSize = Size(compact ? 320 : 390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: buildMestingTheme(
            musicThemePresetById(dark ? 'classic-dark' : 'classic'),
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(compact ? 1.3 : 1)),
            child: RepaintBoundary(
              key: const ValueKey('v119-capture'),
              child: child!,
            ),
          ),
          home: Scaffold(body: page),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(tester.takeException(), isNull);
    return c;
  }

  Future<void> capture(WidgetTester tester, String name) async {
    if (!const bool.fromEnvironment('CAPTURE_V119')) return;
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('v119-capture')),
      );
      final image = await boundary.toImage(pixelRatio: 1.5);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final dir = Directory('.codex-artifacts/2026-10-30-release119/ui');
      await dir.create(recursive: true);
      await File(
        '${dir.path}/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  for (final dark in [false, true]) {
    for (final compact in [false, true]) {
      testWidgets(
        'chat centred header, official face and emoji hit target dark=$dark compact=$compact',
        (tester) async {
          await mount(
            tester,
            const NeteaseChatPage(peer: NeteasePerson('8', '测试朋友')),
            dark: dark,
            compact: compact,
          );
          expect(find.text('💩'), findsOneWidget);
          expect(find.text('[便便]'), findsNothing);
          expect(
            tester.getCenter(find.text('测试朋友')).dx,
            closeTo((compact ? 320 : 390) / 2, 1),
          );
          expect(
            tester.getCenter(find.byTooltip('一起听')).dx,
            lessThan(
              tester.getCenter(find.byType(BetaPopupMenuButton<String>)).dx,
            ),
          );
          await tester.tap(find.byTooltip('表情'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          final emoji = find.text('😀');
          final button = find.ancestor(
            of: emoji,
            matching: find.byType(BetaGlassButton),
          );
          expect(
            tester.getCenter(emoji).dx,
            closeTo(tester.getCenter(button).dx, 1),
          );
          expect(tester.takeException(), isNull);
          await capture(
            tester,
            'chat-${dark ? 'dark' : 'light'}-${compact ? '320' : '390'}',
          );
          await tester.pumpWidget(const SizedBox());
          await tester.pump();
        },
      );
    }
  }
  testWidgets(
    'entry aggregates all unread counts at 99+ and hides duplicate search',
    (tester) async {
      await mount(
        tester,
        const SingleChildScrollView(
          child: Column(
            children: [
              NeteaseFullNavigation(tab: '我的'),
              NeteaseFullNavigation(tab: '发现'),
            ],
          ),
        ),
      );
      expect(find.text('99+'), findsOneWidget);
      expect(find.text('音乐搜索'), findsNothing);
      expect(find.text('我的消息'), findsOneWidget);
      await capture(tester, 'unread-navigation');
    },
  );
  testWidgets(
    'a pending account reload cannot display the previous unread badge',
    (tester) async {
      final c = await mount(
        tester,
        Consumer(
          builder: (context, ref, _) =>
              Text('Unread ${ref.watch(neteaseUnreadTotalProvider)}'),
        ),
      );
      expect(find.text('Unread 101'), findsOneWidget);
      (c.read(platformAccountProvider.notifier) as TestAccount).replace('8');
      await tester.pump();
      expect(find.text('Unread 101'), findsNothing);
      expect(find.text('Unread 0'), findsOneWidget);
    },
  );
  testWidgets(
    'download picker offers official tiers and alternate requests without playing',
    (tester) async {
      PlatformAudioQuality? choice;
      await mount(
        tester,
        Builder(
          builder: (context) => BetaGlassButton(
            onPressed: () async {
              choice = await chooseAudioDownloadQuality(context, [recording()]);
            },
            child: const Text('下载'),
          ),
        ),
      );
      await tester.tap(find.text('下载'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      for (final label in ['标准', '较高', '极高', '无损']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.text('Hi-Res'), findsOneWidget);
      await capture(tester, 'download-quality');
      await tester.tap(find.text('无损'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(choice, PlatformAudioQuality.lossless);
    },
  );
  testWidgets(
    'Kugou picker uses Kugou tier labels without NetEase-only quality choices',
    (tester) async {
      PlatformAudioQuality? choice;
      await mount(
        tester,
        Builder(
          builder: (context) => BetaGlassButton(
            onPressed: () async {
              choice = await chooseAudioDownloadQuality(context, [
                Track.fromJson({
                  ...recording().toJson(),
                  'id': 'kugou_fixture',
                  'source': 'kugou',
                }),
              ]);
            },
            child: const Text('下载'),
          ),
        ),
      );
      await tester.tap(find.text('下载'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      for (final label in ['标准', '高品质', '无损']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.text('较高'), findsNothing);
      expect(find.text('极高'), findsNothing);
      expect(find.text('Hi-Res'), findsNothing);
      await capture(tester, 'download-quality-kugou');
      await tester.tap(find.text('无损'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(choice, PlatformAudioQuality.lossless);
    },
  );
  testWidgets(
    'optional content starts once after route entry and stays mounted on reverse',
    (tester) async {
      var loads = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                PageRouteBuilder<void>(
                  transitionDuration: const Duration(milliseconds: 360),
                  pageBuilder: (_, _, _) => RouteSettledContent(
                    placeholder: const Text('等待入场'),
                    builder: (_) {
                      loads++;
                      return const Text('内容');
                    },
                  ),
                ),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 180));
      expect(loads, 0);
      expect(find.text('等待入场'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 200));
      expect(loads, 1);
      final context = tester.element(find.text('内容'));
      Navigator.of(context).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('等待入场'), findsNothing);
      await tester.pumpAndSettle();
    },
  );
}
