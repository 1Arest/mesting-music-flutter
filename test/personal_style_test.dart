import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'dart:convert';
import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/services.dart';
import 'package:mesting_music/core/audio/playback_providers.dart';
import 'package:mesting_music/core/platform/avatar_media_bridge.dart';
import 'package:mesting_music/features/history/listening_replay.dart';
import 'package:mesting_music/features/themes/listening_keepsake.dart';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/features/themes/personal_style.dart';
import 'package:mesting_music/features/themes/personal_style_page.dart';
import 'package:mesting_music/features/themes/personal_decorations.dart';
import 'package:mesting_music/features/themes/listening_atmosphere.dart';
import 'package:mesting_music/features/player/sharing/song_share.dart';
import 'package:mesting_music/features/music_platform/presentation/platform_avatar.dart';
import 'package:mesting_music/shared/widgets/beta_swipe_pages.dart';
import 'song_share_test.dart' show song;
import 'support/ui_fix_capture.dart';

void main() {
  setUpAll(() async {
    await LiquidGlassWidgets.initialize();
    await initializeUiFixCapture();
    if (uiFixCaptureDirectory.isNotEmpty) {
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    }
  });
  late SharedPreferences prefs;
  late ProviderContainer container;
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'music_progress_style': 'kuromi',
      'music_progress_character': 'nailong',
    });
    prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
  });
  tearDown(() => container.dispose());
  Widget host(Widget child, {double scale = 1, bool dark = true}) =>
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: dark ? ThemeData.dark() : ThemeData.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: RepaintBoundary(key: uiFixCaptureKey, child: child),
        ),
      );
  test('defaults preserve existing appearance and atmosphere is opt-in', () {
    final s = container.read(personalStyleProvider);
    expect(s.atmosphere, ListeningAtmosphere.off);
    expect(s.frame, CoverFrame.none);
    expect(s.accessory, AvatarAccessory.none);
    expect(s.poster, PosterTemplate.original);
    expect(s.mini, MiniPlayerFinish.original);
    expect(s.lyricSize, 0);
    expect(s.lyricPresentation, LyricPresentation.current);
  });
  test(
    'independent choices survive restart, reset and ordered rapid writes',
    () async {
      final control = container.read(personalStyleProvider.notifier);
      await control.change({
        'palette': '海盐蓝调',
        'frame': 'stamp',
        'accessory': 'moon',
        'mini': 'gradient',
        'poster': 'ticket',
        'keepsake': 'postcard',
        'atmosphere': 'stars',
        'serif': true,
        'lyricSize': 32,
        'lyricPresentation': 'focus',
        'lyricColor': 0xffbbddff,
      });
      await Future.wait([
        control.change({'strength': .1}),
        control.change({'strength': .6}),
        control.change({'strength': .8}),
      ]);
      final restored = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      final s = restored.read(personalStyleProvider);
      expect(s.frame, CoverFrame.none);
      expect(s.toJson().containsKey('frame'), false);
      expect(s.poster, PosterTemplate.ticket);
      expect(s.strength, .8);
      expect(s.lyricSize, 32);
      expect(s.lyricPresentation, LyricPresentation.focus);
      expect(s.accessory, AvatarAccessory.moon);
      expect(s.atmosphere, ListeningAtmosphere.stars);
      restored.dispose();
      await control.reset();
      expect(
        container.read(personalStyleProvider).toJson(),
        const PersonalStyle().toJson(),
      );
      expect(prefs.getString('music_progress_style'), 'kuromi');
      expect(prefs.getString('music_progress_character'), 'nailong');
    },
  );
  test('bundle applies once and later edits remain independent', () async {
    final control = container.read(personalStyleProvider.notifier);
    await control.change(personalPaletteBundle('樱花汽水'));
    expect(
      container.read(personalStyleProvider).accessory,
      AvatarAccessory.bow,
    );
    await control.change({'accessory': 'record'});
    expect(container.read(personalStyleProvider).palette, '樱花汽水');
    expect(
      container.read(personalStyleProvider).accessory,
      AvatarAccessory.record,
    );
    expect(prefs.getString('music_progress_character'), 'nailong');
  });
  test('invalid and future saved preferences safely fall back', () {
    final s = PersonalStyle.fromJson({
      'frame': 'acrylic',
      'atmosphere': 'future',
      'strength': 500,
      'lyricSize': 'bad',
    });
    expect(s.frame, CoverFrame.none);
    expect(s.atmosphere, ListeningAtmosphere.off);
    expect(s.strength, 1);
    expect(s.lyricSize, 0);
    final tiny = PersonalStyle.fromJson({
      'lyricSize': 1,
      'lineHeight': .1,
      'lyricColor': -1,
    });
    expect(tiny.lyricSize, 20);
    expect(tiny.lineHeight, 1.1);
    expect(tiny.lyricColor, isNull);
    final theme = ThemeData.dark();
    expect(
      identical(applyPersonalPalette(theme, const PersonalStyle()), theme),
      true,
    );
    expect(
      applyPersonalPalette(
        theme,
        const PersonalStyle(palette: '樱花汽水'),
      ).colorScheme.error,
      theme.colorScheme.error,
    );
  });
  testWidgets('新增清晰歌词预览选择，保存后重开仍保留且不覆盖字号行距', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await container.read(personalStyleProvider.notifier).change({
      'lyricSize': 24,
      'lineHeight': 1.2,
    });
    await tester.pumpWidget(host(const PersonalStylePage()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('歌词').first);
    await tester.pumpAndSettle();
    final choice = find.byKey(const ValueKey('lyric-presentation-clear'));
    await tester.ensureVisible(choice);
    await tester.pumpAndSettle();
    await tester.tap(choice);
    await tester.pumpAndSettle();
    final style = container.read(personalStyleProvider);
    expect(style.lyricPresentation, LyricPresentation.clear);
    expect(style.lyricSize, 24);
    expect(style.lineHeight, 1.2);
    final lyricViewport = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byType(ListView).hitTestable().last,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    lyricViewport.position.jumpTo(0);
    await tester.pumpAndSettle();
    await captureUiFix(tester, 'clear-lyrics-picker-dark');
    await tester.pumpWidget(host(const PersonalStylePage(), dark: false));
    await tester.pumpAndSettle();
    await captureUiFix(tester, 'clear-lyrics-picker-light');
    final restored = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    expect(
      restored.read(personalStyleProvider).lyricPresentation,
      LyricPresentation.clear,
    );
    restored.dispose();
    expect(
      PersonalStyle.fromJson({'lyricPresentation': 'focus'}).lyricPresentation,
      LyricPresentation.focus,
    );
    expect(
      PersonalStyle.fromJson({}).lyricPresentation,
      LyricPresentation.current,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'disabled atmosphere reads no audio provider and starts no ticker',
    (tester) async {
      await tester.pumpWidget(
        host(
          const Scaffold(
            body: SizedBox.expand(child: ListeningAtmosphereLayer()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('local accessory never decorates other public avatars', (
    tester,
  ) async {
    await container.read(personalStyleProvider.notifier).change({
      'accessory': 'moon',
    });
    await tester.pumpWidget(
      host(
        const Scaffold(
          body: Row(
            children: [
              PlatformAvatar(url: '', personal: true),
              PlatformAvatar(url: ''),
            ],
          ),
        ),
      ),
    );
    expect(find.byType(PersonalAvatarDecoration), findsOneWidget);
    expect(find.byIcon(Icons.nightlight_round), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'settings swipe and clicks share retained page selection scale=$scale',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(host(const PersonalStylePage(), scale: scale));
        await tester.pumpAndSettle();
        expect(find.text('播放按钮'), findsNothing);
        expect(find.text('胶片齿孔'), findsNothing);
        expect(find.text('透明亚克力'), findsNothing);
        await tester.drag(find.byType(BetaSwipePages), const Offset(-320, 0));
        await tester.pumpAndSettle();
        expect(
          tester.widget<BetaSwipePages>(find.byType(BetaSwipePages)).index,
          1,
        );
        await tester.tap(find.text('挂件').first);
        await tester.pumpAndSettle();
        expect(
          tester.widget<BetaSwipePages>(find.byType(BetaSwipePages)).index,
          2,
        );
        final moon = find.byKey(const ValueKey('accessory-moon'));
        await tester.ensureVisible(moon);
        await tester.pumpAndSettle();
        await tester.tap(moon);
        await tester.pumpAndSettle();
        expect(
          container.read(personalStyleProvider).accessory,
          AvatarAccessory.moon,
        );
        await captureUiFix(tester, 'personal-style-accessories-$scale');
        await tester.tap(find.bySemanticsLabel('恢复默认').first);
        await tester.pumpAndSettle();
        expect(
          container.read(personalStyleProvider).accessory,
          AvatarAccessory.none,
        );
        await tester.pumpWidget(const SizedBox());
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('atmosphere eases to rest on pause and stops in background', (
    tester,
  ) async {
    final stream = StreamController<PlaybackState>.broadcast(sync: true);
    final audioContainer = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        currentTrackProvider.overrideWithValue(song()),
        playbackStateProvider.overrideWith((ref) => stream.stream),
      ],
    );
    await audioContainer.read(personalStyleProvider.notifier).change({
      'atmosphere': 'stars',
    });
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: audioContainer,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox.expand(child: ListeningAtmosphereLayer()),
          ),
        ),
      ),
    );
    await tester.pump();
    stream.add(PlaybackState(playing: true));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    stream.add(PlaybackState(playing: false));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
    stream.add(PlaybackState(playing: true));
    await tester.pump();
    await audioContainer.read(personalStyleProvider.notifier).change({
      'strength': 0,
    });
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
    await audioContainer.read(personalStyleProvider.notifier).change({
      'strength': .35,
    });
    await tester.pump();
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(const SizedBox());
    audioContainer.dispose();
    await stream.close();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });
  testWidgets(
    'keepsake saves actual period totals through the gallery bridge',
    (tester) async {
      MethodCall? saved;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        AvatarMediaBridge.channel,
        (call) async {
          saved = call;
          return 'saved';
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          AvatarMediaBridge.channel,
          null,
        ),
      );
      await container.read(personalStyleProvider.notifier).change({
        'keepsake': 'postcard',
      });
      await tester.pumpWidget(
        host(
          Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showListeningKeepsake(
                  context,
                  ListeningReplay(120000, [ReplayTrack(song(), 120000, 1)], []),
                  2026,
                  10,
                ),
                child: const Text('纪念卡'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('纪念卡'));
      await tester.pumpAndSettle();
      expect(find.text('音乐陪伴 2 分钟'), findsOneWidget);
      expect(find.text('听过 1 首歌'), findsOneWidget);
      expect(find.text('2026 年 · 10 月'), findsOneWidget);
      await tester.ensureVisible(find.text('保存纪念卡'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存纪念卡'));
      for (var i = 0; i < 20 && saved == null; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(saved?.method, 'saveImage');
      expect((saved!.arguments as Map)['bytes'], isNotEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('each poster exports distinct full-resolution pixels', (
    tester,
  ) async {
    final outputs = <String>{};
    await tester.runAsync(() async {
      for (final template in PosterTemplate.values) {
        final data = await generateSongPoster(song(), template: template);
        final codec = await ui.instantiateImageCodec(data);
        final frame = await codec.getNextFrame();
        expect(frame.image.width, 1080);
        expect(frame.image.height, 1704);
        outputs.add(base64Encode(data));
        frame.image.dispose();
        codec.dispose();
      }
    });
    expect(outputs.length, PosterTemplate.values.length);
  });
}
