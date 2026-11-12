import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mesting_music/features/app_update/app_update_providers.dart';
import 'package:mesting_music/features/app_update/domain/app_update_models.dart';
import 'package:mesting_music/features/app_update/presentation/beta_app_update_sheet.dart';
import 'package:mesting_music/features/themes/app_theme.dart';
import 'package:mesting_music/features/themes/music_theme_preset.dart';
import 'package:ring_download_sdk/ring_download_sdk.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';

const _capture = bool.fromEnvironment('CAPTURE_UPDATE_UI');
const _current = AppVersionInfo(
  packageName: 'com.mesting.music',
  versionName: '1.0.96',
  versionCode: 117,
);
AppUpdateManifest _release({int count = 4}) => AppUpdateManifest(
  packageName: _current.packageName,
  versionName: '1.0.99',
  versionCode: 120,
  minimumVersionCode: 1,
  mandatory: false,
  title: '发现新版本',
  releaseNotes: List.generate(
    count,
    (i) => i < 4
        ? const [
            '修复重新打开后播放进度在点击播放前显示为零的问题。',
            '暂停时可点击或拖动进度条，保存选定位置。',
            '进度和时间在拖动时跟随手指，松手后跳转。',
            '保留原有更新内容、下载校验与系统安装确认。',
          ][i]
        : '第 ${i + 1} 条完整更新说明，长内容也不丢失。',
  ),
  apkUrl: Uri.parse('https://download.csnas.asia/music/download'),
  sha256: 'a' * 64,
  sizeBytes: 124 * 1048576,
  publishedAt: DateTime.utc(2026, 11, 12),
);

AppUpdateState _state(AppUpdatePhase phase, {int notes = 4}) => AppUpdateState(
  phase: phase,
  currentVersion: _current,
  manifest: _release(count: notes),
  receivedBytes: phase == AppUpdatePhase.available ? 0 : 84 * 1048576,
  totalBytes: 124 * 1048576,
);

RingTransferStatistics _stats({
  bool payload = true,
  bool available = true,
  bool cancelling = false,
}) => RingTransferStatistics(
  state: RingDownloadState.transferring,
  elapsed: const Duration(seconds: 6),
  receivedBytes: 84 * 1048576,
  totalBytes: 124 * 1048576,
  available: available,
  cancelling: cancelling,
  bytesPerSecond: 6.8 * 1048576,
  httpsBytesPerSecond: 1.9 * 1048576,
  peerBytesPerSecond: payload ? 3.6 * 1048576 : 0,
  seedBytesPerSecond: payload ? 1.3 * 1048576 : 0,
  peerVerifiedBytes: payload ? 30 * 1048576 : 0,
  seedVerifiedBytes: payload ? 10 * 1048576 : 0,
  estimatedRemaining: const Duration(seconds: 6),
  nodes: [
    for (var i = 1; i <= 3; i++)
      RingNodeTransferStatistics(
        alias: 'node$i',
        source: i == 3 ? RingNodeSource.seed : RingNodeSource.peer,
        state: payload ? RingNodeState.receiving : RingNodeState.connected,
        receivedBytes: payload ? 1048576 : 0,
        verifiedBytes: payload ? 1048576 : 0,
        bytesPerSecond: payload ? 1048576 : 0,
      ),
  ],
);

