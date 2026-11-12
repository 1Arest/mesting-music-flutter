import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mesting_music/core/audio/mesting_audio_handler.dart';
import 'package:mesting_music/core/audio/playback_mode.dart';
import 'package:mesting_music/core/audio/playback_providers.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/core/platform/distribution_channel.dart';
import 'package:mesting_music/features/music_platform/default_playback_quality.dart';
import 'package:mesting_music/features/music_platform/domain/platform_audio_quality.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/music_platform/netease/messages/netease_unread.dart';
import 'package:mesting_music/features/settings/presentation/playback_preferences_page.dart';
import 'package:mesting_music/features/themes/app_theme.dart';
import 'package:mesting_music/features/themes/music_theme_preset.dart';
import 'package:mesting_music/shared/models/track.dart';
import 'package:mesting_music/shared/widgets/beta_glass_popover.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/personal_profile_fixture.dart';
import 'support/ui_fix_capture.dart';

ThemeData _theme(bool dark) {
  final theme = buildMestingTheme(
    musicThemePresetById(dark ? 'classic-dark' : 'classic'),
  );
  return uiFixCaptureDirectory.isEmpty
      ? theme
      : theme.copyWith(
          textTheme: theme.textTheme.apply(fontFamily: 'UiFixCJK'),
          listTileTheme: theme.listTileTheme.copyWith(
            titleTextStyle: theme.listTileTheme.titleTextStyle?.copyWith(
              fontFamily: 'UiFixCJK',
            ),
          ),
        );
}

class _SettingsHandler implements MestingAudioHandler {
  final _changes = StreamController<PlaybackOrder>.broadcast();
  PlaybackOrder order = const PlaybackOrder();

  @override
  PlaybackOrder get playbackOrder => order;

  @override
  Stream<PlaybackOrder> get playbackOrderStream async* {
    yield order;
    yield* _changes.stream;
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    order = order.copyWith(
      repeat: switch (repeatMode) {
        AudioServiceRepeatMode.one => PlaybackRepeat.one,
        AudioServiceRepeatMode.none => PlaybackRepeat.off,
        _ => PlaybackRepeat.all,
      },
    );
    _changes.add(order);
  }

  void close() => unawaited(_changes.close());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(() async {
    await LiquidGlassWidgets.initialize();
    await initializeUiFixCapture();
  });

  for (final spec in [
    (width: 320.0, height: 680.0, scale: 1.6, dark: false),
    (width: 390.0, height: 844.0, scale: 1.0, dark: true),
    (width: 820.0, height: 900.0, scale: 1.3, dark: false),
  ]) {
    testWidgets(
      'settings selectors open below and persist choices $spec',
      (tester) async {
        await tester.binding.setSurfaceSize(Size(spec.width, spec.height));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        SharedPreferences.setMockInitialValues({});
        final preferences = await SharedPreferences.getInstance();
        final handler = _SettingsHandler();
        final container = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(preferences),
            platformAccountProvider.overrideWith(SyntheticProfileAccount.new),
            audioHandlerProvider.overrideWithValue(handler),
          ],
        );
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox());
          container.dispose();
          handler.close();
        });
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: _theme(spec.dark),
              builder: (context, child) => RepaintBoundary(
                key: uiFixCaptureKey,
                child: MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    size: Size(spec.width, spec.height),
                    textScaler: TextScaler.linear(spec.scale),
                    disableAnimations: true,
                  ),
                  child: child!,
                ),
              ),
              home: const PlaybackPreferencesPage(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byType(DropdownButtonFormField<PlaybackRepeat>),
          findsNothing,
        );

        Future<Finder> open(String label) async {
          final trigger = find.byKey(ValueKey('playback-choice-$label'));
          await tester.ensureVisible(trigger);
          await tester.pumpAndSettle();
          await tester.tap(trigger);
          await tester.pumpAndSettle();
          final menu = find.byKey(const ValueKey('beta13-glass-menu-surface'));
          expect(menu, findsOneWidget);
          expect(
            tester.getRect(menu).top,
            greaterThanOrEqualTo(
              tester.getRect(trigger).bottom + betaMenuAnchorGap - .5,
            ),
          );
          expect(tester.getRect(menu).bottom, lessThanOrEqualTo(spec.height));
          expect(tester.takeException(), isNull);
          return menu;
        }

        await open('音乐平台');
        await tester.tap(find.text('网易云').last);
        await tester.pumpAndSettle();
        final qualityMenu = await open('默认音质');
        await captureUiFix(
          tester,
          '202-quality-below-${spec.width}-${spec.scale}',
        );
        final lastQuality = PlatformAudioQuality.vivid;
        final quality = find.descendant(
          of: qualityMenu,
          matching: find.text(lastQuality.label),
        );
        await tester.ensureVisible(quality);
        await tester.pumpAndSettle();
        await tester.tap(quality);
        await tester.pumpAndSettle();
        expect(
          container.read(defaultPlaybackQualityProvider)[TrackSource.netease],
          lastQuality.code,
        );

        final orderMenu = await open('循环方式');
        await captureUiFix(
          tester,
          '202-repeat-below-${spec.width}-${spec.scale}',
        );
        final repeat = find.descendant(
          of: orderMenu,
          matching: find.text(PlaybackRepeat.one.label),
        );
        await tester.ensureVisible(repeat);
        await tester.pumpAndSettle();
        await tester.tap(repeat);
        await tester.pumpAndSettle();
        expect(handler.playbackOrder.repeat, PlaybackRepeat.one);
        await open('循环方式');
        expect(find.byIcon(Icons.check_rounded), findsOneWidget);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
      skip: !DistributionChannel.isBeta,
    );
  }

  for (final dark in [false, true]) {
    for (final scale in [1.0, 1.6, 2.0]) {
      testWidgets('unread numbers remain centered dark=$dark scale=$scale', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(const Size(390, 260));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            theme: _theme(dark),
            home: MediaQuery(
              data: MediaQueryData(
                size: const Size(390, 260),
                textScaler: TextScaler.linear(scale),
              ),
              child: Scaffold(
                body: RepaintBoundary(
                  key: uiFixCaptureKey,
                  child: const Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        NeteaseUnreadBadge(0),
                        NeteaseUnreadBadge(1),
                        SizedBox(width: 16),
                        NeteaseUnreadBadge(12),
                        SizedBox(width: 16),
                        NeteaseUnreadBadge(101),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final badges = find.byKey(const ValueKey('netease-unread-badge'));
        expect(badges, findsNWidgets(3));
        for (var i = 0; i < 3; i++) {
          final badge = badges.at(i);
          final text = find.descendant(of: badge, matching: find.byType(Text));
          final label = tester.getRect(text);
          final background = tester.getRect(badge);
          expect(label.center.dy, closeTo(background.center.dy, .1));
          expect(label.center.dx, closeTo(background.center.dx, .1));
          expect(background.contains(label.topLeft), isTrue);
          expect(background.contains(label.bottomRight), isTrue);
        }
        expect(find.text('0'), findsNothing);
        expect(tester.takeException(), isNull);
        await captureUiFix(tester, '202-badge-$dark-$scale');
      });
    }
  }
}
