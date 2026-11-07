import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/core/audio/playback_providers.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_api.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_models.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_playlist_batch_page.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_playlist_page.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_providers.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_repository.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_session.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_pages.dart';
import 'package:mesting_music/features/experience/presentation/beta_bottom_bar.dart';
import 'package:mesting_music/shared/models/track.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/release_147_qa.dart' show load147IconFonts;

const _capture = bool.fromEnvironment('CAPTURE_QISHUI_PLAYLIST167');
const _boundary = ValueKey('qishui-playlist167-capture');
final _session = QishuiSession(
  userId: 'fixture-owner',
  cookies: [
    {
      'name': 'sessionid',
      'value': 'host-fixture-not-a-real-credential',
      'domain': 'api.qishui.com',
      'path': '/',
    },
  ],
  protocol: QishuiSessionProtocol.web,
);
const _playlist = QishuiPlaylist(
  'fixture-playlist',
  '我喜欢的',
  '',
  kind: 1,
  count: 18,
  ownerId: 'fixture-owner',
  ownerName: '界面测试账号',
  description: '此处仅显示接口实际返回的歌单简介。',
  isPrivate: false,
  likeCount: 12,
  commentCount: 5,
  shareCount: 3,
);

List<Track> _songs() => List.generate(
  18,
  (index) => Track(
    id: 'qishui_fixture-$index',
    platformSongId: 'fixture-$index',
    title: index == 0 ? 'All Time Low' : '歌单测试歌曲 $index',
    artist: index == 0 ? 'Enjoy My Life' : '测试歌手',
    album: '测试专辑',
    duration: const Duration(minutes: 3),
    audioAsset: 'mesting-platform://qishui/fixture-$index',
    coverAsset: '',
    lyricsAsset: '',
    source: TrackSource.qishui,
  ),
);

class _Account extends PlatformAccountController {
  @override
  Future<PlatformSession?> build() async => _session.identity;
  void switchAway() => state = const AsyncData(null);
}

/// The fixture overrides every method exercised below. No network, signer,
/// device, real account or persisted write journal participates in these tests.
class _PlaylistFixture extends QishuiRepository {
  _PlaylistFixture(super.api);
  final writes = <String>[];
  var values = _songs();
  Completer<void>? pendingOrder;

  @override
  Future<Map<String, dynamic>> profile() async => {
    'my_info': {'nickname': '界面测试账号'},
  };

  @override
  Future<List<Track>> playlist(
    String id, {
    String cursor = '',
    Future<void>? abortTrigger,
  }) async => List.of(values);

  @override
  Future<List<QishuiPlaylist>> playlists({Future<void>? abortTrigger}) async =>
      [
        _playlist,
        const QishuiPlaylist(
          'fixture-target',
          '另一个测试歌单',
          '',
          ownerId: 'fixture-owner',
          ownerName: '界面测试账号',
        ),
      ];

  @override
  Future<void> reorderPlaylist(String id, List<Track> ordered) async {
    writes.add('order:$id');
    await pendingOrder?.future;
    values = List.of(ordered);
  }

  @override
  Future<void> removePlaylistTracks(String id, List<Track> tracks) async {
    writes.add('remove:$id:${tracks.length}');
    final ids = tracks.map((track) => track.id).toSet();
    values = values.where((track) => !ids.contains(track.id)).toList();
  }

  @override
  Future<void> addPlaylistTracks(String id, List<Track> tracks) async {
    writes.add('add:$id:${tracks.length}');
  }
}

