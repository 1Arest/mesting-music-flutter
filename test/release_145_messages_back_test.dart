import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mesting_music/app/router/beta_tab_shell.dart';
import 'package:mesting_music/app/system_back_coordinator.dart';
import 'package:mesting_music/features/music_platform/netease/messages/netease_messages_page.dart';
import 'package:mesting_music/features/music_platform/netease/messages/netease_messages_repository.dart';
import 'package:mesting_music/features/music_platform/netease/full/netease_full_page.dart';
import 'package:mesting_music/features/music_platform/netease/full/netease_catalog.dart';
import 'package:mesting_music/features/music_platform/platform_backend_providers.dart';
import 'package:mesting_music/shared/widgets/beta_bottom_search.dart';
import 'package:mesting_music/shared/widgets/beta_page_motion.dart';
import 'support/personal_profile_fixture.dart';
import 'support/release_151_qa.dart';

class _Messages extends NeteaseMessagesRepository {
  _Messages(super.music);
  static const peer = NeteasePerson('7002', '返回测试好友');
  @override
  Future<List<NeteaseConversation>> conversations([int offset = 0]) async => [
    NeteaseConversation(
      peer,
      NeteaseChatMessage(
        id: 'fixture',
        from: peer,
        to: const NeteasePerson('7001', '自己'),
        text: '本机合成会话',
        time: DateTime(2026, 11, 3),
      ),
      0,
    ),
  ];
  @override
  Future<Map<String, int>> counts() async => {};
  @override
  Future<List<NeteaseChatMessage>> history(
    String peer, [
    int before = 0,
  ]) async => [];
}

void main() {
  setUpAll(initialize151QA);
  for (final edge in [false, true]) {
    testWidgets(
      'actual inbox/chat retain My stack after two backs edge=$edge',
      (tester) async {
        final fixture = await PersonalProfileFixture.create(
          extraOverrides: [
            neteaseMessagesRepositoryProvider.overrideWith((ref) {
              final repo = _Messages(ref.watch(neteaseMusicRepositoryProvider));
              ref.onDispose(repo.dispose);
              return repo;
            }),
          ],
        );
        final host = BetaBottomSearchHost(
          location: '/profile',
          openMusicSearch: () {},
        );
        await tester.runAsync(
          () => fixture.container.read(neteaseCatalogProvider.future),
        );
        bool? handlesBack;
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(SystemChannels.platform, (
          call,
        ) async {
          if (call.method == 'SystemNavigator.setFrameworkHandlesBack') {
            handlesBack = call.arguments as bool;
          }
          return null;
        });
        final router = GoRouter(
          initialLocation: '/profile',
          routes: betaTabShellRoutes([
            GoRoute(
              path: '/profile',
              // Use the production My-page link: it opens a Material route,
              // whereas the old fixture manually opened a content route and
              // could not detect the mixed-route delegated-animation defect.
              pageBuilder: (context, state) => BetaRootTransitionPage<void>(
                key: state.pageKey,
                child: const Scaffold(
                  backgroundColor: Colors.white,
                  body: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('我的消息入口'),
                        NeteaseFullNavigation(tab: '我的', categories: {'消息中心'}),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            GoRoute(path: '/discover', builder: (_, _) => const Text('发现')),
          ]),
        );
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(390, 844);
        addTearDown(tester.view.reset);
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox());
          messenger.setMockMethodCallHandler(SystemChannels.platform, null);
          router.dispose();
          host.dispose();
          await fixture.dispose();
        });
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: fixture.container,
            child: MaterialApp.router(
              theme: theme151(false),
              routerConfig: router,
              builder: (_, child) => capture151Builder(
                SystemBackCoordinator(
                  canPop: router.canPop,
                  child: BetaBottomSearchScope(host: host, child: child!),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (!edge) await shot151(tester, 'messages-my');
        await tester.tap(find.text('我的消息'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 90));
        if (!edge) await shot151(tester, 'messages-enter');
        expect(
          tester.getTopLeft(find.byType(NeteaseMessagesPage)).dx,
          greaterThan(0),
        );
        expect(
          tester.getTopLeft(find.byType(NeteaseFullNavigation)).dx,
          lessThan(0),
        );
        await tester.pumpAndSettle();
        if (!edge) await shot151(tester, 'messages-inbox');
        final inboxNavigator = Navigator.of(
          tester.element(find.byType(NeteaseMessagesPage)),
        );
        expect(handlesBack, true);
        await tester.tap(find.text('返回测试好友'));
        await tester.pumpAndSettle();
        expect(
          Navigator.of(tester.element(find.byType(NeteaseChatPage))),
          same(inboxNavigator),
        );
        expect(handlesBack, true);
        var backFrame = 0;
        Future<void> back(Finder outgoing, Finder parent) async {
          if (edge) {
            await tester.dragFrom(const Offset(4, 340), const Offset(180, 0));
          } else {
            await tester.binding.handlePopRoute();
          }
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 80));
          final leavingX = tester.getTopLeft(outgoing).dx;
          final returningX = tester.getTopLeft(parent).dx;
          if (!edge) {
            await shot151(tester, 'messages-return-${backFrame++}');
          }
          expect(leavingX, greaterThan(0));
          expect(returningX, lessThan(0));
          await tester.pump(const Duration(milliseconds: 80));
          expect(tester.getTopLeft(outgoing).dx, greaterThan(leavingX));
          expect(tester.getTopLeft(parent).dx, greaterThan(returningX));
          await tester.pumpAndSettle();
        }

        await back(
          find.byType(NeteaseChatPage),
          find.byType(NeteaseMessagesPage),
        );
        expect(find.byType(NeteaseChatPage), findsNothing);
        expect(find.byType(NeteaseMessagesPage).hitTestable(), findsOneWidget);
        expect(router.canPop(), true);
        expect(
          handlesBack,
          true,
          reason: 'the second Android gesture must still be owned by Flutter',
        );
        await back(
          find.byType(NeteaseMessagesPage),
          find.byType(NeteaseFullNavigation),
        );
        expect(find.byType(NeteaseMessagesPage), findsNothing);
        expect(find.text('我的消息入口').hitTestable(), findsOneWidget);
        expect(router.canPop(), false);
        expect(handlesBack, false);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
