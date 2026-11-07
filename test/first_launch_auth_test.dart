import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/features/auth/auth_providers.dart';
import 'package:mesting_music/features/auth/data/auth_repository.dart';
import 'package:mesting_music/features/auth/presentation/first_launch_auth_coordinator.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'first install opens phone login and guest choice is remembered',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(preferences),
            authRepositoryProvider.overrideWithValue(
              const UnconfiguredAuthRepository(),
            ),
          ],
          child: const MaterialApp(
            home: FirstLaunchAuthCoordinator(
              child: Scaffold(body: Center(child: Text('推荐页面'))),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.byKey(const ValueKey('phone-auth-form')), findsOneWidget);
      expect(find.text('立即体验'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('experience-now')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.text('推荐页面'), findsOneWidget);
      expect(
        preferences.getBool(firstLaunchAuthCompletedPreferenceKey),
        isTrue,
      );
    },
  );

  testWidgets(
    'first-launch auth above the app navigator can open and accept disclaimer',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(preferences),
            authRepositoryProvider.overrideWithValue(
              const UnconfiguredAuthRepository(),
            ),
          ],
          child: MaterialApp(
            builder: (context, child) =>
                FirstLaunchAuthCoordinator(child: child!),
            home: const Scaffold(body: Text('app navigator content')),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      final checkbox = find.byKey(const ValueKey('disclaimer-checkbox'));
      await tester.ensureVisible(checkbox);
      await tester.tap(checkbox);
      await tester.pump(const Duration(milliseconds: 350));

      final confirm = find.byKey(const ValueKey('disclaimer-read-confirm'));
      expect(confirm, findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
      await tester.tap(confirm);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();

      expect(tester.widget<Checkbox>(checkbox).value, isTrue);
    },
  );
}
