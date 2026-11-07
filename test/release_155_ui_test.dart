import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesting_music/core/network/music_network_diagnostics.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/core/security/credential_failure.dart';
import 'package:mesting_music/features/auth/beta_account_choice.dart';
import 'package:mesting_music/features/auth/beta_entry_flow.dart';
import 'package:mesting_music/features/auth/presentation/beta_entry_coordinator.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/music_platform/presentation/platform_login_options_page.dart';

import 'support/release_152_qa.dart';

const _keyFailure = CredentialStoreException(
  MusicDiagnosticPhase.storageRead,
  MusicFailureFamily.keyInvalidated,
);
const _healthy = PlatformSession(userId: '155', token: 'synthetic-current');

class _UnreadableTarget extends PlatformAccountController {
  @override
  Future<PlatformSession?> build() async => _healthy;
  @override
  Future<PlatformSession?> retainedIdentity(MusicPlatform platform) async =>
      throw _keyFailure;
}

class _RestoreFailure extends PlatformAccountController {
  _RestoreFailure(this.family);
  final MusicFailureFamily family;
  @override
  Future<PlatformSession?> build() async =>
      throw CredentialStoreException(MusicDiagnosticPhase.storageRead, family);
}

void main() {
  setUpAll(initialize151QA);
  Future<ProviderContainer> scope155(
    PlatformAccountController Function() factory,
  ) async {
    SharedPreferences.setMockInitialValues({
      BetaAccountChoiceController.preferenceKey: 'kugou',
      BetaEntryFlow.completedKey: true,
    });
    final scope = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(
          await SharedPreferences.getInstance(),
        ),

        platformAccountProvider.overrideWith(factory),
      ],
    );
    return scope;
  }

  Widget app(ProviderContainer scope, Widget page, bool dark, bool large) =>
      UncontrolledProviderScope(
        container: scope,
        child: MaterialApp(
          theme: theme152(dark),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(large ? 2 : 1)),
            child: capture151Builder(child!),
          ),
          home: page,
        ),
      );

  Future<void> frames(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  for (final dark in [false, true]) {
    for (final large in [false, true]) {
      testWidgets(
        '155 unavailable target permits explicit login and cancel; dark=$dark large=$large',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(large ? 320 : 390, 844);
          addTearDown(tester.view.reset);
          final scope = await scope155(_UnreadableTarget.new);
          await scope.read(platformAccountProvider.future);
          await tester.pumpWidget(
            app(scope, const MusicPlatformSwitchPage(), dark, large),
          );
          await tester.tap(find.text('网易云音乐'));
          await frames(tester);
          expect(find.textContaining('登录密钥已失效'), findsOneWidget);
          expect(find.text('酷狗音乐 · 当前平台'), findsOneWidget);
          final label = tester.renderObject<RenderParagraph>(
            find.text('酷狗音乐 · 当前平台'),
          );
          for (final box in label.getBoxesForSelection(
            const TextSelection(baseOffset: 0, extentOffset: 11),
          )) {
            expect(
              box.bottom,
              lessThanOrEqualTo(label.size.height + 0.1),
              reason:
                  'The current-platform label must not be clipped at large text sizes',
            );
          }
          final retry = find.byKey(
            const ValueKey('platform-switch-reauthenticate'),
          );
          await tester.ensureVisible(retry);
          await shot151(
            tester,
            '155-switch-${dark ? 'dark' : 'light'}-${large ? 'large' : 'normal'}',
          );

          // A drag starting on the new action must scroll/cancel, never log out
          // or open a login route before the pointer has been released.
          final gesture = await tester.startGesture(tester.getCenter(retry));
          await gesture.moveBy(const Offset(0, -90));
          await tester.pump(const Duration(milliseconds: 200));
          expect(find.text('网易云登录'), findsNothing);
          await gesture.up();
          await frames(tester);
          await tester.ensureVisible(retry);
          await tester.tap(retry);
          await frames(tester);
          expect(find.text('网易云登录'), findsOneWidget);
          expect(scope.read(platformAccountProvider).value, _healthy);
          await shot151(
            tester,
            '155-reauth-${dark ? 'dark' : 'light'}-${large ? 'large' : 'normal'}',
          );
          Navigator.of(tester.element(find.text('网易云登录'))).pop(false);
          await frames(tester);
          expect(find.text('切换音乐平台'), findsOneWidget);
          expect(scope.read(platformAccountProvider).value, _healthy);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          scope.dispose();
        },
      );

      testWidgets(
        '155 invalidated key offers honest login without futile restore; dark=$dark large=$large',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(large ? 320 : 390, 844);
          addTearDown(tester.view.reset);
          final scope = await scope155(
            () => _RestoreFailure(MusicFailureFamily.keyInvalidated),
          );
          await expectLater(
            scope.read(platformAccountProvider.future),
            throwsA(isA<CredentialStoreException>()),
          );
          await tester.pumpWidget(
            app(
              scope,
              const BetaEntryCoordinator(child: Scaffold(body: Text('应用内容'))),
              dark,
              large,
            ),
          );
          await frames(tester);
          expect(find.textContaining('登录密钥已失效'), findsOneWidget);
          expect(find.text('重试恢复'), findsNothing);
          expect(find.text('重新登录'), findsOneWidget);
          expect(find.text('复制恢复诊断'), findsOneWidget);
          await shot151(
            tester,
            '155-restore-${dark ? 'dark' : 'light'}-${large ? 'large' : 'normal'}',
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          scope.dispose();
        },
      );
    }
  }

  testWidgets('155 transient storage timeout retains user-driven restore', (
    tester,
  ) async {
    final scope = await scope155(
      () => _RestoreFailure(MusicFailureFamily.timeout),
    );
    await expectLater(
      scope.read(platformAccountProvider.future),
      throwsA(isA<CredentialStoreException>()),
    );
    await tester.pumpWidget(
      app(scope, const BetaEntryCoordinator(child: Scaffold()), false, false),
    );
    await frames(tester);
    expect(find.text('重试恢复'), findsOneWidget);
    expect(find.text('重新登录'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    scope.dispose();
  });
}
