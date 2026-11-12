import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';

import 'package:http/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mesting_music/core/audio/mesting_audio_handler.dart';
import 'package:mesting_music/core/audio/playback_providers.dart';
import 'package:mesting_music/features/library/library_providers.dart';
import 'package:mesting_music/features/music_platform/data/embedded_music_server.dart';
import 'package:mesting_music/features/music_platform/data/music_platform_api.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/music_platform/source_media_scope.dart';
import 'package:mesting_music/features/search/presentation/apple_search_results.dart';
import 'package:mesting_music/features/search/search_providers.dart';
import 'package:mesting_music/shared/models/track.dart';

import 'support/deterministic_audio_player.dart';

Track song(String id, TrackSource source) => Track(
  id: id,
  source: source,
  title: '天龙八部之宿敌',
  artist: '许嵩',
  album: '',
  duration: const Duration(minutes: 4),
  audioAsset: 'mesting-platform://${source.name}/$id',
  coverAsset: '',
  lyricsAsset: '',
);
final n = song('netease_fixture', TrackSource.netease);
final k = song('kugou_fixture', TrackSource.kugou);

class _Account extends PlatformAccountController {
  @override
  Future<PlatformSession?> build() async => const PlatformSession(
    userId: 'fixture',
    token: 'synthetic-owner',
    platform: MusicPlatform.netease,
  );
  void change() => state = const AsyncData(
    PlatformSession(
      userId: 'other',
      token: 'synthetic-other',
      platform: MusicPlatform.netease,
    ),
  );
}

class _Search extends MusicSearchController {
  @override
  MusicSearchState build() => MusicSearchState(
    query: n.title,
    onlineTracks: [n],
    sourceChoices: {
      n.id: [n, k],
      k.id: [n, k],
    },
  );
  void changeQuery() => state = state.copyWith(query: 'new query');
}

class _Server implements MusicServer {
  @override
  Future<Uri> start() async => throw StateError('no network in this fixture');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(LiquidGlassWidgets.initialize);
  for (final action in [
    'replace row',
    'change query',
    'change account',
    'leave page',
  ]) {
    testWidgets('folded source playback survives only $action', (tester) async {
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('source-owner-'),
      ))!;
      addTearDown(() => directory.delete(recursive: true));
      const paths = MethodChannel('plugins.flutter.io/path_provider');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(paths, (_) async => directory.path);
      addTearDown(() => messenger.setMockMethodCallHandler(paths, null));
      SharedPreferences.setMockInitialValues({});
      final preferences = (await tester.runAsync(
        SharedPreferences.getInstance,
      ))!;
      late DeterministicAudioPlayer player;
      final handler = (await tester.runAsync(() async {
        player = DeterministicAudioPlayer();
        final handler = MestingAudioHandler(tracks: [], player: player);
        await handler.replaceQueue([], autoplay: false);
        return handler;
      }))!;
      addTearDown(() => tester.runAsync(handler.debugDispose));
      final entered = Completer<void>(), lookup = Completer<Track>();
      addTearDown(() {
        if (!lookup.isCompleted) {
          lookup.complete(k.copyWith(audioAsset: 'assets/fixture.mp3'));
        }
      });
      handler.configureTrackPlaybackResolver((_) {
        entered.complete();
        return lookup.future;
      });
      final controller = ScrollController();
      addTearDown(controller.dispose);
      final api =
          MusicPlatformApi(
              server: _Server(),
              client: MockClient((_) async => http.Response('{}', 200)),
            )
            ..session = const PlatformSession(
              userId: 'retained-kugou',
              token: 'synthetic-retained',
              platform: MusicPlatform.kugou,
            );
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          musicPlatformApiProvider.overrideWithValue(api),
          platformAccountProvider.overrideWith(_Account.new),
          musicSearchControllerProvider.overrideWith(_Search.new),
          audioHandlerProvider.overrideWithValue(handler),
          favoriteTrackIdsProvider.overrideWithValue(const {}),
          sourceMediaScopeProvider(TrackSource.kugou).overrideWith(
            (_) async => SourceMediaScope(
              source: TrackSource.kugou,
              api: api,
              isCurrent: () => true,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.read(platformAccountProvider);
      await tester.pump();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) => AppleSearchResults(
                  state: ref.watch(musicSearchControllerProvider),
                  controller: controller,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final oldRow = tester.element(find.byKey(ValueKey(n.id)));
      await tester.tap(find.byTooltip('选择音源（2）'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('酷狗'));
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pumpAndSettle();
      expect(
        container.read(musicSearchControllerProvider).onlineTracks.single.id,
        k.id,
      );
      expect(entered.isCompleted, isTrue);
      expect(
        oldRow.mounted,
        isFalse,
      ); // The critical real keyed-row replacement.
      final loads = player.loads;
      if (action == 'change query') {
        (container.read(musicSearchControllerProvider.notifier) as _Search)
            .changeQuery();
      } else if (action == 'change account') {
        (container.read(platformAccountProvider.notifier) as _Account).change();
      } else if (action == 'leave page') {
        await tester.pumpWidget(const SizedBox());
      }
      await tester.runAsync(() async {
        lookup.complete(k.copyWith(audioAsset: 'assets/fixture.mp3'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(player.active, action == 'replace row');
      expect(player.loads, loads + (action == 'replace row' ? 1 : 0));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
