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
import 'package:mesting_music/core/audio/audio_output_controller.dart';
import 'package:mesting_music/core/audio/media_volume_controller.dart';
import 'package:mesting_music/core/audio/mesting_audio_handler.dart';
import 'package:mesting_music/core/audio/playback_providers.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/core/platform/distribution_channel.dart';
import 'package:mesting_music/features/auth/auth_providers.dart';
import 'package:mesting_music/features/auth/domain/auth_models.dart';
import 'package:mesting_music/features/auth/presentation/beta_onboarding_page.dart';
import 'package:mesting_music/features/auth/presentation/beta_welcome_page.dart';
import 'package:mesting_music/features/auth/presentation/mesting_music_companions.dart';
import 'package:mesting_music/features/experience/presentation/player_output_dialog.dart';
import 'package:mesting_music/features/legal/domain/legal_documents.dart';
import 'package:mesting_music/features/legal/presentation/disclaimer_dialog.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/music_platform/presentation/platform_account_page.dart';
import 'package:mesting_music/features/queue/presentation/beta_playback_queue.dart';
import 'package:mesting_music/features/queue/presentation/queue_page.dart';
import 'package:mesting_music/features/themes/app_theme.dart';
import 'package:mesting_music/features/themes/music_theme_preset.dart';
import 'package:mesting_music/shared/models/track.dart';
import 'package:mesting_music/shared/widgets/beta_success_feedback.dart';
import 'package:mesting_music/shared/widgets/music_notice.dart';
import 'support/deterministic_audio_player.dart';

const _export = bool.fromEnvironment('EXPORT_BETA21_SCREENSHOTS');
const _song = Track(
  id: 'demo-1',
  title: '午后的音乐',
  artist: '操作示意',
  album: '',
  audioAsset: 'assets/fixture.mp3',
  coverAsset: 'assets/branding/mesting-app-icon.png',
  duration: Duration(minutes: 3, seconds: 26),
  lyricsAsset: '',
);

class _NoAuth extends AuthController {
  @override
  Future<AuthSession?> build() async => null;
}

class _NoPlatform extends PlatformAccountController {
  @override
  Future<PlatformSession?> build() async => null;
}

class _Volume extends MediaVolumeController {
  @override
  MediaVolumeState build() =>
      const MediaVolumeState(value: .27, available: true);
}

class _Routes extends AudioOutputController {
  String get selectedId => state.id;
  Completer<bool>? pending;
  int systems = 0;
  @override
  AudioOutput build() => _state('earbuds');
  AudioOutput _state(String id) => AudioOutput(
    id: id,
    name: id == 'earbuds' ? 'vivo TWS 5' : '本机',
    local: id == 'phone',
    headphones: id == 'earbuds',
    available: true,
    routes: [
      AudioOutputRoute(
        id: 'earbuds',
        name: 'vivo TWS 5',
        headphones: true,
        selected: id == 'earbuds',
        selectable: id != 'earbuds',
      ),
      AudioOutputRoute(
        id: 'phone',
        name: '本机',
        local: true,
        selected: id == 'phone',
        selectable: id != 'phone',
      ),
    ],
  );
  @override
  Future<void> refresh() async {}
  @override
  Future<void> refreshRoutes() async {}
  @override
  Future<bool> transfer(String id) async {
    pending = Completer<bool>();
    final accepted = await pending!.future;
    if (accepted) state = _state(id);
    return accepted;
  }

