import 'package:mesting_music/features/music_platform/source_media_scope.dart';
import 'package:mesting_music/features/music_platform/retained_kugou_scope.dart';
import 'package:mesting_music/features/music_platform/linked_music_providers.dart';
import 'package:mesting_music/features/music_platform/data/linked_music_mvs.dart';
import 'package:mesting_music/features/music_platform/data/platform_mv_repository.dart';
import 'package:mesting_music/features/music_platform/data/platform_search_repository.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:video_player/video_player.dart';
import 'package:mesting_music/core/audio/mesting_audio_handler.dart';
import 'package:mesting_music/core/audio/playback_providers.dart';
import 'package:mesting_music/core/audio/music_equalizer.dart';
import 'package:mesting_music/core/audio/music_equalizer_providers.dart';
import 'package:mesting_music/core/haptics/app_haptics.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/features/app_update/app_update_providers.dart';
import 'package:mesting_music/features/app_update/domain/app_update_models.dart';
import 'package:mesting_music/features/app_update/domain/release_history.dart';
import 'package:mesting_music/features/app_update/presentation/beta_app_update_sheet.dart';
import 'package:mesting_music/features/music_platform/data/embedded_music_server.dart';
import 'package:mesting_music/features/music_platform/data/music_platform_api.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/music_platform/platform_profile_provider.dart';
import 'package:mesting_music/features/music_platform/presentation/platform_profile_edit_page.dart';
import 'package:mesting_music/features/music_platform/presentation/music_effects_page.dart';
import 'package:mesting_music/features/music_platform/presentation/music_mv_page.dart';
import 'package:mesting_music/features/settings/presentation/haptic_settings_page.dart';
import 'package:mesting_music/features/settings/presentation/music_equalizer_page.dart';
import 'package:mesting_music/features/settings/presentation/music_sleep_timer_sheet.dart';
import 'package:mesting_music/features/themes/app_theme.dart';
import 'package:mesting_music/features/themes/music_theme_preset.dart';
import 'package:mesting_music/shared/widgets/beta_glass_controls.dart';
import 'package:mesting_music/shared/widgets/beta_glass_scroll_body.dart';
import 'support/deterministic_audio_player.dart';
import 'support/test_tracks.dart';
import 'package:mesting_music/shared/models/track.dart';
import 'release_103_audio_test.dart' show TestEqualizerBridge;

const _export = bool.fromEnvironment('EXPORT_V103_SCREENSHOTS');
const _version = AppVersionInfo(
  packageName: 'com.mesting.music.beta',
  versionName: '1.0.3',
  versionCode: 24,
);
const _owner = PlatformSession(
  userId: 'ui-fixture',
  token: 'synthetic-ui-token',
  nickname: '音乐旅人',
);

class _Account extends PlatformAccountController {
  @override
  Future<PlatformSession?> build() async => _owner;
  @override
  Future<void> updateProfileMetadata(
    PlatformSession expected, {
    String? nickname,
    String? avatarUrl,
  }) async {}
}

class _Server implements MusicServer {
  @override
  Future<Uri> start() async => Uri.parse('http://127.0.0.1:12345');
}

class _Update extends AppUpdateController {
  @override
  AppUpdateState build() => const AppUpdateState(
    phase: AppUpdatePhase.upToDate,
    currentVersion: _version,
  );
}

class _Video extends VideoPlayerPlatform {
  int ids = 0, plays = 0, disposals = 0;
  final streams = <int, StreamController<VideoEvent>>{};
  @override
  Future<void> init() async {}
  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async => ++ids;
  @override
  Stream<VideoEvent> videoEventsFor(int playerId) {
    final stream = streams.putIfAbsent(
      playerId,
      () => StreamController<VideoEvent>.broadcast(),
    );
    scheduleMicrotask(
      () => stream.add(
        VideoEvent(
          eventType: VideoEventType.initialized,
          duration: const Duration(minutes: 4, seconds: 12),
          size: const Size(1280, 720),
        ),
      ),
    );
    return stream.stream;
  }

  @override
  Widget buildViewWithOptions(VideoViewOptions options) => const ColoredBox(
    color: Color(0xFF1D3446),
    child: Center(
      child: Text(
        '合成 MV 测试画面',
        style: TextStyle(color: Colors.white, fontSize: 16),
      ),
    ),
  );
  @override
  Future<void> dispose(int playerId) async {
    disposals++;
    await streams.remove(playerId)?.close();
  }

