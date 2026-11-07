import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mesting_music/core/cache/browse_response_cache.dart';
import 'package:mesting_music/features/experience/presentation/editorial_widgets.dart';
import 'package:mesting_music/features/experience/presentation/music_landing_page.dart';
import 'package:mesting_music/features/history/listening_history_providers.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/music_platform/retained_kugou_scope.dart';
import 'package:mesting_music/features/music_platform/netease/netease_features_page.dart';
import 'package:mesting_music/features/music_platform/netease/netease_features_repository.dart';
import 'package:mesting_music/features/music_platform/platform_backend_providers.dart';
import 'package:mesting_music/features/music_platform/platform_catalog_providers.dart';
import 'package:mesting_music/features/music_platform/platform_explore_providers.dart';
import 'package:mesting_music/features/music_platform/platform_recommendation_providers.dart';
import 'package:mesting_music/features/music_platform/presentation/retained_platform_snapshot.dart';
import 'package:mesting_music/features/search/data/hot_music_repository.dart';
import 'package:mesting_music/features/search/search_providers.dart';
import 'package:mesting_music/shared/models/track.dart';
import 'package:mesting_music/shared/widgets/music_refresh_indicator.dart';

import 'support/personal_profile_fixture.dart';

class _Account extends PlatformAccountController {
  @override
  Future<PlatformSession?> build() async =>
      const PlatformSession(userId: 'first', token: 'first-token');
  void change() => state = const AsyncData(
    PlatformSession(userId: 'second', token: 'second-token'),
  );
}

class _Hot extends HotMusicController {
  @override
  Future<HotMusicSnapshot> build() async => HotMusicSnapshot(
    tracks: const [],
    updatedAt: DateTime(2026),
    sourceLabel: 'synthetic',
  );
}