  @override
  Future<void> choose() async {
    systems++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await LiquidGlassWidgets.initialize();
    if (_export) {
      final bytes = await File('C:/Windows/Fonts/msyh.ttc').readAsBytes();
      for (final family in [
        'Beta21QA',
        'Roboto',
        'CupertinoSystemText',
        'CupertinoSystemDisplay',
        'sans-serif',
      ]) {
        await (FontLoader(
          family,
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
    final dir = await Directory.systemTemp.createTemp('mesting_beta21_');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => dir.path,
    );
    addTearDown(() async {
      messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        null,
      );
      // This exact test-owned temporary directory was returned by createTemp.
      await dir.delete(recursive: true);
    });
  });
  Future<void> mount(
    WidgetTester tester,
    Widget page, {
    bool dark = false,
    double textScale = 1,
    Size size = const Size(390, 844),
    MestingAudioHandler? handler,
    _Routes? routes,
    bool reduced = true,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    var theme = buildMestingTheme(
      musicThemePresetById(dark ? 'classic-dark' : 'classic'),
    );
    if (_export) {
      theme = theme.copyWith(
        textTheme: theme.textTheme.apply(fontFamily: 'Beta21QA'),
      );
    }
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          authControllerProvider.overrideWith(_NoAuth.new),
          platformAccountProvider.overrideWith(_NoPlatform.new),
          currentTrackProvider.overrideWithValue(_song),
          mediaVolumeProvider.overrideWith(_Volume.new),
          audioOutputProvider.overrideWith(() => routes ?? _Routes()),
          if (handler != null) audioHandlerProvider.overrideWithValue(handler),
        ],
        child: LiquidGlassWidgets.wrap(
          brightnessResolver: Theme.maybeBrightnessOf,
          adaptiveQuality: false,
          child: RepaintBoundary(
            key: const ValueKey('beta21-capture'),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: theme,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(textScale),
                  disableAnimations: reduced,
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
    // The first light capture has a cold image cache. Wait for its real asset
    // frame instead of recording a transient empty artwork slot as UI evidence.
    final context = tester.element(find.byType(MaterialApp).first);
    final images = tester.widgetList<Image>(find.byType(Image)).toList();
    await tester.runAsync(() async {
      await Future.wait(
        images.map((image) => precacheImage(image.image, context)),
      );
    });
    await tester.pump();
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('beta21-capture')),
      );
      final frame = await boundary.toImage();
      final bytes = await frame.toByteData(format: ui.ImageByteFormat.png);
      final dir = Directory(
        const String.fromEnvironment('BETA21_SCREENSHOT_DIR'),
      );
      await dir.create(recursive: true);
      await File(
        '${dir.path}/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      frame.dispose();
    });
  }

  Future<void> decodeCharacters(WidgetTester tester) async {
    final context = tester.element(find.byType(MestingMusicCompanions).first);
    await tester.runAsync(() async {
      await precacheImage(
        const AssetImage('assets/branding/welcome/companions-atlas.png'),
        context,
      );
    });
    await tester.pump();
  }

  testWidgets(
    'first entry removes the duplicate card without recording consent',
    (tester) async {
      await mount(
        tester,
        const FirstLaunchDisclaimerCoordinator(child: BetaWelcomePage()),
      );
      await decodeCharacters(tester);
      expect(prefs.getBool(userAgreementAcceptedPreferenceKey), isNull);
      expect(prefs.getBool(privacyPolicyAcceptedPreferenceKey), isNull);
      expect(find.byKey(liquidGlassDisclaimerSurfaceKey), findsNothing);
      expect(find.text('手机号登录'), findsOneWidget);
      await tester.tap(find.text('手机号登录'));
      await tester.pump(const Duration(milliseconds: 260));
      expect(find.text('请先阅读并同意协议与隐私政策'), findsOneWidget);
      expect(prefs.getBool(userAgreementAcceptedPreferenceKey), isNull);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpWidget(const SizedBox());
    },
    skip: !DistributionChannel.isBeta,
  );

