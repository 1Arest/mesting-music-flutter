// This historical fixture covers NetEase/Kugou; Soda is covered by qishui_* tests.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' show Response;
import 'package:mesting_music/app/router/beta_tab_shell.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/music_platform/data/embedded_music_server.dart';
import 'package:mesting_music/features/music_platform/data/music_platform_api.dart';
import 'package:mesting_music/features/music_platform/netease/netease_api.dart';
import 'package:mesting_music/features/music_platform/netease/netease_providers.dart';
import 'package:mesting_music/features/music_platform/presentation/platform_account_page.dart';
import 'package:mesting_music/features/music_platform/presentation/platform_login_options_page.dart';
import 'package:mesting_music/shared/widgets/beta_glass_controls.dart';
import 'package:mesting_music/shared/widgets/beta_music_chrome_scope.dart';
import 'package:mesting_music/shared/widgets/beta_page_motion.dart';
import 'support/personal_profile_fixture.dart';
import 'support/release_151_qa.dart';

class _Account extends SyntheticProfileAccount {
  _Account(this.platform);
  final MusicPlatform platform;
  @override
  Future<PlatformSession?> build() async => PlatformSession(
    userId: '7001',
    token: 'offline-fixture',
    platform: platform,
  );
  @override
  Future<PlatformSession?> retainedIdentity(MusicPlatform platform) async =>
      null;
}

class _Server implements MusicServer {
  @override
  Future<Uri> start() async => Uri.parse('http://127.0.0.1:1');
}

/// Deliberately pending QR transport exercises cancellation while a method is
/// opening. No test requests a real QR/SMS, signs in, or reads retained secrets.
void main() {
  setUpAll(initialize151QA);
  for (final active in [MusicPlatform.kugou, MusicPlatform.netease]) {
    for (final back in ['header', 'system', 'left-edge', 'right-edge']) {
      testWidgets(
        'all login methods hide chrome and pop one real level active=$active back=$back',
        (tester) async {
          final pending = <Completer<Response>>[];
          Future<Response> hold() {
            final gate = Completer<Response>();
            pending.add(gate);
            return gate.future;
          }

          final kugouClient = MockClient((_) => hold());
          final neteaseClient = MockClient((_) => hold());
          final fixture = await PersonalProfileFixture.create(
            accountFactory: () => _Account(active),
            extraOverrides: [
              musicPlatformApiProvider.overrideWithValue(
                MusicPlatformApi(server: _Server(), client: kugouClient),
              ),
              neteaseApiProvider.overrideWithValue(NeteaseApi(neteaseClient)),
            ],
          );
          final chrome = BetaMusicChromeController();
          final target = active == MusicPlatform.netease
              ? MusicPlatform.kugou
              : MusicPlatform.netease;
          final large = back == 'right-edge';
          final capture = back == 'header' || large;
          final labelPrefix = '${target.name}-${large ? 'large' : 'normal'}';
          final labels = target == MusicPlatform.kugou
              ? ['手机号登录', '酷狗扫码登录', '微信扫码登录', 'QQ 扫码登录']
              : ['网易云扫码', '手机验证码', '手机号与密码', '邮箱与密码'];
          final router = GoRouter(
            initialLocation: '/profile',
            routes: betaTabShellRoutes([
              GoRoute(
                path: '/profile',
                pageBuilder: (_, state) => BetaRootTransitionPage<void>(
                  key: state.pageKey,
                  child: Scaffold(
                    body: Builder(
                      builder: (context) => Center(
                        child: TextButton(
                          onPressed: () => Navigator.of(context).push(
                            betaContentRoute<void>(
                              const MusicPlatformSwitchPage(),
                            ),
                          ),
                          child: const Text('账号菜单入口'),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ]),
          );
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(large ? 320 : 390, 844);
          addTearDown(tester.view.reset);
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: fixture.container,
              child: MaterialApp.router(
                theme: theme151(active == MusicPlatform.netease),
                routerConfig: router,
                builder: (context, child) => capture151Builder(
                  MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: TextScaler.linear(large ? 1.4 : 1)),
                    child: BetaMusicChromeScope(
                      controller: chrome,
                      child: child!,
                    ),
                  ),
                ),
              ),
            ),
          );
          Future<void> settle() async {
            for (var i = 0; i < 9; i++) {
              await tester.pump(const Duration(milliseconds: 50));
            }
          }

          Future<void> leave() async {
            if (back == 'header') {
              await tester.tap(
                find.byType(BetaGlassBackButton).hitTestable().last,
              );
            } else if (back == 'system') {
              await tester.binding.handlePopRoute();
            } else {
              await tester.dragFrom(
                Offset(back == 'left-edge' ? 3 : (large ? 317 : 387), 330),
                Offset(back == 'left-edge' ? 170 : -170, 0),
              );
            }
            await settle();
          }

          await settle();
          await tester.tap(find.text('账号菜单入口'));
          await settle();
          if (capture) {
            await shot151(tester, '$labelPrefix-switch');
          }
          expect(chrome.covered, isTrue);
          await tester.tap(
            find.text(target == MusicPlatform.kugou ? '酷狗音乐' : '网易云音乐'),
          );
          await settle();
          if (capture) {
            await shot151(tester, '$labelPrefix-methods');
          }
          expect(chrome.covered, isTrue);
          for (final label in labels) {
            await tester.tap(find.text(label));
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 90));
            if (capture && label == labels.first) {
              await shot151(tester, '$labelPrefix-enter');
            }
            expect(
              tester.getTopLeft(find.byType(PlatformAccountPage)).dx,
              greaterThan(0),
            );
            expect(
              tester.getTopLeft(find.byType(PlatformLoginOptionsPage)).dx,
              lessThan(0),
            );
            await settle();
            if (capture) {
              await shot151(
                tester,
                '$labelPrefix-form-${labels.indexOf(label)}',
              );
            }
            expect(chrome.covered, isTrue, reason: label);
            expect(
              fixture.container.read(platformAccountProvider).value?.platform,
              active,
            );
            // Type into a real method editor before Back; closing it keeps the
            // selected platform and the actual method/options parent intact.
            final fields = find.byType(TextField).hitTestable();
            if (fields.evaluate().isNotEmpty) {
              await tester.enterText(fields.first, '123');
              await tester.pump();
            }
            await leave();
            expect(find.byType(PlatformAccountPage), findsNothing);
            expect(
              find.byType(PlatformLoginOptionsPage).hitTestable(),
              findsOneWidget,
            );
            expect(chrome.covered, isTrue);
          }
          await leave();
          expect(find.byType(PlatformLoginOptionsPage), findsNothing);
          expect(
            find.byType(MusicPlatformSwitchPage).hitTestable(),
            findsOneWidget,
          );
          expect(chrome.covered, isTrue);
          await leave();
          expect(find.byType(MusicPlatformSwitchPage), findsNothing);
          expect(find.text('账号菜单入口').hitTestable(), findsOneWidget);
          expect(chrome.covered, isFalse);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          for (final gate in pending) {
            gate.complete(Response('{}', 200));
          }
          await tester.pump();
          router.dispose();
          chrome.dispose();
          kugouClient.close();
          neteaseClient.close();
          await fixture.dispose();
        },
      );
    }
  }
}
