import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mesting_music/core/diagnostics/diagnostic_activity.dart';
import 'package:mesting_music/core/audio/playback_providers.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/features/music_platform/netease/ad_probe/netease_ad_probe_page.dart';
import 'package:mesting_music/features/music_platform/netease/ad_probe/netease_ad_probe_provider.dart';
import 'package:mesting_music/features/music_platform/netease/ad_probe/netease_ad_probe_report.dart';
import 'package:mesting_music/features/music_platform/netease/ad_probe/netease_ad_probe_repository.dart';
import 'package:mesting_music/features/music_platform/netease/netease_rewards.dart';
import 'package:mesting_music/features/music_platform/netease/netease_rewards_provider.dart';
import 'package:mesting_music/features/music_platform/presentation/netease_reward_calendar.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'netease_ad_probe181_test.dart' show adProbe181Report;
import 'support/release_147_qa.dart' show load147IconFonts;

const _capture = bool.fromEnvironment('CAPTURE_181');

class _Probe implements NeteaseAdProbeService {
  @override
  bool isCurrent = true;
  int reads = 0, cancels = 0;
  Completer<NeteaseAdProbeReport>? pending;
  @override
  Future<NeteaseAdProbeReport> inspect({
    required Future<void> cancelled,
  }) async {
    reads++;
    unawaited(cancelled.then((_) => cancels++));
    return pending == null ? adProbe181Report() : pending!.future;
  }
}

class _Rewards implements NeteaseRewardService {
  int writes = 0;
  @override
  String get ownerId => 'ad-probe-fixture181';
  @override
  Future<NeteaseRewardSnapshot> load() async => NeteaseRewardSnapshot(
    now: DateTime(2026, 11, 9),
    recordsAvailable: true,
    signedToday: true,
    freeListen: const NeteaseFreeListenSnapshot(remainingSeconds: 300),
  );
  @override
  Future<NeteaseRewardResult> signIn() async {
    writes++;
    return const NeteaseRewardResult(success: false, message: 'test');
  }

  @override
  Future<NeteaseRewardResult> claimAd({bool Function()? stillCurrent}) =>
      signIn();
}

