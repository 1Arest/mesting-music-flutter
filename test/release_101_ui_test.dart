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
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/core/platform/distribution_channel.dart';
import 'package:mesting_music/features/app_update/app_update_providers.dart';
import 'package:mesting_music/features/app_update/domain/app_update_models.dart';
import 'package:mesting_music/features/app_update/presentation/app_update_sheet.dart';
import 'package:mesting_music/features/app_update/presentation/app_update_coordinator.dart';
import 'package:mesting_music/features/auth/beta_entry_flow.dart';
import 'package:mesting_music/features/auth/auth_providers.dart';
import 'package:mesting_music/features/auth/domain/auth_models.dart';
import 'package:mesting_music/features/auth/presentation/beta_welcome_page.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/music_platform/presentation/platform_comment_composer.dart';
import 'package:mesting_music/features/themes/app_theme.dart';
import 'package:mesting_music/features/themes/music_theme_preset.dart';
import 'package:mesting_music/shared/widgets/beta_success_feedback.dart';
import 'package:mesting_music/shared/widgets/beta_activity_indicator.dart';
import 'package:mesting_music/shared/widgets/music_notice.dart';

const _export = bool.fromEnvironment('EXPORT_V101_SCREENSHOTS');
const _current = AppVersionInfo(
  packageName: 'com.mesting.music.beta',
  versionName: '1.0.1',
  versionCode: 22,
);
final _release = AppUpdateManifest(
  packageName: _current.packageName,
  versionName: '1.0.2',
  versionCode: 23,
  minimumVersionCode: 1,
  mandatory: false,
  title: '发现新版本',
  releaseNotes: const [],
  apkUrl: Uri.parse('https://download.csnas.asia/music/download'),
  sha256: '0' * 64,
  sizeBytes: 80 * 1048576,
  publishedAt: DateTime.utc(2026, 10, 27),
);

class _Auth extends AuthController {
  @override
  Future<AuthSession?> build() async => null;
}

class _Platform extends PlatformAccountController {
  @override
  Future<PlatformSession?> build() async => null;
}

class _Update extends AppUpdateController {
  _Update(this.initial);
  final AppUpdateState initial;
  Completer<void>? gate;
  int checks = 0;
  @override
  AppUpdateState build() => initial;
  void display(AppUpdateState value) => state = value;
  @override
  Future<AppUpdateCheckResult?> check({bool manual = false}) async {
    checks++;
    state = state.copyWith(phase: AppUpdatePhase.checking);
    gate = Completer<void>();
    await gate!.future;
    state = const AppUpdateState(
      phase: AppUpdatePhase.upToDate,
      currentVersion: _current,
    );
    return null;
  }
}

class _AutomaticUpdate extends _Update {
  _AutomaticUpdate() : super(const AppUpdateState());
  @override
  Future<AppUpdateCheckResult?> check({bool manual = false}) async {
    checks++;
    state = AppUpdateState(
      phase: AppUpdatePhase.available,
      currentVersion: _current,
      manifest: _release,
    );
    return AppUpdateCheckResult(currentVersion: _current, manifest: _release);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await LiquidGlassWidgets.initialize();
    if (_export) {
      final bytes = await File('C:/Windows/Fonts/msyh.ttc').readAsBytes();
      for (final font in [
        'V101QA',
        'Roboto',
        'CupertinoSystemText',
        'CupertinoSystemDisplay',
        'sans-serif',
      ]) {
        await (FontLoader(
          font,
        )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
      }
      await (FontLoader('packages/cupertino_icons/CupertinoIcons')..addFont(
            rootBundle.load(
              'packages/cupertino_icons/assets/CupertinoIcons.ttf',
            ),
          ))
          .load();
      await (FontLoader('MaterialIcons')..addFont(
            File.fromUri(
              File(
                Platform.resolvedExecutable,
              ).uri.resolve('../../material_fonts/MaterialIcons-Regular.otf'),
            ).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
    }
  });
  late SharedPreferences prefs;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });
  Future<void> mount(
    WidgetTester tester,
    Widget page, {
    bool dark = false,
    double scale = 1,
    Size size = const Size(390, 844),
    _Update? update,
    bool auto = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    var theme = buildMestingTheme(
      musicThemePresetById(dark ? 'classic-dark' : 'classic'),
    );
    if (_export) {
      theme = theme.copyWith(
        textTheme: theme.textTheme.apply(fontFamily: 'V101QA'),
      );
    }
    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          authControllerProvider.overrideWith(_Auth.new),
          platformAccountProvider.overrideWith(_Platform.new),
          appVersionProvider.overrideWith((_) async => _current),
          autoAppUpdateChecksEnabledProvider.overrideWithValue(auto),
          if (update != null)
            appUpdateControllerProvider.overrideWith(() => update),
        ],
        child: LiquidGlassWidgets.wrap(
          brightnessResolver: Theme.maybeBrightnessOf,
          adaptiveQuality: false,
          child: RepaintBoundary(
            key: const ValueKey('v101-capture'),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: theme,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  disableAnimations: true,
                  textScaler: TextScaler.linear(scale),
                ),
                child: child!,
              ),
              home: Scaffold(body: page),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
  }

