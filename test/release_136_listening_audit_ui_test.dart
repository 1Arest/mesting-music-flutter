import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/music_platform/platform_backend_providers.dart';
import 'package:mesting_music/features/music_platform/netease/diagnostics/netease_listening_audit.dart';
import 'package:mesting_music/features/music_platform/netease/diagnostics/netease_listening_audit_page.dart';
import 'package:mesting_music/features/music_platform/netease/diagnostics/netease_listening_audit_provider.dart';
import 'support/release_133_qa.dart';
import 'release_136_listening_audit_test.dart' show report, day, event;

class _Account extends PlatformAccountController {
  @override
  Future<PlatformSession?> build() async => const PlatformSession(
    platform: MusicPlatform.netease,
    userId: '987654',
    token: 'fixture-only',
  );
  void clear() => state = const AsyncData(null);
}

const _capture = ValueKey('audit136');
void main() {
  setUpAll(initialize133QA);
  late List<String> copied;
  late SharedPreferences preferences;
  setUp(() async {
    copied = [];
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add((call.arguments as Map)['text'] as String);
          }
          return null;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null),
  );
  Future<ProviderContainer> mount(
    WidgetTester tester, {
    bool compact = false,
    bool dark = false,
  }) async {
    final value = report(
      days: [day()],
      events: [
        event('private', payload: {'heardMs': 120000, 'time': 120}),
      ],
    );
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        usesNeteaseProvider.overrideWithValue(true),
        platformAccountProvider.overrideWith(_Account.new),
        neteaseListeningAuditProvider(
          '2026-10',
        ).overrideWith((_) async => value),
        neteaseListeningAuditProvider('2026-11').overrideWith(
          (_) async => NeteaseListeningAudit.build(
            owner: 'netease:987654',
            month: '2026-11',
            days: [],
            entries: [],
            now: DateTime(2026, 11, 1),
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
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: RepaintBoundary(
          key: _capture,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            navigatorKey: navigator,
            theme: theme133(dark),
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
    await tester.pump();
    // Match the real settings entry: this diagnostic is a pushed page, rather
    // than a Navigator root whose first popup changes edge-back availability.
    navigator.currentState!.push<void>(
      MaterialPageRoute(
        builder: (_) =>
            const NeteaseListeningAuditPage(initialMonth: '2026-10'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    return container;
  }

  Future<void> export(WidgetTester tester) async {
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('audit-export')),
      300,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('audit-export')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> shot(WidgetTester tester, String name) async {
    if (!const bool.fromEnvironment('CAPTURE_136')) return;
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_capture),
    );
    if (boundary.debugNeedsPaint) await tester.pump();
    final future = boundary.toImage();
    await tester.runAsync(() async {
      final image = await future;
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final f = File('.codex-artifacts/2026-11-01-release136/ui/$name.png');
      await f.parent.create(recursive: true);
      await f.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  for (final compact in [false, true]) {
    testWidgets(
      'monthly report separates local totals and saved log fields compact=$compact',
      (tester) async {
        await mount(tester, compact: compact, dark: compact);
        expect(find.text('全部歌曲真实收听：683 分钟 0 秒'), findsOneWidget);
        expect(copied, isEmpty);
        await shot(tester, 'summary-$compact');
        await export(tester);
        expect(find.text('2026-10 脱敏诊断'), findsOneWidget);
        expect(copied, isEmpty);
        await shot(tester, 'preview-$compact');
        await tester.tap(find.byKey(const ValueKey('audit-copy')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(copied, hasLength(1));
        expect(
          jsonDecode(copied.single)['missingFields']['durationMissingRealtime'],
          1,
        );
        expect(copied.single, isNot(contains('private')));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets('cancel and account switch prevent copying an old diagnostic', (
    tester,
  ) async {
    final container = await mount(tester);
    await export(tester);
    (container.read(platformAccountProvider.notifier) as _Account).clear();
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('audit-copy')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(copied, isEmpty);
    expect(find.text('账号已变化，请返回后重新打开'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'month selection loads a distinct snapshot and cancelling preview never copies',
    (tester) async {
      await mount(tester);
      await tester.tap(find.text('2026-10'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2026-11'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('全部歌曲真实收听：0 分钟 0 秒'), findsOneWidget);
      await export(tester);
      expect(find.text('2026-11 脱敏诊断'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(copied, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('export button cancels held drag and preserves glass feedback', (
    tester,
  ) async {
    await mount(tester);
    final button = find.byKey(const ValueKey('audit-export'));
    await tester.scrollUntilVisible(
      button,
      300,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pump();
    final lens = find
        .descendant(of: button, matching: find.byType(AdaptiveGlass))
        .first;
    final width = tester.getRect(lens).width;
    final gesture = await tester.startGesture(tester.getCenter(button));
    await tester.pump(const Duration(milliseconds: 180));
    await gesture.moveBy(const Offset(0, -50));
    await gesture.moveBy(const Offset(0, -35));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.widget<AdaptiveGlass>(lens).glowIntensity, 0);
    expect(tester.getRect(lens).width, closeTo(width, 1));
    expect(find.byKey(const ValueKey('audit-copy')), findsNothing);
    await gesture.up();
    await tester.pump();
    expect(copied, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
