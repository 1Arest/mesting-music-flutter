import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mesting_music/core/audio/mesting_audio_handler.dart';
import 'package:mesting_music/core/audio/playback_providers.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/features/experience/presentation/floating_playback_pill.dart';
import 'package:mesting_music/features/experience/presentation/beta_bottom_bar.dart';
import 'package:mesting_music/features/lyrics/domain/lyrics_document.dart';
import 'package:mesting_music/features/lyrics/lyrics_providers.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_api.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_models.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_pages.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_player_navigation.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_providers.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_repository.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_signer_connection.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_signer_settings.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_signer_settings_page.dart';
import 'package:mesting_music/shared/models/track.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/testing.dart';

import 'qishui_signer168_test.dart' show MemorySignerStore168, token168;
import 'qishui_ui_test.dart' show FixtureAccount;
import 'qishui_protocol_test.dart' show sodaSession, fixtureJson;
import 'support/release_147_qa.dart' show load147IconFonts;
import 'support/release_152_qa.dart' show theme152;
import 'package:mesting_music/features/library/library_providers.dart';

const capture168 = bool.fromEnvironment('CAPTURE_UI168');
const captureDirectory168 = String.fromEnvironment(
  'UI_CAPTURE_DIRECTORY',
  defaultValue: '.codex-artifacts/2026-11-06-release168/ui',
);
const boundary168 = ValueKey('ui168-capture');
final song168 = Track(
  id: 'qishui_168',
  platformSongId: '168',
  title: '慢慢听见',
  artist: '界面测试歌手',
  album: '测试专辑',
  duration: const Duration(minutes: 3),
  audioAsset: 'mesting-platform://qishui/168',
  coverAsset: 'assets/images/playlists/13416469337261709.jpeg',
  lyricsAsset: '',
  source: TrackSource.qishui,
);

class Player168 extends Fake implements MestingAudioHandler {
  Player168({this.preview = false});
  final bool preview;
  @override
  Stream<Duration?> get durationStream =>
      Stream.value(preview ? const Duration(seconds: 60) : song168.duration);
  final seeks = <Duration>[];
  int plays = 0;
  @override
  Future<void> seek(Duration position, {bool Function()? togetherGuard}) async {
    if (togetherGuard?.call() != false) seeks.add(position);
  }

  @override
  Future<void> play({bool Function()? togetherGuard}) async {
    if (togetherGuard?.call() != false) plays++;
  }

  @override
  Track? trackForId(String id) =>
      id == song168.id ? song168.copyWith(isPreview: preview) : null;
}

class Music168 extends QishuiRepository {
  Music168(super.api);
  @override
  Future<List<Track>> feed({
    QishuiFeedMode? mode,
    Future<void>? abortTrigger,
  }) async => [];
  @override
  Future<Map<String, dynamic>> profile() async => {};
}