class _Controller extends AppUpdateController {
  _Controller(this.initial);
  final AppUpdateState initial;
  int pauses = 0;
  @override
  AppUpdateState build() => initial;
  @override
  Future<void> pauseDownload() async {
    pauses++;
    state = state.copyWith(phase: AppUpdatePhase.paused);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await LiquidGlassWidgets.initialize();
    if (!_capture) return;
    final data = await File('C:/Windows/Fonts/msyh.ttc').readAsBytes();
    for (final family in [
      'UpdateQA',
      'Roboto',
      'CupertinoSystemText',
      'CupertinoSystemDisplay',
    ]) {
      await (FontLoader(
        family,
      )..addFont(Future.value(ByteData.sublistView(data)))).load();
    }
    await (FontLoader('packages/cupertino_icons/CupertinoIcons')..addFont(
          rootBundle.load('packages/cupertino_icons/assets/CupertinoIcons.ttf'),
        ))
        .load();
    final font = File.fromUri(
      File(
        Platform.resolvedExecutable,
      ).uri.resolve('../../material_fonts/MaterialIcons-Regular.otf'),
    );
    await (FontLoader(
      'MaterialIcons',
    )..addFont(font.readAsBytes().then(ByteData.sublistView))).load();
  });

  Future<_Controller> mount(
    WidgetTester tester,
    AppUpdateState state, {
    bool dark = false,
    double scale = 1,
    Size size = const Size(390, 844),
    RingTransferStatistics? statistics,
    Widget? child,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final controller = _Controller(state);
    var theme = buildMestingTheme(
      musicThemePresetById(dark ? 'classic-dark' : 'classic'),
    );
    if (_capture) {
      theme = theme.copyWith(
        textTheme: theme.textTheme.apply(fontFamily: 'UpdateQA'),
      );
    }
    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          appUpdateControllerProvider.overrideWith(() => controller),
          appUpdateDownloadTransportProvider.overrideWithValue(null),
          appUpdateStatisticsProvider.overrideWith(
            (ref) => Stream.value(statistics),
          ),
        ],
        child: LiquidGlassWidgets.wrap(
          adaptiveQuality: false,
          child: MaterialApp(
            theme: theme,
            builder: (context, widget) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: widget!,
            ),
            home: RepaintBoundary(
              key: const ValueKey('update-ui-capture'),
              child: Scaffold(
                body: Align(
                  alignment: Alignment.bottomCenter,
                  child: child ?? const BetaAppUpdateSheet(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (state.phase == AppUpdatePhase.verifying ||
        state.phase == AppUpdatePhase.checking) {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
    } else {
      await tester.pumpAndSettle();
    }
    return controller;
  }

  Future<void> capture(WidgetTester tester, String name) async {
    if (!_capture) return;
    final widgets = tester.widgetList<Image>(find.byType(Image)).toList();
    if (widgets.isNotEmpty) {
      final context = tester.element(find.byType(Image).first);
      await tester.runAsync(
        () => Future.wait([
          for (final image in widgets) precacheImage(image.image, context),
        ]),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
    }
    final future = tester
        .renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('update-ui-capture')),
        )
        .toImage(pixelRatio: 2);
    await tester.runAsync(() async {
      final image = await future;
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final dir = const String.fromEnvironment(
        'UPDATE_UI_OUTPUT',
        defaultValue: '.codex-artifacts/update-ui',
      );
      final file = File('$dir/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    });
  }

  for (final dark in [false, true]) {
    testWidgets('update states retain notes and reachable controls ($dark)', (
      tester,
    ) async {
      await mount(tester, _state(AppUpdatePhase.available), dark: dark);
      expect(find.text('发现新版本'), findsOneWidget);
      expect(find.text('本次更新'), findsOneWidget);
      expect(find.textContaining('当前版本 1.0.96'), findsOneWidget);
      expect(find.textContaining('1.0.96'), findsOneWidget);
      expect(find.textContaining('1.0.99'), findsOneWidget);
      expect(find.text('下载并更新'), findsOneWidget);
      expect(find.text('稍后提醒我'), findsOneWidget);
      expect(find.byKey(const ValueKey('update-download-card')), findsNothing);
      await capture(tester, 'available-${dark ? 'dark' : 'light'}');
      expect(tester.takeException(), isNull);
    });
    testWidgets('live download, disclosure and pause ($dark)', (tester) async {
      final controller = await mount(
        tester,
        _state(AppUpdatePhase.downloading),
        dark: dark,
        statistics: _stats(),
      );
      expect(find.text('P2P 协同下载'), findsOneWidget);
      expect(find.text('6.8 MB/s'), findsOneWidget);
      expect(find.text('预计剩余 6 秒'), findsOneWidget);
      expect(find.text('3 路正在接收'), findsOneWidget);
      await capture(tester, 'downloading-${dark ? 'dark' : 'light'}');
      final action = find.byKey(const ValueKey('app-update-primary'));
      final before = tester.getRect(action);
      await tester.tap(
        find.byKey(const ValueKey('update-transfer-details-toggle')),
      );
      await tester.pumpAndSettle();
      expect(find.text('服务器 HTTPS'), findsOneWidget);
      expect(find.text('普通节点 · 2 路'), findsOneWidget);
      expect(find.text('种子节点 · 1 路'), findsOneWidget);
      expect(tester.getRect(action).bottom, closeTo(before.bottom, .1));
      await capture(tester, 'expanded-${dark ? 'dark' : 'light'}');
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(controller.pauses, 1);
      expect(find.text('下载已暂停'), findsWidgets);
      expect(find.text('6.8 MB/s'), findsNothing);
      expect(find.text('预计剩余 6 秒'), findsNothing);
      expect(find.text('继续下载'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('connected alone and unavailable counters never claim P2P', (
    tester,
  ) async {
    for (final sample in [_stats(payload: false), _stats(available: false)]) {
      await mount(
        tester,
        _state(AppUpdatePhase.downloading),
        statistics: sample,
      );
      expect(find.text('P2P 协同下载'), findsNothing);
      if (sample.available) {
        expect(find.text('节点已连接 · 等待数据'), findsOneWidget);
      } else {
        expect(find.text('6.8 MB/s'), findsNothing);
      }
      expect(tester.takeException(), isNull);
    }
  });
  testWidgets('verification and prepared receipt hide stale transfer rates', (
    tester,
  ) async {
    await mount(tester, _state(AppUpdatePhase.verifying), statistics: _stats());
    expect(find.text('6.8 MB/s'), findsNothing);
    expect(find.text('预计剩余 6 秒'), findsNothing);
    expect(find.text('P2P 协同下载'), findsNothing);
    await capture(tester, 'verifying');
    await mount(
      tester,
      _state(
        AppUpdatePhase.readyToInstall,
      ).copyWith(downloadedPath: 'verified.apk'),
      statistics: _stats(),
    );
    expect(find.text('安装包已校验'), findsOneWidget);
    expect(find.text('安装更新'), findsOneWidget);
    expect(find.text('P2P 协同下载'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('all long notes remain scrollable without displacing actions', (
    tester,
  ) async {
    await mount(
      tester,
      _state(AppUpdatePhase.downloading, notes: 12),
      statistics: _stats(),
    );
    final button = find.byKey(const ValueKey('app-update-primary'));
    final before = tester.getRect(button);
    await tester.scrollUntilVisible(
      find.text('第 12 条完整更新说明，长内容也不丢失。'),
      160,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('update-notes-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(tester.getRect(button).bottom, closeTo(before.bottom, .1));
    expect(find.text('第 12 条完整更新说明，长内容也不丢失。'), findsOneWidget);
    expect(find.byKey(const ValueKey('app-update-view-notes')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'short, narrow and large-text layouts scroll instead of overflow',
    (tester) async {
      for (final size in [const Size(320, 640), const Size(720, 390)]) {
        await mount(
          tester,
          _state(AppUpdatePhase.downloading, notes: 12),
          statistics: _stats(),
          size: size,
          scale: 1.6,
        );
        expect(
          find.byKey(const ValueKey('update-sheet-compact-scroll')),
          findsOneWidget,
        );
        await tester.ensureVisible(
          find.byKey(const ValueKey('app-update-primary')),
        );
        expect(tester.takeException(), isNull);
      }
    },
  );
}
