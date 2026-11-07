import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesting_music/core/audio/playback_providers.dart';
import 'package:mesting_music/features/audiobooks/audiobook_models.dart';
import 'package:mesting_music/features/audiobooks/audiobook_playback.dart';
import 'package:mesting_music/features/audiobooks/audiobook_repository.dart';
import 'package:mesting_music/features/audiobooks/audiobook_resume.dart';
import 'package:mesting_music/features/audiobooks/audiobooks_page.dart';
import 'package:mesting_music/features/kugou_together/together_controller.dart';
import 'package:mesting_music/features/kugou_together/together_models.dart';
import 'package:mesting_music/features/kugou_together/together_page.dart';
import 'package:mesting_music/features/kugou_together/together_repository.dart';
import 'package:mesting_music/features/music_platform/data/embedded_music_server.dart';
import 'package:mesting_music/features/music_platform/data/music_platform_api.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/themes/app_theme.dart';
import 'package:mesting_music/features/themes/music_theme_preset.dart';
import 'package:mesting_music/shared/models/track.dart';
import 'package:mesting_music/shared/widgets/beta_bottom_search.dart';

const _hash = '0123456789abcdef0123456789abcdef';
const _identity = PlatformSession(
  userId: 'synthetic107',
  token: 'fixture-only',
);
const _album = BookAlbum(
  id: '123',
  name: '示例 · 山海故事',
  author: '示例作者',
  intro: '这是一份本地主机界面测试内容，用于检查听书专辑、章节与阅读布局。',
  chapterCount: 80,
);
const _song = TogetherSong(
  hash: _hash,
  mixId: '78',
  title: '示例 · 此刻',
  artist: '示例音乐人',
  duration: Duration(minutes: 4),
);
const _chapter = BookChapter(
  album: _album,
  hash: _hash,
  mixId: '78',
  name: '第一章 · 启程',
  duration: Duration(minutes: 12),
);

class _Server implements MusicServer {
  @override
  Future<Uri> start() async => Uri.parse('http://127.0.0.1:19107');
}

MusicPlatformApi _api(http.Client client) =>
    MusicPlatformApi(server: _Server(), client: client)..session = _identity;
