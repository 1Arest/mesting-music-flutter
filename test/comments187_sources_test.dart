import 'package:mesting_music/shared/widgets/beta_swipe_pages.dart';
import 'package:mesting_music/shared/widgets/beta_glass_controls.dart';
import 'package:mesting_music/features/music_platform/presentation/platform_design.dart';
import 'package:mesting_music/features/music_platform/presentation/platform_comments_page.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesting_music/features/auth/account_capabilities.dart';
import 'package:mesting_music/features/music_platform/data/embedded_music_server.dart';
import 'package:mesting_music/features/music_platform/data/music_platform_api.dart';
import 'package:mesting_music/features/music_platform/data/platform_comments_repository.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/music_platform/presentation/source_comments_page.dart';
import 'package:mesting_music/features/music_platform/presentation/source_login_prompt.dart';
import 'package:mesting_music/features/music_platform/source_media_scope.dart';
import 'package:flutter/cupertino.dart';
import 'package:mesting_music/shared/models/track.dart';
import 'search184_fusion_test.dart' show song;

class _Server implements MusicServer {
  @override
  Future<Uri> start() async => Uri.parse('http://127.0.0.1:18700');
}

class _UI extends PlatformAccountController {
  @override
  Future<PlatformSession?> build() async => const PlatformSession(
    userId: 'ui-net',
    token: 'ui-token',
    platform: MusicPlatform.netease,
  );
}

MusicPlatformApi _api() => MusicPlatformApi(
  server: _Server(),
  client: MockClient((_) async => throw StateError('No live calls')),
);

