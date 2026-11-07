import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesting_music/core/audio/audio_output_controller.dart';
import 'package:mesting_music/core/audio/media_volume_controller.dart';
import 'package:mesting_music/core/audio/playback_mode.dart';
import 'package:mesting_music/core/audio/playback_providers.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/features/experience/presentation/player_output_dialog.dart';
import 'package:mesting_music/features/experience/presentation/player_toolbar_glyphs.dart';
import 'package:mesting_music/features/music_platform/domain/platform_rewards.dart';
import 'package:mesting_music/features/music_platform/platform_rewards_provider.dart';
import 'package:mesting_music/features/music_platform/presentation/platform_reward_calendar.dart';
import 'package:mesting_music/features/themes/app_theme.dart';
import 'package:mesting_music/features/themes/music_theme_preset.dart';
import 'package:mesting_music/shared/models/track.dart';

const _export = bool.fromEnvironment('EXPORT_BETA_SCREENSHOTS');

class _Calendar extends PlatformRewardsController {
  @override
  PlatformRewardState build() => PlatformRewardState(
    ownerId: 'fixture',
    snapshot: RewardSnapshot(
      now: DateTime(2026, 10, 26, 18),
      signedDates: {'2026-10-25', '2026-10-26'},
      memberships: [
        VipEntitlement(
          type: 'tvip',
          active: true,
          expires: DateTime(2027, 9, 22),
        ),
        VipEntitlement(
          type: 'svip',
          active: true,
          expires: DateTime(2026, 10, 27, 14, 21),
        ),
      ],
    ),
  );
  @override
  Future<void> refresh() async {}
  @override
  Future<void> setAutoSignIn(bool enabled) async {
    state = state.copyWith(autoSignIn: enabled);
  }
}

class _Output extends AudioOutputController {
  @override
  AudioOutput build() =>
      const AudioOutput(name: 'vivo TWS 5', headphones: true, available: true);
}

