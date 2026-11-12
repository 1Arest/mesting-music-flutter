import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:mesting_music/core/network/music_network_diagnostics.dart';
import 'package:mesting_music/features/auth/presentation/beta_welcome_page.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/music_platform/netease/netease_api.dart';
import 'package:mesting_music/features/music_platform/netease/netease_login.dart';
import 'package:mesting_music/features/music_platform/netease/netease_providers.dart';
import 'package:mesting_music/features/music_platform/presentation/platform_account_page.dart';
import 'package:mesting_music/features/settings/presentation/music_network_diagnostics_page.dart';
import 'support/personal_profile_fixture.dart';
import 'support/release_152_qa.dart';

class _Guest extends SyntheticProfileAccount {
  @override
  Future<PlatformSession?> build() async => null;
}

void main() {
  setUpAll(initialize151QA);
  for (final dark in [false, true]) {
    for (final large in [false, true]) {
      for (final page in ['welcome', 'diagnostics', 'login']) {
        testWidgets(
          '153 $page ${dark ? 'dark' : 'light'} ${large ? 'large' : 'normal'}',
          (tester) async {
            tester.view.devicePixelRatio = 1;
            tester.view.physicalSize = Size(large ? 320 : 390, 844);
            addTearDown(tester.view.reset);
            final fixture = await PersonalProfileFixture.create(
              accountFactory: _Guest.new,
              extraOverrides: [
                neteaseApiProvider.overrideWithValue(
                  NeteaseApi(
                    MockClient(
                      (_) async => throw const SocketException(
                        'Failed host lookup: fixture',
                      ),
                    ),
                  ),
                ),
              ],
            );
            MusicNetworkDiagnostics.shared.clear();
            MusicNetworkDiagnostics.shared.record(
              platform: 'netease',
              operation: MusicNetworkOperation.login,
              outcome: MusicNetworkOutcome.timeout,
            );
            final Widget child = switch (page) {
              'welcome' => const BetaWelcomePage(),
              'login' => const PlatformAccountPage(
                platform: MusicPlatform.netease,
                neteaseMethod: NeteaseLoginMethod.sms,
                loginOnly: true,
              ),
              _ => const MusicNetworkDiagnosticsPage(),
            };
            await tester.pumpWidget(
              UncontrolledProviderScope(
                container: fixture.container,
                child: MaterialApp(
                  theme: theme152(dark),
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: TextScaler.linear(large ? 2 : 1)),
                    child: capture151Builder(child!),
                  ),
                  home: child,
                ),
              ),
            );
            if (page == 'welcome') {
              await tester.runAsync(
                () => precacheImage(
                  const AssetImage(
                    'assets/branding/welcome/companions-atlas.webp',
                  ),
                  tester.element(find.byType(BetaWelcomePage)),
                ),
              );
              await tester.pump();
            }
            for (var i = 0; i < 12; i++) {
              await tester.pump(const Duration(milliseconds: 30));
            }
            if (page == 'login') {
              await tester.enterText(
                find.byKey(const ValueKey('beta11-phone-field')),
                '13800138000',
              );
              tester.testTextInput.hide();
              await tester.ensureVisible(
                find.byKey(const ValueKey('beta11-send-code')),
              );
              await tester.tap(find.byKey(const ValueKey('beta11-send-code')));
              for (var i = 0; i < 12; i++) {
                await tester.pump(const Duration(milliseconds: 30));
              }
              expect(find.textContaining('地址解析失败'), findsOneWidget);
              await tester.ensureVisible(find.text('查看连接诊断'));
            }
            await shot151(
              tester,
              '153-$page-${dark ? 'dark' : 'light'}-${large ? 'large' : 'normal'}',
            );
            expect(tester.takeException(), null);
            await tester.pumpWidget(const SizedBox());
            await fixture.dispose();
          },
        );
      }
    }
  }
}
