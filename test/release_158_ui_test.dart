import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:audio_service/audio_service.dart';
import 'package:mesting_music/features/player/presentation/beta_playback_actions.dart';
import 'package:mesting_music/core/audio/mesting_audio_handler.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/music_platform/data/platform_explore.dart';
import 'package:mesting_music/features/music_platform/presentation/platform_search_landing.dart';
import 'package:mesting_music/shared/models/track.dart';
import 'package:mesting_music/shared/models/track_page.dart';
import 'support/personal_profile_fixture.dart';
import 'support/release_152_qa.dart';
import 'release_148_data_test.dart' show Metadata148;
import 'release_146_ui_test.dart' show ready146;
import 'release_157_ranking_test.dart' show rank157, song157, api157, reply157;
import 'release_158_collections_test.dart' show playlist158;
import 'package:mesting_music/features/experience/presentation/music_landing_page.dart';
import 'package:mesting_music/features/experience/presentation/editorial_widgets.dart';
import 'package:mesting_music/features/music_platform/presentation/platform_collection_play.dart';
import 'package:mesting_music/features/music_platform/platform_catalog_providers.dart';
import 'package:mesting_music/features/music_platform/platform_recommendation_providers.dart';
import 'package:mesting_music/features/music_platform/netease/netease_features_page.dart';
import 'package:mesting_music/features/music_platform/netease/netease_features_repository.dart';

class _Account extends PlatformAccountController {
  _Account(this.platform);
  final MusicPlatform platform;
  @override
  Future<PlatformSession?> build() async => PlatformSession(
    userId: '7001',
    token: 'fixture-only',
    platform: platform,
  );
}

class _Queue extends Fake implements MestingAudioHandler {
  List<Track> received = [];
  List<MediaItem> pending = [];
  @override
  get manuallyQueuedItems => pending;
  @override
  Future<void> replaceQueue(
    List<Track> tracks, {
    int initialIndex = 0,
    Duration initialPosition = Duration.zero,
    bool autoplay = true,
    bool recommendationContext = false,
    bool Function()? togetherGuard,
  }) async => received = tracks;
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
        for (var n = offset; n < end; n++)
          song157(n).copyWith(coverAsset: profileFixtureCover),
      ],
      offset: offset,
      nextOffset: end,
      total: 77,
      hasMore: end < 77,
    );
  }
}

