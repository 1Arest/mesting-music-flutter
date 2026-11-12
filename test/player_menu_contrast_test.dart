import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:mesting_music/features/themes/beta_appearance.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mesting_music/features/experience/presentation/player_surface_theme.dart';
import 'package:mesting_music/features/library/library_providers.dart';
import 'package:mesting_music/features/music_platform/data/song_menu_details.dart';
import 'package:mesting_music/features/music_platform/presentation/song_actions_sheet.dart';
import 'package:mesting_music/features/themes/app_theme.dart';
import 'package:mesting_music/features/themes/music_theme_preset.dart';
import 'package:mesting_music/features/themes/music_theme_tokens.dart';
import 'package:mesting_music/shared/models/track.dart';
import 'package:mesting_music/shared/widgets/liquid_glass_sheet.dart';

import 'support/personal_profile_fixture.dart';

const _capture = bool.fromEnvironment('CAPTURE_PLAYER_MENU_CONTRAST');
const _captureKey = ValueKey('player-menu-contrast-capture');

// Reproduce the production player's local dark palette over either app theme.
// copyWith deliberately retains the source foreground until the helper fixes it.
ThemeData _playerTheme(ThemeData base, {bool classic = false}) =>
    readablePlayerSurfaceTheme(
      base.copyWith(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: BetaAppearance.blue,
          brightness: Brightness.dark,
        ).copyWith(primary: BetaAppearance.accent(Brightness.dark)),
        extensions: [MusicThemeTokens.forBrightness(Brightness.dark)],
        iconButtonTheme: IconButtonThemeData(
          style: IconButton.styleFrom(
            foregroundColor: Colors.white,
            backgroundColor: classic
                ? const Color(0x66000000)
                : Colors.transparent,
            minimumSize: const Size(48, 48),
          ),
        ),
      ),
    );

