import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/features/auth/auth_providers.dart';
import 'package:mesting_music/features/auth/data/auth_repository.dart';
import 'package:mesting_music/features/auth/domain/auth_models.dart';
import 'package:mesting_music/features/legal/presentation/disclaimer_dialog.dart';
import 'package:mesting_music/features/player/presentation/music_hub_top_bar.dart';
import 'package:mesting_music/features/settings/presentation/settings_page.dart';
import 'package:mesting_music/shared/widgets/liquid_glass_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SharedPreferences preferences;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
  });

  Widget app({Brightness brightness = Brightness.light}) {
    return ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(
          const UnconfiguredAuthRepository(),
        ),
        sharedPreferencesProvider.overrideWithValue(preferences),
      ],
      child: MaterialApp(
        theme: ThemeData(brightness: brightness),
        home: const Scaffold(
          body: SafeArea(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: MusicHubTopBar(title: '发现音乐', subtitle: '探索歌单、新歌与在线音乐'),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('左侧菜单提供设置与法律文档入口', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.menu_rounded));
    await tester.pumpAndSettle();

    expect(find.text('我的喜欢'), findsNothing);
    expect(find.text('我的歌单'), findsNothing);
    expect(find.text('播放列表'), findsNothing);
    expect(find.text('搜索音乐'), findsNothing);
    expect(find.text('设置'), findsOneWidget);
    expect(find.text('用户协议与隐私政策'), findsOneWidget);
    expect(find.text('免责声明'), findsOneWidget);
    expect(find.text('注册 / 登录'), findsNothing);
    expect(find.text('登录后收藏你的音乐'), findsOneWidget);
    expect(find.text('正在恢复账号'), findsNothing);
    expect(find.textContaining('已统一放在“设置”'), findsOneWidget);
    final panel = tester.widget<LiquidGlassSurface>(
      find.byKey(liquidGlassSidePanelSurfaceKey),
    );
    expect(panel.blurSigma, 0);
    expect(panel.showShadow, isFalse);
    expect(panel.showDecorativeGlow, isFalse);
    expect(panel.surfaceColorBuilder, isNotNull);
    final surfaceBody = tester.widget<DecoratedBox>(
      find.descendant(
        of: find.byKey(liquidGlassSidePanelSurfaceKey),
        matching: find.byKey(liquidGlassSurfaceBodyKey),
      ),
    );
    final surfaceDecoration = surfaceBody.decoration as BoxDecoration;
    expect(surfaceDecoration.color, isNotNull);
    expect(surfaceDecoration.color!.a, 1);
    expect(surfaceDecoration.gradient, isNull);
    expect(
      find.descendant(
        of: find.byKey(liquidGlassSidePanelSurfaceKey),
        matching: find.byType(BackdropFilter),
      ),
      findsNothing,
      reason: '全高侧边菜单在平板滑入时不应逐帧重算背景模糊',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('账号恢复完成前侧栏不会误显示未登录提示', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = _DelayedRestoreAuthRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(repository),
          sharedPreferencesProvider.overrideWithValue(preferences),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SafeArea(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: MusicHubTopBar(title: '发现音乐', subtitle: '探索音乐'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.menu_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 310));

    expect(
      find.byKey(const ValueKey('music-hub-account-restoring')),
      findsOneWidget,
    );
    expect(find.text('正在恢复账号'), findsOneWidget);
    expect(find.text('正在读取本机登录状态'), findsOneWidget);
    expect(find.text('登录后收藏你的音乐'), findsNothing);

    repository.restoreGate.complete(
      AuthSession(
        user: const AuthUser(uid: 'restored-user', nickname: 'Mesti'),
        accessToken: 'restored-access',
        refreshToken: 'restored-refresh',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('music-hub-account-signedIn')),
      findsOneWidget,
    );
    expect(find.text('Mesti'), findsOneWidget);
    expect(find.text('欢迎回到你的音乐空间'), findsOneWidget);
    expect(find.text('正在恢复账号'), findsNothing);
    expect(find.text('登录后收藏你的音乐'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('二级页左侧使用同系列实体返回按钮', (tester) async {
    var popped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SafeArea(
            child: MusicHubTopBar(
              title: '每日推荐',
              subtitle: '每天更新的专属音乐队列',
              showBack: true,
              onBack: () => popped = true,
            ),
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.arrow_back_ios_new_rounded), findsOneWidget);
    expect(find.byIcon(Icons.menu_rounded), findsNothing);
    expect(find.byTooltip('返回'), findsOneWidget);
    expect(find.byKey(const ValueKey('textured-solid-返回')), findsOneWidget);
    await tester.tap(find.byTooltip('返回'));
    expect(popped, isTrue);
  });

  testWidgets('可以从左侧菜单重新查看免责声明', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.menu_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('免责声明'));
    await tester.pumpAndSettle();

    expect(find.text('项目性质'), findsOneWidget);
    expect(find.text('音乐与素材版权'), findsOneWidget);
    expect(find.text('关闭'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsNothing);
    expect(find.byKey(liquidGlassDisclaimerCloseActionKey), findsOneWidget);
    expect(
      tester.widget(find.byKey(liquidGlassDisclaimerCloseActionKey)),
      isA<BackdropFilter>(),
    );
    final fill = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('disclaimer-close-action-glass-fill')),
    );
    final fillDecoration = fill.decoration as BoxDecoration;
    expect(fillDecoration.gradient, isNotNull);
    expect(fillDecoration.color, isNull);

    await tester.tap(find.byKey(const ValueKey('disclaimer-close-action')));
    await tester.pump();

    expect(find.text('项目性质'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 160));
    expect(find.text('项目性质'), findsNothing);
    await tester.pumpAndSettle();
    expect(find.text('项目性质'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('菜单和搜索按钮使用与页面背景联动的中性半透明表面', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    final menuFinder = find.byKey(const ValueKey('textured-solid-个人中心与设置'));
    final searchFinder = find.byKey(const ValueKey('textured-solid-搜索音乐'));
    expect(menuFinder, findsOneWidget);
    expect(searchFinder, findsOneWidget);
    final menu = tester.widget<AnimatedContainer>(menuFinder);
    final menuDecoration = menu.decoration! as BoxDecoration;
    expect(menuDecoration.color, isNotNull);
    expect(menuDecoration.gradient, isNull);
    expect(menuDecoration.shape, BoxShape.rectangle);
    expect(menuDecoration.borderRadius, BorderRadius.circular(15));
    expect(menuDecoration.border, isNotNull);
    expect(menuDecoration.boxShadow, hasLength(1));
    expect(menuDecoration.boxShadow!.single.blurRadius, 8);
    expect(menuDecoration.boxShadow!.single.offset, const Offset(0, 3));
    expect(menuDecoration.color!.a, lessThan(.1));
    expect(menuDecoration.color!.r, menuDecoration.color!.g);
    expect(menuDecoration.color!.g, menuDecoration.color!.b);
    expect(
      find.descendant(of: menuFinder, matching: find.byType(ClipRRect)),
      findsNothing,
    );
    expect(
      find.descendant(of: menuFinder, matching: find.byType(Positioned)),
      findsNothing,
      reason: '单层顶栏按钮不应再绘制独立的顶部高光层',
    );
    expect(
      find.byType(BackdropFilter),
      findsNothing,
      reason: '滚动顶栏不应每帧重算背景模糊，避免挤占 120Hz 的 8.33ms 帧预算',
    );
    expect(tester.takeException(), isNull);

    final lightSurface = menuDecoration.color;
    await tester.pumpWidget(app(brightness: Brightness.dark));
    await tester.pumpAndSettle();
    final darkMenu = tester.widget<AnimatedContainer>(menuFinder);
    final darkDecoration = darkMenu.decoration! as BoxDecoration;
    expect(darkDecoration.color, isNot(lightSurface));
    expect(darkDecoration.gradient, isNull);
    expect(tester.takeException(), isNull);
  });
  testWidgets('设置入口打开独立设置页', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const Scaffold(
            body: SafeArea(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: MusicHubTopBar(title: '发现音乐', subtitle: '探索歌单、新歌与在线音乐'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/music/settings',
          builder: (context, state) => const Scaffold(body: SettingsPage()),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(
            const UnconfiguredAuthRepository(),
          ),
          sharedPreferencesProvider.overrideWithValue(preferences),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.menu_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();

    expect(find.text('装扮'), findsOneWidget);
    expect(find.text('登录 / 注册'), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-back')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('消息入口在侧栏退出并完成两个合成帧后再打开消息页', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const Scaffold(
            body: SafeArea(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: MusicHubTopBar(title: '发现音乐', subtitle: '探索音乐'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/social/messages',
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('消息页已打开'))),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(
            const UnconfiguredAuthRepository(),
          ),
          sharedPreferencesProvider.overrideWithValue(preferences),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.menu_rounded));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('music-hub-my-messages')));
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.text('消息页已打开'), findsNothing);

    await tester.pump(const Duration(milliseconds: 160));
    expect(find.text('消息页已打开'), findsNothing);

    await tester.pump();
    expect(find.text('消息页已打开'), findsNothing);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('消息页已打开'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _DelayedRestoreAuthRepository extends UnconfiguredAuthRepository {
  final restoreGate = Completer<AuthSession?>();

  @override
  Future<AuthSession?> restoreSession() => restoreGate.future;
}
