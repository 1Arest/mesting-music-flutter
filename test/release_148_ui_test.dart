import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:audio_service/audio_service.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mesting_music/core/audio/mesting_audio_handler.dart';
import 'package:mesting_music/core/audio/playback_providers.dart';
import 'package:mesting_music/shared/models/track.dart';
import 'package:mesting_music/shared/models/track_page.dart';
import 'package:mesting_music/shared/widgets/artwork_image.dart';
import 'package:mesting_music/shared/widgets/music_activity_indicator.dart';
import 'package:mesting_music/features/experience/presentation/favorite_tracks_search.dart';
import 'package:mesting_music/features/music_platform/netease/netease_features_page.dart';
import 'package:mesting_music/features/music_platform/netease/netease_features_repository.dart';
import 'package:mesting_music/features/music_platform/netease/netease_item_artwork.dart';
import 'package:mesting_music/features/music_platform/data/platform_category_search.dart';
import 'package:mesting_music/features/music_platform/data/playback_quality_catalog.dart';
import 'package:mesting_music/features/music_platform/platform_profile_provider.dart';
import 'package:mesting_music/features/music_platform/platform_quality_providers.dart';
import 'package:mesting_music/features/music_platform/domain/platform_audio_quality.dart';
import 'package:mesting_music/features/music_platform/presentation/platform_catalog_detail_page.dart';
import 'package:mesting_music/features/music_platform/presentation/platform_profile_edit_page.dart';
import 'package:mesting_music/features/music_platform/presentation/platform_comment_composer.dart';
import 'package:mesting_music/features/music_platform/presentation/platform_quality_button.dart';
import 'support/personal_profile_fixture.dart';
import 'support/release_147_qa.dart';
import 'release_146_ui_test.dart' show ready146, theme146;
import 'release_148_data_test.dart' show Metadata148, quality148;

const _capture = bool.fromEnvironment('CAPTURE_148');
const _directory = String.fromEnvironment(
  'CAPTURE_148_DIR',
  defaultValue: '.codex-artifacts/2026-11-04-release148/ui-round1',
);
const _boundary = ValueKey('qa148');

Track song148(int index) => Track(
  id: 'netease_${9000 + index}',
  title: '歌曲 $index',
  artist: '歌手样本',
  album: '本地合成夹具',
  duration: const Duration(minutes: 3),
  audioAsset: 'assets/audio/sample.mp3',
  coverAsset: profileFixtureCover,
  lyricsAsset: '',
  source: TrackSource.netease,
);

/// Observe the collection passed into the existing playback boundary. Widget
/// tests must not wait for real platform audio-session/plugin initialization.
class _Queue148 extends Fake implements MestingAudioHandler {
  final _delegate = BaseAudioHandler();
  List<Track> received = [];
  @override
  get mediaItem => _delegate.mediaItem;
  @override
  get playbackState => _delegate.playbackState;
  @override
  get queue => _delegate.queue;
  @override
  Stream<List<MediaItem>> get upcomingQueueStream => Stream.value(const []);
  @override
  List<MediaItem> get manuallyQueuedItems => const [];
  @override
  Track? trackForId(String id) {
    for (final track in received) {
      if (track.id == id) return track;
    }
    return null;
  }

  @override
  Future<void> debugDispose() async {
    await _delegate.mediaItem.close();
    await _delegate.playbackState.close();
    await _delegate.queue.close();
  }

  @override
  List<Track> get tracks => List.unmodifiable(received);
  @override
  Future<void> replaceQueue(
    List<Track> tracks, {
    int initialIndex = 0,
    Duration initialPosition = Duration.zero,
    bool autoplay = true,
    bool recommendationContext = false,
    bool Function()? togetherGuard,
  }) async {
    received = List.of(tracks);
  }
}