  testWidgets(
    'success feedback retains words and a complete static green mark',
    (tester) async {
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
            child: const Text('切换'),
          ),
        ),
      );
      await tester.tap(find.text('切换'));
      await tester.pump(const Duration(milliseconds: 260));
      expect(find.text('已切换为单曲循环'), findsOneWidget);
      expect(find.byType(BetaSuccessMark), findsOneWidget);
      expect(
        tester.widget<BetaSuccessMark>(find.byType(BetaSuccessMark)).animated,
        false,
      );
      expect(
        find.descendant(
          of: find.byType(BetaSuccessMark),
          matching: find.byType(TweenAnimationBuilder<double>),
        ),
        findsNothing,
      );
      expect(find.byIcon(Icons.check_rounded), findsNothing);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpWidget(const SizedBox());
    },
    skip: !DistributionChannel.isBeta,
  );

  testWidgets(
    'queue drag and swipe mutate only pending tracks and retain transport',
    (tester) async {
      final handler = (await tester.runAsync(() async {
        final value = MestingAudioHandler(
          tracks: [],
          player: DeterministicAudioPlayer(),
        );
        await value.replaceQueue([
          _song,
          for (var i = 2; i < 6; i++)
            Track(
              id: 'demo-$i',
              title: '待播歌曲 $i',
              artist: '操作示意',
              album: '',
              duration: _song.duration,
              audioAsset: _song.audioAsset,
              coverAsset: _song.coverAsset,
              lyricsAsset: '',
            ),
        ], autoplay: false);
        return value;
      }))!;
      await mount(tester, const BetaPlaybackQueue(), handler: handler);
      final before = handler.upcomingQueue.map((e) => e.id).toList();
      final current = handler.mediaItem.value?.id;
      await tester.runAsync(
        () => precacheImage(
          AssetImage(_song.coverAsset),
          tester.element(find.byType(BetaPlaybackQueue)),
        ),
      );
      await tester.pump();
      await capture(tester, 'queue-light');
      await tester.drag(
        find.byKey(ValueKey('queue-drag-${before.first}')),
        const Offset(0, 155),
      );
      await tester.pumpAndSettle();
      expect(handler.upcomingQueue.first.id, isNot(before.first));
      final remove = handler.upcomingQueue.first.id;
      expect(remove, isNot(current));
      final commands = <String>[];
      final subscription = handler.userCommandStream.listen(commands.add);
      await tester.timedDrag(
        find.byKey(ValueKey('pending-$remove')),
        const Offset(-500, 0),
        const Duration(milliseconds: 400),
      );
      await tester.pumpAndSettle();
      expect(commands, contains('removeUpcoming'));
      // The handler's ready future was initialized in runAsync above. Drain
      // that real async zone before asserting its post-await queue mutation.
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(
        handler.upcomingQueue.any((e) => e.id == remove),
        false,
        reason:
            'target=$remove current=$current remaining=${handler.upcomingQueue.map((e) => e.id).toList()}',
      );
      expect(handler.mediaItem.value?.id, current);
      expect(handler.playbackState.value.playing, false);
      expect(tester.takeException(), isNull);
      await tester.runAsync(subscription.cancel);
      // A song can leave the queue while the user is holding another handle.
      // The drop still belongs to the recording captured when the drag began.
      final dragSnapshot = handler.upcomingQueue
          .map((item) => item.id)
          .toList();
      tester
          .widget<ReorderableListView>(find.byType(ReorderableListView))
          .onReorderStart!(1);
      await tester.runAsync(
        () => handler.removeFromUpcomingQueue(dragSnapshot.first),
      );
      await tester.pump();
      tester
          .widget<ReorderableListView>(find.byType(ReorderableListView))
          .onReorder(1, 0);
      await tester.pump();
      expect(handler.upcomingQueue.first.id, dragSnapshot[1]);
      if (_export) {
        for (final dark in [false, true]) {
          await mount(
            tester,
            Builder(
              builder: (context) => TextButton(
                onPressed: () => showPlaybackQueueSheet(context),
                child: const Text('打开播放列表'),
              ),
            ),
            dark: dark,
            handler: handler,
          );
          await tester.tap(find.text('打开播放列表'));
          await tester.pumpAndSettle();
          // Capture the actual sheet surface; the root boundary includes routes.
          await capture(tester, 'queue-sheet-${dark ? 'dark' : 'light'}');
          expect(
            find.byKey(const ValueKey('beta-queue-close')),
            findsOneWidget,
          );
          await tester.tap(find.byKey(const ValueKey('beta-queue-close')));
          await tester.pumpAndSettle();
          await tester.pumpWidget(const SizedBox());
        }
      }
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(handler.debugDispose);
    },
  );

  testWidgets(
    'music refinement output card keeps local switching inside glass',
    (tester) async {
      for (final dark in [false, true]) {
        final routes = _Routes();
        await mount(
          tester,
          const PlayerOutputDialog(),
          dark: dark,
          routes: routes,
        );
        await capture(tester, 'refinement-output-${dark ? 'dark' : 'light'}');
        if (!DistributionChannel.isBeta) await tester.tap(find.text('切换设备'));
        await tester.pumpAndSettle();
        expect(find.text('本机'), findsOneWidget);
        expect(find.text('系统设备管理'), findsNothing);
        expect(routes.systems, 0);
        await capture(
          tester,
          'refinement-output-${dark ? 'dark' : 'light'}-routes',
        );
        await tester.pumpWidget(const SizedBox());
      }
      await mount(
        tester,
        const PlayerOutputDialog(),
        size: const Size(320, 640),
        textScale: 1.5,
      );
      if (!DistributionChannel.isBeta) await tester.tap(find.text('切换设备'));
      await tester.pumpAndSettle();
      await capture(tester, 'refinement-output-narrow-large');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
    skip: !DistributionChannel.isBeta,
  );

  testWidgets(
    'device selection remains in one glass card and waits for confirmation',
    (tester) async {
      final routes = _Routes();
      await mount(tester, const PlayerOutputDialog(), routes: routes);
      if (!DistributionChannel.isBeta) await tester.tap(find.text('切换设备'));
      await tester.pumpAndSettle();
      expect(routes.systems, 0);
      expect(find.byKey(const ValueKey('apple-output-picker')), findsOneWidget);
      await capture(tester, 'output-light-routes');
      await tester.tap(find.byKey(const ValueKey('output-route-phone')));
      await tester.pump();
      expect(routes.selectedId, 'earbuds');
      expect(find.text('正在切换…'), findsOneWidget);
      routes.pending!.complete(false);
      await tester.pumpAndSettle();
      expect(routes.selectedId, 'earbuds');
      expect(find.textContaining('系统尚未确认'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('output-route-phone')));
      await tester.pump();
      routes.pending!.complete(true);
      await tester.pumpAndSettle();
      expect(routes.selectedId, 'phone');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
    skip: !DistributionChannel.isBeta,
  );

  test(
    'Beta legal text follows current services without inventing contact or deletion',
    () {
      if (!DistributionChannel.isBeta) return;
      final policy = legalDocumentFor(LegalDocumentType.privacyPolicy);
      expect(policy.effectiveDate, contains('2026 年 10 月 27 日'));
      expect(
        policy.sections.map((s) => s.body).join(),
        contains('未启用自动听歌时长上报'),
      );
      expect(policy.sections.map((s) => s.body).join(), contains('不会自动注销平台账号'));
      expect(
        policy.sections.map((s) => s.body).join(),
        isNot(contains('@example')),
      );
    },
  );

  test(
    'route controller requires a native readback and rejects unknown targets',
    () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      var selected = 'earbuds', requests = 0;
      Map<String, Object> snapshot() => {
        'id': selected,
        'name': selected,
        'available': true,
        'routes': [
          {
            'id': 'phone',
            'name': '本机扬声器',
            'selected': selected == 'phone',
            'selectable': selected != 'phone',
          },
        ],
      };
      messenger.setMockMethodCallHandler(AudioOutputController.methods, (
        call,
      ) async {
        if (call.method == 'transfer') {
          requests++;
          return true;
        }
        return snapshot();
      });
      messenger.setMockStreamHandler(
        AudioOutputController.events,
        MockStreamHandler.inline(onListen: (_, _) {}),
      );
      final container = ProviderContainer();
      addTearDown(() {
        container.dispose();
        messenger.setMockMethodCallHandler(AudioOutputController.methods, null);
        messenger.setMockStreamHandler(AudioOutputController.events, null);
      });
      final controller = container.read(audioOutputProvider.notifier);
      await controller.refreshRoutes();
      expect(await controller.transfer('unknown-device'), false);
      expect(requests, 0);
      expect(
        await controller.transfer('phone'),
        false,
      ); // Accepted call, unchanged native route.
      expect(container.read(audioOutputProvider).id, 'earbuds');
      selected = 'phone';
      expect(await controller.transfer('phone'), true);
      expect(container.read(audioOutputProvider).id, 'phone');
    },
  );

  for (final dark in [false, true]) {
    testWidgets(
      'current welcome, login and guide render with large type ($dark)',
      (tester) async {
        await mount(tester, const PlayerOutputDialog(), dark: dark);
        await capture(tester, 'output-${dark ? 'dark' : 'light'}');
        if (!DistributionChannel.isBeta) await tester.tap(find.text('切换设备'));
        await tester.pumpAndSettle();
        await capture(tester, 'output-${dark ? 'dark' : 'light'}-routes');
        await tester.pumpWidget(const SizedBox());
        await mount(
          tester,
          const BetaWelcomePage(),
          dark: dark,
          reduced: false,
        );
        await decodeCharacters(tester);
        await capture(tester, 'welcome-${dark ? 'dark' : 'light'}');
        await tester.tap(find.byType(MestingMusicCompanions));
        await tester.pump(const Duration(milliseconds: 350));
        await capture(tester, 'welcome-${dark ? 'dark' : 'light'}-greeting');
        await tester.pumpWidget(const SizedBox());
        await mount(
          tester,
          const PlatformAccountPage(),
          dark: dark,
          textScale: 1.5,
          size: const Size(320, 720),
        );
        await tester.pumpAndSettle();
        await capture(tester, 'login-${dark ? 'dark' : 'light'}-large');
        await tester.drag(find.byType(ListView).first, const Offset(0, 140));
        await tester.pump(const Duration(milliseconds: 32));
        await capture(tester, 'login-${dark ? 'dark' : 'light'}-stretch');
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await mount(
          tester,
          BetaOnboardingPage(onFinish: () {}),
          dark: dark,
          textScale: 1.3,
        );
        for (var page = 0; page < 8; page++) {
          if (page > 0) {
            await tester.tap(find.text('下一步'));
            await tester.pumpAndSettle();
          }
          if (page == 7) await decodeCharacters(tester);
          await capture(tester, 'guide-${dark ? 'dark' : 'light'}-${page + 1}');
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox());
      },
      skip: !DistributionChannel.isBeta,
    );
  }
}
