import 'package:flutter/cupertino.dart';
import 'dart:io';
import 'support/release_147_qa.dart';
import 'package:flutter/services.dart';
import 'release_146_ui_test.dart'
    show capture, capture146Builder, theme146, shot;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesting_music/core/audio/playback_providers.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/music_platform/platform_backend_providers.dart';
import 'package:mesting_music/features/music_platform/netease/footprint/listening_footprint_models.dart';
import 'package:mesting_music/features/music_platform/netease/footprint/listening_footprint_page.dart';
import 'package:mesting_music/features/music_platform/netease/footprint/listening_footprint_providers.dart';
import 'package:mesting_music/features/music_platform/netease/footprint/listening_footprint_reader.dart';
import 'package:mesting_music/features/music_platform/netease/footprint/official_footprint_providers.dart';
import 'package:mesting_music/shared/widgets/beta_swipe_pages.dart';
import 'release_137_footprint_test.dart' show FootprintFixture;
import 'release_145_footprint_test.dart'
    show Footprint145Fixture, footprint145Now;

class _Account147 extends PlatformAccountController {
  @override
  Future<PlatformSession?> build() async => const PlatformSession(
    platform: MusicPlatform.netease,
    userId: '147',
    token: 'synthetic-only',
  );

  void clear() => state = const AsyncData(null);
}