void main() {
  final disposed = <ProviderContainer>{};
  void dispose(ProviderContainer container) {
    if (disposed.add(container)) container.dispose();
  }

  setUpAll(() async {
    await LiquidGlassWidgets.initialize();
    if (_capture) {
      await load147IconFonts();
      await (FontLoader('NeteaseQA181')..addFont(
            File(
              'C:/Windows/Fonts/msyh.ttc',
            ).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
    }
  });
  String clipboard = '';
  setUp(() {
    clipboard = '';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard = (call.arguments as Map)['text'] as String;
          }
          if (call.method == 'Clipboard.getData') return {'text': clipboard};
          return null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<ProviderContainer> mount(
    WidgetTester tester,
    _Probe probe, {
    bool dark = false,
    bool large = false,
    GlobalKey? boundary,
    bool calendar = false,
    _Rewards? rewards,
  }) async {
    final width = large ? 320.0 : 390.0;
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({
      'app_haptics_enabled_v1': false,
      NeteaseRewardsController.autoKey('ad-probe-fixture181'): false,
    });
    final preferences = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        qishuiNavigationProvider.overrideWithValue(false),
        currentMediaItemProvider.overrideWith((ref) => Stream.value(null)),
        audioHandlerProvider.overrideWith(
          (ref) =>
              throw StateError('The configuration page must not start audio'),
        ),
        neteaseAdProbeServiceProvider.overrideWith((ref) async => probe),
        if (rewards != null)
          neteaseRewardServiceProvider.overrideWith((ref) async => rewards),
      ],
    );
    addTearDown(() => dispose(container));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            brightness: dark ? Brightness.dark : Brightness.light,
            fontFamily: _capture ? 'NeteaseQA181' : null,
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(large ? 2 : 1)),
            child: RepaintBoundary(key: boundary, child: child),
          ),
          home: calendar
              ? const NeteaseRewardCalendar()
              : const NeteaseAdProbePage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  Future<void> screenshot(
    WidgetTester tester,
    GlobalKey key,
    String name,
  ) async {
    if (!_capture) return;
    await tester.runAsync(() async {
      final image =
          await (key.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage(pixelRatio: 1);
      try {
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final out = File('.codex-artifacts/2026-11-09-release181/ui/$name.png');
        await out.parent.create(recursive: true);
        await out.writeAsBytes(bytes!.buffer.asUint8List());
      } finally {
        image.dispose();
      }
    });
  }

  for (final dark in [false, true]) {
    for (final large in [false, true]) {
      testWidgets('manual read/copy and layout dark=$dark large=$large', (
        tester,
      ) async {
        final key = GlobalKey();
        final probe = _Probe();
        await mount(tester, probe, dark: dark, large: large, boundary: key);
        expect(probe.reads, 0);
        final read = find.byKey(const ValueKey('netease-ad-probe-read'));
        await tester.ensureVisible(read);
        await tester.tap(read);
        await tester.pumpAndSettle();
        expect(probe.reads, 1);
        expect(
          find.text(NeteaseAdProbeOutcome.configurationObserved.label),
          findsOneWidget,
        );
        final copy = find.byKey(const ValueKey('netease-ad-probe-copy'));
        await tester.ensureVisible(copy);
        await tester.tap(copy);
        await tester.pumpAndSettle();
        expect((jsonDecode(clipboard) as Map)['rewardSubmitted'], isFalse);
        expect(clipboard, isNot(contains('private-')));
        expect(find.text('已复制并核对，可粘贴发送。'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.drag(find.byType(ListView).first, const Offset(0, 1000));
        await tester.pumpAndSettle();
        await screenshot(
          tester,
          key,
          'ad-probe-${dark ? 'dark' : 'light'}-${large ? 'large' : 'normal'}',
        );
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  testWidgets('stop cancels read and late completion cannot appear', (
    tester,
  ) async {
    final pending = Completer<NeteaseAdProbeReport>();
    final probe = _Probe()..pending = pending;
    await mount(tester, probe);
    await tester.tap(find.byKey(const ValueKey('netease-ad-probe-read')));
    await tester.pump();
    expect(probe.reads, 1);
    final stop = find.byKey(const ValueKey('netease-ad-probe-stop'));
    await tester.ensureVisible(stop);
    await tester.tap(stop);
    await tester.pumpAndSettle();
    expect(probe.cancels, 1);
    pending.complete(adProbe181Report());
    await tester.pumpAndSettle();
    expect(
      find.text(NeteaseAdProbeOutcome.configurationObserved.label),
      findsNothing,
    );
    expect(find.text('本次读取已停止。'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('service replacement clears report and pending completion', (
    tester,
  ) async {
    final pending = Completer<NeteaseAdProbeReport>();
    final probe = _Probe()..pending = pending;
    final container = await mount(tester, probe);
    await tester.tap(find.byKey(const ValueKey('netease-ad-probe-read')));
    await tester.pump();
    probe.isCurrent = false;
    container.invalidate(neteaseAdProbeServiceProvider);
    await tester.pumpAndSettle();
    pending.complete(adProbe181Report());
    await tester.pumpAndSettle();
    expect(
      find.text(NeteaseAdProbeOutcome.configurationObserved.label),
      findsNothing,
    );
    expect(clipboard, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('calendar opens read-only scope and releases it on return', (
    tester,
  ) async {
    final probe = _Probe(), rewards = _Rewards();
    final container = await mount(
      tester,
      probe,
      calendar: true,
      rewards: rewards,
    );
    final open = find.byKey(const ValueKey('netease-ad-probe-open'));
    await tester.scrollUntilVisible(
      open,
      350,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(open);
    await tester.pumpAndSettle();
    await tester.tap(open);
    await tester.pumpAndSettle();
    expect(container.read(diagnosticActivityProvider), isTrue);
    expect(probe.reads, 0);
    for (final lifecycle in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(lifecycle);
    }
    await tester.pumpAndSettle();
    expect(rewards.writes, 0);
    final context = tester.element(
      find.byKey(const ValueKey('netease-ad-probe-page')),
    );
    Navigator.of(context).pop();
    await tester.pumpAndSettle();
    expect(container.read(diagnosticActivityProvider), isFalse);
    expect(rewards.writes, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    // The reward controller owns a day-boundary timer; dispose it before the
    // widget harness checks for leaked timers (the teardown then is a no-op).
    dispose(container);
  });
}
