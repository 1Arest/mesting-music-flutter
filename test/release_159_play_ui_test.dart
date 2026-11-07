// This historical fixture covers NetEase/Kugou; Soda is covered by qishui_* tests.
import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/core/audio/mesting_audio_handler.dart';
import 'package:mesting_music/features/experience/presentation/editorial_widgets.dart';
import 'package:mesting_music/features/experience/presentation/music_discovery_sections.dart';
import 'package:mesting_music/features/music_platform/data/platform_explore.dart';
import 'package:mesting_music/features/music_platform/data/platform_recommendations.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/music_platform/netease/netease_features_page.dart';
import 'package:mesting_music/features/music_platform/netease/netease_features_repository.dart';
import 'package:mesting_music/features/music_platform/platform_catalog_providers.dart';
import 'package:mesting_music/features/music_platform/platform_recommendation_providers.dart';
import 'package:mesting_music/features/music_platform/presentation/platform_collection_play.dart';
import 'package:mesting_music/features/music_platform/presentation/platform_mode_play.dart';
import 'package:mesting_music/features/music_platform/presentation/platform_search_landing.dart';
import 'package:mesting_music/shared/models/track.dart';
import 'package:mesting_music/shared/models/track_page.dart';
import 'package:mesting_music/shared/widgets/beta_page_route_observer.dart';
import 'package:mesting_music/shared/widgets/beta_root_tab_viewport.dart';
import 'support/personal_profile_fixture.dart';
import 'support/release_152_qa.dart';
import 'release_146_ui_test.dart' show ready146;
import 'release_148_data_test.dart' show Metadata148;
import 'release_157_ranking_test.dart' show api157, reply157, rank157, song157;
import 'release_158_collections_test.dart' show playlist158;

class _Account extends PlatformAccountController {
  _Account(this.platform);
  final MusicPlatform platform;
  @override
  Future<PlatformSession?> build() async => PlatformSession(
    userId: '7001',
    token: 'fixture-only',
    platform: platform,
  );
  void select(String id) => state = AsyncData(
    PlatformSession(userId: id, token: 'fixture-only', platform: platform),
  );
}

class _Queue extends Fake implements MestingAudioHandler {
  List<Track> received = [];
  List<MediaItem> pending = [];
  @override
  List<MediaItem> get manuallyQueuedItems => pending;
  @override
  Future<void> replaceQueue(
    List<Track> tracks, {
    int initialIndex = 0,
    Duration initialPosition = Duration.zero,
    bool autoplay = true,
    bool recommendationContext = false,
    bool Function()? togetherGuard,
  }) async => received = tracks;
  @override
  Future<void> playSingleTrack(
    Track track, {
    bool autoplay = true,
    bool fromHistory = false,
    Iterable<Track>? playbackContext,
    bool preservePendingAdvance = false,
    Track? returnToUpcoming,
    bool replaceUpcoming = false,
    bool discardRecommendations = false,
    bool Function()? isCurrent,
  }) async => received = [track];
}

class _Radio extends Fake implements PlatformRecommendationSession {
  Track? adopted;
  PlatformRecommendationKind? source;
  @override
  void adoptCurrent(PlatformRecommendationKind kind, Track track) {
    source = kind;
    adopted = track;
  }
}

class _Heart extends NeteaseFeaturesRepository {
  _Heart(this.tracks) : super(Metadata148((_, _) async => {}));
  final List<Track> tracks;
  int loads = 0;
  @override
  Future<NeteaseBatch> load(
    NeteaseFeed feed, {
    int page = 1,
    String id = '',
    String category = '全部',
    String area = 'ALL',
    int artistArea = 1,
    int before = 0,
  }) async {
    expect(feed, NeteaseFeed.intelligence);
    loads++;
    return NeteaseBatch([
      for (final track in tracks)
        NeteaseItem(
          id: track.id,
          name: track.title,
          kind: NeteaseEntity.song,
          track: track,
        ),
    ]);
  }
}

