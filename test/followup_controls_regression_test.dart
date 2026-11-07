import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesting_music/core/audio/mesting_audio_handler.dart';
import 'package:mesting_music/core/audio/playback_mode.dart';
import 'package:mesting_music/core/audio/playback_providers.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/features/auth/presentation/beta_onboarding_page.dart';
import 'package:mesting_music/features/experience/presentation/floating_playback_pill.dart';
import 'package:mesting_music/features/queue/presentation/beta_playback_queue.dart';
import 'package:mesting_music/features/themes/app_theme.dart';
import 'package:mesting_music/features/themes/music_theme_preset.dart';
import 'package:mesting_music/shared/models/track.dart';
import 'package:mesting_music/shared/widgets/beta_glass_action.dart';
import 'package:mesting_music/shared/widgets/beta_glass_controls.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/experience/presentation/playback_pill_track_motion.dart';
import 'package:mesting_music/features/settings/presentation/frame_diagnostics_page.dart';
import 'package:mesting_music/features/music_platform/data/embedded_music_server.dart';
import 'package:mesting_music/features/music_platform/data/music_platform_api.dart';
import 'package:mesting_music/features/music_platform/data/platform_explore.dart';
import 'package:mesting_music/features/music_platform/presentation/platform_search_landing.dart';
import 'package:mesting_music/features/library/library_providers.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'dart:convert';
import 'support/diagnostics_fixture.dart';

class _Server implements MusicServer {
  @override
  Future<Uri> start() async => Uri.parse('http://127.0.0.1:19031');
}

class _Guest extends PlatformAccountController {
  @override
  Future<PlatformSession?> build() async => null;
}

const _one = Track(
  id: 'local_one',
  title: '第一首',
  artist: '音乐旅人',
  album: '',
  duration: Duration(minutes: 3),
  audioAsset: '',
  coverAsset: '',
  lyricsAsset: '',
  source: TrackSource.local,
);
const _two = Track(
  id: 'local_two',
  title: '第二首',
  artist: '另一位歌手',
  album: '',
  duration: Duration(minutes: 3),
  audioAsset: '',
  coverAsset: '',
  lyricsAsset: '',
  source: TrackSource.local,
);
final _selection = NotifierProvider<_Selection, Track>(_Selection.new);

class _Selection extends Notifier<Track> {
  @override
  Track build() => _one;
  void select(Track track) => state = track;
}

class _Transport extends Fake implements MestingAudioHandler {
  _Transport(this.next, this.previous);
  final VoidCallback next, previous;
  final orders = StreamController<PlaybackOrder>.broadcast(sync: true);
  PlaybackOrder order = const PlaybackOrder(repeat: PlaybackRepeat.off);
  int nextCalls = 0, previousCalls = 0;
  bool fail = false;
  @override
  List<MediaItem> get upcomingQueue => [];
  @override
  PlaybackOrder get playbackOrder => order;
  @override
  Future<void> skipToNext() async {
    nextCalls++;
    if (fail) throw StateError('测试切歌失败');
    next();
  }

  @override
  Future<void> skipToPrevious() async {
    previousCalls++;
    previous();
  }

  @override
  Future<void> togglePlayPause() async {}
  @override
  Future<void> setShuffleEnabled(bool enabled) async {
    order = order.copyWith(shuffle: enabled);
    orders.add(order);
  }

