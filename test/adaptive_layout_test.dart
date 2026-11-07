import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mesting_music/features/player/presentation/music_navigation.dart';
import 'package:mesting_music/shared/layout/adaptive_layout.dart';
import 'package:mesting_music/shared/widgets/liquid_glass_sheet.dart';

void main() {
  test('响应式断点保留手机布局并为大屏启用侧边导航', () {
    expect(mestingWindowClassForWidth(599), MestingWindowClass.compact);
    expect(mestingWindowClassForWidth(600), MestingWindowClass.medium);
    expect(mestingWindowClassForWidth(839), MestingWindowClass.medium);
    expect(mestingWindowClassForWidth(840), MestingWindowClass.expanded);
    expect(mestingUsesNavigationRailForWidth(839), isFalse);
    expect(mestingUsesNavigationRailForWidth(840), isTrue);
    expect(mestingPageMaxWidthFor(700), 760);
    expect(mestingPageMaxWidthFor(1280), 1080);
    expect(mestingMusicPageBottomClearanceForWidth(390), 168);
    expect(mestingMusicPageBottomClearanceForWidth(1280), 112);
    expect(mestingGridColumnCount(width: 760), 2);
    expect(mestingGridColumnCount(width: 1080), 4);
  });

  testWidgets('平板内容区限制最大宽度并保持完整高度', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MestingAdaptiveContentFrame(
            child: ColoredBox(color: Colors.red),
          ),
        ),
      ),
    );

    expect(
      tester.getSize(
        find.byKey(const ValueKey('mesting-adaptive-content-frame')),
      ),
      const Size(1080, 800),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('平板侧边导航展示四个稳定入口', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final router = GoRouter(
      initialLocation: '/music/recommend',
      routes: [
        GoRoute(
          path: '/music/recommend',
          builder: (_, _) =>
              const Scaffold(body: Align(child: MusicNavigationRail())),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byKey(const ValueKey('music-navigation-rail'))).width,
      musicNavigationRailWidth,
    );
    for (final label in ['推荐', '发现', '喜欢', '我的']) {
      expect(
        find.byKey(ValueKey('music-navigation-rail-item-$label')),
        findsOneWidget,
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('平板抽屉限制为居中的可读宽度', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => showLiquidGlassBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) =>
                    const SizedBox(width: double.infinity, height: 320),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byKey(liquidGlassSurfaceBodyKey)).width, 720);
    expect(tester.takeException(), isNull);
  });
}