  Future<void> capture(WidgetTester tester, String name) async {
    if (!_export) return;
    // Capture a decoded app-logo frame, including the first/cold light theme.
    final context = tester.element(find.byType(MaterialApp).first);
    final images = tester.widgetList<Image>(find.byType(Image)).toList();
    await tester.runAsync(() async {
      await Future.wait(
        images.map((image) => precacheImage(image.image, context)),
      );
    });
    await tester.pump();
    await tester.runAsync(() async {
      final frame = await tester
          .renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('v101-capture')),
          )
          .toImage();
      final bytes = await frame.toByteData(format: ui.ImageByteFormat.png);
      final directory = Directory(
        const String.fromEnvironment('V101_SCREENSHOT_DIR'),
      );
      await directory.create(recursive: true);
      await File(
        '${directory.path}/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      frame.dispose();
    });
  }

  testWidgets(
    'music refinement current version stays beside its label',
    (tester) async {
      for (final dark in [false, true]) {
        await mount(
          tester,
          Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () => showAppUpdateSheet(context),
              child: const Text('显示更新'),
            ),
          ),
          dark: dark,
          scale: 1.5,
          size: const Size(320, 780),
          update: _Update(
            const AppUpdateState(
              phase: AppUpdatePhase.upToDate,
              currentVersion: _current,
            ),
          ),
        );
        await tester.tap(find.text('显示更新'));
        await tester.pumpAndSettle();
        final label = tester.getRect(find.text('当前版本'));
        final version = tester.getRect(find.text('1.0.1').last);
        expect(version.left - label.right, inInclusiveRange(10, 14));
        expect(version.top, closeTo(label.top, 2));
        await capture(
          tester,
          'refinement-current-version-${dark ? 'dark' : 'light'}-narrow-large',
        );
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('完成'));
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox());
      }
    },
    skip: !DistributionChannel.isBeta,
  );

  testWidgets(
    'manual update opens before response and cannot create a duplicate drawer',
    (tester) async {
      final update = _Update(const AppUpdateState());
      await mount(
        tester,
        Consumer(
          builder: (context, ref, _) => TextButton(
            onPressed: () => checkForUpdatesAndShowSheet(context, ref),
            child: const Text('检查更新'),
          ),
        ),
        update: update,
      );
      await tester.tap(find.text('检查更新'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 450));
      expect(find.text('正在检查更新'), findsOneWidget);
      expect(update.checks, 1);
      update.gate!.complete();
      await tester.pump();
      expect(find.text('已是最新版本'), findsOneWidget);
      await tester.tap(find.byTooltip('关闭版本更新'));
      await tester.pumpAndSettle();
    },
    skip: !DistributionChannel.isBeta,
  );

  testWidgets(
    'automatic check waits for entry; completed guest entry needs no music account',
    (tester) async {
      final update = _AutomaticUpdate();
      await mount(
        tester,
        const AppUpdateCoordinator(child: Text('音乐首页')),
        update: update,
        auto: true,
      );
      await tester.pump(const Duration(seconds: 2));
      expect(update.checks, 0);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(AppUpdateCoordinator)),
      );
      await container.read(betaEntryFlowProvider.notifier).finish();
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 450));
      expect(update.checks, 1);
      expect(find.text('发现新版本'), findsOneWidget);
      await tester.tap(find.byTooltip('关闭版本更新'));
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(seconds: 2));
      expect(update.checks, 1);
      await tester.pumpWidget(const SizedBox());
    },
    skip: !DistributionChannel.isBeta,
  );

  for (final dark in [false, true]) {
    testWidgets(
      'neutral welcome/static mark/comment busy and all update states ($dark)',
      (tester) async {
        await mount(tester, const BetaWelcomePage(), dark: dark);
        await tester.runAsync(
          () => precacheImage(
            const AssetImage('assets/branding/welcome/companions-atlas.png'),
            tester.element(find.byType(BetaWelcomePage)),
          ),
        );
        await tester.pump();
        await capture(tester, 'welcome-${dark ? 'dark' : 'light'}');
        await mount(
          tester,
          const BetaWelcomePage(),
          dark: dark,
          scale: 1.5,
          size: const Size(320, 720),
        );
        await tester.runAsync(
          () => precacheImage(
            const AssetImage('assets/branding/welcome/companions-atlas.png'),
            tester.element(find.byType(BetaWelcomePage)),
          ),
        );
        await tester.pump();
        // The public welcome page now has separate platform entry buttons.
        // Keep exercising its last login entry at a large accessibility scale.
        await tester.ensureVisible(find.text('网易云登录'));
        await tester.pump();
        expect(tester.takeException(), isNull);
        await capture(tester, 'welcome-${dark ? 'dark' : 'light'}-large');
        var sent = 0;
        final text = TextEditingController(text: '评论操作示意');
        await mount(
          tester,
          Align(
            alignment: Alignment.bottomCenter,
            child: PlatformCommentComposer(
              controller: text,
              sending: true,
              onSend: () => sent++,
              keyboardVisible: false,
            ),
          ),
          dark: dark,
        );
        expect(
          tester
              .widget<BetaActivityIndicator>(find.byType(BetaActivityIndicator))
              .color,
          Colors.white,
        );
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('comment-blue-glass-send')),
            matching: find.byWidgetPredicate(
              (w) => w is Opacity && w.opacity == .5,
            ),
          ),
          findsNothing,
        );
        await tester.tap(
          find.byKey(const ValueKey('comment-blue-glass-send')),
          warnIfMissed: false,
        );
        await tester.pump();
        expect(sent, 0);
        await capture(tester, 'comment-${dark ? 'dark' : 'light'}-sending');
        await mount(
          tester,
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showMusicNotice(
                context,
                icon: Icons.check_rounded,
                title: '已切换为单曲循环',
                message: '',
              ),
              child: const Text('提示'),
            ),
          ),
          dark: dark,
        );
        await tester.tap(find.text('提示'));
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          tester.widget<BetaSuccessMark>(find.byType(BetaSuccessMark)).animated,
          false,
        );
        await capture(tester, 'notice-${dark ? 'dark' : 'light'}');
        await tester.pump(const Duration(seconds: 3));
        await tester.pumpAndSettle();
        final update = _Update(
          const AppUpdateState(
            phase: AppUpdatePhase.checking,
            currentVersion: _current,
          ),
        );
        await mount(
          tester,
          Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () => showAppUpdateSheet(context),
              child: const Text('显示更新'),
            ),
          ),
          dark: dark,
          scale: 1.3,
          update: update,
        );
        await tester.tap(find.text('显示更新'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 450));
        for (final phase in [
          AppUpdatePhase.checking,
          AppUpdatePhase.upToDate,
          AppUpdatePhase.available,
          AppUpdatePhase.downloading,
          AppUpdatePhase.paused,
          AppUpdatePhase.verifying,
          AppUpdatePhase.failed,
          AppUpdatePhase.permissionRequired,
          AppUpdatePhase.readyToInstall,
          AppUpdatePhase.installLaunched,
        ]) {
          // Installer and permission phases retain the verified download;
          // model them exactly as the production controller reaches them.
          final hasCompletedDownload = {
            AppUpdatePhase.permissionRequired,
            AppUpdatePhase.readyToInstall,
            AppUpdatePhase.installLaunched,
          }.contains(phase);
          update.display(
            AppUpdateState(
              phase: phase,
              currentVersion: _current,
              manifest:
                  phase == AppUpdatePhase.checking ||
                      phase == AppUpdatePhase.upToDate
                  ? null
                  : _release,
              receivedBytes:
                  phase == AppUpdatePhase.downloading ||
                      phase == AppUpdatePhase.paused
                  ? 30 * 1048576
                  : phase == AppUpdatePhase.verifying || hasCompletedDownload
                  ? 80 * 1048576
                  : 0,
              totalBytes: 80 * 1048576,
              downloadedPath: hasCompletedDownload
                  ? '/fixture/update.apk'
                  : null,
              errorMessage: phase == AppUpdatePhase.failed
                  ? '暂时无法连接更新服务，请检查网络后重试。'
                  : null,
            ),
          );
          await tester.pump();
          await capture(
            tester,
            'update-${dark ? 'dark' : 'light'}-${phase.name}',
          );
          expect(tester.takeException(), isNull);
        }
        await tester.tap(find.byTooltip('关闭版本更新'));
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox());
        text.dispose();
      },
      skip: !DistributionChannel.isBeta,
    );
  }
}