  @override
  Future<void> cycleRepeat() async {
    order = order.copyWith(
      repeat: PlaybackRepeat.values[(order.repeat.index + 1) % 3],
    );
    orders.add(order);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const export = bool.fromEnvironment('EXPORT_FOLLOWUP_UI');
  setUpAll(() async {
    await LiquidGlassWidgets.initialize();
    if (!export) return;
    final font = ByteData.sublistView(
      await File('C:/Windows/Fonts/msyh.ttc').readAsBytes(),
    );
    for (final family in [
      'FollowupQA',
      'Roboto',
      'CupertinoSystemText',
      'CupertinoSystemDisplay',
    ]) {
      await (FontLoader(family)..addFont(Future.value(font))).load();
    }
    await (FontLoader('packages/cupertino_icons/CupertinoIcons')..addFont(
          rootBundle.load('packages/cupertino_icons/assets/CupertinoIcons.ttf'),
        ))
        .load();
    await (FontLoader('MaterialIcons')..addFont(
          File(
            'D:/CodexCache/flutter-3.41.9/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
          ).readAsBytes().then(ByteData.sublistView),
        ))
        .load();
  });
  late SharedPreferences preferences;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
  });
  Future<void> mount(
    WidgetTester tester,
    Widget child, {
    ProviderContainer? container,
    bool dark = false,
    bool reduced = false,
    double width = 390,
    double scale = 1,
  }) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var theme = buildMestingTheme(
      musicThemePresetById(dark ? 'classic-dark' : 'classic'),
    );
    if (export) {
      theme = theme.copyWith(
        textTheme: theme.textTheme.apply(fontFamily: 'FollowupQA'),
      );
    }
    final app = LiquidGlassWidgets.wrap(
      adaptiveQuality: false,
      brightnessResolver: Theme.maybeBrightnessOf,
      child: MaterialApp(
        theme: theme,
        debugShowCheckedModeBanner: false,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: reduced,
            textScaler: TextScaler.linear(scale),
          ),
          child: child!,
        ),
        home: Scaffold(
          body: RepaintBoundary(
            key: const ValueKey('followup-capture'),
            child: ColoredBox(
              color: dark ? const Color(0xFF171719) : Colors.white,
              child: child,
            ),
          ),
        ),
      ),
    );
    await tester.pumpWidget(
      container == null
          ? ProviderScope(
              overrides: [
                sharedPreferencesProvider.overrideWithValue(preferences),
                platformAccountProvider.overrideWith(_Guest.new),
                diagnosticControllerProvider.overrideWith(
                  (ref) async => diagnosticFixture(),
                ),
              ],
              child: app,
            )
          : UncontrolledProviderScope(container: container, child: app),
    );
    await tester.pumpAndSettle();
  }

  Future<void> capture(WidgetTester tester, String name) async {
    if (!export) return;
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('followup-capture')),
      );
      final image = await boundary.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final dir = Directory(
        '.codex-artifacts/2026-10-28-followup-ui-sync/screens',
      )..createSync(recursive: true);
      await File(
        '${dir.path}/$name.png',
      ).writeAsBytes(data!.buffer.asUint8List());
    });
  }

  for (final action in [false, true]) {
    testWidgets(
      'scroll cancels highlight and lens geometry for action=$action',
      (tester) async {
        var calls = 0;
        await mount(
          tester,
          ListView(
            children: [
              const SizedBox(height: 280),
              if (action)
                Center(
                  child: BetaGlassAction(
                    label: '重试',
                    icon: Icons.refresh,
                    blue: false,
                    onPressed: () => calls++,
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: BetaGlassButton(
                    onPressed: () => calls++,
                    child: const Text('复制诊断报告'),
                  ),
                ),
              const SizedBox(height: 1400),
            ],
          ),
        );
        final button = find.byType(GlassButton);
        final lens = find.descendant(
          of: button,
          matching: find.byType(AdaptiveGlass),
        );
        final width = tester.getRect(lens).width;
        final drag = await tester.startGesture(tester.getCenter(button));
        await tester.pump(const Duration(milliseconds: 180));
        await drag.moveBy(const Offset(0, -50));
        await drag.moveBy(const Offset(0, -35));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        expect(tester.widget<AdaptiveGlass>(lens).glowIntensity, 0);
        expect(tester.getRect(lens).width, closeTo(width, 1));
        await capture(tester, 'scroll-held-${action ? 'action' : 'button'}');
        await drag.up();
        await tester.pumpAndSettle();
        expect(calls, 0);
      },
    );
  }

  testWidgets(
    'neutral disabled controls keep clear optics, disabled semantics and no activation',
    (tester) async {
      var calls = 0;
      await mount(
        tester,
        Column(
          children: [
            const SizedBox(height: 200),
            BetaGlassButton(
              onPressed: () => calls++,
              child: const Text('可用按钮'),
            ),
            const SizedBox(height: 30),
            const BetaGlassButton(
              label: '不可用按钮',
              onPressed: null,
              child: Text('不可用按钮'),
            ),
            const SizedBox(height: 30),
            const BetaGlassAction(
              label: '不可用动作',
              icon: Icons.refresh,
              onPressed: null,
            ),
          ],
        ),
      );
      for (final button in tester.widgetList<GlassButton>(
        find.byType(GlassButton),
      )) {
        expect(button.settings!.bodyMode, GlassBodyMode.clear);
      }
      await tester.tap(find.text('不可用按钮'), warnIfMissed: false);
      expect(calls, 0);
      await capture(tester, 'disabled-light');
    },
  );

  testWidgets(
    'disabling a pressed raw button cannot resurrect its highlight on re-enable',
    (tester) async {
      var enabled = true;
      late StateSetter update;
      await mount(
        tester,
        StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return Center(
              child: GlassButton.custom(
                enabled: enabled,
                useOwnLayer: true,
                onTap: () {},
                child: const Text('请求按钮'),
              ),
            );
          },
        ),
      );
      final lens = find.byType(AdaptiveGlass);
      final down = await tester.startGesture(
        tester.getCenter(find.byType(GlassButton)),
      );
      await tester.pump(const Duration(milliseconds: 180));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.widget<AdaptiveGlass>(lens).glowIntensity, greaterThan(0));
      update(() => enabled = false);
      await tester.pump();
      update(() => enabled = true);
      await tester.pump();
      expect(tester.widget<AdaptiveGlass>(lens).glowIntensity, 0);
      await down.up();
      await tester.pumpAndSettle();
    },
  );

  for (final compact in [false, true]) {
    testWidgets(
      'capsule follows, cancels and transitions both directions compact=$compact',
      (tester) async {
        late ProviderContainer container;
        final handler = _Transport(
          () => container.read(_selection.notifier).select(_two),
          () => container.read(_selection.notifier).select(_one),
        );
        container = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(preferences),
            audioHandlerProvider.overrideWithValue(handler),
            currentTrackProvider.overrideWith((ref) => ref.watch(_selection)),
            currentMediaItemProvider.overrideWith(
              (ref) => Stream.value(_one.toMediaItem()),
            ),
            playbackStateProvider.overrideWith(
              (ref) => Stream.value(PlaybackState()),
            ),
          ],
        );
        addTearDown(() async {
          container.dispose();
          await handler.orders.close();
        });
        await mount(
          tester,
          Center(
            child: SizedBox(
              width: compact ? 240 : 350,
              child: FloatingPlaybackPill(compact: compact),
            ),
          ),
          container: container,
        );
        final next = find.bySemanticsLabel('下一首');
        final fixed = tester.getCenter(next);
        var drag = await tester.startGesture(
          tester.getCenter(find.text('第一首')),
        );
        await drag.moveBy(const Offset(-20, 0));
        await drag.moveBy(const Offset(-24, 0));
        await tester.pump();
        expect(
          tester
              .widget<Transform>(
                find.byKey(const ValueKey('pill-track-follow')),
              )
              .transform
              .storage[12],
          lessThan(-10),
        );
        expect(tester.getCenter(next), fixed);
        await capture(
          tester,
          'pill-${compact ? 'compact' : 'expanded'}-follow',
        );
        await drag.cancel();
        await tester.pumpAndSettle();
        expect(handler.nextCalls, 0);
        expect(
          tester
              .widget<Transform>(
                find.byKey(const ValueKey('pill-track-follow')),
              )
              .transform
              .storage[12],
          closeTo(0, .01),
        );
        drag = await tester.startGesture(tester.getCenter(find.text('第一首')));
        await drag.moveBy(const Offset(-20, 0));
        await drag.moveBy(const Offset(-75, 0));
        await tester.pump();
        await drag.up();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 110));
        expect(handler.nextCalls, 1);
        expect(
          find.byKey(const ValueKey('pill-track-incoming')),
          findsOneWidget,
        );
        expect(
          tester
              .widget<Transform>(
                find.byKey(const ValueKey('pill-track-incoming')),
              )
              .transform
              .storage[12],
          greaterThan(0),
        );
        expect(tester.getCenter(next), fixed);
        await capture(tester, 'pill-${compact ? 'compact' : 'expanded'}-next');
        await tester.pumpAndSettle();
        expect(find.text('第一首'), findsNothing);
        drag = await tester.startGesture(tester.getCenter(find.text('第二首')));
        await drag.moveBy(const Offset(20, 0));
        await drag.moveBy(const Offset(75, 0));
        await tester.pump();
        await drag.up();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 110));
        expect(handler.previousCalls, 1);
        expect(
          tester
              .widget<Transform>(
                find.byKey(const ValueKey('pill-track-incoming')),
              )
              .transform
              .storage[12],
          lessThan(0),
        );
        await tester.pumpAndSettle();
        expect(find.text('第二首'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'every immersive shuffle/repeat state retains white ink and one surface color',
    (tester) async {
      final handler = _Transport(() {}, () {});
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          audioHandlerProvider.overrideWithValue(handler),
          upcomingQueueProvider.overrideWith((ref) => Stream.value([])),
          playbackOrderProvider.overrideWith((ref) async* {
            yield handler.order;
            yield* handler.orders.stream;
          }),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await handler.orders.close();
      });
      await mount(
        tester,
        const SizedBox(height: 600, child: BetaPlaybackQueue(immersive: true)),
        container: container,
        dark: true,
      );
      Color? surface;
      for (var i = 0; i < 6; i++) {
        for (final key in ['player-shuffle', 'player-repeat']) {
          final button = find.byKey(ValueKey(key));
          expect(
            tester
                .widget<Icon>(
                  find.descendant(of: button, matching: find.byType(Icon)),
                )
                .color,
            Colors.white,
          );
          final panel = tester.widget<Container>(
            find.descendant(of: button, matching: find.byType(Container)).first,
          );
          final color = (panel.decoration! as BoxDecoration).color;
          surface ??= color;
          expect(color, surface);
          await tester.tap(button);
          await tester.pumpAndSettle();
        }
      }
      await capture(tester, 'queue-modes-white');
    },
  );

  testWidgets(
    'settings replay closes immediately while initial onboarding retains skip',
    (tester) async {
      var closed = false;
      await mount(
        tester,
        BetaOnboardingPage(replay: true, onFinish: () => closed = true),
      );
      expect(find.text('关闭'), findsOneWidget);
      expect(find.text('跳过'), findsNothing);
      await capture(tester, 'guide-replay-close');
      await tester.tap(find.text('关闭'));
      expect(closed, isTrue);
      await mount(tester, BetaOnboardingPage(onFinish: () {}));
      expect(find.text('跳过'), findsOneWidget);
      expect(find.text('关闭'), findsNothing);
    },
  );

  testWidgets('collection scene opens its real playlist and then its songs', (
    tester,
  ) async {
    final paths = <String>[];
    final client = MockClient((request) async {
      paths.add(request.url.path);
      final data = request.url.path == '/scene/collection/list'
          ? {
              'list': [
                {
                  'id': 'collection_3_1903561520_277_0',
                  'title': '店铺音乐歌单',
                  'content_type': 1,
                },
              ],
            }
          : request.url.path == '/playlist/track/all'
          ? {
              'songs': [
                {
                  'hash': '2FFAF2860C7176FBC11692CC593A45C1',
                  'songname': '歌单里的歌曲',
                  'author_name': '歌手',
                },
              ],
            }
          : {'list': []};
      return http.Response(
        jsonEncode({'status': 1, 'data': data}),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    addTearDown(client.close);
    final api = MusicPlatformApi(server: _Server(), client: client);
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        platformAccountProvider.overrideWith(_Guest.new),
        musicPlatformApiProvider.overrideWithValue(api),
        platformExploreRepositoryProvider.overrideWithValue(
          PlatformExploreRepository(api),
        ),
        favoriteTrackIdsProvider.overrideWithValue({}),
      ],
    );
    addTearDown(container.dispose);
    await mount(
      tester,
      const PlatformExploreSongsPage(
        item: PlatformExploreItem(
          id: '7',
          title: '店铺专区',
          cover: '',
          kind: PlatformExploreKind.scene,
          moduleId: '713',
          tag: '42834',
          sceneContent: PlatformSceneContent.collections,
        ),
      ),
      container: container,
    );
    expect(find.text('店铺音乐歌单'), findsOneWidget);
    expect(find.text('歌曲加载失败，请重试'), findsNothing);
    await capture(tester, 'scene-collections');
    await tester.tap(find.text('店铺音乐歌单'));
    await tester.pumpAndSettle();
    expect(find.text('歌单里的歌曲'), findsOneWidget);
    expect(paths, contains('/playlist/track/all'));
    expect(paths, isNot(contains('/scene/audio/list')));
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion switches recordings without spatial animation', (
    tester,
  ) async {
    late StateSetter update;
    var second = false, dragging = false;
    await mount(
      tester,
      StatefulBuilder(
        builder: (context, setState) {
          update = setState;
          return Center(
            child: SizedBox(
              width: 220,
              child: PlaybackPillTrackMotion(
                trackId: second ? 'two' : 'one',
                dragOffset: dragging ? 35 : 0,
                dragging: dragging,
                child: Text(second ? '第二首' : '第一首'),
              ),
            ),
          );
        },
      ),
      reduced: true,
    );
    update(() => dragging = true);
    await tester.pump();
    expect(
      tester
          .widget<Transform>(find.byKey(const ValueKey('pill-track-follow')))
          .transform
          .storage[12],
      0,
    );
    update(() {
      second = true;
      dragging = false;
    });
    await tester.pump();
    expect(find.text('第一首'), findsNothing);
    expect(find.text('第二首'), findsOneWidget);
    expect(find.byKey(const ValueKey('pill-track-incoming')), findsNothing);
  });

  for (final config in [
    (false, 390.0, 1.0),
    (true, 390.0, 1.0),
    (false, 320.0, 1.6),
  ]) {
    testWidgets(
      'real diagnostics copy button restores its lens after scrolling $config',
      (tester) async {
        await mount(
          tester,
          const FrameDiagnosticsPage(),
          dark: config.$1,
          width: config.$2,
          scale: config.$3,
        );
        await tester.scrollUntilVisible(
          find.text('复制诊断报告'),
          180,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        final button = find.ancestor(
          of: find.text('复制诊断报告'),
          matching: find.byType(GlassButton),
        );
        final lens = find.descendant(
          of: button,
          matching: find.byType(AdaptiveGlass),
        );
        final restWidth = tester.getRect(lens).width;
        final drag = await tester.startGesture(tester.getCenter(button));
        await tester.pump(const Duration(milliseconds: 180));
        await drag.moveBy(const Offset(0, -45));
        await drag.moveBy(const Offset(0, -30));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        expect(tester.widget<AdaptiveGlass>(lens).glowIntensity, 0);
        expect(tester.getRect(lens).width, closeTo(restWidth, 1));
        await capture(
          tester,
          'diagnostics-${config.$1 ? 'dark' : 'light'}-${config.$2.toInt()}-scroll',
        );
        await drag.up();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'explicit free-drag glass retains its opt-in press until lift-off',
    (tester) async {
      await mount(
        tester,
        ListView(
          children: [
            const SizedBox(height: 250),
            Center(
              child: GlassButton.custom(
                useOwnLayer: true,
                persistPressOnDrag: true,
                onTap: () {},
                child: const Text('自由拖动控件'),
              ),
            ),
            const SizedBox(height: 1200),
          ],
        ),
      );
      final drag = await tester.startGesture(
        tester.getCenter(find.byType(GlassButton)),
      );
      await tester.pump(const Duration(milliseconds: 180));
      await drag.moveBy(const Offset(0, -55));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        tester.widget<AdaptiveGlass>(find.byType(AdaptiveGlass)).glowIntensity,
        1,
      );
      await drag.up();
      await tester.pumpAndSettle();
      expect(
        tester.widget<AdaptiveGlass>(find.byType(AdaptiveGlass)).glowIntensity,
        0,
      );
    },
  );

  testWidgets(
    'shared wrapper cancels a press when a sibling request disables it',
    (tester) async {
      late StateSetter update;
      var enabled = true;
      var calls = 0;
      await mount(
        tester,
        StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return Center(
              child: BetaGlassButton(
                onPressed: enabled ? () => calls++ : null,
                child: const Text('保存设置'),
              ),
            );
          },
        ),
      );
      final press = await tester.startGesture(
        tester.getCenter(find.byType(GlassButton)),
      );
      await tester.pump(const Duration(milliseconds: 180));
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        tester.widget<AdaptiveGlass>(find.byType(AdaptiveGlass)).glowIntensity,
        greaterThan(0),
      );
      update(() => enabled = false);
      await tester.pump();
      expect(
        tester.widget<GlassButton>(find.byType(GlassButton)).enabled,
        isFalse,
      );
      expect(
        tester.widget<AdaptiveGlass>(find.byType(AdaptiveGlass)).glowIntensity,
        0,
      );
      await press.up();
      await tester.pumpAndSettle();
      expect(calls, 0);
      update(() => enabled = true);
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存设置'));
      await tester.pumpAndSettle();
      expect(calls, 1);
    },
  );
}