  @override
  Future<Duration> getPosition(int playerId) async =>
      const Duration(seconds: 24);
  @override
  Future<void> pause(int playerId) async {}
  @override
  Future<void> play(int playerId) async {
    plays++;
  }

  @override
  Future<void> seekTo(int playerId, Duration position) async {}
  @override
  Future<void> setLooping(int playerId, bool looping) async {}
  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}
  @override
  Future<void> setVolume(int playerId, double volume) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await LiquidGlassWidgets.initialize();
    if (_export) {
      final bytes = await File('C:/Windows/Fonts/msyh.ttc').readAsBytes();
      for (final font in [
        'V103QA',
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
  Future<
    ({
      ProviderContainer container,
      MestingAudioHandler handler,
      List<http.Request> requests,
    })
  >
  mount(
    WidgetTester tester,
    Widget page, {
    bool dark = false,
    double scale = 1,
    Size size = const Size(390, 844),
    bool eq = false,
    bool profileError = false,
    bool mixedMvs = false,
    bool noPlayableMv = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    SharedPreferences.setMockInitialValues({
      HapticPreferencesController.enabledKey: false,
    });
    final prefs = await SharedPreferences.getInstance();
    final actual = (await tester.runAsync(() async {
      final value = MestingAudioHandler(
        tracks: [],
        player: DeterministicAudioPlayer(),
      );
      await value.replaceQueue(testTracks.take(2).toList(), autoplay: false);
      return value;
    }))!;
    final sessions = StreamController<int?>.broadcast();
    final equalizer = MusicEqualizerController(
      bridge: TestEqualizerBridge(),
      preferences: prefs,
      sessions: sessions.stream,
      currentSession: 7,
    );
    if (eq) await equalizer.selectPreset('人声');
    final requests = <http.Request>[];
    final api = MusicPlatformApi(
      server: _Server(),
      client: MockClient((request) async {
        requests.add(request);
        final Map<String, Object?> data = switch (request.url.path) {
          '/user/detail' =>
            profileError
                ? {'status': 0, 'error_code': 1}
                : {
                    'status': 1,
                    'data': {
                      'nickname': '音乐旅人',
                      'signature': '把日常听成喜欢的样子。',
                      'sex': 1,
                      'birthday': '2000-04-16',
                      'province': '四川省',
                      'city': '成都市',
                    },
                  },
          '/user/update' => {'status': 1},
          '/get/model' => {
            'status': 1,
            'data': List.generate(
              5,
              (i) => {
                'id': i + 1,
                'name': ['温柔人声', '夜间流行', '轻盈电子', '低音现场', '清晰高音'][i],
                'author': '合成测试作者',
                'sound': 'https://fixture.example/free.irs',
                'privilege': 0,
              },
            ),
          },
          '/video/barrage' => {
            'status': 1,
            'data': {
              'list': [
                {'id': 'mv-comment', 'content': '酷狗视频评论', 'nickname': '用户'},
              ],
              'total': 1,
            },
          },
          '/kmr/audio/mv' => {
            'status': 1,
            'data': [
              [
                {
                  'video_id': 'fixture-video',
                  'mv_name': '合成 MV · 测试歌曲',
                  'h264': {'hd_hash': 'fixture-hd', 'sd_hash': 'fixture-sd'},
                },
              ],
            ],
          },
          '/video/detail' => {'status': 1, 'data': {}},
          '/video/url' => {
            'status': 1,
            'data': {
              request.url.queryParameters['hash']!: {
                'downurl': 'https://fixture.example/video.mp4',
              },
            },
          },
          _ => {'status': 1, 'data': []},
        };
        return http.Response.bytes(utf8.encode(jsonEncode(data)), 200);
      }),
    )..session = _owner;
    final container = ProviderContainer(
      // Exercise the manual error state after one failed read, rather than
      // Riverpod's automatic retry/backoff state. Other fixtures keep retries.
      retry: profileError ? (retryCount, error) => null : null,
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        audioHandlerProvider.overrideWithValue(actual),
        musicEqualizerProvider.overrideWithValue(equalizer),
        musicPlatformApiProvider.overrideWithValue(api),
        // The original single-platform fixture has no foreign account/network.
        savedKugouSessionProvider.overrideWith((ref) async => null),
        if (!mixedMvs)
          linkedMvSourceProvider(TrackSource.netease).overrideWith(
            (ref) async => MvSourceRepositories(
              PlatformMvRepository(api),
              _NoCounterpartSearch(api),
              () => true,
            ),
          ),
        if (mixedMvs || noPlayableMv)
          linkedMvSourceProvider(TrackSource.kugou).overrideWith(
            (ref) async => MvSourceRepositories(
              _MvChoiceFixture(api, TrackSource.kugou, fail: noPlayableMv),
              _NoCounterpartSearch(api),
              () => true,
            ),
          ),
        if (mixedMvs)
          linkedMvSourceProvider(TrackSource.netease).overrideWith(
            (ref) async => MvSourceRepositories(
              _MvChoiceFixture(api, TrackSource.netease, fail: true),
              _MvCounterpartFixture(api),
              () => true,
            ),
          ),
        if (mixedMvs)
          sourceMediaScopeProvider(TrackSource.netease).overrideWith(
            (ref) async => SourceMediaScope(
              source: TrackSource.netease,
              api:
                  MusicPlatformApi(
                      server: _Server(),
                      client: MockClient(
                        (_) async =>
                            throw StateError('No live foreign requests'),
                      ),
                    )
                    ..session = const PlatformSession(
                      userId: 'foreign-ne',
                      token: 'foreign-test-token',
                      platform: MusicPlatform.netease,
                    ),
              isCurrent: () => true,
            ),
          ),
        platformAccountProvider.overrideWith(_Account.new),
        appVersionProvider.overrideWith((_) async => _version),
        appUpdateControllerProvider.overrideWith(_Update.new),
      ],
    );
    await container.read(platformAccountProvider.future);
    await tester.runAsync(() => container.read(musicRegionsProvider.future));
    var theme = buildMestingTheme(
      musicThemePresetById(dark ? 'classic-dark' : 'classic'),
    );
    if (_export) {
      theme = theme.copyWith(
        textTheme: theme.textTheme.apply(fontFamily: 'V103QA'),
        chipTheme: theme.chipTheme.copyWith(
          labelStyle: (theme.chipTheme.labelStyle ?? const TextStyle())
              .copyWith(fontFamily: 'V103QA'),
          secondaryLabelStyle:
              (theme.chipTheme.secondaryLabelStyle ?? const TextStyle())
                  .copyWith(fontFamily: 'V103QA'),
        ),
      );
    }
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: LiquidGlassWidgets.wrap(
          brightnessResolver: Theme.maybeBrightnessOf,
          adaptiveQuality: false,
          child: RepaintBoundary(
            key: const ValueKey('v103-capture'),
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
              home: page,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await actual.debugDispose();
      equalizer.dispose();
      await sessions.close();
      container.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    return (container: container, handler: actual, requests: requests);
  }

  Future<void> capture(WidgetTester tester, String name) async {
    if (!_export) return;
    final context = tester.element(find.byType(MaterialApp));
    await tester.runAsync(() async {
      await Future.wait(
        tester
            .widgetList<Image>(find.byType(Image))
            .map((image) => precacheImage(image.image, context)),
      );
    });
    await tester.pump();
    await tester.runAsync(() async {
      final image = await tester
          .renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('v103-capture')),
          )
          .toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final dir = Directory(
        const String.fromEnvironment('V103_SCREENSHOT_DIR'),
      );
      await dir.create(recursive: true);
      await File(
        '${dir.path}/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';
    testWidgets(
      'haptics disabled text is visible, inaccessible to taps, $mode',
      (tester) async {
        final result = await mount(
          tester,
          const HapticSettingsPage(),
          dark: dark,
        );
        final semantics = tester.ensureSemantics();
        try {
          final text = find.text('体验触感');
          final style = DefaultTextStyle.of(tester.element(text)).style;
          expect(style.color, isNot(Colors.white));
          expect(
            tester
                    .getSemantics(find.byKey(const ValueKey('haptics-preview')))
                    .flagsCollection
                    .isEnabled ==
                ui.Tristate.isTrue,
            false,
          );
          await tester.tap(
            find.byKey(const ValueKey('haptics-preview')),
            warnIfMissed: false,
          );
          await tester.pump();
          expect(
            result.container.read(hapticPreferencesProvider).enabled,
            false,
          );
          await capture(tester, 'haptics-disabled-$mode');
          await tester.tap(find.byKey(const ValueKey('haptics-enabled')));
          await tester.pumpAndSettle();
          expect(
            DefaultTextStyle.of(tester.element(text)).style.color,
            Colors.white,
          );
          await capture(tester, 'haptics-enabled-$mode');
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      },
    );
    testWidgets('current version opens its own complete release notes, $mode', (
      tester,
    ) async {
      await mount(
        tester,
        const Scaffold(body: BetaAppUpdateSheet()),
        dark: dark,
      );
      expect(find.text('已是最新版本'), findsOneWidget);
      await capture(tester, 'update-current-$mode');
      await tester.tap(find.byKey(const ValueKey('app-update-view-notes')));
      await tester.pumpAndSettle();
      expect(find.text('Mesting Music 1.0.3'), findsOneWidget);
      for (final note in notesForMusicVersion('1.0.3')) {
        expect(find.text(note), findsOneWidget);
      }
      await capture(tester, 'update-notes-$mode');
      expect(tester.takeException(), isNull);
    });
    testWidgets(
      'profile has only requested fields and picker-based region, $mode',
      (tester) async {
        await mount(tester, const PlatformProfileEditPage(), dark: dark);
        await tester.pumpAndSettle();
        expect(find.text('编辑个人资料'), findsOneWidget);
        expect(find.text('备注'), findsNothing);
        expect(find.text('标签'), findsNothing);
        expect(
          tester
              .widget<BetaGlassButton>(
                find.byKey(const ValueKey('platform-edit-save')),
              )
              .onPressed,
          isNull,
        );
        await capture(tester, 'profile-$mode');
        await tester.tap(find.text('地区'));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pumpAndSettle();
        expect(find.byType(CupertinoPicker), findsNWidgets(2));
        await capture(tester, 'region-$mode');
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<BetaGlassButton>(
                find.byKey(const ValueKey('platform-edit-save')),
              )
              .onPressed,
          isNull,
        );
        expect(tester.takeException(), isNull);
      },
    );
    testWidgets('equalizer and catalogue render applied state, $mode', (
      tester,
    ) async {
      await mount(tester, const MusicEqualizerPage(), dark: dark, eq: true);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('music-equalizer-band-4')),
        findsOneWidget,
      );
      await capture(tester, 'equalizer-$mode');
      expect(tester.takeException(), isNull);
    });
    testWidgets(
      'sound catalogue shows real mapping and no fake convolution claim, $mode',
      (tester) async {
        await mount(tester, const MusicEffectsPage(), dark: dark, eq: true);
        await tester.pumpAndSettle();
        expect(find.text('温柔人声'), findsOneWidget);
        final semantics = tester.ensureSemantics();
        try {
          await tester.pump();
          final apply = find.bySemanticsLabel('应用温柔人声音效');
          expect(apply, findsOneWidget);
          await tester.tap(apply);
          await tester.pumpAndSettle();
          expect(
            tester.getSemantics(apply).flagsCollection.isSelected ==
                ui.Tristate.isTrue,
            true,
          );
        } finally {
          semantics.dispose();
        }
        await capture(tester, 'effects-$mode');
        await tester.tap(find.text('耳机'));
        await tester.pumpAndSettle();
        expect(find.textContaining('当前目录暂未返回'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
    testWidgets(
      'sleep sheet starts and cancels the existing owner timer, $mode',
      (tester) async {
        final result = await mount(
          tester,
          Consumer(
            builder: (context, ref, _) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showMusicSleepTimer(context, ref),
                  child: const Text('打开定时'),
                ),
              ),
            ),
          ),
          dark: dark,
        );
        await tester.tap(find.text('打开定时'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('music-sleep-start')));
        await tester.pump();
        expect(result.handler.sleepTimer.active, true);
        await capture(tester, 'sleep-$mode');
        await tester.tap(find.byKey(const ValueKey('music-sleep-cancel')));
        await tester.pump();
        expect(result.handler.sleepTimer.active, false);
        expect(tester.takeException(), isNull);
      },
    );
    testWidgets(
      'failed foreign MV switch retains actual source and its comment default, $mode',
      (tester) async {
        final previous = VideoPlayerPlatform.instance;
        final video = _Video();
        VideoPlayerPlatform.instance = video;
        addTearDown(() => VideoPlayerPlatform.instance = previous);
        final track = Track.fromJson({
          ...testTracks.first.toJson(),
          'id': 'kugou_fixture',
          'source': 'kugou',
          'platformSongId': '12345',
        });
        await mount(
          tester,
          MusicMvPage(track: track),
          dark: dark,
          mixedMvs: true,
        );
        await tester.pumpAndSettle();
        expect(video.ids, 1);
        await tester.tap(find.text('网易云 MV'));
        await tester.pumpAndSettle();
        expect(video.ids, 1);
        expect(find.textContaining('平台暂未提供此清晰度'), findsOneWidget);
        await tester.ensureVisible(find.text('查看评论'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('查看评论'));
        await tester.pumpAndSettle();
        expect(find.text('MV评论').hitTestable(), findsWidgets);
        expect(find.text('酷狗视频评论').hitTestable(), findsOneWidget);
      },
    );
    testWidgets(
      'MV comments remain available when no playback URL is permitted, $mode',
      (tester) async {
        final previous = VideoPlayerPlatform.instance;
        final video = _Video();
        VideoPlayerPlatform.instance = video;
        addTearDown(() => VideoPlayerPlatform.instance = previous);
        final track = Track.fromJson({
          ...testTracks.first.toJson(),
          'id': 'kugou_fixture',
          'source': 'kugou',
          'platformSongId': '12345',
        });
        await mount(
          tester,
          MusicMvPage(track: track),
          dark: dark,
          noPlayableMv: true,
        );
        await tester.pumpAndSettle();
        expect(video.ids, 0);
        await tester.ensureVisible(find.text('查看评论'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('查看评论'));
        await tester.pumpAndSettle();
        expect(find.text('酷狗视频评论').hitTestable(), findsOneWidget);
      },
    );
    testWidgets('MV initializes and switches actual video controllers, $mode', (
      tester,
    ) async {
      final previous = VideoPlayerPlatform.instance;
      final video = _Video();
      VideoPlayerPlatform.instance = video;
      addTearDown(() => VideoPlayerPlatform.instance = previous);
      final track = Track.fromJson({
        ...testTracks.first.toJson(),
        'source': 'kugou',
        'platformSongId': '12345',
      });
      final fixture = await mount(
        tester,
        MusicMvPage(track: track),
        dark: dark,
      );
      await tester.pumpAndSettle();
      expect(
        video.ids,
        1,
        reason:
            'MV routes: ${fixture.requests.map((r) => r.url.path).toList()}; UI: ${tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).whereType<String>().toList()}',
      );
      expect(find.text('720P · H.264'), findsOneWidget);
      await capture(tester, 'mv-$mode');
      await tester.tap(find.text('432P · H.264'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      expect(video.ids, 2);
      expect(
        video.disposals,
        1,
        reason:
            'plays=${video.plays}, live=${video.streams.keys.toList()}, views=${find.byType(VideoPlayer).evaluate().length}',
      );
      expect(tester.takeException(), isNull);
    });
    testWidgets(
      '105 timer uses app brightness beneath a forced-dark player, $mode',
      (tester) async {
        await mount(
          tester,
          Theme(
            data: ThemeData.dark(),
            child: Consumer(
              builder: (context, ref, _) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => showMusicSleepTimer(context, ref),
                    child: const Text('从播放器打开定时'),
                  ),
                ),
              ),
            ),
          ),
          dark: dark,
        );
        await tester.tap(find.text('从播放器打开定时'));
        await tester.pumpAndSettle();
        final sheetContext = tester.element(find.text('自定义时长'));
        expect(
          Theme.of(sheetContext).brightness,
          dark ? Brightness.dark : Brightness.light,
        );
        for (final chip in tester.elementList(find.byType(ChoiceChip))) {
          expect(
            Theme.of(chip).brightness,
            dark ? Brightness.dark : Brightness.light,
          );
        }
        await capture(tester, '105-sleep-from-player-$mode');
      },
    );
    testWidgets(
      '105 profile glass shares the scrolling surface during drag, $mode',
      (tester) async {
        await mount(tester, const PlatformProfileEditPage(), dark: dark);
        await tester.pumpAndSettle();
        expect(find.byType(BetaGlassScrollBody), findsOneWidget);
        final field = find.byType(BetaGlassField).first;
        expect(
          find.ancestor(
            of: field,
            matching: find.byKey(
              const ValueKey('glass-scroll-backing-surface'),
            ),
          ),
          findsOneWidget,
        );
        final gesture = await tester.startGesture(
          tester.getCenter(find.byType(ListView)),
        );
        await gesture.moveBy(const Offset(0, 180));
        await tester.pump(const Duration(milliseconds: 40));
        await capture(tester, '105-profile-overscroll-$mode');
        await gesture.up();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
    testWidgets(
      '105 MV full-screen entry and return retain the same controller, $mode',
      (tester) async {
        final previous = VideoPlayerPlatform.instance;
        final video = _Video();
        VideoPlayerPlatform.instance = video;
        addTearDown(() => VideoPlayerPlatform.instance = previous);
        final track = Track.fromJson({
          ...testTracks.first.toJson(),
          'source': 'kugou',
          'platformSongId': '12345',
        });
        await mount(tester, MusicMvPage(track: track), dark: dark);
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const ValueKey('music-mv-fullscreen')),
        );
        await tester.tap(find.byKey(const ValueKey('music-mv-fullscreen')));
        await tester.pumpAndSettle();
        expect(video.ids, 1);
        expect(video.disposals, 0);
        await tester.tap(
          find.byKey(const ValueKey('music-mv-exit-fullscreen')),
        );
        await tester.pumpAndSettle();
        expect(video.ids, 1);
        expect(video.disposals, 0);
        expect(find.text('720P · H.264'), findsOneWidget);
        expect(find.byType(VideoPlayer), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'profile read failure is retryable and exposes no editable empty draft',
    (tester) async {
      await mount(tester, const PlatformProfileEditPage(), profileError: true);
      // Reduced motion now pauses Apple tickers. Settling animation alone does
      // not imply the asynchronous profile request has reached its error UI.
      for (var i = 0; i < 80 && find.text('重试').evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.byType(TextField), findsNothing);
      }
      expect(find.byType(TextField), findsNothing);
      expect(find.text('重试'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  for (final page in <String, Widget>{
    'profile': const PlatformProfileEditPage(),
    'equalizer': const MusicEqualizerPage(),
    'effects': const MusicEffectsPage(),
  }.entries) {
    testWidgets('small screen large text remains scrollable: ${page.key}', (
      tester,
    ) async {
      await mount(
        tester,
        page.value,
        size: const Size(320, 700),
        scale: 1.6,
        eq: true,
      );
      await tester.pumpAndSettle();
      await capture(tester, '${page.key}-small-large');
      await tester.fling(
        find.byType(ListView).first,
        const Offset(0, -450),
        800,
      );
      await tester.pumpAndSettle();
      await capture(tester, '${page.key}-small-large-bottom');
      expect(tester.takeException(), isNull);
    });
  }
  for (final page in <String, Widget>{
    'profile': const PlatformProfileEditPage(),
    'equalizer': const MusicEqualizerPage(),
    'effects': const MusicEffectsPage(),
  }.entries) {
    testWidgets('wide layout retains readable bounds: ${page.key}', (
      tester,
    ) async {
      await mount(tester, page.value, size: const Size(820, 900), eq: true);
      await tester.pumpAndSettle();
      await capture(tester, '${page.key}-wide');
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('compact EQ points retain a usable drag area', (tester) async {
    final fixture = await mount(tester, const MusicEqualizerPage(), eq: true);
    await tester.pumpAndSettle();
    final controller = fixture.container.read(musicEqualizerProvider);
    final previous = controller.state.levels.first;
    await tester.drag(
      find.byKey(const ValueKey('music-equalizer-band-0')),
      const Offset(28, 0),
    );
    await tester.pumpAndSettle();
    expect(controller.state.levels.first, isNot(previous));
    expect(controller.state.preset, '自定义');
  });
}

class _NoCounterpartSearch extends PlatformSearchRepository {
  _NoCounterpartSearch(super.api);
  @override
  Future<PlatformSearchPage> search(
    String q, {
    int page = 1,
    Future<void>? abortTrigger,
  }) async => const PlatformSearchPage([], 0, false);
}

class _MvChoiceFixture extends PlatformMvRepository {
  _MvChoiceFixture(super.api, this.source, {this.fail = false});
  final TrackSource source;
  final bool fail;
  @override
  Future<MusicMv?> lookup(Track track) async => MusicMv(
    id: '${source.name}-real-video',
    title: track.title,
    artist: track.artist,
    duration: const Duration(minutes: 4),
    source: source,
    qualities: [MusicMvQuality('${source.name}-quality', '高清')],
  );
  @override
  Future<List<Uri>> urls(MusicMvQuality quality) async =>
      fail ? [] : [Uri.parse('https://media.example/mv-${source.name}.mp4')];
}

class _MvCounterpartFixture extends PlatformSearchRepository {
  _MvCounterpartFixture(super.api);
  @override
  Future<PlatformSearchPage> search(
    String q, {
    int page = 1,
    Future<void>? abortTrigger,
  }) async => PlatformSearchPage(
    [
      Track.fromJson({
        ...testTracks.first.toJson(),
        'id': 'netease_700',
        'source': 'netease',
      }),
    ],
    1,
    false,
  );
}
