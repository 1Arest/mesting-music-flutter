import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/music_platform/netease/netease_music_repository.dart';
import 'package:mesting_music/features/music_platform/netease/netease_official_ranking_page.dart';
import 'package:mesting_music/shared/widgets/beta_swipe_pages.dart';

import 'release198_ui_test.dart' show capture193Theme;
import 'support/personal_profile_fixture.dart';
import 'support/ui_fix_capture.dart';

class _Records implements NeteaseMusicRepository {
  final calls = <int>[];
  Completer<Map<String, dynamic>>? pendingWeek;

  static Map<String, dynamic> data(bool weekly) => {
    weekly ? 'weekData' : 'allData': [
      for (var i = 0; i < 40; i++)
        {
          'playCount': (weekly ? 100 : 1000) - i,
          'score': 0,
          'song': {
            'id': (weekly ? 10000 : 20000) + i,
            'name': '${weekly ? '周榜' : '累计'}歌曲 $i',
            'ar': [
              {'id': 1, 'name': '测试歌手'},
            ],
            'al': {'id': 1, 'name': '测试专辑'},
            'dt': 240000,
          },
        },
    ],
  };

  @override
  Future<Map<String, dynamic>> call(
    String route, [
    Map<String, Object?> query = const {},
    Future<void>? abort,
  ]) async {
    if (route != '/user/record') return {};
    final period = query['type']! as int;
    calls.add(period);
    if (period == 1 && pendingWeek != null) return pendingWeek!.future;
    return data(period == 1);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Account extends SyntheticProfileAccount {
  void replace() {
    state = const AsyncData(
      PlatformSession(
        userId: '7002',
        token: 'replacement-fixture',
        nickname: '另一个测试账号',
        platform: MusicPlatform.netease,
      ),
    );
  }
}

/// The shared header intentionally scrolls long titles at large text sizes.
/// Advance beyond the finite tab/scroll transitions without waiting for that
/// continuous accessibility marquee to stop.
Future<void> _finishRankingMotion(WidgetTester tester) async {
  await tester.pump();
  for (var frame = 0; frame < 12; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  final viewport = find.byType(PageView);
  if (viewport.evaluate().isNotEmpty) {
    expect(
      tester
          .widget<PageView>(viewport)
          .controller!
          .position
          .isScrollingNotifier
          .value,
      isFalse,
    );
  }
}

void main() {
  setUpAll(() async {
    await LiquidGlassWidgets.initialize();
    await initializeUiFixCapture();
  });

  for (final spec in [
    (width: 390.0, scale: 1.0, dark: true),
    (width: 320.0, scale: 1.6, dark: false),
    (width: 820.0, scale: 1.3, dark: false),
  ]) {
    testWidgets(
      'ranking uses download-style tabs and retains both pages $spec',
      (tester) async {
        tester.view.physicalSize = Size(spec.width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final records = _Records();
        final fixture = await PersonalProfileFixture.create(
          musicRepository: records,
        );
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox());
          await tester.runAsync(fixture.dispose);
        });
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: fixture.container,
            child: MaterialApp(
              theme: capture193Theme(spec.dark),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(spec.scale)),
                child: child!,
              ),
              home: RepaintBoundary(
                key: uiFixCaptureKey,
                child: const NeteaseOfficialRankingPage(),
              ),
            ),
          ),
        );
        await _finishRankingMotion(tester);
        final tabs = find.byType(CupertinoSlidingSegmentedControl<int>);
        final pages = find.byType(BetaSwipePages);
        expect(tabs, findsOneWidget);
        expect(tester.widget<BetaSwipePages>(pages).index, 0);
        expect(find.text('播放 100 次'), findsOneWidget);
        await captureUiFix(
          tester,
          '202-ranking-week-${spec.width}-${spec.scale}',
          settleAnimations: false,
        );

        final weekly = find.byKey(const ValueKey('official-ranking-week'));
        await tester.drag(weekly, const Offset(0, -470));
        await _finishRankingMotion(tester);
        final weekPosition = tester.widget<ListView>(weekly).controller!.offset;
        expect(weekPosition, greaterThan(100));
        await tester.tap(find.text('累计排行'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 48));
        final viewport = find.descendant(
          of: pages,
          matching: find.byType(PageView),
        );
        expect(
          tester.widget<PageView>(viewport).controller!.page,
          inExclusiveRange(0, 1),
        );
        await _finishRankingMotion(tester);
        expect(tester.widget<BetaSwipePages>(pages).index, 1);
        final all = find.byKey(const ValueKey('official-ranking-all'));
        expect(tester.widget<ListView>(all).controller!.offset, 0);
        expect(
          find.descendant(of: all, matching: find.text('播放 1000 次')),
          findsOneWidget,
        );
        await captureUiFix(
          tester,
          '202-ranking-all-${spec.width}-${spec.scale}',
          settleAnimations: false,
        );
        await tester.drag(all, const Offset(0, -610));
        await _finishRankingMotion(tester);
        final allPosition = tester.widget<ListView>(all).controller!.offset;

        await tester.drag(pages, Offset(spec.width * .8, 0));
        await _finishRankingMotion(tester);
        expect(tester.widget<BetaSwipePages>(pages).index, 0);
        expect(
          tester.widget<ListView>(weekly).controller!.offset,
          closeTo(weekPosition, .1),
        );
        await tester.drag(pages, Offset(-spec.width * .8, 0));
        await _finishRankingMotion(tester);
        expect(tester.widget<BetaSwipePages>(pages).index, 1);
        expect(
          tester.widget<ListView>(all).controller!.offset,
          closeTo(allPosition, .1),
        );
        expect(records.calls.where((period) => period == 0), hasLength(1));
        expect(records.calls.where((period) => period == 1), hasLength(1));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('a previous account response cannot repopulate the ranking', (
    tester,
  ) async {
    final records = _Records()..pendingWeek = Completer();
    final fixture = await PersonalProfileFixture.create(
      musicRepository: records,
      accountFactory: _Account.new,
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(fixture.dispose);
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: fixture.container,
        child: const MaterialApp(home: NeteaseOfficialRankingPage()),
      ),
    );
    await tester.pump();
    expect(records.calls, contains(1));
    (fixture.container.read(platformAccountProvider.notifier) as _Account)
        .replace();
    await tester.pump();
    records.pendingWeek!.complete(_Records.data(true));
    await tester.pumpAndSettle();
    expect(find.text('账号已变化，请返回后重新打开'), findsOneWidget);
    expect(find.byType(BetaSwipePages), findsNothing);
    expect(find.text('播放 100 次'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
