import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/app/branded_launch_screen.dart';
import 'package:mesting_music/features/themes/app_brand_style.dart';

void main() {
  testWidgets('light launch screen uses the selected coral lockup', (
    tester,
  ) async {
    await tester.pumpWidget(const MestingBrandedLaunchApp());
    await tester.pump(const Duration(milliseconds: 520));

    final scaffold = tester.widget<Scaffold>(
      find.byKey(const ValueKey('mesting-branded-launch-screen')),
    );
    expect(scaffold.backgroundColor, mestingBrandCoral);
    expect(find.byKey(const ValueKey('mesting-launch-lockup')), findsOneWidget);

    final image = tester.widget<Image>(find.byType(Image));
    expect(image.image, const AssetImage(mestingLaunchLockupAsset));
  });

  testWidgets('dark launch screen uses the selected ink background', (
    tester,
  ) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    await tester.pumpWidget(const MestingBrandedLaunchApp());

    final scaffold = tester.widget<Scaffold>(
      find.byKey(const ValueKey('mesting-branded-launch-screen')),
    );
    expect(scaffold.backgroundColor, mestingBrandInk);
  });

  testWidgets('saved light mode overrides a dark system launch', (
    tester,
  ) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    await tester.pumpWidget(
      const MestingBrandedLaunchApp(themeMode: ThemeMode.light),
    );

    final scaffold = tester.widget<Scaffold>(
      find.byKey(const ValueKey('mesting-branded-launch-screen')),
    );
    expect(scaffold.backgroundColor, mestingBrandCoral);
  });

  testWidgets('saved dark mode overrides a light system launch', (
    tester,
  ) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    await tester.pumpWidget(
      const MestingBrandedLaunchApp(themeMode: ThemeMode.dark),
    );

    final scaffold = tester.widget<Scaffold>(
      find.byKey(const ValueKey('mesting-branded-launch-screen')),
    );
    expect(scaffold.backgroundColor, mestingBrandInk);
  });

  testWidgets('morning dress-up uses its matching launch artwork', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MestingBrandedLaunchApp(brandStyle: AppBrandStyle.morningMist),
    );

    final scaffold = tester.widget<Scaffold>(
      find.byKey(const ValueKey('mesting-branded-launch-screen')),
    );
    expect(scaffold.backgroundColor, mestingMorningCanvas);
    final image = tester.widget<Image>(
      find.byKey(const ValueKey('brand-launch-background-morning_mist')),
    );
    expect(
      image.image,
      isA<ResizeImage>().having(
        (provider) => provider.imageProvider,
        'imageProvider',
        const AssetImage('assets/branding/dress-morning-launch.webp'),
      ),
    );
    expect(image.fit, BoxFit.cover);
    final lockup = tester.widget<Image>(
      find.descendant(
        of: find.byKey(const ValueKey('mesting-morning-launch-lockup')),
        matching: find.byType(Image),
      ),
    );
    expect(lockup.image, const AssetImage(mestingLaunchLockupAsset));
    expect(lockup.fit, BoxFit.contain);
    expect(lockup.color, mestingMorningInk);
  });

  testWidgets('midnight dress-up uses its matching launch artwork', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MestingBrandedLaunchApp(brandStyle: AppBrandStyle.midnightVinyl),
    );

    final scaffold = tester.widget<Scaffold>(
      find.byKey(const ValueKey('mesting-branded-launch-screen')),
    );
    expect(scaffold.backgroundColor, mestingMidnightCanvas);
    final image = tester.widget<Image>(
      find.byKey(const ValueKey('brand-launch-background-midnight_vinyl')),
    );
    expect(
      image.image,
      isA<ResizeImage>().having(
        (provider) => provider.imageProvider,
        'imageProvider',
        const AssetImage('assets/branding/dress-midnight-launch-v2.webp'),
      ),
    );
    expect(image.fit, BoxFit.cover);
    final lockup = tester.widget<Image>(
      find.descendant(
        of: find.byKey(const ValueKey('mesting-midnight-launch-lockup')),
        matching: find.byType(Image),
      ),
    );
    expect(lockup.image, const AssetImage(mestingLaunchLockupAsset));
    expect(lockup.fit, BoxFit.contain);
    expect(lockup.color, mestingMidnightPaper);
  });
}
