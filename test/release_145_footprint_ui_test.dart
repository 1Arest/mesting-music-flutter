import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesting_music/core/audio/playback_providers.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/music_platform/platform_backend_providers.dart';
import 'package:mesting_music/features/music_platform/netease/footprint/official_footprint_providers.dart';
import 'package:mesting_music/features/music_platform/netease/footprint/listening_footprint_page.dart';
import 'package:mesting_music/features/music_platform/netease/footprint/listening_footprint_providers.dart';
import 'package:mesting_music/shared/widgets/artwork_image.dart';
import 'package:mesting_music/shared/widgets/beta_glass_controls.dart';
import 'package:mesting_music/shared/widgets/beta_page_search_layout.dart';
import 'release_137_footprint_test.dart' show FootprintFixture;
import 'release_145_footprint_test.dart';
import 'support/release_144_qa.dart' show theme144;

const _capture = bool.fromEnvironment('CAPTURE_145_FOOTPRINT');
const _captureKey = ValueKey('footprint145-capture');

class _Account145 extends PlatformAccountController {
  @override
  Future<PlatformSession?> build() async => const PlatformSession(
    platform: MusicPlatform.netease,
    userId: '145',
    token: 'synthetic-only',
  );
  void clear() => state = const AsyncData(null);
}

Future<void> _initialize145() async {
  await LiquidGlassWidgets.initialize();
  if (!_capture) return;
  for (final name in [
    'MestingFootprintQA',
    'Roboto',
    'CupertinoSystemText',
    'CupertinoSystemDisplay',
  ]) {
    await (FontLoader(name)..addFont(
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
}

Future<void> _shot(WidgetTester tester, String name) async {
  if (!_capture) return;
  // Only bundled synthetic fixture covers are decoded; no real user/account or
  // external media is needed for these host-side layout renders.
  final images = tester.widgetList<Image>(find.byType(Image)).toList();
  if (images.isNotEmpty) {
    final context = tester.element(find.byType(Image).first);
    await tester.runAsync(
      () => Future.wait([
        for (final image in images) precacheImage(image.image, context),
      ]),
    );
    await tester.pump();
  }
  final future = tester
      .renderObject<RenderRepaintBoundary>(find.byKey(_captureKey))
      .toImage();
  await tester.runAsync(() async {
    final image = await future;
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final path = File(
      '.codex-artifacts/2026-11-03-release145/footprint/ui/$name.png',
    );
    await path.parent.create(recursive: true);
    await path.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(_initialize145);
  late Footprint145Fixture detail;
  late FootprintFixture summary;
  late List<String> selectedSongs;
  setUp(() {
    detail = Footprint145Fixture();
    summary = FootprintFixture();
    selectedSongs = [];
    SharedPreferences.setMockInitialValues({});
  });

  Future<ProviderContainer> mount(
    WidgetTester tester, {
    bool dark = false,
    bool compact = false,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        usesNeteaseProvider.overrideWithValue(true),
        platformAccountProvider.overrideWith(_Account145.new),
        officialFootprintSourceProvider.overrideWithValue(summary),
        officialFootprintDetailSourceProvider.overrideWithValue(detail),
        officialFootprintClockProvider.overrideWithValue(() => footprint145Now),
        currentMediaItemProvider.overrideWith((_) => Stream.value(null)),
      ],
    );
    addTearDown(container.dispose);
    await container.read(platformAccountProvider.future);
    tester.view.physicalSize = compact
        ? const Size(320, 720)
        : const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final navigation = GlobalKey<NavigatorState>();
    final theme = theme144(dark);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          navigatorKey: navigation,
          theme: _capture
              ? theme.copyWith(
                  textTheme: theme.textTheme.apply(
                    fontFamily: 'MestingFootprintQA',
                  ),
                )
              : theme,
          builder: (context, child) => RepaintBoundary(
            key: _captureKey,
            child: MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(compact ? 1.5 : 1)),
              child: child!,
            ),
          ),
          home: const Scaffold(body: Text('合成测试根页')),
        ),
      ),
    );
    navigation.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => NeteaseListeningFootprintPage(
          onSongSelected: (song) async => selectedSongs.add(song.id),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    return container;
  }

  Finder scrollable() => find
      .descendant(
        of: find.byKey(const ValueKey('listening-footprint-scroll')),
        matching: find.byType(Scrollable),
      )
      .first;
  Future<void> reveal(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(finder, 250, scrollable: scrollable());
    await Scrollable.ensureVisible(tester.element(finder), alignment: .4);
    await tester.pumpAndSettle();
  }

  Future<void> selectScale(WidgetTester tester, String name) async {
    await tester.tap(find.byKey(ValueKey('footprint-scale-$name')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
  }

  for (final dark in [false, true]) {
    testWidgets(
      'official daily chart, selection and collapsing pinned segment dark=$dark',
      (tester) async {
        await mount(tester, dark: dark);
        expect(find.text('累计听歌 5609 小时 16 分钟'), findsOneWidget);
        expect(find.text('3 小时 15 分钟'), findsOneWidget);
        expect(find.text('收听了 3 天'), findsOneWidget);
        final title = find.byKey(const ValueKey('footprint-collapsing-title'));
        expect(tester.widget<Text>(title).style!.fontSize, 34);
        final plot = find.byKey(const ValueKey('footprint-chart-scrub'));
        final rect = tester.getRect(plot);
        await tester.tapAt(
          Offset(rect.left + rect.width * 1.5 / 7, rect.center.dy),
        );
        await tester.pump();
        expect(find.text('1 小时 12 分钟'), findsOneWidget);
        expect(find.textContaining('播客 12 分钟'), findsOneWidget);
        await _shot(tester, 'week-${dark ? 'dark' : 'light'}');
        await tester.drag(
          find.byKey(const ValueKey('listening-footprint-scroll')),
          const Offset(0, -260),
        );
        await tester.pumpAndSettle();
        expect(tester.widget<Text>(title).style!.fontSize, 17);
        expect(
          tester
              .getRect(find.byKey(const ValueKey('footprint-scale-control')))
              .top,
          lessThan(90),
        );
        expect(find.byType(ArtworkImage), findsWidgets);
        await _shot(tester, 'collapsed-${dark ? 'dark' : 'light'}');
        await selectScale(tester, 'month');
        expect(
          find.byKey(const ValueKey('footprint-bar-2026-11-30')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const ValueKey('footprint-previous')));
        await tester.pumpAndSettle();
        expect(find.text('2026年10月'), findsOneWidget);
        await selectScale(tester, 'year');
        expect(find.text('2025年'), findsOneWidget);
        expect(find.textContaining('官方未提供月度明细'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('footprint-previous')));
        await tester.pumpAndSettle();
        expect(find.text('2024年'), findsOneWidget);
        await _shot(tester, 'year-${dark ? 'dark' : 'light'}');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'today songs stay today under historic selection, local filter and song action work',
    (tester) async {
      await mount(tester);
      await tester.tap(find.byKey(const ValueKey('footprint-previous')));
      await tester.pumpAndSettle();
      final search = tester
          .widget<BetaPageSearchLayout>(find.byType(BetaPageSearchLayout))
          .controller;
      search.text.text = '雨后';
      search.changed('雨后');
      await tester.pump();
      await reveal(tester, find.byKey(const ValueKey('footprint-song-1001')));
      expect(find.text('今日听过'), findsOneWidget);
      expect(find.text('以下为今日记录，与上方历史区间分开展示。'), findsOneWidget);
      expect(find.text('找到 3 首歌曲'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('footprint-song-1001')));
      await tester.pump();
      expect(selectedSongs, ['1001']);
      expect(detail.songReads, 1);
      await _shot(tester, 'today-filter-light');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final dark in [false, true]) {
    testWidgets(
      '320dp 1.5x header and bottom diagnostic action remain visible dark=$dark',
      (tester) async {
        await mount(tester, dark: dark, compact: true);
        final title = tester.getRect(
          find.byKey(const ValueKey('footprint-collapsing-title')),
        );
        final total = tester.getRect(
          find.byKey(const ValueKey('footprint-official-total')),
        );
        expect(title.bottom, lessThanOrEqualTo(total.top));
        await _shot(tester, 'compact-${dark ? 'dark' : 'light'}');
        final diagnostic = find.byKey(
          const ValueKey('footprint-open-diagnostics'),
        );
        await reveal(tester, diagnostic);
        final position = tester.state<ScrollableState>(scrollable()).position;
        position.jumpTo(position.maxScrollExtent);
        await tester.pumpAndSettle();
        final rect = tester.getRect(diagnostic);
        expect(rect.bottom, lessThan(tester.view.physicalSize.height - 100));
        expect(tester.widget<BetaGlassButton>(diagnostic).onPressed, isNotNull);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'failed refresh retains official value and account clear removes all old-account rows',
    (tester) async {
      final container = await mount(tester);
      detail.fail = true;
      summary.fail = true;
      await tester.tap(
        find.byKey(const ValueKey('listening-footprint-refresh')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 450));
      expect(find.text('3 小时 15 分钟'), findsOneWidget);
      expect(find.textContaining('刷新失败，保留上次成功数据'), findsWidgets);
      expect(find.text('刷新失败，保留上次官方读数'), findsOneWidget);
      await _shot(tester, 'retained-error-light');
      (container.read(platformAccountProvider.notifier) as _Account145).clear();
      await tester.pump();
      expect(find.text('请返回并选择网易云账号'), findsOneWidget);
      expect(find.text('3 小时 15 分钟'), findsNothing);
      expect(find.text('累计听歌 5609 小时 16 分钟'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'first read failure is explicit and never displays a confirmed zero',
    (tester) async {
      detail.fail = true;
      summary.fail = true;
      await mount(tester);
      expect(find.text('官方累计时长暂未获取'), findsOneWidget);
      expect(find.textContaining('所选区间暂时无法读取'), findsOneWidget);
      expect(find.text('0 分钟'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
