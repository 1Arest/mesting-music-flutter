import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mesting_music/features/music_platform/data/platform_explore.dart';
import 'package:mesting_music/features/music_platform/data/platform_recommendations.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/music_platform/netease/netease_features_page.dart';
import 'package:mesting_music/features/music_platform/netease/netease_features_repository.dart';
import 'package:mesting_music/features/music_platform/platform_catalog_providers.dart';
import 'package:mesting_music/features/music_platform/platform_recommendation_providers.dart';
import 'package:mesting_music/features/music_platform/presentation/beta_personal_profile.dart';
import 'package:mesting_music/features/music_platform/presentation/platform_ranking_header.dart';
import 'package:mesting_music/features/music_platform/presentation/platform_recommendations_page.dart';
import 'package:mesting_music/features/music_platform/presentation/platform_search_landing.dart';
import 'package:mesting_music/shared/models/track.dart';
import 'package:mesting_music/shared/models/track_page.dart';
import 'package:mesting_music/shared/widgets/beta_glass_controls.dart';
import 'package:mesting_music/shared/widgets/beta_glass_popover.dart';
import 'package:mesting_music/shared/widgets/collection_play_all_button.dart';
import 'support/personal_profile_fixture.dart';
import 'support/pump_artwork_ready.dart';
import 'support/release_145_qa.dart';
import 'release_148_data_test.dart' show Metadata148;
import 'release_157_ranking_test.dart' show api157, reply157;

const _capture = bool.fromEnvironment('CAPTURE_UI189');
const _boundary = ValueKey('ui189-capture');

class _Account extends PlatformAccountController {
  _Account(this.platform);
  final MusicPlatform platform;
  @override
  Future<PlatformSession?> build() async => PlatformSession(
    userId: '7001',
    token: 'fixture-only',
    nickname: '固定测试账号',
    platform: platform,
  );
}

List<Track> _songs(MusicPlatform platform) => List.generate(
  20,
  (i) => Track(
    id: '${platform == MusicPlatform.netease ? 'netease' : 'kugou'}_${7000 + i}',
    title: '合成歌曲 ${i + 1}',
    artist: '合成歌手',
    album: '',
    duration: const Duration(minutes: 3),
    audioAsset: '',
    coverAsset: profileFixtureCover,
    lyricsAsset: '',
    source: platform == MusicPlatform.netease
        ? TrackSource.netease
        : TrackSource.kugou,
  ),
);

class _Pages extends PlatformExploreRepository {
  _Pages(this.items)
    : super(api157((_) async => reply157({'status': 1, 'data': {}})));
  final List<Track> items;
  @override
  Future<PlatformExploreItem> resolveScene(PlatformExploreItem item) async =>
      item;
  @override
  Future<TrackPage> tracksPage(
    PlatformExploreItem item, {
    int offset = 0,
    int limit = 30,
  }) async => TrackPage(
    offset == 0 ? items : [],
    offset: offset,
    nextOffset: items.length,
    total: items.length,
    hasMore: false,
  );
}

class _Feeds extends NeteaseFeaturesRepository {
  _Feeds(this.tracks) : super(Metadata148((_, _) async => {}));
  final List<Track> tracks;
  @override
  Future<NeteaseBatch> load(
    NeteaseFeed feed, {
    int page = 1,
    int before = 0,
    String id = '',
    String category = '全部',
    String area = 'ALL',
    int artistArea = 1,
  }) async => NeteaseBatch([
    for (final track in tracks)
      NeteaseItem(
        id: track.id,
        name: track.title,
        kind: NeteaseEntity.song,
        track: track,
      ),
  ]);
}

