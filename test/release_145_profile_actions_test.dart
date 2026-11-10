import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/features/music_platform/netease/netease_connection_models.dart';
import 'package:mesting_music/features/music_platform/netease/netease_features_page.dart';
import 'package:mesting_music/features/music_platform/netease/netease_features_repository.dart';
import 'package:mesting_music/features/music_platform/netease/footprint/official_footprint.dart';
import 'package:mesting_music/features/music_platform/netease/footprint/official_footprint_providers.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/music_platform/presentation/beta_personal_profile.dart';
import 'package:mesting_music/features/music_platform/presentation/netease_personal_statistics.dart';
import 'package:mesting_music/shared/widgets/beta_bottom_search.dart';
import 'package:mesting_music/shared/widgets/beta_glass_controls.dart';
import 'package:mesting_music/shared/widgets/beta_scroll_behavior.dart';
import 'support/personal_profile_fixture.dart';
import 'support/pump_artwork_ready.dart';
import 'support/release_145_qa.dart';

class _TotalSource implements OfficialFootprintSource {
  int calls = 0;
  bool fail = false;
  @override
  Future<int> totalSeconds() async {
    calls++;
    if (fail) throw StateError('Synthetic unavailable');
    return 5610 * 3600 + 120;
  }

  @override
  Future<OfficialListenPeriod> currentWeek() async =>
      throw UnimplementedError();
  @override
  Future<OfficialListenPeriod> currentMonth() async =>
      throw UnimplementedError();
  @override
  Future<OfficialListenPeriod> history(String month) async =>
      throw UnimplementedError();
}

void main() {
  setUpAll(initialize145QA);
  Future<void> mount(
    WidgetTester tester,
    PersonalProfileFixture fixture,
    Widget child, {
    bool dark = false,
    bool narrow = false,
  }) async {
    final host = BetaBottomSearchHost(
      location: '/profile',
      openMusicSearch: () {},
    );
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(narrow ? 320 : 390, 844);
    tester.view.padding = const FakeViewPadding(top: 44, bottom: 34);
    tester.view.viewPadding = const FakeViewPadding(top: 44, bottom: 34);
    addTearDown(tester.view.reset);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      host.dispose();
      await fixture.dispose();
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: fixture.container,
        child: MaterialApp(
          theme: theme145(dark),
          scrollBehavior: const BetaScrollBehavior(),
          builder: (context, child) => capture145Builder(
            context,
            MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(
                disableAnimations: true,
                textScaler: TextScaler.linear(narrow ? 1.3 : 1),
              ),
              child: child!,
            ),
          ),
          home: BetaBottomSearchScope(
            host: host,
            child: Scaffold(body: child),
          ),
        ),
      ),
    );
    await pumpArtworkReady(tester);
    await tester.pumpAndSettle();
  }

  for (final dark in [false, true]) {
    testWidgets(
      'My shows official metric row, preserves music collections dark=$dark',
      (tester) async {
        final source = _TotalSource();
        final fixture = await PersonalProfileFixture.create(
          footprintSource: source,
        );
        await mount(tester, fixture, const BetaPersonalProfile(), dark: dark);
        expect(find.text('674 首喜欢  ·  5 个歌单'), findsNothing);
        expect(find.text('9 关注'), findsOneWidget);
        expect(find.text('4 粉丝'), findsOneWidget);
        expect(find.text('5610 小时'), findsOneWidget);
        expect(find.text('Lv.9'), findsOneWidget);
        expect(find.text('我喜欢的音乐'), findsOneWidget);
        final metricYs = [
          for (final id in ['following', 'followers', 'level', 'duration'])
            tester.getCenter(find.byKey(ValueKey('netease-personal-$id'))).dy,
        ];
        expect(metricYs.toSet().length, 1);
        expect(source.calls, 1);
        source.fail = true;
        await fixture.container
            .read(officialFootprintReaderProvider)!
            .refreshTotalOnly();
        await tester.pumpAndSettle();
        expect(find.text('5610 小时'), findsOneWidget);
        expect(
          find.byTooltip('官方总时长 5610 小时 2 分钟，刷新失败，保留上次结果'),
          findsOneWidget,
        );
        await capture145UI(tester, 'my-${dark ? 'dark' : 'light'}');
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'missing or mismatched account totals never become zero or another owner',
    (tester) async {
      final source = _TotalSource()..fail = true;
      final fixture = await PersonalProfileFixture.create(
        footprintSource: source,
        personalStats: const NeteasePersonalStats(
          following: 123,
          followers: 456,
          ownerId: 'netease:other',
        ),
      );
      await mount(
        tester,
        fixture,
        NeteasePersonalStatistics(
          session: fixture.container.read(platformAccountProvider).value!,
        ),
        narrow: true,
      );
      expect(find.text('— 关注'), findsOneWidget);
      expect(find.text('— 粉丝'), findsOneWidget);
      expect(find.text('— 小时'), findsOneWidget);
      expect(find.text('123 关注'), findsNothing);
      expect(find.text('0 小时'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final narrow in [false, true]) {
    testWidgets(
      'four resource actions remain one accessible row narrow=$narrow',
      (tester) async {
        final fixture = await PersonalProfileFixture.create();
        var downloads = 0;
        await mount(
          tester,
          fixture,
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 40),
                NeteaseResourceActions(
                  item: const NeteaseItem(
                    id: '123',
                    name: '测试歌单',
                    kind: NeteaseEntity.playlist,
                  ),
                  showDownload: true,
                  onDownload: () => downloads++,
                ),
              ],
            ),
          ),
          dark: narrow,
          narrow: narrow,
        );
        final actions = ['save', 'more', 'comments', 'download'];
        final rects = [
          for (final id in actions)
            tester.getRect(find.byKey(ValueKey('resource-action-$id'))),
        ];
        expect(rects.map((r) => r.top).toSet().length, 1);
        expect(rects.every((r) => r.width >= 44 && r.height >= 44), true);
        expect(find.byTooltip('更多相关功能'), findsOneWidget);
        expect(find.byTooltip('歌单评论'), findsOneWidget);
        await tester.tap(
          find.byKey(const ValueKey('resource-action-download')),
        );
        await tester.pumpAndSettle();
        expect(downloads, 1);
        await tester.tap(find.byKey(const ValueKey('resource-action-save')));
        await tester.pumpAndSettle();
        expect(find.text('已收藏'), findsOneWidget);
        expect(
          tester
              .widget<BetaGlassButton>(
                find.byKey(const ValueKey('resource-action-save')),
              )
              .label,
          '取消收藏',
        );
        await capture145UI(
          tester,
          narrow ? 'actions-dark-narrow' : 'actions-light',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