class _Feed148 extends NeteaseFeaturesRepository {
  _Feed148(super.music);
  final pages = <int>[];
  @override
  Future<NeteaseBatch> load(
    NeteaseFeed feed, {
    int page = 1,
    int before = 0,
    String id = '',
    String category = '全部',
    String area = 'ALL',
    int artistArea = 1,
  }) async {
    pages.add(page);
    if (feed == NeteaseFeed.categories) {
      return const NeteaseBatch([
        NeteaseItem(id: '综艺', name: '综艺', kind: NeteaseEntity.category),
        NeteaseItem(id: '流行', name: '流行', kind: NeteaseEntity.category),
        NeteaseItem(id: '怀旧', name: '怀旧', kind: NeteaseEntity.category),
      ]);
    }
    return NeteaseBatch([
      for (var i = page == 1 ? 0 : 30; i < (page == 1 ? 30 : 35); i++)
        NeteaseItem(
          id: '${9000 + i}',
          name: '歌曲 $i',
          kind: NeteaseEntity.song,
          cover: profileFixtureCover,
          track: song148(i),
        ),
    ], more: page == 1);
  }

  @override
  Future<bool> subscribed(NeteaseItem item) async => true;
}

class _Art148 extends NeteaseArtworkRepository {
  _Art148(super.music);
  @override
  Future<String> category(
    String name, {
    bool refresh = false,
    String rejected = '',
  }) async => profileFixtureCover;
}

class _Music148 extends Metadata148 {
  _Music148() : super((_, _) async => {});
  final offsets = <int>[];
  @override
  Future<TrackPage> categoryTrackPage(
    PlatformSearchHit hit, {
    int offset = 0,
    int limit = 30,
  }) async {
    offsets.add(offset);
    final end = (offset + limit).clamp(0, 35);
    return TrackPage(
      [for (var i = offset; i < end; i++) song148(i)],
      offset: offset,
      nextOffset: end,
      total: 35,
      hasMore: end < 35,
    );
  }
}

Future<void> mount148(
  WidgetTester tester,
  PersonalProfileFixture fixture,
  Widget page, {
  bool dark = false,
  bool large = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(large ? 320 : 390, 844);
  tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
  addTearDown(tester.view.reset);
  final base = theme146(dark);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: fixture.container,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _capture
            ? base.copyWith(
                textTheme: base.textTheme.apply(fontFamily: 'MestingQA148'),
              )
            : base,
        builder: (context, child) => RepaintBoundary(
          key: _boundary,
          child: ColoredBox(
            color: Theme.of(context).colorScheme.surface,
            child: MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(large ? 1.4 : 1)),
              child: child!,
            ),
          ),
        ),
        home: page,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await ready146(tester);
}