Track _track(String title) => Track(
  id: 'netease_17',
  title: title,
  artist: '合成歌手',
  album: '合成专辑',
  duration: const Duration(minutes: 4),
  audioAsset: '',
  coverAsset: profileFixtureCover,
  lyricsAsset: '',
  source: TrackSource.netease,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(LiquidGlassWidgets.initialize);

  for (final netease in [true, false]) {
    testWidgets(
      'production ${netease ? 'NetEase' : 'Kugou'} discovery keeps old rows during a slow pull refresh',
      (tester) async {
        Completer<List<Track>>? pending;
        var dailyCalls = 0;
        final fixture = (await tester.runAsync(
          () => PersonalProfileFixture.create(
            extraOverrides: [
              usesNeteaseProvider.overrideWithValue(netease),
              savedKugouSessionProvider.overrideWith((ref) async => null),
              platformDailyProvider.overrideWith((ref) async {
                dailyCalls++;
                return pending?.future ?? [_track('old-song')];
              }),
              platformNewSongsProvider.overrideWith((ref) async => []),
              platformDiscoveryProvider.overrideWith((ref) async => []),
              platformFeaturedProvider.overrideWith((ref) async => []),
              platformFmProvider.overrideWith((ref) async => []),
              platformExploreProvider.overrideWith((ref, kind) async => []),
              neteaseFeedPreviewProvider.overrideWith(
                (ref, feed) async => const NeteaseBatch([]),
              ),
              hotMusicControllerProvider.overrideWith(_Hot.new),
              recentPlaybackProvider.overrideWith((ref) => Stream.value([])),
            ],
          ),
        ))!;
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: fixture.container,
            child: const MaterialApp(home: Scaffold(body: MusicLandingPage())),
          ),
        );
        for (var i = 0; i < 12; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        final repository = fixture.container.read(
          neteaseMusicRepositoryProvider,
        );
        // Both platforms now present daily recommendations as a cover card;
        // inspect its actual track snapshot rather than an obsolete song row.
        Finder song(String title) => find.byWidgetPredicate(
          (widget) => widget is EditorialCover && widget.track?.title == title,
        );
        expect(song('old-song'), findsOneWidget);
        pending = Completer<List<Track>>();
        final refresh = tester
            .widget<MusicRefreshIndicator>(
              find.byType(MusicRefreshIndicator).first,
            )
            .onRefresh();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 150));
        expect(dailyCalls, 2);
        expect(song('old-song'), findsOneWidget);
        expect(song('fresh-song'), findsNothing);
        expect(
          fixture.container.read(neteaseMusicRepositoryProvider),
          same(repository),
        );
        pending.complete([_track('fresh-song')]);
        await tester.pump();
        await refresh;
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(song('old-song'), findsNothing);
        expect(song('fresh-song'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(fixture.dispose);
      },
    );
  }

  testWidgets(
    'a refresh failure retains data but an account switch strips previous values',
    (tester) async {
      final container = ProviderContainer(
        overrides: [platformAccountProvider.overrideWith(_Account.new)],
      );
      await container.read(platformAccountProvider.future);
      Completer<String>? pending;
      final content = FutureProvider<String>((ref) async {
        final owner = ref.watch(platformAccountProvider).value?.userId;
        return pending?.future ?? '$owner-owner-content';
      }, retry: (_, _) => null);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) {
                return RetainedPlatformSnapshot(
                  value: ref.watch(content),
                  loading: () => const Text('loading-current-owner'),
                  error: (_, _) => const Text('current-owner-error'),
                  data: Text.new,
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('first-owner-content'), findsOneWidget);
      pending = Completer<String>();
      container.invalidate(content);
      await tester.pump();
      expect(find.text('first-owner-content'), findsOneWidget);
      final failed = expectLater(
        container.read(content.future),
        throwsStateError,
      );
      pending.completeError(StateError('offline'));
      await tester.pump();
      await failed;
      await tester.pump();
      expect(find.text('first-owner-content'), findsOneWidget);
      pending = Completer<String>();
      (container.read(platformAccountProvider.notifier) as _Account).change();
      await tester.pump();
      expect(find.text('first-owner-content'), findsNothing);
      expect(find.text('loading-current-owner'), findsOneWidget);
      final secondFailed = expectLater(
        container.read(content.future),
        throwsStateError,
      );
      pending.completeError(StateError('second account offline'));
      await tester.pump();
      await secondFailed;
      await tester.pump();
      expect(find.text('current-owner-error'), findsOneWidget);
      pending = null;
      container.invalidate(content);
      await tester.pump();
      await tester.pump();
      expect(find.text('second-owner-content'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      container.dispose();
    },
  );

  for (final outcome in ['ready', 'image failed', 'network failed']) {
    test(
      'refresh completion waits for the cached network/cover transaction: $outcome',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'mesting-144-refresh-',
        );
        final cache = BrowseResponseCache(
          directory: () async => directory,
          initializeOnRead: true,
        );
        final watch = BrowseCacheWatch(() {});
        var fresh = false;
        final response = Completer<BrowseJson>();
        final prepare = Completer<bool>();
        final preparing = Completer<void>();
        cache.prepareRefresh = (_, _) {
          preparing.complete();
          return prepare.future;
        };
        Future<BrowseJson> read() => watch.run(
          () => cache.read(
            scope: 'netease:synthetic',
            route: '/recommend/songs',
            query: const {},
            checkCurrent: () {},
            load: () async => fresh ? response.future : {'title': 'old'},
          ),
        );
        expect((await read())['title'], 'old');
        fresh = true;
        cache.revalidateScope('netease:synthetic');
        expect((await read())['title'], 'old');
        var settled = false;
        final completion = cache
            .settleRefreshes('netease:synthetic')
            .then((_) => settled = true);
        await Future<void>.delayed(Duration.zero);
        expect(settled, false);
        if (outcome == 'network failed') {
          response.completeError(StateError('synthetic offline'));
        } else {
          response.complete({'title': 'fresh'});
          await preparing.future;
          expect(settled, false);
          expect((await BrowseResponseCache.restoreOnly(read))['title'], 'old');
          prepare.complete(outcome == 'ready');
        }
        await completion;
        expect(
          (await BrowseResponseCache.restoreOnly(read))['title'],
          outcome == 'ready' ? 'fresh' : 'old',
        );
        watch.dispose();
        await directory.delete(recursive: true);
      },
    );
  }
}