class _Pages extends PlatformExploreRepository {
  _Pages() : super(api157((_) async => reply157({'status': 1, 'data': {}})));
  @override
  Future<TrackPage> tracksPage(
    PlatformExploreItem item, {
    int offset = 0,
    int limit = 30,
  }) async {
    final end = (offset + 30).clamp(0, 77);
    return TrackPage(
      [
        for (var i = offset; i < end; i++)
          song157(i).copyWith(coverAsset: profileFixtureCover),
      ],
      offset: offset,
      nextOffset: end,
      total: 77,
      hasMore: end < 77,
    );
  }
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Widget _host(
  PersonalProfileFixture fixture,
  Widget child, {
  BetaPageRouteObserver? observer,
}) => UncontrolledProviderScope(
  container: fixture.container,
  child: MaterialApp(
    navigatorObservers: [?observer],
    home: Scaffold(body: child),
  ),
);

void main() {
  setUpAll(initialize151QA);
  testWidgets(
    '36dp visible lens retains a tappable 48dp margin and cancels drag',
    (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: PlatformCoverPlayControl(
                key: const ValueKey('lens'),
                label: '播放样本',
                onPressed: () => taps++,
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      final rect = tester.getRect(find.byKey(const ValueKey('lens')));
      expect(rect.size, const Size(48, 48));
      final transform = tester.widget<Transform>(
        find
            .descendant(
              of: find.byKey(const ValueKey('lens')),
              matching: find.byType(Transform),
            )
            .first,
      );
      expect(transform.transformHitTests, isFalse);
      expect(transform.transform.storage[0], .75);
      await tester.tapAt(Offset(rect.left + 2, rect.center.dy));
      await tester.pump(const Duration(milliseconds: 200));
      expect(taps, 1);
      final held = await tester.startGesture(rect.center);
      await held.moveBy(const Offset(0, -60));
      await held.up();
      await tester.pump(const Duration(milliseconds: 200));
      expect(taps, 1);
      expect(tester.takeException(), isNull);
    },
  );

  for (final platform in [MusicPlatform.kugou, MusicPlatform.netease]) {
    testWidgets(
      'daily mode plays full 77 tracks without navigating ${platform.name}',
      (tester) async {
        final queue = _Queue();
        var opened = 0;
        final tracks = List.generate(77, song157);
        final fixture = await PersonalProfileFixture.create(
          audioHandler: queue,
          accountFactory: () => _Account(platform),
          extraOverrides: [
            platformDailyProvider.overrideWith((ref) async => tracks),
          ],
        );
        addTearDown(fixture.dispose);
        await tester.pumpWidget(
          _host(
            fixture,
            Center(
              child: EditorialCover(
                cover: profileFixtureCover,
                title: '每日推荐',
                onTap: () => opened++,
                coverAction: const PlatformModePlayButton(
                  mode: PlatformHighlightMode.daily,
                  title: '每日推荐',
                ),
              ),
            ),
          ),
        );
        await ready146(tester);
        await tester.tap(find.byKey(const ValueKey('cover-play-mode-daily')));
        await _settle(tester);
        expect(queue.received, hasLength(77));
        expect(queue.received.last.id, tracks.last.id);
        expect(opened, 0);
        await tester.tap(find.text('每日推荐'));
        expect(opened, 1);
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      },
    );

    testWidgets(
      'FM starts the source session rather than queuing its preview ${platform.name}',
      (tester) async {
        final queue = _Queue(), radio = _Radio();
        final tracks = List.generate(3, song157);
        final fixture = await PersonalProfileFixture.create(
          audioHandler: queue,
          accountFactory: () => _Account(platform),
          extraOverrides: [
            platformFmProvider.overrideWith((ref) async => tracks),
            platformRecommendationSessionProvider.overrideWithValue(radio),
          ],
        );
        addTearDown(fixture.dispose);
        await tester.pumpWidget(
          _host(
            fixture,
            const PlatformModePlayButton(
              mode: PlatformHighlightMode.fm,
              title: '连续推荐',
            ),
          ),
        );
        await tester.tap(find.byKey(const ValueKey('cover-play-mode-fm')));
        await _settle(tester);
        expect(queue.received, [tracks.first]);
        expect(radio.adopted, tracks.first);
        expect(radio.source, PlatformRecommendationKind.fm);
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      },
    );
  }

  testWidgets(
    'heart action loads the official finite batch instead of a preview',
    (tester) async {
      final queue = _Queue();
      final tracks = List.generate(36, song157);
      final heart = _Heart([...tracks, tracks.first]);
      final fixture = await PersonalProfileFixture.create(
        audioHandler: queue,
        extraOverrides: [neteaseFeaturesProvider.overrideWithValue(heart)],
      );
      addTearDown(fixture.dispose);
      await tester.pumpWidget(
        _host(
          fixture,
          const PlatformModePlayButton(
            mode: PlatformHighlightMode.heart,
            title: '心动模式',
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('cover-play-mode-heart')));
      await _settle(tester);
      expect(heart.loads, 1);
      expect(queue.received, tracks);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );

  testWidgets('a later explicit selection wins over a slower earlier mode', (
    tester,
  ) async {
    final queue = _Queue(), pending = Completer<List<Track>>();
    final fixture = await PersonalProfileFixture.create(audioHandler: queue);
    addTearDown(fixture.dispose);
    await tester.pumpWidget(
      _host(
        fixture,
        Row(
          children: [
            PlatformSelectionPlayButton(
              selectionKey: 'old',
              label: '旧选择',
              load: (_, _) => pending.future,
            ),
            PlatformSelectionPlayButton(
              selectionKey: 'new',
              label: '新选择',
              load: (_, _) async => [song157(2)],
            ),
          ],
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('old')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('new')));
    await _settle(tester);
    pending.complete([song157(1)]);
    await _settle(tester);
    expect(queue.received.single.id, song157(2).id);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets(
    'leaving a full page permanently revokes its old request even after returning',
    (tester) async {
      final queue = _Queue(), pending = Completer<List<Track>>();
      final fixture = await PersonalProfileFixture.create(audioHandler: queue);
      addTearDown(fixture.dispose);
      final observer = BetaPageRouteObserver();
      await tester.pumpWidget(
        _host(
          fixture,
          PlatformSelectionPlayButton(
            selectionKey: 'old-page',
            label: '旧页面',
            load: (_, _) => pending.future,
          ),
          observer: observer,
        ),
      );
      await tester.tap(find.byKey(const ValueKey('old-page')));
      await tester.pump();
      final other = MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('其他页面')),
      );
      observer.navigator!.push(other);
      // The old request deliberately remains pending, so its activity indicator
      // keeps ticking after the route returns. Wait only for each 300ms page
      // transition instead of treating an active spinner as unsettled routing.
      await tester.pump();
      await tester.pump(other.transitionDuration);
      await tester.pump();
      expect(other.isCurrent, isTrue);
      expect(find.text('其他页面'), findsOneWidget);
      observer.navigator!.pop();
      expect(other.isCurrent, isFalse);
      await tester.pump();
      await tester.pump(other.reverseTransitionDuration);
      await tester.pump();
      // Windows host snapshot transitions can retain their outgoing subtree
      // after the route animation is dismissed. Pump a bounded number of actual
      // frames until its overlay is removed; never wait for the old spinner.
      for (
        var frame = 0;
        frame < 30 && find.text('其他页面').evaluate().isNotEmpty;
        frame++
      ) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(
        find.text('其他页面'),
        findsNothing,
        reason:
            'popped route overlay should be removed; animation=${other.animation?.status} value=${other.animation?.value} active=${other.isActive}',
      );
      expect(find.byKey(const ValueKey('old-page')), findsOneWidget);
      pending.complete([song157(1)]);
      await _settle(tester);
      expect(queue.received, isEmpty);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );

  testWidgets('A to B to A cannot revive an old-account selection', (
    tester,
  ) async {
    final queue = _Queue(), pending = Completer<List<Track>>();
    final fixture = await PersonalProfileFixture.create(
      audioHandler: queue,
      accountFactory: () => _Account(MusicPlatform.netease),
    );
    addTearDown(fixture.dispose);
    await tester.pumpWidget(
      _host(
        fixture,
        PlatformSelectionPlayButton(
          selectionKey: 'old-account',
          label: '旧账号',
          load: (_, _) => pending.future,
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('old-account')));
    await tester.pump();
    final account =
        fixture.container.read(platformAccountProvider.notifier) as _Account;
    account.select('7002');
    account.select('7001');
    pending.complete([song157(1)]);
    await _settle(tester);
    expect(queue.received, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets(
    'a minimal host without an observer also revokes a covered read',
    (tester) async {
      final queue = _Queue(), pending = Completer<List<Track>>();
      final fixture = await PersonalProfileFixture.create(audioHandler: queue);
      addTearDown(fixture.dispose);
      await tester.pumpWidget(
        _host(
          fixture,
          PlatformSelectionPlayButton(
            selectionKey: 'fallback-page',
            label: '无观察器页面',
            load: (_, _) => pending.future,
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('fallback-page')));
      await tester.pump();
      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('覆盖页面')),
        ),
      );
      await _settle(tester);
      expect(find.text('覆盖页面'), findsOneWidget);
      navigator.pop();
      await tester.pump();
      for (
        var frame = 0;
        frame < 30 && find.text('覆盖页面').evaluate().isNotEmpty;
        frame++
      ) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.text('覆盖页面'), findsNothing);
      pending.complete([song157(1)]);
      await _settle(tester);
      expect(queue.received, isEmpty);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );

  testWidgets(
    'collection playback starts immediately with a pending queue and no observer',
    (tester) async {
      final queue = _Queue()
        ..pending = [const MediaItem(id: 'pending-fixture', title: '旧待播')];
      final fixture = await PersonalProfileFixture.create(audioHandler: queue);
      addTearDown(fixture.dispose);
      await tester.pumpWidget(
        _host(
          fixture,
          PlatformSelectionPlayButton(
            selectionKey: 'fallback-dialog',
            label: '确认播放',
            load: (_, _) async => [song157(1)],
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('fallback-dialog')));
      await _settle(tester);
      expect(queue.received.single.id, song157(1).id);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );

  testWidgets(
    'switching a retained tab away and back revokes its old selection',
    (tester) async {
      final queue = _Queue(), pending = Completer<List<Track>>();
      final fixture = await PersonalProfileFixture.create(audioHandler: queue);
      addTearDown(fixture.dispose);
      var visible = true;
      late StateSetter update;
      await tester.pumpWidget(
        _host(
          fixture,
          StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return BetaTabVisibility(
                visible: visible,
                child: PlatformSelectionPlayButton(
                  selectionKey: 'retained',
                  label: '保留页面',
                  load: (_, _) => pending.future,
                ),
              );
            },
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('retained')));
      await tester.pump();
      update(() => visible = false);
      await tester.pump();
      update(() => visible = true);
      await tester.pump();
      pending.complete([song157(1)]);
      await _settle(tester);
      expect(queue.received, isEmpty);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );

  for (final platform in [MusicPlatform.kugou, MusicPlatform.netease]) {
    for (final rank in [false, true]) {
      testWidgets(
        'masthead independently plays the full collection ${platform.name} rank=$rank',
        (tester) async {
          final queue = _Queue();
          final item = rank ? rank157 : playlist158;
          final music = Metadata148(
            (_, _) async => {
              'playlist': {
                'trackCount': 77,
                'creator': {'nickname': '合成创建者', 'userId': 8},
              },
            },
          );
          final fixture = await PersonalProfileFixture.create(
            audioHandler: queue,
            musicRepository: music,
            accountFactory: () => _Account(platform),
            extraOverrides: [
              platformExploreRepositoryProvider.overrideWithValue(_Pages()),
              musicPlatformApiProvider.overrideWithValue(
                api157(
                    (_) async => reply157({
                      'status': 1,
                      'data': {
                        'rank_cid': 42,
                        'info': [
                          {
                            'global_collection_id': item.id,
                            'count': 77,
                            'list_create_username': '合成创建者',
                            'list_create_userid': 8,
                          },
                        ],
                      },
                    }),
                  )
                  ..session = PlatformSession(
                    userId: '7001',
                    token: 'fixture-only',
                    platform: platform,
                  ),
              ),
            ],
          );
          addTearDown(fixture.dispose);
          await tester.pumpWidget(
            _host(fixture, PlatformExploreSongsPage(item: item)),
          );
          await _settle(tester);
          await ready146(tester);
          final key = ValueKey(
            rank ? 'ranking-cover-play' : 'playlist-cover-play',
          );
          expect(find.byKey(key), findsOneWidget);
          await tester.tap(find.byKey(key));
          await _settle(tester);
          expect(queue.received, hasLength(77));
          expect(queue.received.last.id, song157(76).id);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          await tester.pump();
        },
      );
    }
  }

  for (final platform in [MusicPlatform.kugou, MusicPlatform.netease]) {
    testWidgets(
      'all highlight modes expose independent play controls ${platform.name}',
      (tester) async {
        final tracks = [song157(1).copyWith(coverAsset: profileFixtureCover)];
        final fixture = await PersonalProfileFixture.create(
          accountFactory: () => _Account(platform),
          extraOverrides: [
            platformDailyProvider.overrideWith((ref) async => tracks),
            platformFmProvider.overrideWith((ref) async => tracks),
            platformExploreProvider.overrideWith(
              (ref, kind) async => [
                PlatformExploreItem(
                  id: '8888',
                  title: '合成榜单',
                  cover: profileFixtureCover,
                  kind: kind,
                ),
              ],
            ),
            neteaseFeedPreviewProvider.overrideWith(
              (ref, feed) async => NeteaseBatch([
                NeteaseItem(
                  id: '1',
                  name: '合成心动',
                  kind: NeteaseEntity.song,
                  track: tracks.first,
                ),
              ]),
            ),
          ],
        );
        addTearDown(fixture.dispose);
        await tester.pumpWidget(
          _host(
            fixture,
            const SingleChildScrollView(child: MusicDiscoveryHighlights()),
          ),
        );
        await ready146(tester);
        await _settle(tester);
        expect(
          find.byKey(const ValueKey('cover-play-mode-daily')),
          findsOneWidget,
        );
        await tester.drag(find.byType(ListView).first, const Offset(-600, 0));
        await tester.pump(const Duration(milliseconds: 500));
        if (platform == MusicPlatform.netease) {
          expect(
            find.byKey(const ValueKey('cover-play-mode-heart')),
            findsOneWidget,
          );
          await tester.drag(find.byType(ListView).first, const Offset(-380, 0));
          await tester.pump(const Duration(milliseconds: 500));
        }
        expect(
          find.byKey(const ValueKey('cover-play-mode-fm')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      },
    );
  }
}