class _Volume extends MediaVolumeController {
  @override
  MediaVolumeState build() =>
      const MediaVolumeState(value: .42, available: true);
  @override
  Future<void> setVolume(double value) async {
    state = MediaVolumeState(value: value, available: true);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await LiquidGlassWidgets.initialize();
    if (!_export) return;
    final bytes = await File('C:/Windows/Fonts/msyh.ttc').readAsBytes();
    for (final family in [
      'Beta17QA',
      'Roboto',
      'CupertinoSystemText',
      'CupertinoSystemDisplay',
    ]) {
      await (FontLoader(
        family,
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    }
    await (FontLoader('MaterialIcons')..addFont(
          File.fromUri(
            File(
              Platform.resolvedExecutable,
            ).uri.resolve('../../material_fonts/MaterialIcons-Regular.otf'),
          ).readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
        ))
        .load();
    await (FontLoader('packages/cupertino_icons/CupertinoIcons')..addFont(
          rootBundle.load('packages/cupertino_icons/assets/CupertinoIcons.ttf'),
        ))
        .load();
  });
  late SharedPreferences preferences;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
  });

  Future<void> capture(WidgetTester tester, String name) async {
    if (!_export) return;
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('beta17-capture')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      final directory = Directory(
        const String.fromEnvironment('BETA_SCREENSHOT_DIR'),
      );
      await directory.create(recursive: true);
      await File(
        '${directory.path}/$name.png',
      ).writeAsBytes(png!.buffer.asUint8List());
      image.dispose();
    });
  }

  Future<void> pump(
    WidgetTester tester,
    Widget page, {
    bool dark = false,
    double scale = 1,
    Size size = const Size(390, 844),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    var theme = buildMestingTheme(
      musicThemePresetById(dark ? 'classic-dark' : 'classic'),
    );
    if (_export) {
      theme = theme.copyWith(
        textTheme: theme.textTheme.apply(fontFamily: 'Beta17QA'),
        listTileTheme: theme.listTileTheme.copyWith(
          subtitleTextStyle:
              (theme.listTileTheme.subtitleTextStyle ?? const TextStyle())
                  .copyWith(fontFamily: 'Beta17QA'),
        ),
      );
    }
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          platformRewardsProvider.overrideWith(_Calendar.new),
          audioOutputProvider.overrideWith(_Output.new),
          mediaVolumeProvider.overrideWith(_Volume.new),
          currentTrackProvider.overrideWithValue(
            const Track(
              id: 'fixture',
              title: '测试歌曲',
              artist: '测试歌手',
              album: '',
              audioAsset: '',
              coverAsset: '',
              lyricsAsset: '',
              duration: Duration(minutes: 3),
            ),
          ),
        ],
        child: RepaintBoundary(
          key: const ValueKey('beta17-capture'),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: theme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: page,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final variant in [
    (name: 'light', dark: false, scale: 1.0, size: const Size(390, 844)),
    (name: 'dark', dark: true, scale: 1.0, size: const Size(390, 844)),
    (name: 'large', dark: false, scale: 1.6, size: const Size(320, 640)),
    (name: 'landscape', dark: true, scale: 1.0, size: const Size(844, 390)),
  ]) {
    testWidgets('calendar and membership stay reachable: ${variant.name}', (
      tester,
    ) async {
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await pump(
        tester,
        const PlatformRewardCalendar(),
        dark: variant.dark,
        scale: variant.scale,
        size: variant.size,
      );
      expect(find.text('2026 年 10 月'), findsOneWidget);
      expect(find.byKey(const ValueKey('reward-day-31')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await capture(tester, 'calendar-${variant.name}');
      await tester.ensureVisible(find.text('会员到期时间'));
      await tester.pumpAndSettle();
      await capture(tester, 'calendar-${variant.name}-membership');
      await tester.ensureVisible(
        find.byKey(const ValueKey('reward-auto-sign-in')),
      );
      await tester.pumpAndSettle();
      final control = tester.widget<CupertinoSwitch>(
        find.byKey(const ValueKey('reward-auto-sign-in')),
      );
      expect(control.value, true);
      await tester.tap(find.byKey(const ValueKey('reward-auto-sign-in')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CupertinoSwitch>(
              find.byKey(const ValueKey('reward-auto-sign-in')),
            )
            .value,
        false,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
    testWidgets('glass device card fits: ${variant.name}', (tester) async {
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await pump(
        tester,
        const Scaffold(
          body: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF23485F),
                  Color(0xFF54565D),
                  Color(0xFF101A25),
                ],
              ),
            ),
            child: Center(child: PlayerOutputDialog()),
          ),
        ),
        dark: variant.dark,
        scale: variant.scale,
        size: variant.size,
      );
      expect(find.text('vivo TWS 5'), findsOneWidget);
      await capture(tester, 'output-${variant.name}');
      await tester.ensureVisible(
        find.byKey(const ValueKey('output-open-system-picker')),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  testWidgets(
    'queue badge distinguishes sequential, repeat, one and shuffle priorities',
    (tester) async {
      final orders = [
        const PlaybackOrder(repeat: PlaybackRepeat.off),
        const PlaybackOrder(),
        const PlaybackOrder(repeat: PlaybackRepeat.one),
        const PlaybackOrder(shuffle: true),
        const PlaybackOrder(shuffle: true, repeat: PlaybackRepeat.one),
      ];
      final images = <List<int>>[];
      for (var index = 0; index < orders.length; index++) {
        await pump(
          tester,
          Scaffold(
            backgroundColor: const Color(0xFF132E45),
            body: Center(
              child: PlayerToolbarGlyph(
                tool: PlayerToolbarTool.queue,
                order: orders[index],
              ),
            ),
          ),
        );
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('beta17-capture')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          images.add((await image.toByteData())!.buffer.asUint8List());
          image.dispose();
        });
      }
      expect(images[0], isNot(orderedEquals(images[1])));
      expect(images[1], isNot(orderedEquals(images[2])));
      expect(images[2], isNot(orderedEquals(images[3])));
      expect(images[4], orderedEquals(images[2]));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