Future<void> _frames(WidgetTester tester) async {
  // Membership and marquees can legitimately keep ticking behind these pages.
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _capturePage(WidgetTester tester, String name) async {
  if (!_capture) return;
  await tester.runAsync(() async {
    final render = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_boundary),
    );
    final image = await render.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('.codex-artifacts/2026-11-10-ui189/ui-final/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await LiquidGlassWidgets.initialize();
    if (!_capture) return;
    final bytes = await File('C:/Windows/Fonts/msyh.ttc').readAsBytes();
    for (final name in [
      'MestingQA',
      'Ahem',
      'Roboto',
      'sans-serif',
      'Noto Sans SC',
      'Microsoft YaHei',
      'CupertinoSystemText',
      'CupertinoSystemDisplay',
    ]) {
      await (FontLoader(
        name,
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    }
    await (FontLoader('MaterialIcons')..addFont(
          File(
            'D:/CodexCache/flutter-3.41.9/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
          ).readAsBytes().then(ByteData.sublistView),
        ))
        .load();
    await (FontLoader('packages/cupertino_icons/CupertinoIcons')..addFont(
          rootBundle.load('packages/cupertino_icons/assets/CupertinoIcons.ttf'),
        ))
        .load();
  });

  Future<PersonalProfileFixture> mount(
    WidgetTester tester,
    MusicPlatform platform,
    Widget page,
    bool large,
  ) async {
    final tracks = _songs(platform);
    final fixture = await PersonalProfileFixture.create(
      accountFactory: () => _Account(platform),
      musicRepository: Metadata148(
        (_, _) async => {
          'playlist': {
            'trackCount': 20,
            'coverImgUrl': profileFixtureCover,
            'creator': {'nickname': '合成创建者', 'userId': 8},
          },
        },
      ),
      extraOverrides: [
        if (page is PlatformExploreSongsPage &&
            page.item.kind == PlatformExploreKind.rank)
          musicPlatformApiProvider.overrideWithValue(
            api157(
                (_) async => reply157({
                  'status': 1,
                  'data': {
                    'rank_cid': 42,
                    'info': [
                      {
                        'global_collection_id': '8008',
                        'count': 20,
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
        platformDailyProvider.overrideWith((ref) async => tracks),
        platformFmProvider.overrideWith((ref) async => tracks),
        platformDiscoveryProvider.overrideWith((ref) async => tracks),
        platformExploreRepositoryProvider.overrideWithValue(_Pages(tracks)),
        neteaseFeaturesProvider.overrideWithValue(_Feeds(tracks)),
      ],
    );
    addTearDown(fixture.dispose);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(large ? 320 : 390, 844);
    addTearDown(tester.view.reset);
    var theme = theme145(large);
    if (_capture) {
      theme = theme.copyWith(
        textTheme: theme.textTheme.apply(fontFamily: 'MestingQA'),
        listTileTheme: theme.listTileTheme.copyWith(
          titleTextStyle:
              (theme.listTileTheme.titleTextStyle ?? theme.textTheme.bodyLarge!)
                  .copyWith(fontFamily: 'MestingQA'),
          subtitleTextStyle:
              (theme.listTileTheme.subtitleTextStyle ??
                      theme.textTheme.bodyMedium!)
                  .copyWith(fontFamily: 'MestingQA'),
        ),
      );
    }
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: fixture.container,
        child: MaterialApp(
          theme: theme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(large ? 2 : 1)),
            child: RepaintBoundary(key: _boundary, child: child!),
          ),
          home: Scaffold(body: page),
        ),
      ),
    );
    await pumpArtworkReady(tester);
    await _frames(tester);
    return fixture;
  }

  for (final large in [false, true]) {
    for (final platform in [MusicPlatform.netease, MusicPlatform.kugou]) {
      for (final mode in ['daily', 'fm', 'discover', 'rank', 'album']) {
        testWidgets(
          'collection $mode ${platform.name} large=$large has one photo header and one consistent play entry',
          (tester) async {
            final page = ['rank', 'album'].contains(mode)
                ? PlatformExploreSongsPage(
                    item: PlatformExploreItem(
                      id: '8008',
                      title: mode == 'rank' ? '合成榜单' : '合成专辑',
                      cover: profileFixtureCover,
                      kind: mode == 'rank'
                          ? PlatformExploreKind.rank
                          : PlatformExploreKind.album,
                    ),
                  )
                : PlatformRecommendationDetail(
                    title: mode == 'daily'
                        ? '每日推荐'
                        : mode == 'fm'
                        ? '私人FM'
                        : '刷歌推荐',
                    kind: mode == 'daily'
                        ? null
                        : mode == 'fm'
                        ? PlatformRecommendationKind.fm
                        : PlatformRecommendationKind.discover,
                  );
            await mount(tester, platform, page, large);
            final masthead = tester.widget<PlatformCollectionMasthead>(
              find.byType(PlatformCollectionMasthead),
            );
            expect(masthead.coverOnly, true);
            expect(masthead.cover, isNotEmpty);
            expect(masthead.onSearch, isNull);
            expect(masthead.onDetails, isNull);
            expect(masthead.coverAction, isNull);
            expect(
              tester
                  .widget<Text>(
                    find.byKey(const ValueKey('ranking-masthead-title')),
                  )
                  .style!
                  .fontSize,
              32,
            );
            expect(find.byType(CollectionPlayGlyph), findsOneWidget);
            expect(
              tester.getSize(find.byType(CollectionPlayGlyph)),
              const Size(26, 26),
            );
            if (mode == 'fm' || mode == 'discover') {
              expect(find.text('已加载 20 首歌曲'), findsOneWidget);
              expect(find.text('播放推荐'), findsOneWidget);
            }
            expect(tester.takeException(), isNull);
            await _capturePage(
              tester,
              '189-$mode-${platform.name}-${large ? '320-dark-2x' : '390-light'}',
            );
            await tester.pumpWidget(const SizedBox());
            await tester.pump();
          },
        );
      }
      testWidgets(
        'profile ${platform.name} large=$large uses anchored liquid menu with retained actions',
        (tester) async {
          await mount(tester, platform, const BetaPersonalProfile(), large);
          final button = find.byWidgetPredicate(
            (w) => w is BetaGlassButton && w.label == '账号选项',
          );
          final anchor = tester.getRect(button);
          await tester.tap(button);
          await _frames(tester);
          expect(find.byType(BetaLiquidMenu), findsOneWidget);
          final menu = tester.getRect(
            find.byKey(const ValueKey('beta13-glass-menu-surface')),
          );
          expect(menu.top, greaterThanOrEqualTo(anchor.bottom));
          expect(menu.right, lessThanOrEqualTo(large ? 320 : 390));
          for (final label in ['编辑个人资料', '切换音乐平台', '切换酷狗账号', '管理当前账号']) {
            expect(find.text(label), findsOneWidget);
          }
          if (platform == MusicPlatform.kugou) {
            expect(find.text('验证酷狗官方功能'), findsOneWidget);
          }
          await tester
              .state<BetaPersonalProfileState>(find.byType(BetaPersonalProfile))
              .openAccountMenu();
          expect(
            find.byType(BetaLiquidMenu),
            findsOneWidget,
            reason: 'A rapid second activation cannot stack another menu',
          );
          expect(tester.takeException(), isNull);
          await _capturePage(
            tester,
            '189-profile-menu-${platform.name}-${large ? '320-dark-2x' : '390-light'}',
          );
          await tester.tapAt(const Offset(4, 800));
          await _frames(tester);
          expect(find.byType(BetaLiquidMenu), findsNothing);
          await tester.pumpWidget(const SizedBox());
          await tester.pump();
        },
      );
    }
    testWidgets('heart and cloud song feeds share masthead large=$large', (
      tester,
    ) async {
      for (final feed in [NeteaseFeed.intelligence, NeteaseFeed.cloud]) {
        await mount(
          tester,
          MusicPlatform.netease,
          NeteaseFeaturesPage(feed: feed),
          large,
        );
        expect(find.byType(PlatformCollectionMasthead), findsOneWidget);
        expect(find.byType(CollectionPlayGlyph), findsOneWidget);
        expect(find.byKey(const ValueKey('platform-play-all')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _capturePage(
          tester,
          '189-${feed.name}-${large ? '320-dark-2x' : '390-light'}',
        );
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      }
    });
  }
}
