import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mesting_music/app/router/app_router.dart' as production;
import 'package:mesting_music/app/system_back_coordinator.dart';
import 'package:mesting_music/core/audio/mesting_audio_handler.dart';
import 'package:mesting_music/core/audio/playback_mode.dart';
import 'package:mesting_music/core/audio/playback_providers.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/core/platform/distribution_channel.dart';
import 'package:mesting_music/features/auth/auth_providers.dart';
import 'package:mesting_music/features/library/library_providers.dart';
import 'package:mesting_music/features/lyrics/domain/lyrics_document.dart';
import 'package:mesting_music/features/lyrics/lyrics_providers.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/music_platform/platform_rewards_provider.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_api.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_lyrics_back_scope.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_lyrics_page.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_now_playing.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_pages.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_playback_progress.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_player_navigation.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_providers.dart';
import 'package:mesting_music/shared/models/track.dart';
import 'package:mesting_music/shared/widgets/beta_content_insets.dart';

import 'qishui_appearance172_ui_test.dart'
    show AuditAuth172, AuditLibrary172, AuditMusic172;
import 'qishui_protocol_test.dart' show fixtureJson, sodaSession;
import 'qishui_ui168_test.dart' show song168;
import 'qishui_ui_test.dart' show FixtureAccount;
import 'support/release_152_qa.dart' show theme152;

/// Metadata intentionally says three minutes while the player exposes a
/// one-minute preview. UI tests must never confuse these independent facts.
class _Timeline173 {
  const _Timeline173({
    required this.track,
    this.duration = const Duration(minutes: 1),
    this.position = const Duration(seconds: 15),
    this.processing = AudioProcessingState.ready,
  });

  final Track track;
  final Duration? duration;
  final Duration position;
  final AudioProcessingState processing;
}

final _timeline173 = NotifierProvider<_TimelineController173, _Timeline173>(
  _TimelineController173.new,
);

class _TimelineController173 extends Notifier<_Timeline173> {
  @override
  _Timeline173 build() =>
      _Timeline173(track: song168.copyWith(isPreview: true));
  void set(_Timeline173 value) => state = value;
}

class _Seeker173 extends Fake implements MestingAudioHandler {
  final seeks = <Duration>[];
  Completer<void>? seekGate;
  int toggles = 0;

  @override
  Future<void> seek(Duration position, {bool Function()? togetherGuard}) async {
    await seekGate?.future;
    if (togetherGuard?.call() != false) seeks.add(position);
  }

  @override
  Future<void> togglePlayPause() async => toggles++;
}