void main() {
  setUpAll(initialize151QA);
  for (final platform in MusicPlatform.values) {
    for (final dark in [false, true]) {
      for (final large in [false, true]) {
        testWidgets(
          'public playlist controls render and play every page; ${platform.name} dark=$dark large=$large',
          (tester) async {
            tester.view.devicePixelRatio = 1;
            tester.view.physicalSize = Size(large ? 320 : 390, 844);
            addTearDown(tester.view.reset);
            var subscribed = false;
            final queue = _Queue();
            final music = Metadata148((route, query) async {
              if (route == '/playlist/subscribe') {
                subscribed = query['subscribe'] == true;
                return {'code': 200};
              }
              return {
                'playlist': {
                  'trackCount': 77,
                  'subscribedCount': 13234000,
                  'commentCount': 319000,
                  'shareCount': 67679,
                  'subscribed': subscribed,
                  'updateTime': DateTime(2026, 11, 5).millisecondsSinceEpoch,
                  'description': '合成榜单 · 每日更新，保持完整歌曲顺序。',
                },
              };
            });
            final fixture = await PersonalProfileFixture.create(
              musicRepository: music,
              audioHandler: queue,
              accountFactory: () => _Account(platform),
              extraOverrides: [
                platformExploreRepositoryProvider.overrideWithValue(_Pages()),
                musicPlatformApiProvider.overrideWithValue(
                  api157(
                      (_) async => reply157({
                        'status': 1,
                        'data': {
                          'info': [
                            {
                              'global_collection_id': playlist158.id,
                              'count': 77,
                              'intro': '合成公开歌单',
                              'list_create_username': '合成创建者',
                              'list_create_userid': 9,
                              'list_create_listid': 12,
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
            // A synthetic loopback reply supplies only rank metadata. No platform
            // host, real account, native player or phone is involved in this test.
            await tester.pumpWidget(
              UncontrolledProviderScope(
                container: fixture.container,
                child: MaterialApp(
                  debugShowCheckedModeBanner: false,
                  theme: theme152(dark),
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: TextScaler.linear(large ? 2 : 1)),
                    child: capture151Builder(child!),
                  ),
                  home: const PlatformExploreSongsPage(item: playlist158),
                ),
              ),
            );
            for (var i = 0; i < 12; i++) {
              await tester.pump(const Duration(milliseconds: 50));
            }
            await ready146(tester);
            expect(
              find.byKey(const ValueKey('playlist-play-all')),
              findsOneWidget,
            );
            expect(
              find.byKey(const ValueKey('ranking-action-save')),
              findsOneWidget,
            );
            expect(
              find.byKey(const ValueKey('ranking-action-comments')),
              findsOneWidget,
            );
            expect(
              find.byKey(const ValueKey('ranking-action-share')),
              findsOneWidget,
            );
            expect(tester.takeException(), isNull);
            expect(find.text('11月5日更新'), findsNothing);
            await shot151(
              tester,
              '158-playlist-${platform.name}-${dark ? 'dark' : 'light'}-${large ? 'large' : 'normal'}',
            );
            if (platform == MusicPlatform.netease) {
              await tester.tap(
                find.byKey(const ValueKey('ranking-action-save')),
              );
              await tester.pump();
              await tester.pump(const Duration(milliseconds: 100));
              expect(subscribed, isTrue);
            }
            await Scrollable.ensureVisible(
              tester.element(find.byKey(const ValueKey('playlist-play-all'))),
              alignment: .4,
            );
            await tester.pump(const Duration(milliseconds: 400));
            await tester.tap(find.byKey(const ValueKey('playlist-play-all')));
            for (var i = 0; i < 8; i++) {
              await tester.pump(const Duration(milliseconds: 50));
            }
            expect(queue.received.length, 77);
            expect(queue.received.last.id, song157(76).id);
            final shares = <String>[];
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
                .setMockMethodCallHandler(
                  const MethodChannel('com.mesting.music/share'),
                  (call) async {
                    shares.add('${(call.arguments as Map)['text']}');
                    return null;
                  },
                );
            addTearDown(
              () => TestDefaultBinaryMessengerBinding
                  .instance
                  .defaultBinaryMessenger
                  .setMockMethodCallHandler(
                    const MethodChannel('com.mesting.music/share'),
                    null,
                  ),
            );
            await Scrollable.ensureVisible(
              tester.element(
                find.byKey(const ValueKey('ranking-action-share')),
              ),
              alignment: .3,
            );
            await tester.pump(const Duration(milliseconds: 300));
            await tester.tap(
              find.byKey(const ValueKey('ranking-action-share')),
            );
            await tester.pump();
            expect(
              shares.single,
              contains(
                platform == MusicPlatform.netease
                    ? 'music.163.com'
                    : 'kugou.com',
              ),
            );
            expect(shares.single, isNot(contains('fixture-only')));
            // Starting a list drag on an action must cancel its tap while
            // leaving a usable back control after the masthead scrolls away.
            final gesture = await tester.startGesture(
              tester.getCenter(
                find.byKey(const ValueKey('ranking-action-share')),
              ),
            );
            await gesture.moveBy(const Offset(0, -40));
            await gesture.moveBy(const Offset(0, -220));
            await tester.pump(const Duration(milliseconds: 100));
            expect(
              find.byKey(const ValueKey('ranking-collapsed-back')),
              findsOneWidget,
            );
            expect(shares, hasLength(1));
            await gesture.up();
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox());
            await tester.pump();
          },
        );
        testWidgets(
          'discovery has platform modes and independent collection play; ${platform.name} dark=$dark large=$large',
          (tester) async {
            tester.view.devicePixelRatio = 1;
            tester.view.physicalSize = Size(large ? 320 : 390, 844);
            addTearDown(tester.view.reset);
            final songs = [
              for (var n = 0; n < 12; n++)
                song157(n).copyWith(coverAsset: profileFixtureCover),
            ];
            final fixture = await PersonalProfileFixture.create(
              accountFactory: () => _Account(platform),
              extraOverrides: [
                platformDailyProvider.overrideWith((ref) async => songs),
                platformFmProvider.overrideWith((ref) async => songs),
                platformDiscoveryProvider.overrideWith((ref) async => songs),
                platformNewSongsProvider.overrideWith((ref) async => songs),
                platformExploreProvider.overrideWith(
                  (ref, kind) async => [
                    PlatformExploreItem(
                      id: '8888',
                      title: '合成热歌榜',
                      cover: profileFixtureCover,
                      kind: kind,
                    ),
                  ],
                ),
                platformFeaturedProvider.overrideWith(
                  (ref) async => [
                    {
                      'global_collection_id': playlist158.id,
                      'name': playlist158.title,
                      'pic': profileFixtureCover,
                    },
                  ],
                ),
                neteaseFeedPreviewProvider.overrideWith(
                  (ref, feed) async => NeteaseBatch([
                    NeteaseItem(
                      id: '42',
                      name: '合成推荐',
                      cover: profileFixtureCover,
                      kind: feed == NeteaseFeed.intelligence
                          ? NeteaseEntity.song
                          : NeteaseEntity.playlist,
                      track: songs.first,
                    ),
                  ]),
                ),
              ],
            );
            addTearDown(fixture.dispose);
            await tester.pumpWidget(
              UncontrolledProviderScope(
                container: fixture.container,
                child: MaterialApp(
                  debugShowCheckedModeBanner: false,
                  theme: theme152(dark),
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: TextScaler.linear(large ? 2 : 1)),
                    child: capture151Builder(child!),
                  ),
                  home: const Scaffold(body: MusicLandingPage()),
                ),
              ),
            );
            await ready146(tester);
            for (var n = 0; n < 10; n++) {
              await tester.pump(const Duration(milliseconds: 50));
            }
            // The real home preserves a readiness fence until visible artwork
            // is decoded. Precache exact resized providers even while fenced;
            // this is host fixture preparation, not a product timing bypass.
            for (var pass = 0; pass < 4; pass++) {
              final images = tester
                  .widgetList<Image>(find.byType(Image, skipOffstage: false))
                  .toList();
              await tester.runAsync(() async {
                await Future.wait([
                  for (final image in images)
                    precacheImage(
                      image.image,
                      tester.element(find.byType(MaterialApp)),
                    ),
                ]);
              });
              await tester.pump(const Duration(milliseconds: 350));
            }
            expect(find.text('为你精选'), findsOneWidget);
            expect(find.text('每日推荐'), findsWidgets);
            expect(find.text('我的喜欢'), findsNothing);
            await shot151(
              tester,
              '158-home-${platform.name}-${dark ? 'dark' : 'light'}-${large ? 'large' : 'normal'}',
            );
            expect(find.text('每日推荐').hitTestable(), findsWidgets);
            await tester.drag(find.text('每日推荐').first, const Offset(-580, 0));
            await tester.pump(const Duration(milliseconds: 600));
            if (platform == MusicPlatform.netease) {
              expect(find.text('心动模式'), findsWidgets);
            } else {
              expect(find.text('猜你喜欢'), findsWidgets);
            }
            await shot151(
              tester,
              '158-modes-${platform.name}-${dark ? 'dark' : 'light'}-${large ? 'large' : 'normal'}',
            );
            for (var step = 0; step < 2; step++) {
              await tester.drag(
                find.byType(CustomScrollView).first,
                const Offset(0, -360),
              );
              await ready146(tester);
              await tester.pump(const Duration(milliseconds: 400));
            }
            await shot151(
              tester,
              '158-feed-${platform.name}-${dark ? 'dark' : 'light'}-${large ? 'large' : 'normal'}',
            );
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox());
            await tester.pump();
          },
        );
      }
    }
    testWidgets(
      'cover play is independent from navigation and reads all 77 songs ${platform.name}',
      (tester) async {
        final queue = _Queue();
        var opened = 0;
        final fixture = await PersonalProfileFixture.create(
          accountFactory: () => _Account(platform),
          audioHandler: queue,
          extraOverrides: [
            platformExploreRepositoryProvider.overrideWithValue(_Pages()),
          ],
        );
        addTearDown(fixture.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: fixture.container,
            child: MaterialApp(
              home: Scaffold(
                body: Center(
                  child: EditorialCover(
                    cover: profileFixtureCover,
                    title: playlist158.title,
                    onTap: () => opened++,
                    coverAction: const PlatformCollectionPlayButton(
                      item: playlist158,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await ready146(tester);
        final held = await tester.startGesture(
          tester.getCenter(
            find.byKey(ValueKey('cover-play-playlist-${playlist158.id}')),
          ),
        );
        await held.moveBy(const Offset(0, -40));
        await held.moveBy(const Offset(0, -40));
        await tester.pump(const Duration(milliseconds: 350));
        expect(queue.received, isEmpty);
        expect(opened, 0);
        await held.up();
        await tester.tap(
          find.byKey(ValueKey('cover-play-playlist-${playlist158.id}')),
        );
        for (var n = 0; n < 8; n++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(opened, 0);
        expect(queue.received, hasLength(77));
        await tester.tap(find.text(playlist158.title));
        await tester.pump();
        expect(opened, 1);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      },
    );
  }
  for (final platform in MusicPlatform.values) {
    testWidgets(
      'rank cover plays every page without opening details ${platform.name}',
      (tester) async {
        final queue = _Queue();
        var opened = 0;
        final music = Metadata148(
          (_, _) async => {
            'playlist': {'trackCount': 77},
          },
        );
        final api =
            api157(
                (_) async => reply157({
                  'status': 1,
                  'data': {'rank_cid': 42},
                }),
              )
              ..session = PlatformSession(
                userId: '7001',
                token: 'fixture-only',
                platform: platform,
              );
        final fixture = await PersonalProfileFixture.create(
          musicRepository: music,
          accountFactory: () => _Account(platform),
          audioHandler: queue,
          extraOverrides: [
            platformExploreRepositoryProvider.overrideWithValue(_Pages()),
            musicPlatformApiProvider.overrideWithValue(api),
          ],
        );
        addTearDown(fixture.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: fixture.container,
            child: MaterialApp(
              home: Scaffold(
                body: Center(
                  child: EditorialCover(
                    cover: profileFixtureCover,
                    title: rank157.title,
                    onTap: () => opened++,
                    coverAction: const PlatformCollectionPlayButton(
                      item: rank157,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await ready146(tester);
        await tester.tap(find.byKey(const ValueKey('cover-play-rank-8888')));
        for (var n = 0; n < 8; n++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(queue.received, hasLength(77));
        expect(opened, 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      },
    );
  }
  testWidgets(
    'a newer selection revokes playback while the queue confirmation is open',
    (tester) async {
      final queue = _Queue()
        ..pending = [const MediaItem(id: 'previous-pending', title: '待播样本')];
      final fixture = await PersonalProfileFixture.create(audioHandler: queue);
      addTearDown(fixture.dispose);
      var current = true;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: fixture.container,
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) => TextButton(
                  onPressed: () => playBetaSelection(
                    context,
                    ref,
                    song157(1),
                    playAll: [song157(1)],
                    stillCurrent: () => current,
                  ),
                  child: const Text('播放样本'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('播放样本'));
      await tester.pumpAndSettle();
      expect(find.text('替换待播歌曲'), findsOneWidget);
      current = false;
      await tester.tap(find.text('替换待播歌曲'));
      await tester.pumpAndSettle();
      expect(queue.received, isEmpty);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );
}
