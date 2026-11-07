import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/core/audio/mesting_audio_handler.dart';
import 'package:mesting_music/core/audio/playback_mode.dart';
import 'package:mesting_music/core/audio/playback_providers.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/core/platform/lyrics_overlay_bridge.dart';
import 'package:mesting_music/features/library/library_providers.dart';
import 'package:mesting_music/features/lyrics/domain/lyrics_document.dart';
import 'package:mesting_music/features/lyrics/lyrics_providers.dart';
import 'package:mesting_music/features/player/presentation/now_playing_page.dart';
import 'package:mesting_music/features/player/presentation/player_visual_stages.dart';
import 'package:mesting_music/features/themes/app_theme.dart';
import 'package:mesting_music/features/themes/mesting_palette.dart';
import 'package:mesting_music/features/themes/music_theme_preset.dart';
import 'package:mesting_music/features/themes/theme_controller.dart';
import 'package:mesting_music/shared/models/track.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _HiddenLyricsOverlayController extends LyricsOverlayController {
  @override
  LyricsOverlaySettings build() => const LyricsOverlaySettings();
}

class _TestAudioHandler extends MestingAudioHandler {
  _TestAudioHandler() : super(tracks: const [_track]);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('经典浅色和深色歌词页共享封面模糊背景与顶部信息', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final lightPalette = await _pumpLyricsPlayer(
      tester,
      musicThemePresetById('classic'),
    );
    expect(find.byKey(const ValueKey('lyrics-artwork-blur')), findsOneWidget);
    expect(find.byKey(const ValueKey('lyrics-track-heading')), findsOneWidget);
    expect(find.byKey(const ValueKey('lyrics-top-safe-clip')), findsOneWidget);
    final lyricMask = tester.widget<ShaderMask>(
      find.byKey(const ValueKey('lyrics-top-fade-mask')),
    );
    expect(lyricMask.blendMode, BlendMode.dstIn);
    expect(nowPlayingLyricsViewportTop(0), 78);
    expect(nowPlayingLyricsViewportTop(44), 92);
    expect(find.text(_track.title), findsOneWidget);
    expect(find.text(_track.artist), findsOneWidget);
    expect(find.text('0:54'), findsOneWidget);

    final darkPalette = await _pumpLyricsPlayer(
      tester,
      musicThemePresetById('classic-dark'),
    );
    expect(darkPalette, lightPalette);
    expect(find.byKey(const ValueKey('lyrics-artwork-blur')), findsOneWidget);
    expect(find.text('0:54'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('唱片页只保留舞台曲目信息，进入歌词后保留顶部信息', (tester) async {
    tester.view.physicalSize = const Size(390, 873);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpLyricsPlayer(
      tester,
      musicThemePresetById('classic-dark'),
      showLyricsInitially: false,
      playerVisualStyle: 'aurora',
    );

    expect(find.byKey(const ValueKey('player-track-heading')), findsNothing);
    expect(find.byKey(const ValueKey('lyrics-track-heading')), findsNothing);
    expect(
      find.byKey(const ValueKey('alternative-player-favorite-aurora')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('playback-elapsed-time')), findsOneWidget);
    expect(find.text('0:54'), findsOneWidget);
    expect(find.text(_track.title), findsOneWidget);
    expect(find.text(_track.artist), findsOneWidget);
    expect(
      find.byKey(const ValueKey('listen-together-player-entry')),
      findsOneWidget,
    );
    expect(find.text('好友一起听'), findsOneWidget);
    expect(find.byTooltip('分享给好友'), findsOneWidget);
    expect(find.byIcon(Icons.ios_share_rounded), findsOneWidget);
    expect(find.byIcon(Icons.desktop_windows_rounded), findsNothing);
    final backButton = find.byKey(const ValueKey('now-playing-back-button'));
    expect(backButton, findsOneWidget);
    expect(
      find.descendant(
        of: backButton,
        matching: find.byIcon(Icons.arrow_back_ios_new_rounded),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: backButton, matching: find.byType(BackdropFilter)),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('aurora-player-disc')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('lyrics-track-heading')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('listen-together-player-entry')),
      findsNothing,
    );
    expect(find.text(_track.title), findsOneWidget);
    expect(find.text(_track.artist), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('经典唱片收藏按钮使用心动红圆形表面与图标', (tester) async {
    tester.view.physicalSize = const Size(390, 873);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpLyricsPlayer(
      tester,
      musicThemePresetById('classic-dark'),
      showLyricsInitially: false,
    );

    final favoriteButton = find.byKey(
      const ValueKey('classic-player-favorite'),
    );
    expect(favoriteButton, findsOneWidget);
    final icon = tester.widget<Icon>(
      find.descendant(
        of: favoriteButton,
        matching: find.byIcon(Icons.favorite_border_rounded),
      ),
    );
    expect(icon.color, MestingPalette.favorite);

    final material = tester.widget<Material>(
      find.descendant(of: favoriteButton, matching: find.byType(Material)),
    );
    expect(material.color, MestingPalette.favorite.withValues(alpha: .10));
    final shape = material.shape! as CircleBorder;
    expect(shape.side.color, MestingPalette.favorite.withValues(alpha: .34));
    expect(tester.takeException(), isNull);
  });

  testWidgets('唱片页和歌词页控制区均整体上移并保留歌词底部空间', (tester) async {
    tester.view.physicalSize = const Size(390, 873);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpLyricsPlayer(
      tester,
      musicThemePresetById('classic-dark'),
      showLyricsInitially: false,
    );

    final recordDock = tester.getSize(
      find.byKey(const ValueKey('playback-controls-dock')),
    );
    expect(recordDock.height, 150 + nowPlayingRecordControlsLift);
    expect(find.byKey(const ValueKey('playback-elapsed-time')), findsOneWidget);
    expect(find.text('0:54'), findsOneWidget);
    expect(find.text('点击唱片查看歌词'), findsNothing);

    await _pumpLyricsPlayer(
      tester,
      musicThemePresetById('classic-dark'),
      showLyricsInitially: true,
    );

    final lyricsDock = tester.getSize(
      find.byKey(const ValueKey('playback-controls-dock')),
    );
    expect(lyricsDock.height, 150 + nowPlayingLyricsControlsLift);
    expect(recordDock.height, lyricsDock.height);
    final lyricsPadding = tester.widget<Padding>(
      find.byKey(const ValueKey('lyrics')),
    );
    expect(
      (lyricsPadding.padding as EdgeInsets).bottom,
      150 + nowPlayingLyricsControlsLift,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('三套非经典播放器连同氛围层共享经典歌词切换过渡', (tester) async {
    tester.view.physicalSize = const Size(390, 873);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const styles =
        <
          ({
            String preference,
            String stageKey,
            String tapTargetKey,
            String eyebrow,
          })
        >[
          (
            preference: 'aurora',
            stageKey: 'player-stage-aurora',
            tapTargetKey: 'aurora-player-disc',
            eyebrow: 'AURORA ORBIT',
          ),
          (
            preference: 'cassette',
            stageKey: 'player-stage-cassette',
            tapTargetKey: 'cosmic-pulse-stage',
            eyebrow: 'COSMIC PULSE',
          ),
          (
            preference: 'lyricStage',
            stageKey: 'player-stage-lyricStage',
            tapTargetKey: 'liquid-spectrum-stage',
            eyebrow: 'LIQUID SPECTRUM',
          ),
        ];

    for (final style in styles) {
      await _pumpLyricsPlayer(
        tester,
        musicThemePresetById('classic-dark'),
        showLyricsInitially: false,
        playerVisualStyle: style.preference,
        topSafeInset: 44,
      );

      final stage = find.byKey(ValueKey(style.stageKey));
      expect(stage, findsOneWidget);
      expect(find.byType(PlayerStyleAtmosphere), findsOneWidget);
      final togetherEntry = tester.getRect(
        find.byKey(const ValueKey('listen-together-player-entry')),
      );
      final eyebrow = tester.getRect(find.text(style.eyebrow));
      expect(
        eyebrow.top,
        greaterThanOrEqualTo(togetherEntry.bottom + 12),
        reason: '${style.preference} 的舞台标题必须完整避让顶部一起听入口',
      );
      final switcher = tester.widget<AnimatedSwitcher>(
        find.byKey(const ValueKey('now-playing-content-switcher')),
      );
      expect(switcher.duration, const Duration(milliseconds: 520));

      await tester.tap(find.byKey(ValueKey(style.tapTargetKey)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 260));

      expect(stage, findsOneWidget);
      expect(find.byKey(const ValueKey('lyrics')), findsOneWidget);
      expect(
        find.byType(PlayerStyleAtmosphere),
        findsOneWidget,
        reason: '${style.preference} 的氛围层必须随舞台一起退场',
      );

      await tester.pumpAndSettle();
      expect(stage, findsNothing);
      expect(find.byType(PlayerStyleAtmosphere), findsNothing);
      expect(find.byKey(const ValueKey('lyrics')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('lyrics-track-heading')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 260));

      expect(stage, findsOneWidget);
      expect(find.byKey(const ValueKey('lyrics')), findsOneWidget);
      expect(find.byType(PlayerStyleAtmosphere), findsOneWidget);

      await tester.pumpAndSettle();
      expect(stage, findsOneWidget);
      expect(find.byKey(const ValueKey('lyrics')), findsNothing);
      expect(find.byType(PlayerStyleAtmosphere), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('平板横屏播放器同时展示视觉舞台与同步歌词', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpLyricsPlayer(
      tester,
      musicThemePresetById('classic-dark'),
      showLyricsInitially: false,
      playerVisualStyle: 'aurora',
    );

    expect(
      find.byKey(const ValueKey('now-playing-wide-visual-pane')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('now-playing-tablet-lyrics-pane')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('player-stage-aurora')), findsOneWidget);
    expect(find.byKey(const ValueKey('lyrics-top-safe-clip')), findsOneWidget);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('now-playing-wide-visual-pane')))
          .width,
      closeTo(1280 * .54, .1),
    );
    expect(tester.takeException(), isNull);
  });
}

Future<List<Color>> _pumpLyricsPlayer(
  WidgetTester tester,
  MusicThemePreset preset, {
  bool showLyricsInitially = true,
  String playerVisualStyle = 'classic',
  double topSafeInset = 0,
}) async {
  SharedPreferences.setMockInitialValues({
    'player_visual_style': playerVisualStyle,
  });
  final preferences = await SharedPreferences.getInstance();
  final handler = _TestAudioHandler();
  final mediaQueryData = MediaQueryData.fromView(tester.view).copyWith(
    padding: EdgeInsets.only(top: topSafeInset),
    viewPadding: EdgeInsets.only(top: topSafeInset),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        audioHandlerProvider.overrideWithValue(handler),
        currentTrackProvider.overrideWithValue(_track),
        favoriteTrackIdsProvider.overrideWithValue(const <String>{}),
        effectiveMusicThemeProvider.overrideWithValue(preset),
        playbackStateProvider.overrideWith(
          (_) => Stream.value(
            PlaybackState(processingState: AudioProcessingState.ready),
          ),
        ),
        positionProvider.overrideWith(
          (_) => Stream.value(const Duration(seconds: 54)),
        ),
        durationProvider.overrideWith(
          (_) => Stream<Duration?>.value(_track.duration),
        ),
        playbackModeProvider.overrideWith(
          (_) => Stream.value(PlaybackMode.list),
        ),
        lyricsOverlayProvider.overrideWith(_HiddenLyricsOverlayController.new),
        lyricsProvider.overrideWith((ref, path) async => _lyrics),
      ],
      child: MaterialApp(
        theme: buildMestingTheme(preset),
        home: MediaQuery(
          data: mediaQueryData,
          child: NowPlayingPage(
            key: ValueKey(
              'now-playing-$playerVisualStyle-$showLyricsInitially',
            ),
            showLyricsInitially: showLyricsInitially,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  if (!showLyricsInitially) return const [];

  final base = tester.widget<ColoredBox>(
    find.byKey(const ValueKey('lyrics-backdrop-base')),
  );
  final veil = tester.widget<DecoratedBox>(
    find.byKey(const ValueKey('lyrics-backdrop-neutral-veil')),
  );
  final gradient =
      (veil.decoration as BoxDecoration).gradient! as LinearGradient;
  return [base.color, ...gradient.colors];
}

const _track = Track(
  id: 'lyrics-player-visual',
  title: '终生老友',
  artist: '张诗莉 / 朱彦安',
  album: '',
  duration: Duration(minutes: 3, seconds: 54),
  audioAsset: 'assets/audio/test.mp3',
  coverAsset: 'assets/images/theme_gallery/shinchan-avatar-v2.png',
  lyricsAsset: 'lyrics-player-visual.lrc',
);

const _lyrics = LyricsDocument(
  isSynced: true,
  lines: [
    LyricsLine(time: Duration.zero, text: '还因她不忍'),
    LyricsLine(time: Duration(seconds: 54), text: '两句赞美也很吸引'),
    LyricsLine(time: Duration(minutes: 1), text: '傻得很似我'),
  ],
);
