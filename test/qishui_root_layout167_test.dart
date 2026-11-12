import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_chrome_policy.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_feed_mode_menu.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_mine_widgets.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_models.dart';
import 'package:mesting_music/shared/widgets/music_activity_indicator.dart';
import 'support/release_147_qa.dart' show load147IconFonts;

const _capture = bool.fromEnvironment('CAPTURE_QISHUI_ROOT167');
const _boundary = ValueKey('qishui-root167-capture');

void main() {
  setUpAll(() async {
    await LiquidGlassWidgets.initialize();
    if (_capture) {
      await load147IconFonts();
      await (FontLoader('QishuiRootQA')..addFont(
            File(
              'C:/Windows/Fonts/msyh.ttc',
            ).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
    }
  });

  Future<void> mount(
    WidgetTester tester,
    Widget child, {
    Size size = const Size(390, 844),
    double scale = 1,
    bool dark = true,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      LiquidGlassWidgets.wrap(
        adaptiveQuality: false,
        child: MaterialApp(
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xffef4261),
              brightness: dark ? Brightness.dark : Brightness.light,
            ),
            fontFamily: _capture ? 'QishuiRootQA' : null,
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: RepaintBoundary(key: _boundary, child: child!),
          ),
          home: Scaffold(body: SafeArea(child: child)),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> shot(WidgetTester tester, String name) async {
    if (!_capture) return;
    final box = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_boundary),
    );
    await tester.runAsync(() async {
      final image = await box.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File(
        '.codex-artifacts/2026-11-06-release167/ui-final/$name.png',
      );
      await file.parent.create(recursive: true);
      await file.writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    });
  }

  test('only Soda music root replaces the accessory with its own player', () {
    bool hidden(String path, {bool soda = true, bool secondary = false}) =>
        qishuiMusicRootHidesMiniPlayer(
          qishui: soda,
          location: path,
          hasSecondaryPage: secondary,
        );
    expect(hidden('/music'), isTrue);
    expect(hidden('/music', soda: false), isFalse);
    expect(hidden('/music', secondary: true), isFalse);
    for (final location in [
      '/profile',
      '/music/recommend',
      '/player',
      '/music?view=favorites',
      '/music/search',
    ]) {
      expect(hidden(location), isFalse, reason: location);
    }
  });

  testWidgets('feed dropdown retries, scrolls and marks the server selection', (
    tester,
  ) async {
    var attempts = 0;
    QishuiFeedMode? selected;
    late StateSetter rebuild;
    final modes = List.generate(
      18,
      (i) => QishuiFeedMode('mode-$i', '模式 $i', {'scene_mode_id': i}),
    );
    await mount(
      tester,
      StatefulBuilder(
        builder: (context, setState) {
          rebuild = setState;
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                const Text('音乐', style: TextStyle(fontSize: 28)),
                const SizedBox(width: 16),
                Expanded(
                  child: QishuiFeedModeMenu(
                    load: () async {
                      attempts++;
                      if (attempts == 1) {
                        throw StateError('fixture read failure');
                      }
                      return modes;
                    },
                    isCurrent: () => true,
                    selected: selected,
                    onSelected: (mode) => rebuild(() => selected = mode),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
    await tester.tap(find.byKey(const ValueKey('qishui-feed-mode-dropdown')));
    await tester.pumpAndSettle();
    expect(find.text('听歌模式暂时无法读取'), findsOneWidget);
    await tester.tap(find.text('重新读取'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('模式 13').hitTestable(),
      180,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('qishui-feed-mode-options')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.tap(find.text('模式 13').hitTestable());
    await tester.pumpAndSettle();
    expect(selected?.id, 'mode-13');
    expect(attempts, 2);
    await tester.tap(find.byKey(const ValueKey('qishui-feed-mode-dropdown')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('模式 13').hitTestable(),
      180,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('qishui-feed-mode-options')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(
      tester
          .widget<ListTile>(
            find.ancestor(
              of: find.text('模式 13'),
              matching: find.byType(ListTile),
            ),
          )
          .selected,
      isTrue,
    );
    expect(tester.takeException(), isNull);
    await shot(tester, 'root-mode-dropdown-selected');
    await tester.tapAt(const Offset(20, 700));
    await tester.pumpAndSettle();
  });

  testWidgets('a dismissed old account dropdown cannot choose a mode', (
    tester,
  ) async {
    var current = true;
    var chosen = false;
    final loaded = Completer<List<QishuiFeedMode>>();
    await mount(
      tester,
      Padding(
        padding: const EdgeInsets.all(24),
        child: QishuiFeedModeMenu(
          load: () => loaded.future,
          isCurrent: () => current,
          onSelected: (_) => chosen = true,
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('qishui-feed-mode-dropdown')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(MusicActivityIndicator), findsOneWidget);
    current = false;
    loaded.complete([const QishuiFeedMode('late', '迟到模式', {})]);
    await tester.pumpAndSettle();
    await tester.tap(find.text('迟到模式'));
    await tester.pumpAndSettle();
    expect(chosen, isFalse);
    expect(tester.takeException(), isNull);
  });

  for (final variant in [
    (const Size(390, 844), 1.0, false),
    (const Size(320, 740), 1.8, true),
  ]) {
    testWidgets(
      'Mine official hierarchy fits ${variant.$1.width} at ${variant.$2}',
      (tester) async {
        const lists = [
          QishuiPlaylist('likes', '我喜欢的', '', count: 78, kind: 1),
          QishuiPlaylist('douyin', '抖音收藏的音乐', '', count: 6),
          QishuiPlaylist('custom', '测试歌单', '', count: 61),
        ];
        var creates = 0, imports = 0;
        await mount(
          tester,
          CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: QishuiMineHeader(
                  nickname: '界面测试账号',
                  avatar: '',
                  playlists: lists,
                  onAccount: () {},
                  onMembership: () {},
                  onEffects: () {},
                  onSwitchPlatform: () {},
                  onSettings: () {},
                ),
              ),
              SliverToBoxAdapter(
                child: QishuiMineTabs(
                  selected: QishuiMineTab.playlists,
                  onSelected: (_) {},
                ),
              ),
              SliverToBoxAdapter(
                child: QishuiMinePlaylistToolbar(
                  onCreate: () => creates++,
                  onImport: () => imports++,
                ),
              ),
              QishuiMinePlaylistList(playlists: lists, open: (_) {}),
              const SliverToBoxAdapter(child: SizedBox(height: 180)),
            ],
          ),
          size: variant.$1,
          scale: variant.$2,
          dark: variant.$3,
        );
        expect(find.text('界面测试账号'), findsOneWidget);
        expect(find.text('听歌总时长'), findsOneWidget);
        expect(find.text('1582'), findsNothing);
        expect(tester.takeException(), isNull);
        await shot(
          tester,
          'root-mine-${variant.$1.width.toInt()}-${variant.$2}',
        );
        await tester.scrollUntilVisible(
          find.text('创建').hitTestable(),
          180,
          scrollable: find
              .descendant(
                of: find.byType(CustomScrollView),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.tap(find.text('创建'));
        await tester.tap(find.text('导入'));
        expect(creates, 1);
        expect(imports, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