void main() {
  setUpAll(() async {
    await LiquidGlassWidgets.initialize();
    if (capture) {
      await load147IconFonts();
      for (final family in [
        'MestingQA146',
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
    }
  });
  late Footprint145Fixture source;
  late FootprintFixture summary;
  setUp(() {
    source = Footprint145Fixture();
    summary = FootprintFixture();
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
        platformAccountProvider.overrideWith(_Account147.new),
        officialFootprintSourceProvider.overrideWithValue(summary),
        officialFootprintDetailSourceProvider.overrideWithValue(source),
        officialFootprintClockProvider.overrideWithValue(() => footprint145Now),
        currentMediaItemProvider.overrideWith((_) => Stream.value(null)),
      ],
    );
    addTearDown(container.dispose);
    await container.read(platformAccountProvider.future);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = compact
        ? const Size(320, 720)
        : const Size(390, 844);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: theme146(dark),
          builder: (context, child) => capture146Builder(
            context,
            MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(compact ? 1.5 : 1)),
              child: child!,
            ),
          ),
          home: const NeteaseListeningFootprintPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  Finder byKey(String key) => find.byKey(ValueKey(key));
  CustomScrollView activeScroll(WidgetTester tester) =>
      tester.widget<CustomScrollView>(
        find.descendant(
          of: byKey('listening-footprint-scroll'),
          matching: find.byType(CustomScrollView),
        ),
      );
  ListeningFootprintReader reader(ProviderContainer container) =>
      container.read(listeningFootprintReaderProvider)!;
  Future<void> swipe(WidgetTester tester, int direction) async {
    // Start in the content margin so the chart's scrubbing recognizer cannot
    // own a gesture intended to switch whole report pages.
    await tester.dragFrom(
      Offset(
        tester.view.physicalSize.width - 8,
        tester.getRect(byKey('footprint-shared-header')).bottom + 30,
      ),
      Offset(310.0 * direction, 0),
    );
    await tester.pumpAndSettle();
  }

  for (final dark in [false, true]) {
    testWidgets(
      'common title total and segments stay fixed while only reports swipe dark=$dark',
      (tester) async {
        final container = await mount(tester, dark: dark);
        await shot(tester, 'footprint-initial-${dark ? 'dark' : 'light'}');
        var swipeIndex = 0;
        final common = [
          byKey('footprint-collapsing-title'),
          byKey('footprint-official-total'),
          byKey('footprint-scale-control'),
        ];
        for (final finder in common) {
          expect(finder, findsOneWidget);
          expect(
            find.descendant(of: find.byType(BetaSwipePages), matching: finder),
            findsNothing,
          );
        }
        for (final destination in [
          FootprintScale.month,
          FootprintScale.year,
          FootprintScale.month,
          FootprintScale.week,
        ]) {
          final direction = destination.index > reader(container).scale.index
              ? -1
              : 1;
          final before = [for (final finder in common) tester.getRect(finder)];
          final period = byKey('footprint-period-label').hitTestable();
          final oldPeriodLeft = tester.getTopLeft(period).dx;
          final gesture = await tester.startGesture(tester.getCenter(period));
          await gesture.moveBy(Offset(20.0 * direction, 0));
          await tester.pump();
          await gesture.moveBy(Offset(120.0 * direction, 0));
          await tester.pump(const Duration(milliseconds: 60));
          for (var i = 0; i < common.length; i++) {
            expect(common[i], findsOneWidget);
            expect(tester.getRect(common[i]), before[i]);
          }
          // The content must actually move; an unchanged header alone cannot
          // distinguish the repaired structure from disabled horizontal input.
          final periodRects = tester
              .elementList(byKey('footprint-period-label'))
              .map(
                (element) => tester
                    .getTopLeft(
                      find.byElementPredicate(
                        (candidate) => identical(candidate, element),
                      ),
                    )
                    .dx,
              );
          expect(
            periodRects.any((left) => (left - oldPeriodLeft).abs() > 20),
            isTrue,
          );
          await shot(
            tester,
            'footprint-mid-${swipeIndex++}-${dark ? 'dark' : 'light'}',
          );
          await gesture.moveBy(Offset(230.0 * direction, 0));
          await gesture.up();
          await tester.pumpAndSettle();
          expect(reader(container).scale, destination);
          final control = tester
              .widget<CupertinoSlidingSegmentedControl<FootprintScale>>(
                byKey('footprint-scale-control'),
              );
          expect(control.groupValue, destination);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('vertical drags starting on common title keep normal collapse', (
    tester,
  ) async {
    await mount(tester);
    await tester.dragFrom(
      tester.getCenter(byKey('footprint-collapsing-title')),
      const Offset(0, -260),
    );
    await tester.pumpAndSettle();
    expect(activeScroll(tester).controller!.offset, greaterThan(116));
    expect(
      tester.widget<Text>(byKey('footprint-collapsing-title')).style!.fontSize,
      17,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'crossing halfway holds header geometry until destination vertical state settles',
    (tester) async {
      final container = await mount(tester);
      await tester.drag(
        byKey('listening-footprint-scroll'),
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();
      final weekOffset = activeScroll(tester).controller!.offset;
      final common = [
        byKey('footprint-collapsing-title'),
        byKey('footprint-official-total'),
        byKey('footprint-scale-control'),
      ];
      for (final destination in [FootprintScale.month, FootprintScale.week]) {
        final direction = destination == FootprintScale.month ? -1 : 1;
        final before = [for (final finder in common) tester.getRect(finder)];
        final gesture = await tester.startGesture(
          Offset(
            tester.view.physicalSize.width - 8,
            tester.getRect(byKey('footprint-shared-header')).bottom + 30,
          ),
        );
        await gesture.moveBy(Offset(20.0 * direction, 0));
        await tester.pump();
        await gesture.moveBy(Offset(240.0 * direction, 0));
        await tester.pump(const Duration(milliseconds: 60));
        expect(reader(container).scale, destination);
        for (var i = 0; i < common.length; i++) {
          expect(tester.getRect(common[i]), before[i]);
        }
        await gesture.up();
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<Text>(byKey('footprint-collapsing-title'))
              .style!
              .fontSize,
          17,
        );
      }
      expect(activeScroll(tester).controller!.offset, closeTo(weekOffset, .1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'date arrows and each scale scroll survive swipes without relabeling neighboring reports',
    (tester) async {
      final container = await mount(tester);
      await tester.tap(byKey('footprint-previous'));
      await tester.pumpAndSettle();
      final week = reader(container).selection.key;
      await tester.drag(
        byKey('listening-footprint-scroll'),
        const Offset(0, -320),
      );
      await tester.pumpAndSettle();
      final weekScroll = activeScroll(tester).controller!;
      final weekOffset = weekScroll.offset;
      expect(weekOffset, greaterThan(116));
      expect(
        tester
            .widget<Text>(byKey('footprint-collapsing-title'))
            .style!
            .fontSize,
        17,
      );

      await swipe(tester, -1);
      expect(reader(container).scale, FootprintScale.month);
      expect(activeScroll(tester).controller!.offset, 116);
      expect(
        tester
            .widget<Text>(byKey('footprint-collapsing-title'))
            .style!
            .fontSize,
        17,
      );
      await tester.tap(byKey('footprint-previous'));
      await tester.pumpAndSettle();
      final month = reader(container).selection.key;
      expect(find.text('2026年10月'), findsOneWidget);
      await tester.drag(
        byKey('listening-footprint-scroll'),
        const Offset(0, -190),
      );
      await tester.pumpAndSettle();
      final monthOffset = activeScroll(tester).controller!.offset;
      await swipe(tester, -1);
      expect(reader(container).scale, FootprintScale.year);
      await tester.tap(byKey('footprint-previous'));
      await tester.pumpAndSettle();
      expect(find.text('2024年'), findsOneWidget);
      final year = reader(container).selection.key;

      // A retained hidden page may be laid out or have its scroll corrected;
      // its notifications must never compact the active common glass header.
      final headerBefore = tester.getRect(byKey('footprint-shared-header'));
      weekScroll.jumpTo(weekOffset + 30);
      await tester.pump();
      expect(tester.getRect(byKey('footprint-shared-header')), headerBefore);
      weekScroll.jumpTo(weekOffset);
      await tester.pump();

      await swipe(tester, 1);
      expect(reader(container).selection.key, month);
      expect(activeScroll(tester).controller!.offset, closeTo(monthOffset, .1));
      await swipe(tester, 1);
      expect(reader(container).selection.key, week);
      expect(activeScroll(tester).controller!.offset, closeTo(weekOffset, .1));
      await swipe(tester, -1);
      await swipe(tester, -1);
      expect(reader(container).selection.key, year);
      expect(find.text('2024年'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final dark in [false, true]) {
    testWidgets(
      'shared compact header keeps title spacing refresh and account clear dark=$dark',
      (tester) async {
        final container = await mount(tester, dark: dark, compact: true);
        final title = byKey('footprint-collapsing-title');
        final total = byKey('footprint-official-total');
        expect(
          tester.getRect(title).bottom,
          lessThanOrEqualTo(tester.getRect(total).top),
        );
        source.fail = true;
        summary.fail = true;
        await tester.tap(byKey('listening-footprint-refresh'));
        await tester.pumpAndSettle();
        expect(find.text('3 小时 15 分钟'), findsOneWidget);
        expect(find.text('刷新失败，保留上次官方读数'), findsOneWidget);
        await tester.drag(
          byKey('listening-footprint-scroll'),
          const Offset(0, -300),
        );
        await tester.pumpAndSettle();
        expect(tester.widget<Text>(title).style!.fontSize, 17);
        expect(
          tester.getRect(byKey('footprint-scale-control')).top,
          lessThan(90),
        );
        (container.read(platformAccountProvider.notifier) as _Account147)
            .clear();
        await tester.pumpAndSettle();
        expect(find.text('请返回并选择网易云账号'), findsOneWidget);
        expect(find.text('总时长 5609 小时 16 分钟'), findsNothing);
        expect(find.byKey(const ValueKey('footprint-song-1000')), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