void main() {
  setUpAll(() async {
    await LiquidGlassWidgets.initialize();
    if (!_capture) return;
    await (FontLoader('PlayerMenuQA')..addFont(
          File(
            'C:/Windows/Fonts/msyh.ttc',
          ).readAsBytes().then(ByteData.sublistView),
        ))
        .load();
    await (FontLoader('MaterialIcons')..addFont(
          File(
            'D:/flutter_windows_3.47.7-stable/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
          ).readAsBytes().then(ByteData.sublistView),
        ))
        .load();
    await (FontLoader('packages/cupertino_icons/CupertinoIcons')..addFont(
          rootBundle.load('packages/cupertino_icons/assets/CupertinoIcons.ttf'),
        ))
        .load();
  });

  for (final dark in [false, true]) {
    test('播放器继承${dark ? "深色" : "浅色"}主题时所有默认前景均使用深色表面配色', () {
      final base = buildMestingTheme(
        musicThemePresetById(dark ? 'classic-dark' : 'classic'),
      );
      final player = _playerTheme(base);
      final tokens = player.extension<MusicThemeTokens>()!;
      expect(player.brightness, Brightness.dark);
      expect(player.textTheme.bodyLarge?.color, tokens.textPrimary);
      expect(player.listTileTheme.textColor, tokens.textPrimary);
      expect(player.listTileTheme.titleTextStyle?.color, tokens.textPrimary);
      expect(player.listTileTheme.iconColor, tokens.textSecondary);
      expect(
        player.listTileTheme.subtitleTextStyle?.color,
        tokens.textSecondary,
      );
      expect(
        player.cupertinoOverrideTheme?.textTheme?.textStyle.color,
        tokens.textPrimary,
      );
      expect(player.cupertinoOverrideTheme?.brightness, Brightness.dark);
      final background = Color.alphaBlend(
        tokens.glass,
        const Color(0xFF12384E),
      );
      expect(
        _contrast(tokens.textPrimary, background),
        greaterThanOrEqualTo(7),
      );
      expect(
        _contrast(tokens.textSecondary, background),
        greaterThanOrEqualTo(4.5),
      );
      expect(base.brightness, dark ? Brightness.dark : Brightness.light);
      if (!dark) {
        expect(base.listTileTheme.textColor!.computeLuminance(), lessThan(.1));
      }
      expect(
        player.iconButtonTheme.style?.backgroundColor?.resolve({}),
        Colors.transparent,
      );
      expect(
        _playerTheme(
          base,
          classic: true,
        ).iconButtonTheme.style?.backgroundColor?.resolve({}),
        const Color(0x66000000),
      );
    });

    testWidgets('真实歌曲菜单捕获播放器配色，文字图标可读且原有操作可用 dark=$dark', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fixture = await PersonalProfileFixture.create();
      addTearDown(fixture.dispose);
      const track = Track(
        id: 'netease_362937',
        title: '心似烟火',
        artist: '陈壹千',
        album: '梦了吧',
        duration: Duration(minutes: 3),
        source: TrackSource.netease,
        audioAsset: '',
        lyricsAsset: '',
        coverAsset: profileFixtureCover,
      );
      final base = buildMestingTheme(
        musicThemePresetById(dark ? 'classic-dark' : 'classic'),
      );
      var player = _playerTheme(base);
      if (_capture) {
        player = player.copyWith(
          textTheme: player.textTheme.apply(fontFamily: 'PlayerMenuQA'),
          listTileTheme: player.listTileTheme.copyWith(
            titleTextStyle: player.listTileTheme.titleTextStyle?.copyWith(
              fontFamily: 'PlayerMenuQA',
            ),
            subtitleTextStyle: player.listTileTheme.subtitleTextStyle?.copyWith(
              fontFamily: 'PlayerMenuQA',
            ),
          ),
        );
      }
      final intents = <Object>[];
      await tester.pumpWidget(
        RepaintBoundary(
          key: _captureKey,
          child: UncontrolledProviderScope(
            container: fixture.container,
            child: ProviderScope(
              overrides: [
                favoriteTrackIdsProvider.overrideWithValue({track.id}),
              ],
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: base,
                home: Theme(
                  data: player,
                  child: Scaffold(
                    body: DecoratedBox(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF071C2C), Color(0xFF12384E)],
                        ),
                      ),
                      child: Builder(
                        builder: (context) => Center(
                          child: TextButton(
                            onPressed: () => showLiquidGlassBottomSheet<void>(
                              context: context,
                              useRootNavigator: true,
                              useSafeArea: true,
                              isScrollControlled: true,
                              builder: (_) => SongActionsPanel(
                                track: track,
                                onSelect: intents.add,
                                loadDetails: () async => const SongMenuDetails(
                                  artists: [SongMenuPerson('陈壹千', id: '17')],
                                  creators: [SongMenuPerson('陈壹千', role: '作词')],
                                  album: '梦了吧',
                                  albumId: '19',
                                ),
                              ),
                            ),
                            child: const Text('打开歌曲菜单'),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开歌曲菜单'));
      await tester.pumpAndSettle();
      if (_capture) {
        await tester.runAsync(
          () => precacheImage(
            const AssetImage(profileFixtureCover),
            tester.element(find.byType(SongActionsPanel)),
          ),
        );
        await tester.pump();
      }
      final tokens = player.extension<MusicThemeTokens>()!;
      for (final intent in [
        'next',
        'playlist',
        'download',
        'comments',
        'share',
      ]) {
        final tile = find.byKey(ValueKey('song-menu-$intent'));
        final label = find
            .descendant(of: tile, matching: find.byType(Text))
            .first;
        final text = tester.widget<RichText>(
          find.descendant(of: label, matching: find.byType(RichText)).first,
        );
        expect(text.text.style?.color, tokens.textPrimary, reason: intent);
        final icon = tester.element(
          find.descendant(of: tile, matching: find.byType(Icon)).first,
        );
        expect(IconTheme.of(icon).color, tokens.textSecondary, reason: intent);
      }
      final favorite = find.byKey(const ValueKey('song-menu-favorite'));
      final selectedLabel = find
          .descendant(of: favorite, matching: find.byType(Text))
          .first;
      final selectedText = tester.widget<RichText>(
        find
            .descendant(of: selectedLabel, matching: find.byType(RichText))
            .first,
      );
      expect(
        selectedText.text.style?.color,
        BetaAppearance.favorite(player.brightness),
      );
      expect(find.text('取消喜欢'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('song-menu-next')));
      expect(intents, ['next']);
      if (_capture) {
        await _shot(tester, 'menu-from-${dark ? "dark" : "light"}-theme-top');
      }
      await tester.drag(find.byType(ListView), const Offset(0, -340));
      await tester.pumpAndSettle();
      expect(find.text('专辑：梦了吧').hitTestable(), findsOneWidget);
      if (_capture) {
        await _shot(
          tester,
          'menu-from-${dark ? "dark" : "light"}-theme-details',
        );
      }
      await tester.tap(find.byTooltip('关闭歌曲菜单'));
      await tester.pumpAndSettle();
      expect(find.byType(SongActionsPanel), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}

double _contrast(Color foreground, Color background) {
  final a = Color.alphaBlend(foreground, background).computeLuminance();
  final b = background.computeLuminance();
  return (a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05));
}

Future<void> _shot(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final image = await tester
        .renderObject<RenderRepaintBoundary>(find.byKey(_captureKey))
        .toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final path = File('../player-menu-contrast-proof/$name.png');
    await path.parent.create(recursive: true);
    await path.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}