class _Comments extends PlatformCommentsRepository {
  _Comments(PlatformSession who, this.text, {super.readOnly})
    : super(_api(), who);
  final String text;
  int reads = 0;
  @override
  Future<PlatformCommentPage> load(
    PlatformCommentResource resource, {
    int page = 1,
    PlatformComment? thread,
    String? hottestChildrenId,
  }) async {
    reads++;
    return PlatformCommentPage(
      text.isEmpty
          ? []
          : [
              for (var row = 0; row < 40; row++)
                PlatformComment(
                  id: '${identity.platform.name}-comment-$row',
                  userId: 'author',
                  nickname: '作者',
                  content: row == 0 ? text : '$text $row',
                  likes: 40 - row,
                  time: DateTime.utc(
                    2026,
                    11,
                    10,
                  ).subtract(Duration(minutes: row)),
                ),
            ],
      false,
      total: text.isEmpty ? 0 : 40,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'anonymous MV reads use video ID, not audio IDs; anonymous writes cannot reach transport',
    () async {
      final requests = <http.Request>[];
      final api = MusicPlatformApi(
        server: _Server(),
        client: MockClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode({
              'status': 1,
              'data': {
                'list': [
                  {'id': 'c1', 'content': 'MV评论', 'nickname': '用户'},
                ],
                'total': 1,
              },
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      final repo = PlatformCommentsRepository(
        api,
        const PlatformSession(userId: '', token: ''),
        readOnly: true,
      );
      const resource = PlatformCommentResource(
        kind: PlatformCommentKind.mv,
        id: 'real-video-id',
        name: '作品MV',
        hash: 'video-hash',
      );
      final page = await repo.load(resource);
      expect(page.comments.single.content, 'MV评论');
      expect(requests.single.url.path, '/video/barrage');
      expect(requests.single.url.queryParameters['video_id'], 'real-video-id');
      expect(
        requests.single.url.queryParameters.containsKey('mixsongid'),
        false,
      );
      expect(api.session, isNull);
      await expectLater(
        repo.send(resource, 'test'),
        throwsA(isA<MusicPlatformException>()),
      );
      expect(requests, hasLength(1));
    },
  );
  for (final guest in [false, true]) {
    testWidgets(
      'actual Kugou source opens under NetEase UI, both comment tabs stay independent guest=$guest',
      (tester) async {
        final n = song('netease_701', TrackSource.netease),
            k = song('kugou_hash', TrackSource.kugou);
        final nr = SourceCommentRequest(n), kr = SourceCommentRequest(k);
        final ne = _Comments(
          const PlatformSession(
            userId: 'net-source',
            token: 'ne-fake',
            platform: MusicPlatform.netease,
          ),
          '网易云实际评论',
        );
        final kg = _Comments(
          PlatformSession(
            userId: guest ? '' : 'kg-source',
            token: guest ? '' : 'kg-fake',
          ),
          '酷狗实际评论',
          readOnly: guest,
        );
        final container = ProviderContainer(
          overrides: [
            platformAccountProvider.overrideWith(_UI.new),
            showPlatformFeaturesProvider.overrideWithValue(true),
            sourceCommentBindingProvider(nr).overrideWith(
              (ref) async => SourceCommentBinding(
                ne,
                const PlatformCommentResource(
                  kind: PlatformCommentKind.song,
                  id: '701',
                  name: '晴天',
                ),
                () => true,
              ),
            ),
            sourceCommentBindingProvider(kr).overrideWith(
              (ref) async => SourceCommentBinding(
                kg,
                const PlatformCommentResource(
                  kind: PlatformCommentKind.song,
                  id: '900',
                  name: '晴天',
                ),
                () => true,
              ),
            ),
          ],
        );
        addTearDown(container.dispose);
        await container.read(platformAccountProvider.future);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: _glass(
              MaterialApp(
                home: SourceCommentsPage(
                  track: k,
                  resources: [nr, kr],
                  initialSource: TrackSource.kugou,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('酷狗实际评论').hitTestable(), findsOneWidget);
        if (guest) expect(find.text('登录酷狗后参与评论'), findsOneWidget);
        final backRect = tester.getRect(find.byType(BetaGlassBackButton));
        final selectorRect = tester.getRect(
          find.byType(CupertinoSlidingSegmentedControl<TrackSource>),
        );
        if (!guest) {
          await tester.enterText(find.byType(TextField), '酷狗未发送草稿');
        }
        await tester.tap(find.text('网易云').last);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        // Download management's exact content viewport moves, while one shared
        // frame/selector stays fixed throughout the middle of the transition.
        final pages = tester.widget<PageView>(find.byType(PageView));
        expect(pages.controller!.page, allOf(greaterThan(0), lessThan(1)));
        expect(find.byType(BetaSwipePages), findsOneWidget);
        expect(find.byType(PlatformPageFrame), findsOneWidget);
        expect(tester.getRect(find.byType(BetaGlassBackButton)), backRect);
        expect(
          tester.getRect(
            find.byType(CupertinoSlidingSegmentedControl<TrackSource>),
          ),
          selectorRect,
        );
        await tester.pumpAndSettle();
        expect(find.text('网易云实际评论').hitTestable(), findsOneWidget);
        await tester.enterText(
          find.byType(TextField).hitTestable(),
          '网易云未发送草稿',
        );
        await tester.tap(find.text('酷狗').last);
        await tester.pumpAndSettle();
        expect(find.text('酷狗实际评论').hitTestable(), findsOneWidget);
        if (!guest) {
          expect(
            tester
                .widget<TextField>(find.byType(TextField).hitTestable())
                .controller!
                .text,
            '酷狗未发送草稿',
          );
        }
        final kgPage = find.byWidgetPredicate(
          (widget) =>
              widget is PlatformCommentsPage &&
              identical(widget.repository, kg),
        );
        final kgScroll = find.descendant(
          of: kgPage,
          matching: find.byType(ListView),
        );
        await tester.drag(kgScroll, const Offset(0, -360));
        await tester.pumpAndSettle();
        final offset = tester.widget<ListView>(kgScroll).controller!.offset;
        expect(offset, greaterThan(0));
        await tester.tap(find.text('网易云').last);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<TextField>(find.byType(TextField).hitTestable())
              .controller!
              .text,
          '网易云未发送草稿',
        );
        await tester.tap(find.text('酷狗').last);
        await tester.pumpAndSettle();
        expect(
          tester.widget<ListView>(kgScroll).controller!.offset,
          closeTo(offset, 0.1),
        );
        expect(container.read(platformAccountProvider).value!.userId, 'ui-net');
        expect(ne.reads, 1, reason: 'Switching back retains the source page');
        expect(
          kg.reads,
          1,
          reason: 'Visited source pagination is not restarted',
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  for (final playback in [true, false]) {
    testWidgets(
      'foreign login dialog coalesces taps and preserves UI, playback=$playback',
      (tester) async {
        final outcomes = <Future<bool>>[];
        final container = ProviderContainer(
          overrides: [
            platformAccountProvider.overrideWith(_UI.new),
            sourceMediaScopeProvider(TrackSource.kugou).overrideWith(
              (ref) async => SourceMediaScope(
                source: TrackSource.kugou,
                api: _api(),
                isCurrent: () => true,
              ),
            ),
          ],
        );
        addTearDown(container.dispose);
        await container.read(platformAccountProvider.future);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              home: Consumer(
                builder: (context, ref, _) => Scaffold(
                  body: TextButton(
                    onPressed: () {
                      outcomes.add(
                        ensureSourceLogin(
                          context,
                          ref,
                          TrackSource.kugou,
                          forPlayback: playback,
                        ),
                      );
                      outcomes.add(
                        ensureSourceLogin(
                          context,
                          ref,
                          TrackSource.kugou,
                          forPlayback: playback,
                        ),
                      );
                    },
                    child: const Text('打开来源登录'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('打开来源登录'));
        await tester.pumpAndSettle();
        expect(find.byType(CupertinoAlertDialog), findsOneWidget);
        expect(find.text(playback ? '登录酷狗后播放' : '登录酷狗后参与评论'), findsOneWidget);
        expect(
          find.textContaining('账号会员权限'),
          playback ? findsOneWidget : findsNothing,
        );
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(await Future.wait(outcomes), [false, false]);
        expect(container.read(platformAccountProvider).value!.userId, 'ui-net');
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets(
    'a single source has a valid comment page without a two-item segment assertion',
    (tester) async {
      final k = song('kugou_hash', TrackSource.kugou),
          request = SourceCommentRequest(song('kugou_hash', TrackSource.kugou));
      final repo = _Comments(
        const PlatformSession(userId: 'kg', token: 'fake'),
        '',
      );
      final container = ProviderContainer(
        overrides: [
          platformAccountProvider.overrideWith(_UI.new),
          showPlatformFeaturesProvider.overrideWithValue(true),
          sourceCommentBindingProvider(request).overrideWith(
            (ref) async => SourceCommentBinding(
              repo,
              const PlatformCommentResource(
                kind: PlatformCommentKind.song,
                id: '9',
                name: '作品',
              ),
              () => true,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(platformAccountProvider.future);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: _glass(
            MaterialApp(
              home: SourceCommentsPage(track: k, resources: [request]),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('暂时没有评论，来写下你的感受'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

Widget _glass(Widget child) => LiquidGlassWidgets.wrap(
  brightnessResolver: Theme.maybeBrightnessOf,
  adaptiveQuality: false,
  child: child,
);