Future<void> shot148(WidgetTester tester, String name) async {
  if (!_capture) return;
  await ready146(tester);
  final frame = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_boundary),
  );
  await tester.runAsync(() async {
    final image = await frame.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('$_directory/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    await LiquidGlassWidgets.initialize();
    if (_capture) {
      await load147IconFonts();
      for (final family in [
        'MestingQA148',
        'Roboto',
        'CupertinoSystemText',
        'CupertinoSystemDisplay',
        'sans-serif',
      ]) {
        await (FontLoader(family)..addFont(
              File(
                'C:/Windows/Fonts/msyh.ttc',
              ).readAsBytes().then(ByteData.sublistView),
            ))
            .load();
      }
    }
  });
  testWidgets('unrepairable empty artwork settles without a metadata spinner', (
    tester,
  ) async {
    // Artist, podcast and other entities do not have playlist-cover recovery.
    // Exercise the shared row widget directly so a missing image cannot leave
    // an indefinite ticker or accidentally invoke the wrong metadata endpoint.
    var calls = 0;
    final music = Metadata148((_, _) async {
      calls++;
      throw StateError('No metadata endpoint exists for this entity');
    });
    final fixture = await PersonalProfileFixture.create(musicRepository: music);
    addTearDown(fixture.dispose);
    final kinds = NeteaseEntity.values.where(
      (kind) =>
          kind != NeteaseEntity.category && kind != NeteaseEntity.playlist,
    );
    await mount148(
      tester,
      fixture,
      Scaffold(
        body: Column(
          children: [
            for (final kind in kinds)
              NeteaseItemArtwork(
                item: NeteaseItem(id: kind.name, name: kind.name, kind: kind),
              ),
          ],
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('无封面'), findsNWidgets(kinds.length));
    expect(find.byType(MusicActivityIndicator), findsNothing);
    expect(calls, 0);
    for (final artwork in tester.widgetList<ArtworkImage>(
      find.byType(ArtworkImage),
    )) {
      expect(artwork.onLoadFailure, isNull);
      expect(artwork.onRetry, isNull);
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  for (final dark in [false, true]) {
    for (final resize in [false, true]) {
      testWidgets(
        'favorite editor remains above keyboard resize=$resize dark=$dark',
        (tester) async {
          final fixture = await PersonalProfileFixture.create();
          addTearDown(fixture.dispose);
          await mount148(
            tester,
            fixture,
            Scaffold(
              resizeToAvoidBottomInset: resize,
              body: SafeArea(
                child: FavoriteTracksSearch(
                  tracks: fixture.tracks,
                  header: const Text('674 首歌曲'),
                  onRefresh: () async {},
                  onCreatePlaylist: () {},
                ),
              ),
            ),
            dark: dark,
          );
          await tester.tap(find.byTooltip('搜索我的喜欢'));
          await tester.pump();
          tester.view.viewInsets = const FakeViewPadding(bottom: 310);
          tester.view.padding = const FakeViewPadding(top: 24);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          final rect = tester.getRect(find.byType(PlatformCommentComposer));
          expect(rect.bottom, lessThanOrEqualTo(534.1));
          expect(rect.bottom, greaterThan(510));
          await tester.enterText(find.byType(TextField), '673');
          await tester.pump();
          expect(find.text('测试歌曲 673'), findsOneWidget);
          expect(tester.getRect(find.byType(TextField)).bottom, lessThan(534));
          await shot148(tester, 'favorites-keyboard-$resize-$dark');
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
    testWidgets('profile editing names the owning platform dark=$dark', (
      tester,
    ) async {
      final fixture = await PersonalProfileFixture.create(
        extraOverrides: [
          currentMediaItemProvider.overrideWith((_) => Stream.value(null)),
          platformEditableProfileProvider.overrideWith(
            (ref, session) async => const PlatformProfileInfo(
              '测试昵称',
              profileFixtureCover,
              signature: '本地合成账号',
            ),
          ),
        ],
      );
      addTearDown(fixture.dispose);
      await mount148(
        tester,
        fixture,
        const PlatformProfileEditPage(),
        dark: dark,
      );
      final notice = find.textContaining('修改将同步到当前网易云');
      await tester.ensureVisible(notice);
      await tester.pump(const Duration(milliseconds: 350));
      expect(notice, findsOneWidget);
      expect(find.textContaining('当前酷狗账号'), findsNothing);
      await shot148(tester, 'profile-$dark');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
    for (final large in [false, true]) {
      testWidgets(
        'artist compact actions and complete play all large=$large dark=$dark',
        (tester) async {
          final music = _Music148();
          final feed = _Feed148(music);
          final handler = _Queue148();
          addTearDown(() => tester.runAsync(handler.debugDispose));
          final fixture = await PersonalProfileFixture.create(
            audioHandler: handler,
            musicRepository: music,
            extraOverrides: [neteaseFeaturesProvider.overrideWithValue(feed)],
          );
          addTearDown(fixture.dispose);
          await mount148(
            tester,
            fixture,
            const PlatformCatalogDetailPage(
              hit: PlatformSearchHit(
                kind: PlatformSearchKind.artists,
                id: '7',
                title: '歌手样本',
                cover: profileFixtureCover,
              ),
            ),
            dark: dark,
            large: large,
          );
          final navigation = find.byKey(
            const ValueKey('artist-navigation-compact'),
          );
          expect(navigation, findsOneWidget);
          final navRect = tester.getRect(navigation);
          expect(navRect.height, lessThanOrEqualTo(large ? 102 : 52));
          expect(navRect.bottom, lessThan(large ? 430 : 360));
          await shot148(tester, 'artist-$large-$dark');
          await tester.tap(find.byKey(const ValueKey('platform-play-all')));
          for (var i = 0; i < 12; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          expect(music.offsets, contains(30));
          expect(handler.tracks.length, 35);
          expect(handler.tracks.last.id, 'netease_9034');
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
    testWidgets('categories show real representative images dark=$dark', (
      tester,
    ) async {
      final music = _Music148();
      final fixture = await PersonalProfileFixture.create(
        extraOverrides: [
          currentMediaItemProvider.overrideWith((_) => Stream.value(null)),
          neteaseFeaturesProvider.overrideWithValue(_Feed148(music)),
          neteaseArtworkRepositoryProvider.overrideWithValue(_Art148(music)),
        ],
      );
      addTearDown(fixture.dispose);
      await mount148(
        tester,
        fixture,
        const NeteaseFeaturesPage(feed: NeteaseFeed.categories),
        dark: dark,
      );
      await tester.pump();
      await ready146(tester);
      expect(find.byType(NeteaseItemArtwork), findsNWidgets(3));
      expect(find.text('重试'), findsNothing);
      await shot148(tester, 'categories-$dark');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
    testWidgets('heart mode plays all including an unloaded page dark=$dark', (
      tester,
    ) async {
      final music = _Music148();
      final feed = _Feed148(music);
      final handler = _Queue148();
      addTearDown(() => tester.runAsync(handler.debugDispose));
      final fixture = await PersonalProfileFixture.create(
        audioHandler: handler,
        extraOverrides: [neteaseFeaturesProvider.overrideWithValue(feed)],
      );
      addTearDown(fixture.dispose);
      await mount148(
        tester,
        fixture,
        const NeteaseFeaturesPage(feed: NeteaseFeed.intelligence),
        dark: dark,
      );
      expect(feed.pages.first, 1);
      final playRect = tester.getRect(
        find.byKey(const ValueKey('platform-play-all')),
      );
      final download = find
          .ancestor(
            of: find.text('下载已加载歌曲'),
            matching: find.byWidgetPredicate((widget) => widget is TextButton),
          )
          .first;
      final downloadRect = tester.getRect(download);
      expect(downloadRect.left, greaterThanOrEqualTo(playRect.right));
      expect((downloadRect.center.dy - playRect.center.dy).abs(), lessThan(1));
      await shot148(tester, 'heart-$dark');
      await tester.tap(find.byKey(const ValueKey('platform-play-all')));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(feed.pages, [1, 2]);
      expect(handler.tracks.length, 35);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
    testWidgets(
      'Kugou fallback quality menu excludes original NetEase tiers dark=$dark',
      (tester) async {
        final track = quality148();
        final fixture = await PersonalProfileFixture.create(
          extraOverrides: [
            currentTrackProvider.overrideWithValue(track),
            platformPlaybackQualitiesProvider.overrideWith(
              (ref, value) async => VerifiedPlaybackQualities(value, {
                PlatformAudioQuality.high: value,
                PlatformAudioQuality.standard: quality148(code: '128'),
              }, current: () => true),
            ),
          ],
        );
        addTearDown(fixture.dispose);
        await mount148(
          tester,
          fixture,
          Scaffold(
            body: Consumer(
              builder: (context, ref, _) => Center(
                child: TextButton(
                  onPressed: () => showPlatformQualityPicker(context, ref),
                  child: const Text('打开音质'),
                ),
              ),
            ),
          ),
          dark: dark,
        );
        await tester.tap(find.text('打开音质'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.textContaining('酷狗公开音源'), findsOneWidget);
        expect(find.text('高清臻音'), findsNothing);
        expect(find.text('杜比全景声'), findsNothing);
        expect(
          find.byKey(const ValueKey('quality-option-128')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('quality-option-flac')), findsNothing);
        // Data can arrive on the last pump above. Finish both content reveal
        // and AnimatedSize before capturing the actual visible options.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        final option = find.byKey(const ValueKey('quality-option-128'));
        expect(
          tester.getRect(option).bottom,
          lessThan(tester.getRect(find.byType(Dialog)).bottom),
        );
        await shot148(tester, 'quality-$dark');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
