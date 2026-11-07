import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../features/themes/app_brand_style.dart';

const mestingBrandCoral = Color(0xFFD95046);
const mestingBrandPaper = Color(0xFFF7F8FF);
const mestingBrandInk = Color(0xFF17131B);
const mestingMorningCanvas = Color(0xFFFFF7E5);
const mestingMorningInk = Color(0xFF173C4A);
const mestingMidnightCanvas = Color(0xFF081824);
const mestingMidnightPaper = Color(0xFFF4F1E8);
const mestingLaunchLockupAsset =
    'assets/branding/mesting-launch-lockup-master.png';

class MestingBrandedLaunchApp extends StatelessWidget {
  const MestingBrandedLaunchApp({
    this.brandStyle = AppBrandStyle.coral,
    this.themeMode = ThemeMode.system,
    this.failed = false,
    this.onRetry,
    this.forceCoral = false,
    super.key,
  });

  final AppBrandStyle brandStyle;
  final ThemeMode themeMode;
  final bool failed;
  final VoidCallback? onRetry;
  final bool forceCoral;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: mestingBrandCoral,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: mestingBrandInk,
      ),
      home: MestingBrandedLaunchScreen(
        brandStyle: brandStyle,
        failed: failed,
        onRetry: onRetry,
        forceCoral: forceCoral,
      ),
    );
  }
}

class MestingBrandedLaunchScreen extends StatelessWidget {
  const MestingBrandedLaunchScreen({
    this.brandStyle = AppBrandStyle.coral,
    this.failed = false,
    this.onRetry,
    this.forceCoral = false,
    super.key,
  });

  final AppBrandStyle brandStyle;
  final bool failed;
  final VoidCallback? onRetry;
  final bool forceCoral;

  @override
  Widget build(BuildContext context) {
    final background = switch (brandStyle) {
      AppBrandStyle.coral =>
        !forceCoral && Theme.of(context).brightness == Brightness.dark
            ? mestingBrandInk
            : mestingBrandCoral,
      AppBrandStyle.morningMist => mestingMorningCanvas,
      AppBrandStyle.midnightVinyl => mestingMidnightCanvas,
    };
    final darkSystemUi = brandStyle == AppBrandStyle.morningMist;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final alternateLockupColor = switch (brandStyle) {
      AppBrandStyle.coral => null,
      AppBrandStyle.morningMist => mestingMorningInk,
      AppBrandStyle.midnightVinyl => mestingMidnightPaper,
    };
    final actionColor =
        alternateLockupColor ??
        (Theme.of(context).brightness == Brightness.dark
            ? mestingBrandPaper
            : Colors.white);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: background,
        statusBarIconBrightness: darkSystemUi
            ? Brightness.dark
            : Brightness.light,
        systemNavigationBarColor: background,
        systemNavigationBarIconBrightness: darkSystemUi
            ? Brightness.dark
            : Brightness.light,
      ),
      child: Scaffold(
        key: const ValueKey('mesting-branded-launch-screen'),
        backgroundColor: background,
        body: Stack(
          fit: StackFit.expand,
          children: [
            if (brandStyle.launchAsset != null)
              Image.asset(
                key: ValueKey('brand-launch-background-${brandStyle.id}'),
                brandStyle.launchAsset!,
                fit: BoxFit.cover,
                cacheWidth:
                    (MediaQuery.sizeOf(context).width *
                            MediaQuery.devicePixelRatioOf(context))
                        .ceil()
                        .clamp(720, 1440),
                filterQuality: FilterQuality.high,
                semanticLabel: '${brandStyle.name}启动页',
              ),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (brandStyle == AppBrandStyle.coral)
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: .94, end: 1),
                      duration: const Duration(milliseconds: 520),
                      curve: Curves.easeOutCubic,
                      builder: (context, value, child) => Opacity(
                        opacity: ((value - .94) / .06).clamp(0, 1),
                        child: Transform.scale(scale: value, child: child),
                      ),
                      child: SizedBox(
                        key: const ValueKey('mesting-launch-lockup'),
                        width: screenWidth,
                        height: (screenWidth * .72).clamp(250, 360),
                        child: OverflowBox(
                          maxWidth: screenWidth * 1.24,
                          child: Image.asset(
                            mestingLaunchLockupAsset,
                            width: screenWidth * 1.24,
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.high,
                            semanticLabel: 'Mesting Music',
                          ),
                        ),
                      ),
                    ),
                  if (brandStyle != AppBrandStyle.coral)
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: .94, end: 1),
                      duration: const Duration(milliseconds: 520),
                      curve: Curves.easeOutCubic,
                      builder: (context, value, child) => Opacity(
                        opacity: ((value - .94) / .06).clamp(0, 1),
                        child: Transform.scale(scale: value, child: child),
                      ),
                      child: SizedBox.square(
                        key: ValueKey(
                          'mesting-${brandStyle == AppBrandStyle.morningMist ? 'morning' : 'midnight'}-launch-lockup',
                        ),
                        dimension: (screenWidth * .76).clamp(250, 390),
                        child: Image.asset(
                          mestingLaunchLockupAsset,
                          fit: BoxFit.contain,
                          color: alternateLockupColor,
                          colorBlendMode: BlendMode.srcIn,
                          filterQuality: FilterQuality.high,
                          semanticLabel: 'Mesting Music',
                        ),
                      ),
                    ),
                  if (failed) ...[
                    const SizedBox(height: 18),
                    GestureDetector(
                      onTap: onRetry,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: actionColor.withValues(alpha: .10),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: actionColor.withValues(alpha: .30),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 10,
                          ),
                          child: Text(
                            '启动失败，点击重试',
                            style: TextStyle(
                              color: actionColor,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