Future<void> settle168(WidgetTester tester) async {
  // Long settings titles legitimately marquee at large text sizes. Advance a
  // bounded set of frames instead of waiting for that continuous motion to end.
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

class FailedSettings169 extends MemorySignerStore168 {
  @override
  Future<QishuiSignerConfig?> read() async {
    reads++;
    throw const QishuiSignerSettingsFailure('fixture local read failure');
  }
}

void main() {
  setUpAll(() async {
    await LiquidGlassWidgets.initialize();
    if (capture168) {
      await load147IconFonts();
      for (final name in [
        'SodaQA',
        'Microsoft YaHei',
        'Noto Sans SC',
        'Roboto',
        'CupertinoSystemText',
        'CupertinoSystemDisplay',
        'Ahem',
      ]) {
        await (FontLoader(name)..addFont(
              File(
                'C:/Windows/Fonts/msyh.ttc',
              ).readAsBytes().then(ByteData.sublistView),
            ))
            .load();
      }
    }
  });

  Future<ProviderContainer> mount(
    WidgetTester tester, {
    bool music = false,
    bool preview = false,
    Size size = const Size(390, 844),
    double scale = 1,
    bool dark = false,
    QishuiSignerProbe? probe,
    MemorySignerStore168? store,
    Stream<Duration>? positions,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final api = QishuiApi(MockClient((_) async => fixtureJson({})))
      ..configure(sodaSession());
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        platformAccountProvider.overrideWith(FixtureAccount.new),
        qishuiNavigationProvider.overrideWithValue(true),
        qishuiApiProvider.overrideWithValue(api),
        qishuiRepositoryProvider.overrideWithValue(Music168(api)),
        qishuiSignerSettingsStoreProvider.overrideWithValue(
          store ?? MemorySignerStore168(),
        ),
        qishuiSignerProbeProvider.overrideWithValue(probe ?? (_, _) async {}),
        audioHandlerProvider.overrideWithValue(Player168(preview: preview)),
        favoriteTrackIdsProvider.overrideWithValue(<String>{}),
        currentTrackProvider.overrideWithValue(
          song168.copyWith(isPreview: preview),
        ),
        currentMediaItemProvider.overrideWith(
          (_) => Stream.value(
            music
                ? MediaItem(
                    id: song168.id,
                    title: song168.title,
                    extras: {'source': 'qishui'},
                  )
                : null,
          ),
        ),
        playbackStateProvider.overrideWith(
          (_) => Stream.value(PlaybackState()),
        ),
        positionProvider.overrideWith(
          (_) => positions ?? Stream.value(Duration.zero),
        ),
        lyricsProvider.overrideWith(
          (_, _) async => LyricsDocument(
            isSynced: true,
            lines: [
              LyricsLine(time: Duration.zero, text: '这是界面验证用歌词'),
              LyricsLine(time: Duration(seconds: 10), text: '保留音乐与文字的呼吸'),
              ...List.generate(
                16,
                (index) => LyricsLine(
                  time: Duration(seconds: (index + 2) * 10),
                  text: index % 3 == 0
                      ? '让音乐慢慢穿过这个安静的夜晚，界面验证歌词 ${index + 2}'
                      : '第 ${index + 2} 句界面验证歌词',
                ),
              ),
            ],
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(api.dispose);
    await container.read(platformAccountProvider.future);
    var theme = theme152(dark);
    if (capture168) {
      theme = theme.copyWith(
        textTheme: theme.textTheme.apply(fontFamily: 'SodaQA'),
      );
    }
    final router = GoRouter(
      initialLocation: music ? '/discover' : '/settings',
      routes: [
        GoRoute(
          path: '/settings',
          builder: (_, _) => const QishuiSignerSettingsPage(),
        ),
        GoRoute(
          path: '/discover',
          builder: (_, _) => const Scaffold(
            body: Center(
              child: SizedBox(width: 340, child: FloatingPlaybackPill()),
            ),
          ),
        ),
        GoRoute(
          path: '/music',
          builder: (_, _) => Scaffold(
            body: Stack(
              children: [
                const QishuiRootPage(QishuiRoot.music),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: BetaMusicBottomBar(
                    soda: true,
                    selectedIndex: 1,
                    onTabSelected: (_) {},
                    searchConfig: GlassSearchBarConfig(onSearchToggle: (_) {}),
                  ),
                ),
              ],
            ),
          ),
        ),
        GoRoute(
          path: '/player',
          builder: (_, _) => const Text('unexpected player route'),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: LiquidGlassWidgets.wrap(
          adaptiveQuality: false,
          child: MaterialApp.router(
            routerConfig: router,
            theme: theme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: RepaintBoundary(key: boundary168, child: child!),
            ),
          ),
        ),
      ),
    );
    if (music) {
      await tester.runAsync(
        () => precacheImage(
          AssetImage(song168.coverAsset),
          tester.element(find.byType(Scaffold).first),
        ),
      );
    }
    await settle168(tester);
    return container;
  }

  Future<void> shot(WidgetTester tester, String name) async {
    if (!capture168) return;
    // Resized artwork decodes outside the fake test clock. Record the settled
    // state instead of a transient thumbnail placeholder.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await settle168(tester);
    await tester.runAsync(() async {
      final box = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(boundary168),
      );
      final picture = await box.toImage();
      final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$captureDirectory168/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      picture.dispose();
    });
  }

  for (final dark in [false, true]) {
    testWidgets(
      'settings edit, real probe boundary and durable save dark=$dark',
      (tester) async {
        final store = MemorySignerStore168();
        var probes = 0;
        await mount(
          tester,
          dark: dark,
          store: store,
          probe: (config, abort) async {
            probes++;
            expect(
              config.baseUri.toString(),
              'https://nas.example.test/qishui-signer/',
            );
          },
        );
        await tester.enterText(
          find.byKey(const ValueKey('qishui-signer-address')),
          'https://nas.example.test/qishui-signer/sign',
        );
        await tester.enterText(
          find.byKey(const ValueKey('qishui-signer-token')),
          token168,
        );
        expect(
          tester
              .widget<TextField>(
                find.byKey(const ValueKey('qishui-signer-token')),
              )
              .obscureText,
          isTrue,
        );
        await tester.ensureVisible(
          find.byKey(const ValueKey('qishui-signer-test')),
        );
        await tester.tap(find.byKey(const ValueKey('qishui-signer-test')));
        await settle168(tester);
        expect(probes, 1);
        expect(find.textContaining('连接和签名检查通过'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('qishui-signer-save')));
        await settle168(tester);
        expect(store.value?.signUri.path, '/qishui-signer/sign');
        expect(find.textContaining('已保存，后续签名请求'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await shot(tester, 'settings-${dark ? 'dark' : 'light'}');
      },
    );
  }
  testWidgets('narrow large text reports bad input and remains scrollable', (
    tester,
  ) async {
    await mount(tester, size: const Size(320, 760), scale: 1.8, dark: true);
    // The explicit Cookie disclosure adds variable-height content. Locate the
    // action semantically instead of assuming a fixed 500px scroll distance.
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('qishui-signer-save')),
      300,
      scrollable: find
          .descendant(
            of: find.byType(ListView).first,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await settle168(tester);
    await tester.tap(find.byKey(const ValueKey('qishui-signer-save')));
    await settle168(tester);
    expect(find.textContaining('请填写签名助手生成的访问令牌'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await shot(tester, 'settings-narrow-large');
  });
  testWidgets(
    'HTTP helper refusal is shown with an unchanged saved configuration',
    (tester) async {
      final store = MemorySignerStore168()
        ..value = QishuiSignerConfig.parse(
          'http://192.168.1.8:18899/',
          token168,
        );
      await mount(
        tester,
        store: store,
        probe: (_, _) async =>
            throw const QishuiException('签名助手尚未就绪（HTTP 503）'),
      );
      await tester.tap(find.byKey(const ValueKey('qishui-signer-test')));
      await settle168(tester);
      expect(find.text('签名助手尚未就绪（HTTP 503）'), findsOneWidget);
      expect(store.value?.baseUri.scheme, 'http');
      await shot(tester, 'settings-helper-not-ready');
    },
  );
  testWidgets('pill selects music tab; cover opens inline lyrics and returns', (
    tester,
  ) async {
    final container = await mount(tester, music: true);
    await tester.tap(find.byKey(const ValueKey('beta6-official-play-pill')));
    await settle168(tester);
    expect(find.text('unexpected player route'), findsNothing);
    expect(find.byKey(const ValueKey('qishui-music-cover')), findsOneWidget);
    await shot(tester, 'music-cover');
    await tester.tap(find.byKey(const ValueKey('qishui-music-cover')));
    await settle168(tester);
    expect(container.read(qishuiMusicLyricsProvider), isTrue);
    expect(find.byKey(const ValueKey('qishui-inline-lyrics')), findsOneWidget);
    expect(find.text('这是界面验证用歌词'), findsOneWidget);
    await shot(tester, 'music-inline-lyrics');
    await tester.tap(find.byKey(const ValueKey('qishui-lyric-line-1')));
    await settle168(tester);
    final player = container.read(audioHandlerProvider) as Player168;
    expect(player.seeks, isEmpty);
    expect(find.text('00:10'), findsOneWidget);
    await shot(tester, 'music-selected-line');
    await tester.tap(find.byKey(const ValueKey('qishui-lyric-play-1')));
    await settle168(tester);
    expect(player.seeks, [const Duration(seconds: 10)]);
    expect(player.plays, 1);
    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await settle168(tester);
    expect(container.read(qishuiMusicLyricsProvider), isFalse);
    expect(find.byKey(const ValueKey('qishui-music-cover')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'official lyric view follows playback but respects manual browsing',
    (tester) async {
      final positions = StreamController<Duration>.broadcast();
      addTearDown(positions.close);
      await mount(tester, music: true, positions: positions.stream);
      await tester.tap(find.byKey(const ValueKey('beta6-official-play-pill')));
      await settle168(tester);
      await tester.tap(find.byKey(const ValueKey('qishui-music-cover')));
      await settle168(tester);
      final list = find.byKey(const ValueKey('qishui-official-lyric-lines'));
      positions.add(const Duration(seconds: 30));
      await settle168(tester);
      final scroll = tester.widget<ListView>(list).controller!;
      expect(scroll.offset, greaterThan(20));
      await tester.timedDrag(
        list,
        const Offset(0, -130),
        const Duration(seconds: 1),
      );
      await settle168(tester);
      final manual = scroll.offset;
      positions.add(const Duration(seconds: 40));
      await settle168(tester);
      expect(scroll.offset, closeTo(manual, 2));
      expect(find.text('回到当前句'), findsOneWidget);
      await tester.tap(find.text('回到当前句'));
      await settle168(tester);
      expect(find.text('回到当前句'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'official lyric view wraps long lines at narrow large text and returns on Back',
    (tester) async {
      final container = await mount(
        tester,
        music: true,
        size: const Size(320, 760),
        scale: 1.8,
        dark: true,
      );
      await tester.tap(find.byKey(const ValueKey('beta6-official-play-pill')));
      await settle168(tester);
      await tester.tap(find.byKey(const ValueKey('qishui-music-cover')));
      await settle168(tester);
      expect(
        find.byKey(const ValueKey('qishui-inline-lyrics')),
        findsOneWidget,
      );
      await shot(tester, 'music-lyrics-narrow-large');
      expect(tester.takeException(), isNull);
      await tester.binding.handlePopRoute();
      await settle168(tester);
      expect(container.read(qishuiMusicLyricsProvider), isFalse);
      expect(find.byKey(const ValueKey('qishui-music-cover')), findsOneWidget);
    },
  );
  testWidgets(
    '169 initial form prefills NAS with no token and sends no probe',
    (tester) async {
      var probes = 0;
      await mount(
        tester,
        probe: (_, _) async {
          probes++;
        },
      );
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('qishui-signer-address')),
            )
            .controller!
            .text,
        qishuiSelfHostedSignerAddress,
      );
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('qishui-signer-token')),
            )
            .controller!
            .text,
        isEmpty,
      );
      expect(find.textContaining('未配置访问令牌'), findsOneWidget);
      expect(probes, 0);
      await shot(tester, 'settings-initial-unconfigured');
    },
  );
  for (final narrow in [false, true]) {
    testWidgets(
      '170 official preview stays labeled in cover and lyrics narrow=$narrow',
      (tester) async {
        final container = await mount(
          tester,
          music: true,
          preview: true,
          size: narrow ? const Size(320, 760) : const Size(390, 844),
          scale: narrow ? 1.8 : 1,
          dark: narrow,
        );
        GoRouter.of(
          tester.element(find.byType(FloatingPlaybackPill)),
        ).go('/music');
        await settle168(tester);
        expect(
          find.byKey(const ValueKey('qishui-official-preview-notice')),
          findsOneWidget,
        );
        await shot(tester, narrow ? 'preview-cover-narrow' : 'preview-cover');
        await tester.tap(find.byKey(const ValueKey('qishui-music-cover')));
        await settle168(tester);
        expect(
          find.byKey(const ValueKey('qishui-inline-lyrics')),
          findsOneWidget,
        );
        expect(find.text('官方试听'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await shot(tester, narrow ? 'preview-lyrics-narrow' : 'preview-lyrics');
        expect(
          container.read(currentTrackProvider).duration,
          const Duration(minutes: 3),
        );
      },
    );
  }
  testWidgets(
    '169 rejected local settings show manual retry instead of a spinner',
    (tester) async {
      final store = FailedSettings169();
      await mount(tester, store: store);
      expect(find.text('正在读取签名服务设置…'), findsNothing);
      expect(find.text('设置未能读取，点击重试'), findsOneWidget);
      expect(store.reads, 1);
      await shot(tester, 'settings-read-failed');
      await tester.tap(find.text('设置未能读取，点击重试'));
      await settle168(tester);
      expect(store.reads, 2);
    },
  );
}