Future<void> _settle173(WidgetTester tester) async {
  // Glass, retained tab motion and local-history registration schedule several
  // frames. Bounded pumping also works when a legitimate title is marqueeing.
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

void main() {
  setUpAll(LiquidGlassWidgets.initialize);

  Future<(ProviderContainer, _Seeker173)> fixture(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final api = QishuiApi(MockClient((_) async => fixtureJson({})))
      ..configure(sodaSession());
    final seeker = _Seeker173();
    final c = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        platformAccountProvider.overrideWith(FixtureAccount.new),
        authControllerProvider.overrideWith(AuditAuth172.new),
        qishuiNavigationProvider.overrideWithValue(true),
        qishuiApiProvider.overrideWithValue(api),
        qishuiRepositoryProvider.overrideWithValue(AuditMusic172(api)),
        platformRewardAutomationProvider.overrideWith((_) {}),
        audioHandlerProvider.overrideWithValue(seeker),
        libraryRepositoryProvider.overrideWithValue(AuditLibrary172()),
        favoriteTrackIdsProvider.overrideWithValue(<String>{}),
        currentTrackProvider.overrideWith(
          (ref) => ref.watch(_timeline173).track,
        ),
        currentMediaItemProvider.overrideWith(
          (ref) => Stream.value(ref.watch(_timeline173).track.toMediaItem()),
        ),
        durationProvider.overrideWith(
          (ref) => Stream.value(ref.watch(_timeline173).duration),
        ),
        positionProvider.overrideWith(
          (ref) => Stream.value(ref.watch(_timeline173).position),
        ),
        playbackStateProvider.overrideWith(
          (ref) => Stream.value(
            PlaybackState(processingState: ref.watch(_timeline173).processing),
          ),
        ),
        playbackModeProvider.overrideWith(
          (_) => Stream.value(PlaybackMode.list),
        ),
        upcomingQueueProvider.overrideWith((_) => Stream.value([])),
        playbackOrderProvider.overrideWith(
          (_) => Stream.value(const PlaybackOrder()),
        ),
        lyricsProvider.overrideWith(
          (_, _) async => LyricsDocument(
            isSynced: true,
            lines: [
              const LyricsLine(time: Duration.zero, text: '只读界面测试歌词'),
              const LyricsLine(
                time: Duration(seconds: 10),
                text: '保持选句预览，只有明确的播放操作才跳转',
              ),
            ],
          ),
        ),
      ],
    );
    await c.read(platformAccountProvider.future);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      api.dispose();
    });
    return (c, seeker);
  }

  Future<void> mountProgress(
    WidgetTester tester,
    ProviderContainer c, {
    Widget child = const QishuiPlaybackProgress(),
    Size size = const Size(390, 844),
    double scale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: theme152(false),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            body: BetaContentInsets(bottom: 104, child: Center(child: child)),
          ),
        ),
      ),
    );
    await _settle173(tester);
  }

  Slider slider(WidgetTester tester) =>
      tester.widget(find.byKey(const ValueKey('qishui-playback-slider')));

  testWidgets('preview progress uses media length and seeks only on release', (
    tester,
  ) async {
    final (c, seeker) = await fixture(tester);
    await mountProgress(tester, c);
    expect(slider(tester).max, 60000);
    expect(find.text('1:00'), findsOneWidget);
    expect(find.text('3:00'), findsNothing);
    slider(tester).onChangeStart!(45000);
    slider(tester).onChanged!(45000);
    await tester.pump();
    expect(seeker.seeks, isEmpty);
    expect(find.text('0:45'), findsOneWidget);
    slider(tester).onChangeEnd!(45000);
    await tester.pump();
    expect(seeker.seeks, [const Duration(seconds: 45)]);
  });

  testWidgets(
    'unknown media duration disables seeking despite catalog length',
    (tester) async {
      final (c, seeker) = await fixture(tester);
      c
          .read(_timeline173.notifier)
          .set(_Timeline173(track: song168, duration: null));
      await mountProgress(tester, c);
      expect(slider(tester).onChanged, isNull);
      expect(slider(tester).value, 0);
      expect(find.text('--:--'), findsOneWidget);
      expect(seeker.seeks, isEmpty);
    },
  );

  testWidgets('new track cancels old drag and delayed seek', (tester) async {
    final (c, seeker) = await fixture(tester);
    await mountProgress(tester, c);
    slider(tester).onChangeStart!(45000);
    slider(tester).onChanged!(45000);
    seeker.seekGate = Completer<void>();
    slider(tester).onChangeEnd!(45000);
    await tester.pump();
    c
        .read(_timeline173.notifier)
        .set(
          _Timeline173(
            track: Track(
              id: 'qishui_new-recording',
              platformSongId: 'new-recording',
              title: '另一首界面歌曲',
              artist: song168.artist,
              album: song168.album,
              duration: song168.duration,
              audioAsset: 'mesting-platform://qishui/new-recording',
              coverAsset: song168.coverAsset,
              lyricsAsset: '',
              source: TrackSource.qishui,
            ),
            position: const Duration(seconds: 5),
          ),
        );
    await _settle173(tester);
    seeker.seekGate!.complete();
    await tester.pump();
    expect(seeker.seeks, isEmpty);
    expect(slider(tester).value, 5000);
    expect(find.text('0:45'), findsNothing);
  });

  testWidgets('loading cannot seek and position is clamped to actual media', (
    tester,
  ) async {
    final (c, _) = await fixture(tester);
    c
        .read(_timeline173.notifier)
        .set(
          _Timeline173(
            track: song168,
            position: const Duration(minutes: 2),
            processing: AudioProcessingState.loading,
          ),
        );
    await mountProgress(tester, c);
    expect(slider(tester).value, 60000);
    expect(slider(tester).onChanged, isNull);
  });

  for (final surface in ['cover', 'lyrics']) {
    testWidgets('$surface progress remains usable at 320px with large text', (
      tester,
    ) async {
      final (c, _) = await fixture(tester);
      await mountProgress(
        tester,
        c,
        size: const Size(320, 700),
        scale: 1.8,
        child: surface == 'cover'
            ? const SingleChildScrollView(child: QishuiNowPlaying())
            : const QishuiLyricsPage(),
      );
      expect(find.byType(QishuiPlaybackProgress), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (surface == 'lyrics') {
        final share = tester.getCenter(find.byIcon(Icons.ios_share_rounded));
        final queue = tester.getCenter(find.byIcon(Icons.queue_music_rounded));
        final favorite = tester.getCenter(
          find.byKey(ValueKey('favorite-button-${song168.id}')),
        );
        expect(share.dy, closeTo(queue.dy, 1));
        expect(favorite.dy, closeTo(queue.dy, 1));
        expect(favorite.dx - share.dx, closeTo(queue.dx - favorite.dx, 1));
      }
    });
  }

  for (final direction in ['system', 'left', 'right']) {
    testWidgets(
      'production router advertises lyrics and both search entries to Android: $direction',
      (tester) async {
        final (c, _) = await fixture(tester);
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        bool? handlesBack;
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(SystemChannels.platform, (
          call,
        ) async {
          if (call.method == 'SystemNavigator.setFrameworkHandlesBack') {
            handlesBack = call.arguments as bool;
          }
          return null;
        });
        addTearDown(
          () =>
              messenger.setMockMethodCallHandler(SystemChannels.platform, null),
        );
        production.appRouter.go('/music');
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: c,
            child: MaterialApp.router(
              theme: theme152(false),
              routerConfig: production.appRouter,
              builder: (_, child) => SystemBackCoordinator(
                canPop: production.appRouter.canPop,
                navigationChanges: production.appRouter.routerDelegate,
                child: child!,
              ),
            ),
          ),
        );
        await _settle173(tester);
        expect(handlesBack, isFalse);

        Future<void> back() async {
          tester.testTextInput.hide();
          if (direction == 'system') {
            await tester.binding.handlePopRoute();
          } else {
            await tester.dragFrom(
              Offset(direction == 'left' ? 3 : 387, 300),
              Offset(direction == 'left' ? 150 : -150, 0),
            );
          }
          await _settle173(tester);
        }

        // The title search belongs to a retained branch Navigator.
        await tester.tap(find.byTooltip('搜索汽水音乐').hitTestable().last);
        await _settle173(tester);
        expect(find.byType(QishuiSearchPage), findsOneWidget);
        expect(handlesBack, isTrue);
        await back();
        expect(find.byType(QishuiSearchPage), findsNothing);
        expect(handlesBack, isFalse);

        // Lyrics have no second player route, but must have a native target.
        await tester.tap(find.byKey(const ValueKey('qishui-music-cover')));
        await _settle173(tester);
        expect(handlesBack, isTrue);
        expect(production.appRouter.canPop(), isTrue);
        await back();
        expect(c.read(qishuiMusicLyricsProvider), isFalse);
        expect(handlesBack, isFalse);

        // Bottom search is owned by the outer shell, not the branch above.
        await tester.tap(find.byIcon(CupertinoIcons.search).hitTestable().last);
        await _settle173(tester);
        expect(find.byType(QishuiSearchPage), findsOneWidget);
        expect(handlesBack, isTrue);
        await back();
        expect(find.byType(QishuiSearchPage), findsNothing);
        expect(handlesBack, isFalse);

        // A retained hidden music tab must not advertise Back on another root.
        await tester.tap(find.byKey(const ValueKey('qishui-music-cover')));
        await _settle173(tester);
        production.appRouter.go('/music/recommend');
        await _settle173(tester);
        final hidden = find.byType(QishuiLyricsBackScope, skipOffstage: false);
        if (hidden.evaluate().isNotEmpty) {
          const NavigationNotification(
            canHandlePop: true,
          ).dispatch(tester.element(hidden.first));
        }
        await _settle173(tester);
        expect(handlesBack, isFalse);
        expect(tester.takeException(), isNull);
      },
      skip: !DistributionChannel.isBeta,
    );
  }
}
