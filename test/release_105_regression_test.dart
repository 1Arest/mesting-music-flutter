import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mesting_music/features/experience/presentation/player_more_menu.dart';
import 'package:mesting_music/features/music_platform/presentation/music_mv_fullscreen.dart';
import 'package:mesting_music/shared/models/track.dart';
import 'package:mesting_music/shared/widgets/beta_glass_popover.dart';
import 'package:mesting_music/shared/widgets/beta_text_editing.dart';
import 'package:mesting_music/shared/widgets/music_effect_glyph.dart';
import 'support/test_tracks.dart';

const _export = bool.fromEnvironment('EXPORT_V105_SCREENSHOTS');
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await LiquidGlassWidgets.initialize();
    if (_export) {
      final bytes = await File('C:/Windows/Fonts/msyh.ttc').readAsBytes();
      for (final name in [
        'Roboto',
        'CupertinoSystemText',
        'CupertinoSystemDisplay',
      ]) {
        await (FontLoader(
          name,
        )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
      }
      await (FontLoader('packages/cupertino_icons/CupertinoIcons')..addFont(
            rootBundle.load(
              'packages/cupertino_icons/assets/CupertinoIcons.ttf',
            ),
          ))
          .load();
    }
  });

  Future<void> capture(WidgetTester tester, String name) async {
    if (!_export) return;
    await tester.runAsync(() async {
      final image = await tester
          .renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('v105-capture')),
          )
          .toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final directory = Directory(
        const String.fromEnvironment('V105_SCREENSHOT_DIR'),
      );
      await directory.create(recursive: true);
      await File(
        '${directory.path}/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  Future<void> mount(
    WidgetTester tester,
    Widget page, {
    bool dark = false,
    bool reduced = false,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      LiquidGlassWidgets.wrap(
        brightnessResolver: Theme.maybeBrightnessOf,
        adaptiveQuality: false,
        child: RepaintBoundary(
          key: const ValueKey('v105-capture'),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              brightness: dark ? Brightness.dark : Brightness.light,
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
              child: child!,
            ),
            home: page,
          ),
        ),
      ),
    );
  }

  test(
    'restored and new tracks share clean display/media titles without changing source identity',
    () {
      for (final extension in [
        'mp3',
        'FLAC',
        'm4a',
        'wav',
        'aac',
        'opus',
        'ape',
      ]) {
        final raw = {
          ...testTracks.first.toJson(),
          'title': '陈粒 - 虚拟.$extension  ',
        };
        final restored = Track.fromJson(
          jsonDecode(jsonEncode(raw)) as Map<String, dynamic>,
        );
        expect(restored.title, '陈粒 - 虚拟');
        expect(restored.toMediaItem().title, restored.title);
        expect(restored.toJson()['title'], raw['title']);
        expect(restored.audioAsset, testTracks.first.audioAsset);
        expect(restored.id, testTracks.first.id);
      }
      for (final title in [
        '退后',
        'Song (Live)',
        '歌曲（伴奏）',
        'Mr. Blue',
        '.mp3',
        'Song.mp3 (Live)',
        'FLAC之歌',
      ]) {
        expect(musicDisplayTitle(title), title);
      }
    },
  );

  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';
    testWidgets(
      'disclosure keeps the menu compact and selection waits for fusion, $mode',
      (tester) async {
        String? result;
        await mount(
          tester,
          Scaffold(
            body: Center(
              child: PlayerMoreMenu(
                trigger: const Text('更多'),
                groups: const [
                  [
                    PlayerMenuAction(
                      'mv',
                      '观看 MV',
                      CupertinoIcons.play_rectangle,
                    ),
                  ],
                ],
                disclosure: const PlayerMenuDisclosure(
                  title: '封面样式',
                  current: '沉浸封面',
                  actions: [
                    PlayerMenuAction(
                      'cover',
                      '沉浸封面',
                      CupertinoIcons.photo,
                      selected: true,
                    ),
                    PlayerMenuAction('classic', '黑胶唱片', CupertinoIcons.circle),
                  ],
                ),
                onSelected: (value) => result = value,
              ),
            ),
          ),
          dark: dark,
        );
        await tester.tap(find.text('更多'));
        await tester.pumpAndSettle();
        expect(find.text('黑胶唱片'), findsNothing);
        await capture(tester, 'menu-collapsed-$mode');
        await tester.tap(find.byKey(const ValueKey('player-style-disclosure')));
        await tester.pumpAndSettle();
        expect(find.text('黑胶唱片'), findsOneWidget);
        await capture(tester, 'menu-expanded-$mode');
        await tester.tap(find.text('黑胶唱片'));
        await tester.pump();
        expect(result, isNull);
        await tester.pumpAndSettle();
        expect(result, 'classic');
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'liquid source flight reverses in place and keeps menu child builds bounded, $mode',
      (tester) async {
        final motion = AnimationController(
          vsync: tester,
          duration: betaMenuOpenDuration,
          reverseDuration: betaMenuCloseDuration,
        );
        var builds = 0;
        await mount(
          tester,
          Scaffold(
            body: Builder(
              builder: (context) => BetaLiquidMenu(
                animation: motion,
                layout: BetaMenuLayout(
                  anchor: const Rect.fromLTWH(22, 710, 346, 52),
                  media: MediaQuery.of(context),
                  width: 300,
                ),
                child: Builder(
                  builder: (_) {
                    builds++;
                    return const SizedBox(
                      width: 300,
                      height: 240,
                      child: Center(child: Text('合成菜单')),
                    );
                  },
                ),
              ),
            ),
          ),
          dark: dark,
        );
        motion.forward();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        final menu = find.byKey(const ValueKey('beta13-glass-menu-surface'));
        final before = tester.getRect(menu);
        await capture(tester, 'liquid-flight-$mode');
        motion.reverse();
        await tester.pump();
        final after = tester.getRect(menu);
        expect((before.topLeft - after.topLeft).distance, lessThan(.1));
        expect(before.size, after.size);
        await tester.pumpAndSettle();
        expect(builds, 1, reason: 'paint ticks must not rebuild menu content');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        motion.dispose();
      },
    );

    testWidgets('catalog uses consistent local symbols, $mode', (tester) async {
      await mount(
        tester,
        Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final name in ['耳机音效', '汽车音效', '空间环绕', '低音', '人声', '电子'])
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        MusicEffectGlyph(name: name, category: '', preset: ''),
                        const SizedBox(width: 18),
                        Text(name),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        dark: dark,
      );
      expect(find.byType(Image), findsNothing);
      expect(find.byType(MusicEffectGlyph), findsNWidgets(6));
      await capture(tester, 'effect-symbols-$mode');
    });
  }

  testWidgets(
    'fullscreen requests landscape, Back restores portrait and the same detail route',
    (tester) async {
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          calls.add(call);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      var completed = false;
      await mount(
        tester,
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              child: const Text('原 MV 详情页'),
              onPressed: () async {
                await showMusicMvFullscreen(
                  context: context,
                  origin: const Rect.fromLTWH(22, 112, 346, 195),
                  video: const ColoredBox(
                    color: Colors.blue,
                    child: Center(child: Text('同一视频画面')),
                  ),
                );
                completed = true;
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('原 MV 详情页'));
      await tester.pumpAndSettle();
      expect(
        calls.any(
          (c) =>
              c.method == 'SystemChrome.setPreferredOrientations' &&
              (c.arguments as List).contains('DeviceOrientation.landscapeLeft'),
        ),
        true,
      );
      tester.view.physicalSize = const Size(844, 390);
      await tester.pumpAndSettle();
      await capture(tester, 'mv-fullscreen-landscape');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpAndSettle();
      expect(completed, true);
      expect(find.text('原 MV 详情页'), findsOneWidget);
      expect(
        calls
            .where((c) => c.method == 'SystemChrome.setPreferredOrientations')
            .last
            .arguments,
        ['DeviceOrientation.portraitUp'],
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'editing exposes Copy and Cut and preserves the framework selected text',
    (tester) async {
      final controller = TextEditingController(text: '音乐不打断');
      await mount(
        tester,
        Scaffold(
          body: Center(
            child: TextField(
              controller: controller,
              contextMenuBuilder: buildBetaEditingMenu,
              selectionControls: betaTextSelectionControls,
            ),
          ),
        ),
      );
      await tester.tap(find.byType(TextField));
      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 2,
      );
      final editable = tester.state<EditableTextState>(
        find.byType(EditableText),
      );
      editable.showToolbar();
      await tester.pumpAndSettle();
      expect(find.text('复制'), findsOneWidget);
      expect(find.text('剪切'), findsOneWidget);
      await tester.tap(find.text('剪切'));
      await tester.pumpAndSettle();
      expect(controller.text, '不打断');
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );
}
