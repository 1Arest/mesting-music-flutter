import 'package:flutter/cupertino.dart';
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
import 'package:mesting_music/features/music_platform/netease/footprint/official_footprint_providers.dart';
import 'package:mesting_music/features/music_platform/netease/footprint/listening_footprint_page.dart';
import 'package:mesting_music/features/music_platform/netease/footprint/official_report_extras.dart';
import 'package:mesting_music/features/music_platform/netease/footprint/official_report_extras_view.dart';
import 'package:mesting_music/shared/widgets/artwork_image.dart';
import 'package:mesting_music/features/music_platform/netease/footprint/official_report_language_chart.dart';
import 'package:mesting_music/features/themes/lyric_highlight_swatch.dart';
import 'package:mesting_music/shared/widgets/beta_control_scope.dart';
import 'package:mesting_music/features/music_platform/netease/footprint/listening_footprint_providers.dart';
import 'release_137_footprint_test.dart' show FootprintFixture;
import 'release_145_footprint_test.dart'
    show Footprint145Fixture, footprint145Now;
import 'support/release_144_qa.dart' show theme144;
import 'support/ui_fix_capture.dart';

class _Account extends PlatformAccountController {
  @override
  Future<PlatformSession?> build() async => const PlatformSession(
    platform: MusicPlatform.netease,
    userId: '214',
    token: 'synthetic-only',
  );
}

