import 'support/source187_paging_fixture.dart';
// This historical fixture covers NetEase/Kugou; Soda is covered by qishui_* tests.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
  @override
  int get transportRevision => 0;
  List<Track> received = [];
  @override
  get manuallyQueuedItems => [];
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
  for (final platform in [MusicPlatform.kugou, MusicPlatform.netease]) {
    for (final dark in [false, true]) {
      for (final large in [false, true]) {
        testWidgets(
          'chart controls render and play every page; ${platform.name} dark=$dark large=$large',
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
                retainedPagingLogin187(),
                platformExploreRepositoryProvider.overrideWithValue(_Pages()),
                musicPlatformApiProvider.overrideWithValue(
                  api157(
                      (_) async => reply157({
                        'status': 1,
                        'data': {'rank_cid': 42, 'intro': '合成榜单 · 收藏本期歌曲'},
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
                  home: const PlatformExploreSongsPage(item: rank157),
                ),
              ),
            );
            for (var i = 0; i < 12; i++) {
              await tester.pump(const Duration(milliseconds: 50));
            }
            await ready146(tester);
            expect(
              find.byKey(const ValueKey('ranking-play-all')),
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
            if (platform == MusicPlatform.netease) {
              expect(find.text('11月5日更新'), findsOneWidget);
            }
            await shot151(
              tester,
              '157-rank-${platform.name}-${dark ? 'dark' : 'light'}-${large ? 'large' : 'normal'}',
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
              tester.element(find.byKey(const ValueKey('ranking-play-all'))),
              alignment: .4,
            );
            await tester.pump(const Duration(milliseconds: 400));
            await tester.tap(find.byKey(const ValueKey('ranking-play-all')));
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
      }
    }
  }
}
