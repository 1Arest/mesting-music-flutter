import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mesting_music/features/music_platform/data/kugou_account_store.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/music_platform/presentation/kugou_accounts_page.dart';
import 'package:mesting_music/features/music_platform/presentation/kugou_standard_authorization_page.dart';
import 'support/release_152_qa.dart';

const _owner = PlatformSession(
  userId: '7',
  token: 'fixture-primary',
  nickname: '当前账号',
);

class _Account extends PlatformAccountController {
  @override
  Future<PlatformSession?> build() async => _owner;
  void select(PlatformSession next) => state = AsyncData(next);
}

void main() {
  setUpAll(initialize151QA);
  Future<ProviderContainer> container({http.Client Function()? client}) async {
    final value = ProviderContainer(
      overrides: [
        platformAccountProvider.overrideWith(_Account.new),
        savedKugouAccountsProvider.overrideWith(
          (ref) async => const [
            KugouSavedAccount(
              userId: '7',
              nickname: '当前账号',
              avatarUrl: '',
              loginMethod: 'qqQr',
            ),
            KugouSavedAccount(
              userId: '8',
              nickname: '第二个账号',
              avatarUrl: '',
              loginMethod: 'wechatQr',
              standardAuthorized: true,
            ),
          ],
        ),
        kugouStandardAuthorizationDeviceProvider.overrideWithValue(
          () async => {
            'mid': 'fixture-mid',
            'dfid': 'fixture-dfid',
            'uuid': 'fixture-uuid',
          },
        ),
        kugouStandardAuthorizationClientFactoryProvider.overrideWithValue(
          client ??
              () => MockClient(
                (r) async => http.Response(
                  jsonEncode({
                    'error_code': 0,
                    'data': r.url.path.endsWith('/qrcode')
                        ? {'qrcode': 'fixture-code'}
                        : {'status': 1},
                  }),
                  200,
                ),
              ),
        ),
      ],
    );
    await value.read(platformAccountProvider.future);
    return value;
  }

  Widget app(ProviderContainer container, Widget page, bool dark, bool large) =>
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: theme152(dark),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(large ? 2 : 1)),
            child: child!,
          ),
          home: capture151Builder(page),
        ),
      );
  for (final dark in [false, true]) {
    for (final large in [false, true]) {
      testWidgets('account manager and standard QR fit dark=$dark large=$large', (
        tester,
      ) async {
        tester.view.physicalSize = Size(large ? 320 : 390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        for (final page in [
          const KugouAccountsPage(),
          const KugouStandardAuthorizationPage(owner: _owner),
        ]) {
          final scope = await container();
          await tester.pumpWidget(app(scope, page, dark, large));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 30)),
          );
          for (var frame = 0; frame < 15; frame++) {
            await tester.pump(const Duration(milliseconds: 50));
          }
          expect(tester.takeException(), isNull);
          if (page is KugouAccountsPage) {
            expect(find.text('当前登录'), findsOneWidget);
            expect(find.text('切换'), findsOneWidget);
          } else {
            expect(find.byType(QrImageView), findsOneWidget);
          }
          await shot151(
            tester,
            '152-${page.runtimeType}-${dark ? 'dark' : 'light'}-${large ? 'large' : 'normal'}',
          );
          await tester.pumpWidget(const SizedBox());
          scope.dispose();
        }
      });
    }
  }
  testWidgets('account A to B to A cannot revive a pending standard QR', (
    tester,
  ) async {
    final pending = Completer<http.Response>();
    final scope = await container(
      client: () => MockClient((_) => pending.future),
    );
    await tester.pumpWidget(
      app(
        scope,
        const KugouStandardAuthorizationPage(owner: _owner),
        false,
        false,
      ),
    );
    await tester.pump();
    final account = scope.read(platformAccountProvider.notifier) as _Account;
    account.select(const PlatformSession(userId: '8', token: 'other'));
    account.select(_owner);
    pending.complete(
      http.Response('{"error_code":0,"data":{"qrcode":"late-code"}}', 200),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byType(QrImageView), findsNothing);
    expect(find.text('当前账号已变化，请返回后重新打开。'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    scope.dispose();
  });
}
