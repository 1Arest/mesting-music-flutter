import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/features/auth/beta_entry_flow.dart';
import 'package:mesting_music/features/experience/presentation/cold_start_greeting.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/themes/personal_style.dart';

class _Guest extends PlatformAccountController {
  @override
  Future<PlatformSession?> build() async => null;
}

void main() {
  for (final reduced in [false, true]) {
    testWidgets(
      'flourish follows greeting once and respects reduced motion=$reduced',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          BetaEntryFlow.completedKey: true,
        });
        final prefs = await SharedPreferences.getInstance();
        final container = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            platformAccountProvider.overrideWith(_Guest.new),
          ],
        );
        Widget host() => UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: reduced),
              child: const Scaffold(body: Center(child: ColdStartGreeting())),
            ),
          ),
        );
        await tester.pumpWidget(host());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(
          find.byKey(const ValueKey('beta13-cold-greeting')),
          findsOneWidget,
        );
        await tester.pump(const Duration(seconds: 5));
        await tester.pump(const Duration(milliseconds: 400));
        expect(
          find.byKey(const ValueKey('discovery-note-flourish')),
          reduced ? findsNothing : findsOneWidget,
        );
        await tester.pump(const Duration(seconds: 3));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('discovery-note-flourish')),
          findsNothing,
        );
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(host());
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('beta13-cold-greeting')),
          findsNothing,
        );
        expect(container.read(personalStyleProvider).discoveryNotes, true);
        await tester.pumpWidget(const SizedBox());
        container.dispose();
      },
    );
  }
}
