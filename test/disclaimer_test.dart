import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/features/legal/presentation/disclaimer_dialog.dart';
import 'package:mesting_music/shared/widgets/liquid_glass_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SharedPreferences preferences;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
  });

  Widget app() {
    return ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
      child: const MaterialApp(
        home: FirstLaunchDisclaimerCoordinator(
          child: Scaffold(body: Center(child: Text('推荐页面'))),
        ),
      ),
    );
  }

  testWidgets('首次启动必须分别确认用户协议和隐私政策', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('使用前请先了解'), findsOneWidget);
    expect(find.text('我已阅读并同意《用户协议》'), findsOneWidget);
    expect(find.text('我已阅读并同意《隐私政策》'), findsOneWidget);
    final confirm = tester.widget<FilledButton>(
      find.byKey(const ValueKey('legal-consent-confirm')),
    );
    expect(confirm.onPressed, isNull);
    expect(find.byKey(liquidGlassDisclaimerSurfaceKey), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(liquidGlassDisclaimerSurfaceKey),
        matching: find.byType(BackdropFilter),
      ),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('legal-consent-userAgreement-checkbox')),
    );
    await tester.tap(
      find.byKey(const ValueKey('legal-consent-privacyPolicy-checkbox')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('legal-consent-confirm')));
    await tester.pumpAndSettle();

    expect(find.text('使用前请先了解'), findsNothing);
    expect(find.text('推荐页面'), findsOneWidget);
    expect(preferences.getBool(disclaimerAcceptedPreferenceKey), isTrue);
    expect(preferences.getBool(disclaimerReadPreferenceKey), isTrue);
    expect(preferences.getBool(userAgreementAcceptedPreferenceKey), isTrue);
    expect(preferences.getBool(privacyPolicyAcceptedPreferenceKey), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('已经确认后不再自动弹出', (tester) async {
    await preferences.setBool(userAgreementAcceptedPreferenceKey, true);
    await preferences.setBool(privacyPolicyAcceptedPreferenceKey, true);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('使用前请先了解'), findsNothing);
    expect(find.text('推荐页面'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('登录免责声明抽屉按内容收拢而非占满高屏', (tester) async {
    tester.view.physicalSize = const Size(570, 1267);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  await showRequiredDisclaimerReading(
                    context,
                    minimumReadDuration: Duration.zero,
                  );
                },
                child: const Text('查看免责声明'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('查看免责声明'));
    await tester.pumpAndSettle();

    final surface = find.byKey(liquidGlassSheetSurfaceKey);
    expect(surface, findsOneWidget);
    expect(tester.getSize(surface).height, lessThan(800));
    expect(find.text('我已阅读并理解'), findsOneWidget);
    expect(find.text('查看《用户协议》'), findsOneWidget);
    expect(find.text('查看《隐私政策》'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
