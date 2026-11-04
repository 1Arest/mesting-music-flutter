import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/music_platform/platform_backend_providers.dart';
import 'package:mesting_music/features/music_platform/netease/diagnostics/netease_listening_audit.dart';
import 'package:mesting_music/features/music_platform/netease/diagnostics/netease_listening_audit_provider.dart';
import 'package:mesting_music/features/music_platform/netease/footprint/official_footprint_page.dart';
import 'package:mesting_music/features/music_platform/netease/footprint/official_footprint_providers.dart';
import 'release_137_footprint_test.dart' show FootprintFixture;
import 'release_136_listening_audit_test.dart' show report, day;
import 'support/release_133_qa.dart';

class _Account extends PlatformAccountController {
  @override
  Future<PlatformSession?> build() async => const PlatformSession(
    platform: MusicPlatform.netease,
    userId: '987654',
    token: 'fixture-only',
  );
  void clear() => state = const AsyncData(null);
  void change() => state = const AsyncData(
    PlatformSession(
      platform: MusicPlatform.netease,
      userId: '222',
      token: 'second-fixture',
    ),
  );
}

void main() {
  setUpAll(initialize133QA);
  late FootprintFixture source;
  late FootprintFixture second;
  late DateTime now;
  setUp(() {
    source = FootprintFixture();
    second = FootprintFixture()
      ..dailyMinutes = 1
      ..monthlyMinutes = 60
      ..totalValue = 7200;
    now = DateTime.utc(2026, 11, 2);
    SharedPreferences.setMockInitialValues({});
  });
  const capture = ValueKey('footprint137-capture');
  Future<ProviderContainer> mount(
    WidgetTester tester, {
    bool compact = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        usesNeteaseProvider.overrideWithValue(true),
        platformAccountProvider.overrideWith(_Account.new),
        officialFootprintSourceProvider.overrideWith(
          (ref) => ref.watch(platformAccountProvider).value?.userId == '222'
              ? second
              : source,
        ),
        officialFootprintClockProvider.overrideWithValue(() => now),
        neteaseListeningAuditProvider(
          '2026-10',
        ).overrideWith((_) async => report(days: [day()])),
        neteaseListeningAuditProvider('2026-09').overrideWith(
          (_) async => NeteaseListeningAudit.build(
            owner: 'netease:987654',
            month: '2026-09',
            days: [],
            entries: [],
            now: now,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(platformAccountProvider.future);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = compact
        ? const Size(320, 650)
        : const Size(390, 844);
    addTearDown(tester.view.reset);
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: RepaintBoundary(
          key: capture,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            navigatorKey: nav,
            theme: theme133(compact),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(compact ? 1.5 : 1)),
              child: child!,
            ),
            home: const Scaffold(body: Text('设置根页')),
          ),
        ),
      ),
    );
    nav.currentState!.push<void>(
      MaterialPageRoute(builder: (_) => const OfficialFootprintPage()),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    return container;
  }

  Finder scrollable() => find
      .descendant(
        of: find.byKey(const ValueKey('official-footprint-list')),
        matching: find.byType(Scrollable),
      )
      .first;
  Future<void> reveal(
    WidgetTester tester,
    Finder finder, {
    bool up = false,
  }) async {
    await tester.scrollUntilVisible(
      finder,
      up ? -280 : 280,
      scrollable: scrollable(),
    );
    await Scrollable.ensureVisible(tester.element(finder), alignment: .3);
    await tester.pumpAndSettle();
  }

  Future<void> shot(WidgetTester tester, String name) async {
    if (!const bool.fromEnvironment('CAPTURE_137')) return;
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(capture),
    );
    if (boundary.debugNeedsPaint) await tester.pump();
    final future = boundary.toImage();
    await tester.runAsync(() async {
      final image = await future;
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        final path = Directory(
          'D:/AnLi/.codex-artifacts/2026-11-02-release137/ui',
        );
        await path.create(recursive: true);
        await File(
          '${path.path}/$name.png',
        ).writeAsBytes(data!.buffer.asUint8List());
      } finally {
        image.dispose();
      }
    });
  }

  for (final compact in [false, true]) {
    testWidgets(
      'official readings, retained failure and monthly comparison compact=$compact',
      (tester) async {
        final container = await mount(tester, compact: compact);
        expect(find.text('17 分钟'), findsOneWidget);
        expect(find.text('1 小时 18 分钟'), findsOneWidget);
        await shot(tester, 'current-$compact');
        await reveal(tester, find.text('历史总时长'));
        expect(find.text('5609 小时 16 分钟'), findsOneWidget);
        await reveal(
          tester,
          find.byKey(const ValueKey('footprint-refresh')),
          up: true,
        );
        source.fail = true;
        await tester.tap(find.byKey(const ValueKey('footprint-refresh')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('17 分钟'), findsOneWidget);
        expect(find.text('刷新失败，保留上次成功读取值'), findsWidgets);
        final reader = container.read(officialFootprintReaderProvider)!;
        expect(
          reader.today.failed && reader.month.failed && reader.total.failed,
          isTrue,
        );
        await shot(tester, 'failed-$compact');
        source.fail = false;
        final history = find.byKey(const ValueKey('footprint-history'));
        await reveal(tester, history);
        // The fixed-height glass pill must not clip a wrapped label at 1.5x.
        final label = tester.renderObject<RenderParagraph>(
          find.text('读取月报并核对'),
        );
        expect(
          label.getBoxesForSelection(
            const TextSelection(baseOffset: 0, extentOffset: 7),
          ),
          hasLength(1),
        );
        await tester.tap(history);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump();
        expect(find.text('2026-10 官方月报：10 小时 0 分钟'), findsOneWidget);
        expect(find.textContaining('本机网易云歌曲：11 小时 23 分钟'), findsOneWidget);
        await reveal(tester, find.text('2026-10 官方月报：10 小时 0 分钟'));
        await shot(tester, 'history-$compact');
        // At the real scroll limit the final paragraph clears the footer.
        final position = tester.state<ScrollableState>(scrollable()).position;
        position.jumpTo(position.maxScrollExtent);
        await tester.pumpAndSettle();
        expect(
          tester.getRect(find.textContaining('官方包含多端、播客及有声书')).bottom,
          lessThan(tester.view.physicalSize.height - 100),
        );
        expect(source.historyReads, 1);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets(
    'late response from first account cannot replace second account readings',
    (tester) async {
      source.totalPending = Completer();
      final container = await mount(tester);
      (container.read(platformAccountProvider.notifier) as _Account).change();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(find.text('1 分钟'), findsOneWidget);
      source.totalPending!.complete(20193360);
      await tester.pump();
      await reveal(tester, find.text('历史总时长'));
      expect(find.text('2 小时 0 分钟'), findsOneWidget);
      expect(find.text('5609 小时 16 分钟'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'switching account while a request is pending removes all previous readings',
    (tester) async {
      source.totalPending = Completer();
      final container = await mount(tester);
      expect(find.text('17 分钟'), findsOneWidget);
      (container.read(platformAccountProvider.notifier) as _Account).clear();
      await tester.pump();
      source.totalPending!.complete(20193360);
      await tester.pump();
      expect(find.text('请返回并选择网易云账号'), findsOneWidget);
      expect(find.text('17 分钟'), findsNothing);
      expect(find.text('5609 小时 16 分钟'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'month switch clears previous month and new empty local data is distinct',
    (tester) async {
      await mount(tester);
      await reveal(tester, find.byKey(const ValueKey('footprint-history')));
      await tester.tap(find.byKey(const ValueKey('footprint-history')));
      await tester.pumpAndSettle();
      await reveal(tester, find.byKey(const ValueKey('footprint-month')));
      await tester.tap(find.text('2026-10'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2026-09'));
      await tester.pumpAndSettle();
      expect(find.text('2026-10 官方月报：10 小时 0 分钟'), findsNothing);
      await reveal(tester, find.byKey(const ValueKey('footprint-history')));
      await tester.tap(find.byKey(const ValueKey('footprint-history')));
      await tester.pumpAndSettle();
      expect(find.text('2026-09 官方月报：10 小时 0 分钟'), findsOneWidget);
      expect(find.textContaining('本机网易云歌曲：0 分钟'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'history glass button cancels held scrolling without starting a read',
    (tester) async {
      await mount(tester);
      final button = find.byKey(const ValueKey('footprint-history'));
      await reveal(tester, button);
      final glass = find
          .descendant(of: button, matching: find.byType(AdaptiveGlass))
          .first;
      final width = tester.getRect(glass).width;
      final gesture = await tester.startGesture(tester.getCenter(button));
      await tester.pump(const Duration(milliseconds: 180));
      await gesture.moveBy(const Offset(0, -55));
      await gesture.moveBy(const Offset(0, -30));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.widget<AdaptiveGlass>(glass).glowIntensity, 0);
      expect(tester.getRect(glass).width, closeTo(width, 1));
      expect(source.historyReads, 0);
      await gesture.up();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'foreground recovery rereads a new day and keeps the old date explicit on failure',
    (tester) async {
      await mount(tester);
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      now = DateTime.utc(2026, 11, 2, 16, 1);
      source.day = '2026-11-03';
      source.fail = true;
      for (final state in [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('今日收听 · 2026-11-03'), findsOneWidget);
      expect(find.text('上次记录 2026-11-02：17 分钟'), findsOneWidget);
      expect(find.text('日期已变化，上次记录不代表当前日期的数据'), findsNWidgets(2));
      expect(source.weekReads, 2);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