void main() {
  setUpAll(() async {
    await LiquidGlassWidgets.initialize();
    if (!_capture) return;
    await load147IconFonts();
    for (final name in [
      'QishuiPlaylistQA',
      'Roboto',
      'CupertinoSystemText',
      'CupertinoSystemDisplay',
    ]) {
      await (FontLoader(name)..addFont(
            File(
              'C:/Windows/Fonts/msyh.ttc',
            ).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
    }
  });

  Future<(ProviderContainer, _PlaylistFixture)> mount(
    WidgetTester tester,
    Widget page, {
    Size size = const Size(390, 844),
    double scale = 1,
    bool pushed = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = QishuiApi(
      MockClient((_) => throw StateError('No fixture should perform HTTP')),
    )..configure(_session);
    SharedPreferences.setMockInitialValues({
      'beta_active_account_v2': 'qishui',
    });
    final preferences = await SharedPreferences.getInstance();
    final repository = _PlaylistFixture(api);
    final container = ProviderContainer(
      overrides: [
        platformAccountProvider.overrideWith(_Account.new),
        qishuiApiProvider.overrideWithValue(api),
        qishuiRepositoryProvider.overrideWithValue(repository),
        sharedPreferencesProvider.overrideWithValue(preferences),
        currentMediaItemProvider.overrideWith(
          (_) => Stream<MediaItem?>.value(null),
        ),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(api.dispose);
    await container.read(platformAccountProvider.future);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: LiquidGlassWidgets.wrap(
          adaptiveQuality: false,
          child: MaterialApp(
            theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xffef4261),
                brightness: Brightness.dark,
              ),
              fontFamily: _capture ? 'QishuiPlaylistQA' : null,
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(scale),
                padding: const EdgeInsets.only(top: 28, bottom: 24),
                viewPadding: const EdgeInsets.only(top: 28, bottom: 24),
              ),
              child: RepaintBoundary(key: _boundary, child: child!),
            ),
            home: pushed
                ? Scaffold(
                    body: Builder(
                      builder: (context) => Center(
                        child: TextButton(
                          onPressed: () => Navigator.of(
                            context,
                          ).push<bool>(MaterialPageRoute(builder: (_) => page)),
                          child: const Text('打开测试页面'),
                        ),
                      ),
                    ),
                  )
                : page,
          ),
        ),
      ),
    );
    if (pushed) {
      await tester.tap(find.text('打开测试页面'));
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    return (container, repository);
  }

  Future<void> shot(WidgetTester tester, String name) async {
    if (!_capture) return;
    final frame = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_boundary),
    );
    await tester.runAsync(() async {
      final image = await frame.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File(
        '.codex-artifacts/2026-11-06-release167/ui-final/$name.png',
      );
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  for (final spec in const [(390.0, 1.0), (320.0, 1.8)]) {
    final width = spec.$1;
    final scale = spec.$2;
    testWidgets('playlist detail and root drawer $width/$scale', (
      tester,
    ) async {
      final (_, repository) = await mount(
        tester,
        const QishuiPlaylistPage(playlist: _playlist, owned: true),
        size: Size(width, 844),
        scale: scale,
      );
      expect(find.text('我喜欢的'), findsOneWidget);
      expect(find.text('18 首歌曲 · 公开歌单'), findsOneWidget);
      expect(
        tester
            .widget<BetaMusicBottomBar>(find.byType(BetaMusicBottomBar))
            .selectedIndex,
        3,
      );
      expect(tester.takeException(), isNull);
      await shot(tester, 'playlist-detail-${width.toInt()}-$scale');
      await tester.scrollUntilVisible(
        find.text('All Time Low'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('All Time Low').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await shot(tester, 'playlist-detail-list-${width.toInt()}-$scale');
      await tester.tap(find.byTooltip('歌单菜单'));
      await tester.pumpAndSettle();
      expect(find.text('添加歌曲'), findsOneWidget);
      expect(find.text('批量管理歌曲'), findsOneWidget);
      expect(find.text('下载歌单内歌曲'), findsOneWidget);
      final privacy = find.text('设置歌单隐私');
      await tester.ensureVisible(privacy);
      await tester.pumpAndSettle();
      expect(privacy.hitTestable(), findsOneWidget);
      expect(tester.getBottomRight(privacy).dy, lessThan(844 - 24));
      expect(tester.takeException(), isNull);
      expect(repository.writes, isEmpty);
      await shot(tester, 'playlist-drawer-${width.toInt()}-$scale');
      await tester.tap(privacy);
      await tester.pumpAndSettle();
      expect(find.text('仅自己可见'), findsOneWidget);
      expect(find.text('公开歌单'), findsOneWidget);
      expect(repository.writes, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('batch safe area and cancelled removal $width/$scale', (
      tester,
    ) async {
      final (_, repository) = await mount(
        tester,
        QishuiPlaylistBatchPage(
          playlist: _playlist,
          tracks: _songs(),
          owned: true,
        ),
        size: Size(width, 844),
        scale: scale,
      );
      await tester.tap(find.text('全选'));
      await tester.pumpAndSettle();
      expect(find.text('已选择 18 首'), findsOneWidget);
      expect(tester.getTopLeft(find.text('批量管理')).dy, greaterThanOrEqualTo(28));
      expect(find.text('取消全选').hitTestable(), findsOneWidget);
      for (final label in ['添加到歌单', '下载歌曲', '批量删除']) {
        final target = find.text(label);
        expect(target.hitTestable(), findsOneWidget);
        expect(tester.getBottomRight(target).dy, lessThan(844 - 24));
      }
      expect(tester.takeException(), isNull);
      await shot(tester, 'playlist-batch-${width.toInt()}-$scale');
      await tester.tap(find.text('批量删除'));
      await tester.pumpAndSettle();
      expect(find.text('从汽水歌单移除 18 首歌曲？'), findsOneWidget);
      expect(repository.writes, isEmpty);
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('取消'),
        ),
      );
      await tester.pumpAndSettle();
      expect(repository.writes, isEmpty);
      expect(find.text('已选择 18 首'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('batch confirms one removal and refreshes server membership', (
    tester,
  ) async {
    final (_, repository) = await mount(
      tester,
      QishuiPlaylistBatchPage(
        playlist: _playlist,
        tracks: _songs(),
        owned: true,
      ),
    );
    await tester.tap(find.text('All Time Low'));
    await tester.pump();
    await tester.tap(find.text('批量删除'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认移除'));
    await tester.pumpAndSettle();
    expect(repository.writes, ['remove:fixture-playlist:1']);
    expect(find.text('All Time Low'), findsNothing);
    expect(find.text('已选择 0 首'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('batch drafts order and ignores repeated Done while submitting', (
    tester,
  ) async {
    final (_, repository) = await mount(
      tester,
      QishuiPlaylistBatchPage(
        playlist: _playlist,
        tracks: _songs(),
        owned: true,
      ),
      pushed: true,
    );
    final list = tester.widget<ReorderableListView>(
      find.byType(ReorderableListView),
    );
    list.onReorder(0, 3);
    await tester.pump();
    expect(repository.writes, isEmpty);
    repository.pendingOrder = Completer<void>();
    await tester.tap(find.text('完成'));
    await tester.pump();
    await tester.tap(find.text('完成'));
    await tester.pump();
    expect(repository.writes, ['order:fixture-playlist']);
    repository.pendingOrder!.complete();
    await tester.pumpAndSettle();
    expect(find.text('打开测试页面'), findsOneWidget);
    expect(repository.values.first.platformSongId, 'fixture-1');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('switching account hides private songs and prevents writes', (
    tester,
  ) async {
    final (container, repository) = await mount(
      tester,
      QishuiPlaylistBatchPage(
        playlist: _playlist,
        tracks: _songs(),
        owned: true,
      ),
    );
    await tester.tap(find.text('全选'));
    await tester.pump();
    (container.read(platformAccountProvider.notifier) as _Account).switchAway();
    await tester.pump();
    expect(find.text('账号已变化'), findsOneWidget);
    expect(find.text('All Time Low'), findsNothing);
    expect(find.text('批量删除'), findsNothing);
    expect(repository.writes, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('switching account also hides metadata in an open root drawer', (
    tester,
  ) async {
    final (container, repository) = await mount(
      tester,
      const QishuiPlaylistPage(playlist: _playlist, owned: true),
    );
    await tester.tap(find.byTooltip('歌单菜单'));
    await tester.pumpAndSettle();
    expect(find.text('添加歌曲'), findsOneWidget);
    (container.read(platformAccountProvider.notifier) as _Account).switchAway();
    await tester.pump();
    expect(find.text('账号已变化，请关闭后重新操作'), findsOneWidget);
    expect(find.text('界面测试账号 · 18 首'), findsNothing);
    expect(find.text('添加歌曲'), findsNothing);
    expect(repository.writes, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Mine opens favorites with Mine still selected', (tester) async {
    await mount(tester, const QishuiRootPage(QishuiRoot.mine));
    await tester.tap(find.text('我喜欢的').hitTestable());
    await tester.pumpAndSettle();
    expect(find.byType(QishuiPlaylistPage), findsOneWidget);
    final bar = tester.widget<BetaMusicBottomBar>(
      find.byType(BetaMusicBottomBar),
    );
    expect(bar.soda, isTrue);
    expect(bar.selectedIndex, 3);
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.byType(QishuiRootPage), findsOneWidget);
    expect(find.text('创建的歌单'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
