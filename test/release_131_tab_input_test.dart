import 'package:flutter_test/flutter_test.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:mesting_music/shared/widgets/beta_tab_navigation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mesting_music/app/router/beta_tab_shell.dart';
import 'package:mesting_music/features/experience/presentation/beta_bottom_bar.dart';
import 'package:mesting_music/shared/widgets/music_activity_indicator.dart';
import 'package:mesting_music/features/music_platform/presentation/platform_design.dart';
import 'package:mesting_music/features/themes/app_theme.dart';
import 'package:mesting_music/features/themes/music_theme_preset.dart';

void main() {
  setUpAll(() async {
    await LiquidGlassWidgets.initialize();
    if (const bool.fromEnvironment('CAPTURE_131')) {
      for (final family in [
        'Roboto',
        'CupertinoSystemText',
        'CupertinoSystemDisplay',
      ]) {
        await (FontLoader(family)..addFont(
              File(
                'C:/Windows/Fonts/msyh.ttc',
              ).readAsBytes().then(ByteData.sublistView),
            ))
            .load();
      }
      await (FontLoader('MaterialIcons')..addFont(
            File(
              'D:/CodexCache/flutter-3.41.9/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
            ).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
      await (FontLoader('packages/cupertino_icons/CupertinoIcons')..addFont(
            rootBundle.load(
              'packages/cupertino_icons/assets/CupertinoIcons.ttf',
            ),
          ))
          .load();
    }
  });
  Future<void> capture(WidgetTester tester, String name) async {
    if (!const bool.fromEnvironment('CAPTURE_131')) return;
    final shot = tester
        .renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('tab-capture')),
        )
        .toImage();
    await tester.runAsync(() async {
      final image = await shot;
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final path = File('.codex-artifacts/2026-11-01-release131/ui/$name.png');
      await path.parent.create(recursive: true);
      await path.writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    });
  }

  test(
    'an older router acknowledgement cannot discard the newest tab request',
    () {
      final navigation = BetaTabNavigation();
      final routed = <int>[];
      void request(int index, int current) => navigation.request(
        index: index,
        currentIndex: current,
        navigate: routed.add,
      );
      request(3, 0);
      request(1, 0);
      // The router publishes the older tap while the newer destination is still
      // pending. A fresh tap on that visible destination must cancel the newer
      // request, even though the published location already names this tab.
      navigation.settled(3);
      request(3, 3);
      expect(routed, [3, 1, 3]);
      navigation.dispose();
    },
  );
  testWidgets(
    'actual glass tab taps retarget the live page while all data is pending',
    (tester) async {
      tester.view.physicalSize = const Size(400, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const paths = ['/discover', '/functions', '/library', '/profile'];
      final navigation = BetaTabNavigation();
      final events = <int>[];
      final router = GoRouter(
        initialLocation: paths.first,
        routes: [
          ShellRoute(
            builder: (context, state, child) {
              final index = paths.indexOf(state.uri.path);
              navigation.settled(index);
              return Scaffold(
                body: child,
                bottomNavigationBar: BetaMusicBottomBar(
                  selectedIndex: index,
                  searchConfig: GlassSearchBarConfig(onSearchToggle: (_) {}),
                  onTabSelected: (target) => navigation.request(
                    index: target,
                    currentIndex: index,
                    navigate: (target) {
                      events.add(target);
                      context.go(paths[target]);
                    },
                  ),
                ),
              );
            },
            routes: betaTabShellRoutes([
              for (var i = 0; i < paths.length; i++)
                GoRoute(
                  path: paths[i],
                  builder: (_, _) => const PlatformStyle(
                    child: Center(child: MusicActivityIndicator()),
                  ),
                ),
            ]),
          ),
        ],
      );
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('tab-capture'),
          child: MaterialApp.router(
            debugShowCheckedModeBanner: false,
            routerConfig: router,
            theme: buildMestingTheme(musicThemePresetById('classic')),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      final controller = tester
          .widget<PageView>(find.byType(PageView).first)
          .controller!;
      for (final target in [3, 1, 0, 2, 3, 0]) {
        final label = find
            .descendant(
              of: find.byType(BetaMusicBottomBar),
              matching: find.text(['发现', '功能', '音乐库', '我的'][target]),
            )
            .last;
        await tester.tapAt(tester.getCenter(label));
        await tester.pump();
        expect(router.routeInformationProvider.value.uri.path, paths[target]);
        await tester.pump(const Duration(milliseconds: 16));
        if (target == 2) await capture(tester, 'tab-latest-during-motion');
      }
      expect(events, [3, 1, 0, 2, 3, 0]);
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(controller.page, closeTo(0, .001));
      await capture(tester, 'tab-latest-settled');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      router.dispose();
      navigation.dispose();
    },
  );
}