http.Response _response(Object data) => http.Response(
  jsonEncode(data),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

class _Playback implements TogetherPlayback {
  final events = StreamController<String>.broadcast(sync: true);
  Track? track;
  Duration at = Duration.zero;
  bool isPlaying = false;
  int loads = 0, seeks = 0;
  @override
  Track? get current => track;
  @override
  List<Track> get queue => track == null ? [] : [track!];
  @override
  Duration get position => at;
  @override
  bool get playing => isPlaying;
  @override
  Stream<String> get commands => events.stream;
  @override
  Future<void> load(
    TogetherSong song, {
    required bool autoplay,
    required Duration position,
    List<TogetherSong> queue = const [],
  }) async {
    loads++;
    track = song.track;
    at = position;
    isPlaying = autoplay;
    events.add('replaceQueue');
  }

  @override
  Future<void> setPlaying(bool value) async {
    isPlaying = value;
    events.add(value ? 'play' : 'pause');
  }

  @override
  Future<void> seek(Duration value) async {
    seeks++;
    at = value;
    events.add('seek');
  }

  Future<void> dispose() => events.close();
}

class _RoomRepo extends TogetherRepository {
  _RoomRepo() : super(_api(MockClient((_) async => _response({}))), _identity);
  Completer<List<TogetherRoom>>? roomGate;
  int requests = 0, joins = 0, leaves = 0;
  String ownerId = 'other';
  String? addVersion, switchVersion;
  bool failure = false;
  TogetherPlayerSnapshot snapshot = TogetherPlayerSnapshot(
    hash: _hash,
    mixId: '78',
    playing: true,
    position: const Duration(seconds: 15),
    receivedAt: DateTime.now(),
  );
  @override
  Future<List<TogetherRoom>> rooms() async {
    requests++;
    if (failure) throw const MusicPlatformException('示例房间暂未加载');
    return roomGate?.future ?? [];
  }

  @override
  Future<String> currentRoom() async => '';
  @override
  Future<TogetherRoom> detail(String room) async =>
      TogetherRoom(id: room, name: '示例 · 午后一起听', ownerId: ownerId);
  @override
  Future<void> join(String room) async {
    joins++;
  }

  @override
  Future<void> leave(String room, {required bool owner}) async {
    leaves++;
  }

  @override
  Future<List<TogetherSong>> songs(String room) async => [_song];
  @override
  Future<List<TogetherMember>> members(String room) async => const [
    TogetherMember('other', '示例房主', ''),
  ];
  @override
  Future<TogetherPlayerSnapshot> player(String room) async => snapshot;
  @override
  Future<void> heartbeat(String room) async {}
  @override
  Future<void> add(
    String room,
    List<TogetherSong> songs,
    String version,
  ) async {
    addVersion = version;
    snapshot = TogetherPlayerSnapshot(
      hash: snapshot.hash,
      mixId: snapshot.mixId,
      playing: snapshot.playing,
      position: snapshot.position,
      receivedAt: DateTime.now(),
      listVersion: 'after-add',
    );
  }

  @override
  Future<void> switchSong(
    String room,
    TogetherSong song,
    String version,
  ) async {
    switchVersion = version;
    snapshot = TogetherPlayerSnapshot(
      hash: song.hash,
      mixId: song.mixId,
      playing: true,
      position: Duration.zero,
      receivedAt: DateTime.now(),
      listVersion: version,
    );
  }
}

class _Books extends AudiobookRepository {
  _Books() : super(_api(MockClient((_) async => _response({}))), _identity);
  String? lastSearch, category;
  bool fail = false;
  Completer<BookPage<BookAlbum>>? gate;
  @override
  Future<List<BookCategory>> categories({Future<void>? abortTrigger}) async =>
      const [
        BookCategory('906', '有声小说'),
        BookCategory('1097', '玄幻异界'),
        BookCategory('1080', '人文历史'),
      ];
  @override
  Future<BookPage<BookAlbum>> albums({
    String category = '906',
    int page = 1,
    Future<void>? abortTrigger,
  }) async {
    this.category = category;
    if (fail) throw const MusicPlatformException('示例书库暂未加载');
    return gate?.future ??
        const BookPage(
          [
            _album,
            BookAlbum(id: '124', name: '示例 · 城市来信', author: '示例作者二'),
            BookAlbum(id: '125', name: '示例 · 山间日记', author: '示例作者三'),
          ],
          hasMore: false,
          page: 1,
        );
  }

  @override
  Future<BookPage<BookAlbum>> search(
    String query, {
    int page = 1,
    Future<void>? abortTrigger,
  }) async {
    lastSearch = query;
    return const BookPage([_album], hasMore: false, page: 1);
  }

  @override
  Future<BookAlbum> detail(
    BookAlbum initial, {
    Future<void>? abortTrigger,
  }) async => initial;
  @override
  Future<BookPage<BookChapter>> chapters(
    BookAlbum album, {
    int page = 1,
    Future<void>? abortTrigger,
  }) async => const BookPage(
    [
      _chapter,
      BookChapter(
        album: _album,
        hash: _hash,
        mixId: '79',
        name: '第二章 · 雨声',
        duration: Duration(minutes: 14),
      ),
      BookChapter(
        album: _album,
        hash: _hash,
        mixId: '80',
        name: '第三章 · 遇见',
        canPlay: false,
      ),
    ],
    hasMore: false,
    page: 1,
  );
}

class _NoProgress implements AudiobookPlaybackBinding {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const export = bool.fromEnvironment('EXPORT_V107_FEATURES');
  setUpAll(() async {
    await LiquidGlassWidgets.initialize();
    if (export) {
      final bytes = await File('C:/Windows/Fonts/msyh.ttc').readAsBytes();
      for (final family in [
        'Roboto',
        'CupertinoSystemText',
        'CupertinoSystemDisplay',
        'BookQA',
        'Noto Sans SC',
      ]) {
        await (FontLoader(
          family,
        )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
      }
      await (FontLoader('packages/cupertino_icons/CupertinoIcons')..addFont(
            rootBundle.load(
              'packages/cupertino_icons/assets/CupertinoIcons.ttf',
            ),
          ))
          .load();
    }
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'chapter milliseconds and stable identities never confuse recording and album IDs',
    () {
      final short = BookChapter.fromJson({
        'hash': _hash,
        'album_audio_id': 78,
        'duration_ms': 5000,
      }, _album);
      expect(short.duration, const Duration(seconds: 5));
      expect(bookIdentity(short.track)?.albumId, '123');
      expect(bookIdentity(short.track)?.mixId, '78');
      expect(bookIdentity(short.track)?.hash, _hash);
      expect(
        bookIdentity(
          Track.fromJson({
            ...short.track.toJson(),
            'id': 'audiobooks_123_78_https://bad',
          }),
        ),
        isNull,
      );
      expect(
        TogetherSong.fromJson({'hash': _hash, 'timelength': 5000}).duration,
        const Duration(seconds: 5),
      );
    },
  );

  test(
    'book categories/list/search/chapters use actual endpoint identities and pagination',
    () async {
      final requests = <http.Request>[];
      final client = MockClient((req) async {
        requests.add(req);
        if (req.url.path == '/longaudio/tag/list') {
          return _response({
            'data': [
              {
                'tag_id': 906,
                'tag_name': '有声小说',
                'son': [
                  {'tag_id': 1097, 'tag_name': '玄幻'},
                ],
              },
            ],
          });
        }
        if (req.url.path == '/longaudio/album/list') {
          return _response({
            'data': {
              'data_list': [
                {'album_id': 123, 'album_name': '山海'},
              ],
              'is_end': 1,
            },
          });
        }
        if (req.url.path == '/search/audiobook') {
          return _response({
            'data': {
              'lists': [
                {'AlbumID': 123, 'AlbumName': '山海'},
              ],
            },
          });
        }
        return _response({
          'data': {
            'audios': [
              {
                'album_audio_id': 78,
                'hash': _hash,
                'audio_name': '启程',
                'duration': 12,
              },
            ],
          },
        });
      });
      addTearDown(client.close);
      final repo = AudiobookRepository(_api(client), _identity);
      expect((await repo.categories()).map((c) => c.id), ['906', '1097']);
      expect((await repo.albums(category: '1097', page: 3)).hasMore, isFalse);
      expect((await repo.search('山海', page: 2)).items.single.id, '123');
      expect((await repo.chapters(_album, page: 4)).items.single.mixId, '78');
      expect(requests[1].url.queryParameters, containsPair('tag_id', '1097'));
      expect(requests[1].url.queryParameters, containsPair('page', '3'));
      expect(requests[1].url.queryParameters, containsPair('free', '1'));
      expect(requests[2].url.queryParameters, containsPair('keyword', '山海'));
      expect(
        requests.last.url.queryParameters,
        containsPair('album_id', '123'),
      );
      expect(requests.last.url.queryParameters, containsPair('pagesize', '50'));
    },
  );

  test(
    'book resolver blocks paid/preview chapter and rejects switched identity',
    () async {
      var preview = true;
      final client = MockClient((req) async {
        if (req.url.path == '/register/dev') {
          return _response({
            'data': {'dfid': 'synthetic-device'},
          });
        }
        return _response({
          'data': {
            'url': 'https://media.example.invalid/book.mp3',
            'priv_status': 1,
            'is_preview': preview ? 1 : 0,
          },
        });
      });
      addTearDown(client.close);
      final api = _api(client),
          repo = AudiobookRepository(
            _api(MockClient((_) async => _response({}))),
            _identity,
          );
      final actual = AudiobookRepository(api, _identity);
      await expectLater(
        actual.resolve(_chapter.track),
        throwsA(isA<MusicPlatformException>()),
      );
      preview = false;
      expect(
        (await actual.resolve(_chapter.track)).audioAsset,
        'https://media.example.invalid/book.mp3',
      );
      api.session = const PlatformSession(
        userId: 'different',
        token: 'different',
      );
      await expectLater(
        actual.albums(),
        throwsA(isA<MusicPlatformException>()),
      );
      expect(repo.identity?.userId, _identity.userId);
    },
  );

  test(
    'resume snapshots isolate accounts and remove signed chapter URLs',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final a = AudiobookResumeStore(prefs, 'one'),
          b = AudiobookResumeStore(prefs, 'two');
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      await a.save(
        BookResume(
          album: _album,
          track: _chapter.track.copyWith(
            audioAsset: 'https://private.invalid/expiring?token=synthetic',
          ),
          position: const Duration(seconds: 39),
          updatedAt: DateTime(2026, 10, 28),
          chapterPage: 3,
          nextPage: 4,
          hasMore: true,
        ),
      );
      expect(b.entries, isEmpty);
      final restored = AudiobookResumeStore(prefs, 'one');
      addTearDown(restored.dispose);
      expect(restored.forAlbum('123')?.position, const Duration(seconds: 39));
      expect(restored.forAlbum('123')?.chapterPage, 3);
      expect(prefs.getString(a.key), isNot(contains('private.invalid')));
      expect(
        restored.entries.single.track.audioAsset,
        startsWith('mesting-audiobook:'),
      );
    },
  );

  test(
    'room writes bind current account and use seconds plus explicit pause values',
    () async {
      final requests = <http.Request>[];
      final client = MockClient((req) async {
        requests.add(req);
        return _response({'status': 1, 'data': {}});
      });
      addTearDown(client.close);
      final api = _api(client),
          repo = TogetherRepository(
            _api(MockClient((_) async => _response({}))),
            _identity,
          );
      final actual = TogetherRepository(api, _identity);
      await actual.seek('room-7', const Duration(milliseconds: 12900));
      await actual.playing('room-7', true);
      await actual.playing('room-7', false);
      final seek = jsonDecode(requests[0].body) as Map;
      expect(seek['operation'], 'player_operation');
      expect(seek['action'], 2);
      expect(seek['progress'], 12);
      expect(seek['room_id'], 'room-7');
      expect(seek['biz'], 1009);
      expect((jsonDecode(requests[1].body) as Map)['pause'], 1);
      expect((jsonDecode(requests[2].body) as Map)['pause'], 2);
      api.session = const PlatformSession(userId: 'other', token: 'other');
      await expectLater(
        actual.playing('room-7', true),
        throwsA(isA<MusicPlatformException>()),
      );
      expect(requests, hasLength(3));
      expect(repo.identity.userId, _identity.userId);
    },
  );

  test(
    'follower sync uses host time, preserves manual pause and cancels on leave',
    () async {
      final playback = _Playback(), repo = _RoomRepo();
      final controller = TogetherController(repo, playback);
      expect(await controller.join('room-7'), isTrue);
      expect(playback.loads, 1);
      expect(playback.playing, isTrue);
      expect(controller.detached, isFalse);
      await playback.setPlaying(false);
      expect(controller.detached, isTrue);
      await controller.refresh();
      expect(playback.playing, isFalse);
      await controller.follow();
      expect(playback.playing, isTrue);
      expect(playback.seeks, greaterThanOrEqualTo(1));
      expect(await controller.leave(), isTrue);
      expect(controller.active, isFalse);
      expect(repo.leaves, 1);
      controller.dispose();
      await playback.dispose();
    },
  );

  test(
    'late room-list response cannot publish after disposal; invitation parsing is bounded',
    () async {
      final playback = _Playback(),
          repo = _RoomRepo()..roomGate = Completer<List<TogetherRoom>>();
      final controller = TogetherController(repo, playback);
      var notifications = 0;
      controller.addListener(() => notifications++);
      final pending = controller.loadRooms();
      controller.dispose();
      repo.roomGate!.complete(const [TogetherRoom(id: 'room-7', name: '示例')]);
      await pending;
      expect(controller.rooms, isEmpty);
      expect(notifications, 1);
      expect(
        parseTogetherRoomId('https://example.invalid/invite?room_id=room-7'),
        'room-7',
      );
      expect(parseTogetherRoomId('来一起听，房间号：room-7'), 'room-7');
      expect(parseTogetherRoomId('invalid room id'), isEmpty);
      await playback.dispose();
    },
  );

  test(
    'host refreshes playlist version between adding and switching a new song',
    () async {
      final playback = _Playback();
      final repo = _RoomRepo()..ownerId = _identity.userId;
      final controller = TogetherController(repo, playback);
      expect(await controller.join('room-host'), isTrue);
      playback.track = const TogetherSong(
        hash: 'fedcba9876543210fedcba9876543210',
        mixId: '79',
        title: '下一首示例',
      ).track;
      await controller.refresh();
      expect(repo.switchVersion, 'after-add');
      expect(controller.error, isNull);
      controller.dispose();
      await playback.dispose();
    },
  );

  Future<void> mount(
    WidgetTester tester,
    Widget page, {
    _Books? books,
    TogetherController? together,
    bool dark = false,
    double width = 390,
    double scale = 1,
  }) async {
    // Each fixture owns its provider container; swapping from books to a room
    // must not mutate an existing ProviderScope's override list.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    tester.view.physicalSize = Size(width, width > 700 ? 1024 : 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final prefs = await SharedPreferences.getInstance();
    final store = AudiobookResumeStore(prefs, 'synthetic');
    addTearDown(store.dispose);
    var theme = buildMestingTheme(
      musicThemePresetById(dark ? 'classic-dark' : 'classic'),
    );
    if (export) {
      theme = theme.copyWith(
        textTheme: theme.textTheme.apply(fontFamily: 'BookQA'),
        // ListTile's explicit subtitle style bypasses textTheme in host tests.
        // Use the same QA-only CJK font; production theme/fonts are untouched.
        listTileTheme: theme.listTileTheme.copyWith(
          titleTextStyle: theme.listTileTheme.titleTextStyle?.copyWith(
            fontFamily: 'BookQA',
          ),
          subtitleTextStyle: theme.listTileTheme.subtitleTextStyle?.copyWith(
            fontFamily: 'BookQA',
          ),
        ),
      );
    }
    await tester.pumpWidget(
      LiquidGlassWidgets.wrap(
        adaptiveQuality: false,
        brightnessResolver: Theme.maybeBrightnessOf,
        child: ProviderScope(
          overrides: [
            audiobookRepositoryProvider.overrideWithValue(books ?? _Books()),
            audiobookResumeStoreProvider.overrideWithValue(store),
            audiobookProgressBindingProvider.overrideWithValue(_NoProgress()),
            currentMediaItemProvider.overrideWith((ref) => Stream.value(null)),
            if (together != null)
              togetherControllerProvider.overrideWithValue(together),
          ],
          child: RepaintBoundary(
            key: const ValueKey('features-capture'),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: theme,
              locale: const Locale('zh', 'CN'),
              supportedLocales: const [Locale('zh', 'CN')],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: page,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> capture(WidgetTester tester, String name) async {
    if (!export) return;
    await tester.runAsync(() async {
      final image = await tester
          .renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('features-capture')),
          )
          .toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final dir = Directory(
        const String.fromEnvironment('V107_FEATURES_SCREENSHOT_DIR'),
      );
      await dir.create(recursive: true);
      await File(
        '${dir.path}/$name.png',
      ).writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets(
    'book category, search and chapter failures render without side effects',
    (tester) async {
      final books = _Books();
      await mount(tester, const AudiobooksPage(), books: books);
      expect(find.text('示例 · 山海故事'), findsOneWidget);
      expect(find.text('有声小说'), findsOneWidget);
      await tester.tap(find.text('玄幻异界'));
      await tester.pumpAndSettle();
      expect(books.category, '1097');
      // This fixture isolates book business states. The shared glass field's
      // real input/keyboard flow is covered by search_menu_fm_regression_test.
      final search = tester
          .widget<BetaBottomSearchBinding>(find.byType(BetaBottomSearchBinding))
          .controller;
      search.text.text = '山海';
      search.submit('山海');
      await tester.pumpAndSettle();
      expect(books.lastSearch, '山海');
      books.fail = true;
      await tester.tap(find.text('返回书库'));
      await tester.pumpAndSettle();
      expect(find.text('示例书库暂未加载'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'room lobby exposes actionable failure and retry; guest has login path',
    (tester) async {
      final playback = _Playback(), repo = _RoomRepo()..failure = true;
      final controller = TogetherController(repo, playback);
      await mount(tester, const TogetherPage(), together: controller);
      expect(find.text('示例房间暂未加载'), findsOneWidget);
      expect(find.text('创建房间'), findsOneWidget);
      repo.failure = false;
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(find.text('暂时没有可加入的房间，你可以创建一个私密房间。'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      await playback.dispose();
      final guestPlayback = _Playback(),
          guest = TogetherController(null, guestPlayback);
      await mount(tester, const TogetherPage(), together: guest);
      expect(find.text('登录酷狗账号'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      guest.dispose();
      await guestPlayback.dispose();
    },
  );

  for (final config in [
    (false, 390.0, 1.0, 'light'),
    (true, 390.0, 1.0, 'dark'),
    (false, 320.0, 1.6, 'small-large-text'),
    (true, 768.0, 1.0, 'tablet'),
  ]) {
    testWidgets('book and together surfaces ${config.$4}', (tester) async {
      await mount(
        tester,
        const AudiobooksPage(),
        dark: config.$1,
        width: config.$2,
        scale: config.$3,
      );
      expect(tester.takeException(), isNull);
      await capture(tester, 'books-${config.$4}');
      await mount(
        tester,
        const AudiobookAlbumPage(album: _album),
        dark: config.$1,
        width: config.$2,
        scale: config.$3,
      );
      expect(find.text('第一章 · 启程'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await capture(tester, 'chapters-${config.$4}');
      final playback = _Playback();
      final controller = TogetherController(
        config.$4 == 'light' || config.$4 == 'small-large-text'
            ? null
            : _RoomRepo(),
        playback,
      );
      if (controller.signedIn) {
        controller.room = const TogetherRoom(
          id: 'synthetic-room-107',
          name: '示例 · 午后一起听',
        );
        controller.songs = const [_song];
        controller.detached = true;
        controller.lastSync = DateTime(2026, 10, 28, 12);
      }
      await mount(
        tester,
        const TogetherPage(),
        together: controller,
        dark: config.$1,
        width: config.$2,
        scale: config.$3,
      );
      expect(tester.takeException(), isNull);
      await capture(tester, 'together-${config.$4}');
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      await playback.dispose();
    });
  }
}
