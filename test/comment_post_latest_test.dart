import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
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
import 'package:mesting_music/features/music_platform/netease/netease_api.dart';
import 'package:mesting_music/features/music_platform/netease/netease_comments_repository.dart';
import 'package:mesting_music/features/music_platform/netease/netease_music_repository.dart';
import 'package:mesting_music/features/music_platform/presentation/platform_comment_composer.dart';
import 'package:mesting_music/features/music_platform/presentation/platform_comments_page.dart';
import 'package:mesting_music/shared/widgets/beta_anchored_menu.dart';

class _Server implements MusicServer {
  @override
  Future<Uri> start() async => Uri.parse('http://127.0.0.1:18701');
}

http.Client _noNetwork() =>
    MockClient((_) async => throw StateError('No network'));
MusicPlatformApi _api() =>
    MusicPlatformApi(server: _Server(), client: _noNetwork());
const _who = PlatformSession(userId: 'self', token: 'fixture-only');

class _Account extends PlatformAccountController {
  @override
  Future<PlatformSession?> build() async => _who;
}

const _resource = PlatformCommentResource(
  kind: PlatformCommentKind.song,
  id: '17',
  name: '测试歌曲',
);

class _Feed {
  _Feed({this.failure = false});
  final bool failure;
  bool posted = false;
  int writes = 0;
  final sorts = <PlatformCommentSort>[];
  PlatformCommentPage page(PlatformCommentSort sort) {
    sorts.add(sort);
    return PlatformCommentPage([
      if (posted && sort == PlatformCommentSort.newest)
        PlatformComment(
          id: 'new-own',
          userId: 'self',
          nickname: '我',
          content: '刚刚发送的评论',
          time: DateTime(2026, 11, 11, 12),
        ),
      for (var i = 0; i < 40; i++)
        PlatformComment(
          id: 'old-$i',
          userId: 'other',
          nickname: '其他人',
          content: '原有热门评论 $i',
          likes: 1000 - i,
          specialId: 'hot-cursor',
          time: DateTime(2026, 11, 10).subtract(Duration(minutes: i)),
        ),
    ], false);
  }

  Future<void> send() async {
    writes++;
    if (failure) throw const MusicPlatformException('发送未成功');
    posted = true;
  }
}

class _Kugou extends PlatformCommentsRepository {
  _Kugou(this.feed) : super(_api(), _who);
  final _Feed feed;
  @override
  Future<PlatformCommentPage> load(
    PlatformCommentResource resource, {
    int page = 1,
    PlatformComment? thread,
    String? hottestChildrenId,
  }) async => feed.page(
    hottestChildrenId == null
        ? PlatformCommentSort.newest
        : PlatformCommentSort.hottest,
  );
  @override
  Future<void> send(
    PlatformCommentResource resource,
    String content, {
    PlatformComment? replyTo,
    PlatformComment? thread,
  }) => feed.send();
}

class _Netease extends NeteaseCommentsRepository {
  _Netease(this.feed)
    : super(_api(), _who, NeteaseMusicRepository(NeteaseApi(_noNetwork())));
  final _Feed feed;
  @override
  Future<PlatformCommentPage> loadSorted(
    PlatformCommentResource resource, {
    int page = 1,
    PlatformComment? thread,
    required PlatformCommentSort sort,
  }) async => feed.page(sort);
  @override
  Future<void> send(
    PlatformCommentResource resource,
    String content, {
    PlatformComment? replyTo,
    PlatformComment? thread,
  }) => feed.send();
}

void main() {
  setUpAll(LiquidGlassWidgets.initialize);
  testWidgets(
    'comment rows are prepared fifteen at a time during downward browsing',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repository = _Kugou(_Feed());
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            showPlatformFeaturesProvider.overrideWithValue(true),
            platformAccountProvider.overrideWith(_Account.new),
            sharedPreferencesProvider.overrideWithValue(prefs),
          ],
          child: LiquidGlassWidgets.wrap(
            brightnessResolver: Theme.maybeBrightnessOf,
            adaptiveQuality: false,
            child: MaterialApp(
              home: PlatformCommentsPage(
                repository: repository,
                resource: _resource,
                sourceCurrent: () => true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('comment-reveal-old-14')),
        findsOneWidget,
      );
      final scroll = tester.widget<ListView>(find.byType(ListView)).controller!;
      scroll.jumpTo(1400);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('comment-reveal-old-29')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final netease in [false, true]) {
    for (final failure in [false, true]) {
      testWidgets(
        '${netease ? "网易云" : "酷狗"}发送${failure ? "失败保留最热与草稿" : "成功切最新并回顶部显示本人评论"}',
        (tester) async {
          tester.view.physicalSize = const Size(390, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          SharedPreferences.setMockInitialValues({});
          final preferences = await SharedPreferences.getInstance();
          final feed = _Feed(failure: failure);
          final repository = netease ? _Netease(feed) : _Kugou(feed);
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                showPlatformFeaturesProvider.overrideWithValue(true),
                platformAccountProvider.overrideWith(_Account.new),
                sharedPreferencesProvider.overrideWithValue(preferences),
              ],
              child: LiquidGlassWidgets.wrap(
                brightnessResolver: Theme.maybeBrightnessOf,
                adaptiveQuality: false,
                child: MaterialApp(
                  home: PlatformCommentsPage(
                    repository: repository,
                    resource: _resource,
                    sourceCurrent: () => true,
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          BetaAnchoredMenu<PlatformCommentSort> sort() =>
              tester.widget(find.byType(BetaAnchoredMenu<PlatformCommentSort>));
          expect(sort().value, PlatformCommentSort.hottest);
          await tester.drag(find.byType(ListView), const Offset(0, -420));
          await tester.pumpAndSettle();
          await tester.enterText(find.byType(TextField), '刚刚发送的评论');
          await tester.tap(
            find.byKey(const ValueKey('comment-blue-glass-send')),
          );
          await tester.pumpAndSettle();
          final composer = tester.widget<PlatformCommentComposer>(
            find.byType(PlatformCommentComposer),
          );
          expect(feed.writes, 1);
          if (failure) {
            expect(sort().value, PlatformCommentSort.hottest);
            expect(composer.controller.text, '刚刚发送的评论');
            expect(find.text('已发送'), findsNothing);
          } else {
            expect(sort().value, PlatformCommentSort.newest);
            expect(feed.sorts.last, PlatformCommentSort.newest);
            expect(composer.controller.text, isEmpty);
            expect(find.text('刚刚发送的评论'), findsOneWidget);
            final scroll = tester
                .widget<ListView>(find.byType(ListView))
                .controller!;
            expect(scroll.offset, 0);
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
}
