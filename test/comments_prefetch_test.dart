import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/features/auth/account_capabilities.dart';
import 'package:mesting_music/features/music_platform/data/embedded_music_server.dart';
import 'package:mesting_music/features/music_platform/data/music_platform_api.dart';
import 'package:mesting_music/features/music_platform/data/platform_comments_repository.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/music_platform/netease/netease_comments_repository.dart';
import 'package:mesting_music/features/music_platform/netease/netease_music_repository.dart';
import 'package:mesting_music/features/music_platform/netease/netease_api.dart';
import 'package:mesting_music/features/music_platform/presentation/platform_comments_page.dart';

const who = PlatformSession(userId: 'comment-fixture', token: 'fixture-only');
const resource = PlatformCommentResource(
  kind: PlatformCommentKind.song,
  id: '17',
  name: '分页测试',
);

class _Account extends PlatformAccountController {
  @override
  Future<PlatformSession?> build() async => who;
}

class _Server implements MusicServer {
  @override
  Future<Uri> start() async => Uri.parse('http://127.0.0.1:18709');
}

MusicPlatformApi api() => MusicPlatformApi(
  server: _Server(),
  client: MockClient((_) async => throw StateError('No network')),
);

class _Pages extends PlatformCommentsRepository {
  _Pages({this.short = false, this.fail = false}) : super(api(), who);
  final bool short, fail;
  final calls = <int>[];
  final pending = Completer<PlatformCommentPage>();
  PlatformCommentPage page(int page) => PlatformCommentPage([
    for (var i = 0; i < (short ? 2 : platformCommentPageSize); i++)
      PlatformComment(
        id: '${page}_$i',
        userId: 'reader',
        nickname: '读者',
        content: '分页评论 $page/$i',
        likes: 10000 - page * 30 - i,
      ),
  ], true);
  @override
  Future<PlatformCommentPage> load(
    PlatformCommentResource resource, {
    int page = 1,
    PlatformComment? thread,
    String? hottestChildrenId,
  }) async {
    calls.add(page);
    if (page == 1 || short) return this.page(page);
    if (fail) throw const MusicPlatformException('临时网络错误');
    return pending.future;
  }
}

class _Netease extends NeteaseMusicRepository {
  _Netease()
    : super(
        NeteaseApi(MockClient((_) async => throw StateError('No network'))),
      );
  final queries = <Map<String, Object?>>[];
  @override
  Future<Map<String, dynamic>> call(
    String path, [
    Map<String, Object?> query = const {},
    Future<void>? abort,
  ]) async {
    queries.add(query);
    return {
      'data': {'comments': [], 'hasMore': false},
    };
  }
}

Future<ScrollController> _mount(WidgetTester tester, _Pages pages) async {
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        showPlatformFeaturesProvider.overrideWithValue(true),
        platformAccountProvider.overrideWith(_Account.new),
        sharedPreferencesProvider.overrideWithValue(preferences),
      ],
      child: MaterialApp(
        home: PlatformCommentsPage(
          resource: resource,
          repository: pages,
          sourceCurrent: () => true,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return tester.widget<ListView>(find.byType(ListView).first).controller!;
}

void main() {
  setUpAll(LiquidGlassWidgets.initialize);
  test(
    'NetEase song pages and replies explicitly request 30 comments',
    () async {
      final music = _Netease();
      final repository = NeteaseCommentsRepository(api(), who, music);
      await repository.loadSorted(resource, sort: PlatformCommentSort.hottest);
      await repository.loadSorted(
        resource,
        page: 2,
        sort: PlatformCommentSort.newest,
      );
      await repository.loadSorted(
        resource,
        thread: const PlatformComment(
          id: 'parent',
          userId: 'u',
          nickname: 'u',
          content: '',
        ),
        sort: PlatformCommentSort.newest,
      );
      expect(music.queries.map((q) => q['pageSize']), [30, 30, 30]);
    },
  );
  testWidgets(
    'scrolling a few comments uses the existing batch, next page prefetches once and preserves position',
    (tester) async {
      final pages = _Pages();
      final scroll = await _mount(tester, pages);
      expect(pages.calls, [1]);
      scroll.jumpTo(200);
      await tester.pump();
      expect(pages.calls, [1]);
      scroll.jumpTo(scroll.position.maxScrollExtent - 500);
      await tester.pump();
      expect(pages.calls, [1, 2]);
      for (var i = 0; i < 5; i++) {
        // Grouped variable-height rows refine the sliver extent as they mount.
        // Keep synthetic jumps inside the actual scroll range, as a gesture is.
        scroll.jumpTo(
          (scroll.offset + 1).clamp(0, scroll.position.maxScrollExtent),
        );
        await tester.pump();
      }
      expect(pages.calls, [1, 2]);
      final position = scroll.offset;
      pages.pending.complete(pages.page(2));
      await tester.pumpAndSettle();
      expect(scroll.offset, closeTo(position, .01));
      expect(pages.calls, [1, 2]);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('upstream short pages have bounded background top-ups', (
    tester,
  ) async {
    final pages = _Pages(short: true);
    await _mount(tester, pages);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(pages.calls.length, greaterThan(1));
    expect(pages.calls.length, lessThanOrEqualTo(4));
    final count = pages.calls.length;
    await tester.pump(const Duration(seconds: 2));
    expect(pages.calls.length, count);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'prefetch failure keeps existing rows and does not retry on every scroll',
    (tester) async {
      final pages = _Pages(fail: true);
      final scroll = await _mount(tester, pages);
      scroll.jumpTo(scroll.position.maxScrollExtent - 500);
      await tester.pumpAndSettle();
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(find.text('加载失败，点击重试'), findsOneWidget);
      final count = pages.calls.length;
      scroll.jumpTo(scroll.offset - 20);
      await tester.pumpAndSettle();
      expect(pages.calls.length, count);
      expect(
        find.byKey(const ValueKey('comments-initial-loading')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