void main() {
  setUpAll(() async {
    await LiquidGlassWidgets.initialize();
    await initializeUiFixCapture();
  });
  Future<void> mount(
    WidgetTester tester,
    Widget child, {
    bool dark = false,
    Size size = const Size(390, 844),
    double scale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var theme = theme144(dark);
    if (uiFixCaptureDirectory.isNotEmpty) {
      theme = theme.copyWith(
        textTheme: theme.textTheme.apply(fontFamily: 'UiFixCJK'),
      );
    }
    await tester.pumpWidget(
      BetaControlScope(
        apple: true,
        child: RepaintBoundary(
          key: uiFixCaptureKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: theme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: child,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final dark in [false, true]) {
    testWidgets('era covers and language report render together dark=$dark', (
      tester,
    ) async {
      const covers = [
        'assets/images/playlists/13416469337261709.jpeg',
        'assets/images/playlists/13416469354055551.jpeg',
        'assets/images/playlists/13416469356600254.jpeg',
      ];
      await mount(
        tester,
        ProviderScope(
          child: Scaffold(
            body: ListView(
              padding: const EdgeInsets.all(22),
              children: [
                OfficialReportExtrasView(
                  period: '合成报表预览',
                  weekly: true,
                  data: OfficialReportExtras(
                    ages: [
                      for (var i = 0; i < 3; i++)
                        OfficialReportItem(
                          title: ['2020年后', '2010–2019', '2000–2009'][i],
                          id: '${42 + i}',
                          cover: covers[i],
                        ),
                    ],
                    languages: const [
                      OfficialReportItem(title: '华语', percent: 74),
                      OfficialReportItem(title: '英语', percent: 30),
                      OfficialReportItem(title: '粤语', percent: 2),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        dark: dark,
      );
      expect(
        tester
            .widgetList<ArtworkImage>(find.byType(ArtworkImage))
            .map((image) => image.uri)
            .toSet(),
        covers.toSet(),
      );
      expect(find.text('无封面'), findsNothing);
      await captureUiFix(tester, '214-era-language-$dark');
      expect(tester.takeException(), isNull);
    });
    testWidgets('white lyric swatch edge and selected check dark=$dark', (
      tester,
    ) async {
      var selected = false;
      await mount(
        tester,
        Scaffold(
          body: Center(
            child: StatefulBuilder(
              builder: (context, setState) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('高亮颜色'),
                  LyricHighlightSwatch(
                    color: Colors.white,
                    selected: selected,
                    onPressed: () => setState(() => selected = !selected),
                  ),
                ],
              ),
            ),
          ),
        ),
        dark: dark,
      );
      final swatch = find.byKey(
        ValueKey('lyric-color-${Colors.white.toARGB32()}'),
      );
      final decoration =
          tester.widget<Container>(swatch).decoration! as BoxDecoration;
      expect((decoration.border! as Border).top.width, greaterThan(1));
      await captureUiFix(tester, '214-white-unselected-$dark');
      await tester.tap(swatch);
      await tester.pumpAndSettle();
      expect(find.byIcon(CupertinoIcons.check_mark), findsOneWidget);
      await captureUiFix(tester, '214-white-selected-$dark');
    });
    testWidgets('official language columns preserve values dark=$dark', (
      tester,
    ) async {
      await mount(
        tester,
        const Scaffold(
          body: Center(
            child: Padding(
              padding: EdgeInsets.all(22),
              child: OfficialReportLanguageChart(
                languages: [
                  OfficialReportItem(title: '华语', percent: 74),
                  OfficialReportItem(title: '英语', percent: 30),
                  OfficialReportItem(title: '粤语', percent: 2),
                ],
              ),
            ),
          ),
        ),
        dark: dark,
        size: const Size(320, 720),
        scale: 1.5,
      );
      expect(find.text('74%'), findsOneWidget);
      expect(find.text('30%'), findsOneWidget);
      final first = tester.getRect(
        find.byKey(const ValueKey('footprint-language-column-0')),
      );
      final second = tester.getRect(
        find.byKey(const ValueKey('footprint-language-column-1')),
      );
      expect(first.left, lessThan(second.left));
      expect(first.height, greaterThan(second.height));
      expect(tester.takeException(), isNull);
      await captureUiFix(tester, '214-language-$dark');
    });
  }
  testWidgets(
    'footprint collapse stays fixed through tap swipe and lazy period mounting',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(
            await SharedPreferences.getInstance(),
          ),
          usesNeteaseProvider.overrideWithValue(true),
          platformAccountProvider.overrideWith(_Account.new),
          officialFootprintSourceProvider.overrideWithValue(FootprintFixture()),
          officialFootprintDetailSourceProvider.overrideWithValue(
            Footprint145Fixture(),
          ),
          officialFootprintClockProvider.overrideWithValue(
            () => footprint145Now,
          ),
          currentMediaItemProvider.overrideWith((_) => Stream.value(null)),
        ],
      );
      addTearDown(container.dispose);
      await container.read(platformAccountProvider.future);
      await mount(
        tester,
        UncontrolledProviderScope(
          container: container,
          child: const NeteaseListeningFootprintPage(),
        ),
      );
      final segments = find.byKey(const ValueKey('footprint-segment-width'));
      final full = tester.getRect(segments);
      final scroll = find
          .descendant(
            of: find.byKey(const ValueKey('listening-footprint-scroll')),
            matching: find.byType(Scrollable),
          )
          .first;
      final control = tester.state<ScrollableState>(scroll).position;
      control.jumpTo(500);
      await tester.pumpAndSettle();
      final small = tester.getRect(segments);
      expect(small.width, lessThan(full.width - 60));
      await captureUiFix(tester, '214-footprint-collapsed');
      await tester.tap(find.byKey(const ValueKey('footprint-scale-month')));
      await tester.pump();
      for (var frame = 0; frame < 12; frame++) {
        await tester.pump(const Duration(milliseconds: 30));
        expect(tester.getRect(segments).top, closeTo(small.top, .1));
        expect(tester.getRect(segments).width, closeTo(small.width, .1));
      }
      await tester.pumpAndSettle();
      await tester.dragFrom(const Offset(280, 400), const Offset(-270, 0));
      for (var frame = 0; frame < 12; frame++) {
        await tester.pump(const Duration(milliseconds: 30));
        expect(tester.getRect(segments).width, closeTo(small.width, .1));
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await captureUiFix(tester, '214-footprint-after-switch');
      final active = find
          .descendant(
            of: find.byKey(const ValueKey('listening-footprint-scroll')),
            matching: find.byType(Scrollable),
          )
          .first;
      tester.state<ScrollableState>(active).position.jumpTo(0);
      await tester.pumpAndSettle();
      expect(tester.getSize(segments).width, closeTo(full.width, .1));
    },
  );
}
