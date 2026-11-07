import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mesting_music/features/player/presentation/music_navigation.dart';
import 'package:mesting_music/features/player/presentation/music_page_transition.dart';
import 'package:mesting_music/features/themes/mesting_palette.dart';

void main() {
  test('底部导航选中态使用清晰的心动红配色', () {
    expect(
      musicBottomNavigationSelectedColorFor(Brightness.light),
      MestingPalette.heart,
    );
    expect(
      musicBottomNavigationSelectedColorFor(Brightness.dark),
      MestingPalette.heartBright,
    );
  });

  test('消息页在侧栏关闭后以更早的共享轴接管内容', () {
    expect(messagesPageTransitionDuration, const Duration(milliseconds: 360));
    expect(
      messagesPageReverseTransitionDuration,
      const Duration(milliseconds: 280),
    );
    expect(messagesPageHandoffProgress, lessThan(musicPageHandoffProgress));
    expect(messagesPageStartScale, lessThan(1));
  });

  test('底部导航背景不再绘制粉色椭圆或半圆', () async {
    final source = await File(
      'lib/features/player/presentation/music_navigation.dart',
    ).readAsString();

    expect(source, isNot(contains('canvas.drawOval(')));
  });

  testWidgets('底部导航不再绘制选中胶囊椭圆', (tester) async {
    final router = GoRouter(
      initialLocation: '/music/recommend',
      routes: [
        GoRoute(
          path: '/music/recommend',
          builder: (_, _) =>
              const Scaffold(bottomNavigationBar: MusicBottomNavigation()),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );
    await tester.pumpAndSettle();

    final selected = tester.widget<AnimatedContainer>(
      find.byKey(const ValueKey('music-bottom-navigation-indicator-推荐')),
    );
    expect(selected.decoration, isNull);
    expect(selected.foregroundDecoration, isNull);
  });
}
