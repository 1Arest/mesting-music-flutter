import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/features/auth/data/auth_repository.dart';
import 'package:mesting_music/features/auth/auth_providers.dart';
import 'package:mesting_music/features/auth/domain/auth_models.dart';
import 'package:mesting_music/features/auth/presentation/auth_page.dart';
import 'package:mesting_music/features/auth/presentation/account_bindings_page.dart';
import 'package:mesting_music/features/auth/presentation/forgot_password_page.dart';
import 'package:mesting_music/features/library/presentation/favorite_toggle_button.dart';
import 'package:mesting_music/features/history/listening_history_providers.dart';
import 'package:mesting_music/features/history/presentation/listening_history_page.dart';
import 'package:mesting_music/features/legal/presentation/disclaimer_dialog.dart';
import 'package:mesting_music/features/profile/presentation/profile_edit_page.dart';
import 'package:mesting_music/features/profile/presentation/profile_background_visual.dart';
import 'package:mesting_music/features/profile/presentation/profile_page.dart';
import 'package:mesting_music/features/settings/presentation/settings_page.dart';
import 'package:mesting_music/features/social/data/social_repository.dart';
import 'package:mesting_music/features/social/domain/social_models.dart';
import 'package:mesting_music/features/social/presentation/social_widgets.dart';
import 'package:mesting_music/features/social/social_attention.dart';
import 'package:mesting_music/features/social/social_providers.dart';
import 'package:mesting_music/features/themes/mesting_palette.dart';
import 'package:mesting_music/shared/widgets/artwork_image.dart';
import 'package:mesting_music/shared/widgets/liquid_glass_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/test_tracks.dart';

void main() {
  late SharedPreferences preferences;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
  });

  Widget app(Widget child) {
    return ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(
          const UnconfiguredAuthRepository(),
        ),
        sharedPreferencesProvider.overrideWithValue(preferences),
      ],
      child: MaterialApp(home: Scaffold(body: child)),
    );
  }

  testWidgets('favorite button explains login requirement before navigation', (
    tester,
  ) async {
    await tester.pumpWidget(app(FavoriteToggleButton(track: testTracks.first)));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();

    expect(find.text('登录后继续'), findsOneWidget);
    expect(find.textContaining('登录后才能收藏歌曲'), findsOneWidget);
    expect(find.text('去登录 / 注册'), findsOneWidget);
  });

  testWidgets('auth page defaults to phone and switches to email modes', (
    tester,
  ) async {
    await preferences.setBool('mesting_disclaimer_accepted_v1', true);
    await tester.pumpWidget(
      app(const AuthPage(initialMode: 'register', redirect: '/music')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('phone-auth-form')), findsOneWidget);
    expect(find.text('手机号码'), findsOneWidget);
    expect(find.text('一键登录'), findsOneWidget);
    expect(find.byKey(const ValueKey('phone-code-field')), findsNothing);
    expect(find.textContaining('微信'), findsNothing);
    expect(find.textContaining('QQ'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('auth-method-switch')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('email-auth-form')), findsOneWidget);
    expect(find.text('邮箱地址'), findsOneWidget);
    expect(find.text('邮箱验证码'), findsOneWidget);
    expect(find.text('确认密码'), findsOneWidget);
    final passwordField = find.byKey(const ValueKey('email-password-field'));
    final passwordVisibility = find.byKey(
      const ValueKey('email-password-visibility'),
    );
    final confirmPasswordField = find.byKey(
      const ValueKey('email-confirm-password-field'),
    );
    final confirmPasswordVisibility = find.byKey(
      const ValueKey('email-confirm-password-visibility'),
    );
    expect(
      tester.getRect(passwordField).right -
          tester.getRect(passwordVisibility).right,
      greaterThanOrEqualTo(9),
    );
    expect(
      tester.getRect(confirmPasswordField).right -
          tester.getRect(confirmPasswordVisibility).right,
      greaterThanOrEqualTo(9),
    );

    await tester.tap(find.text('登录').first);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, '登录'), findsOneWidget);
    expect(find.text('确认密码'), findsNothing);
  });

  testWidgets('首次登录识别手机号后不显示 SIM 成功提示', (tester) async {
    const channel = MethodChannel('com.mesting.music/device_identity');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      expect(call.method, 'getDataSimPhoneNumber');
      return <String, Object?>{
        'phoneNumber': '13100009498',
        'maskedPhoneNumber': '131****9498',
        'simSlot': 1,
        'unavailableReason': '',
      };
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );

    await preferences.setBool('mesting_disclaimer_accepted_v1', true);
    await tester.pumpWidget(
      app(
        const AuthPage(
          initialMode: 'login',
          redirect: '/music',
          firstLaunch: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final phoneField = find.byKey(const ValueKey('phone-number-field'));
    final editable = tester.widget<EditableText>(
      find.descendant(of: phoneField, matching: find.byType(EditableText)),
    );
    expect(editable.readOnly, isTrue);
    expect(find.text('131****9498'), findsOneWidget);
    expect(find.textContaining('正在识别当前上网卡'), findsNothing);
    expect(find.textContaining('已识别当前上网卡'), findsNothing);
    expect(find.textContaining('SIM 1'), findsNothing);
  });

  testWidgets('email login and registration share one sliding selection', (
    tester,
  ) async {
    await preferences.setBool('mesting_disclaimer_accepted_v1', true);
    await tester.pumpWidget(
      app(const AuthPage(initialMode: 'login', redirect: '/music')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('auth-method-switch')));
    await tester.pumpAndSettle();

    final switchFinder = find.byKey(const ValueKey('email-mode-switch'));
    final indicatorFinder = find.byKey(const ValueKey('email-mode-indicator'));
    expect(indicatorFinder, findsOneWidget);
    expect(
      tester.getCenter(indicatorFinder).dx,
      lessThan(tester.getCenter(switchFinder).dx),
    );

    await tester.tap(find.byKey(const ValueKey('email-mode-register')));
    await tester.pump(const Duration(milliseconds: 90));
    expect(indicatorFinder, findsOneWidget);
    expect(find.byKey(const ValueKey('email-mode-login')), findsOneWidget);
    expect(find.byKey(const ValueKey('email-mode-register')), findsOneWidget);

    await tester.pumpAndSettle();
    expect(
      tester.getCenter(indicatorFinder).dx,
      greaterThan(tester.getCenter(switchFinder).dx),
    );
    expect(
      find.byKey(const ValueKey('email-confirm-password-field')),
      findsOneWidget,
    );
  });

  testWidgets('email registration rejects mismatched confirmation password', (
    tester,
  ) async {
    await preferences.setBool('mesting_disclaimer_accepted_v1', true);
    await tester.pumpWidget(
      app(const AuthPage(initialMode: 'register', redirect: '/music')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('auth-method-switch')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('email-account-field')),
      'music@example.com',
    );
    await tester.enterText(
      find.byKey(const ValueKey('email-code-field')),
      '123456',
    );
    await tester.enterText(
      find.byKey(const ValueKey('email-password-field')),
      'password123',
    );
    await tester.enterText(
      find.byKey(const ValueKey('email-confirm-password-field')),
      'password456',
    );
    await tester.ensureVisible(find.widgetWithText(FilledButton, '注册并登录'));
    await tester.tap(find.widgetWithText(FilledButton, '注册并登录'));
    await tester.pumpAndSettle();

    expect(find.text('两次输入的密码不一致'), findsOneWidget);
  });

  testWidgets(
    'unchecked phone login stays muted and shakes the disclaimer checkbox',
    (tester) async {
      await tester.pumpWidget(
        app(const AuthPage(initialMode: 'login', redirect: '/music')),
      );
      await tester.pumpAndSettle();

      FilledButton primary = tester.widget(
        find.byKey(const ValueKey('phone-primary-action')),
      );
      expect(primary.onPressed, isNotNull);
      expect(
        primary.style?.backgroundColor?.resolve(<WidgetState>{}),
        const Color(0xFF5268D7).withValues(alpha: .25),
      );

      await tester.enterText(
        find.byKey(const ValueKey('phone-number-field')),
        '13100009498',
      );
      final primaryFinder = find.byKey(const ValueKey('phone-primary-action'));
      await tester.ensureVisible(primaryFinder);
      await tester.pumpAndSettle();
      await tester.tap(primaryFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 35));

      final shake = tester.widget<Transform>(
        find.byKey(const ValueKey('disclaimer-checkbox-shake')),
      );
      expect(shake.transform.storage[12].abs(), greaterThan(.3));
      expect(
        find.byKey(const ValueKey('disclaimer-read-confirm')),
        findsNothing,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('需阅读 5 秒'));
      await tester.pump(const Duration(milliseconds: 350));
      expect(
        find.byKey(const ValueKey('disclaimer-read-confirm')),
        findsOneWidget,
      );
      FilledButton confirm = tester.widget(
        find.byKey(const ValueKey('disclaimer-read-confirm')),
      );
      expect(confirm.onPressed, isNull);

      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
      confirm = tester.widget(
        find.byKey(const ValueKey('disclaimer-read-confirm')),
      );
      expect(confirm.onPressed, isNotNull);
      await tester.tap(find.byKey(const ValueKey('disclaimer-read-confirm')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('disclaimer-checkbox')));
      await tester.pump();
      primary = tester.widget(
        find.byKey(const ValueKey('phone-primary-action')),
      );
      expect(primary.onPressed, isNotNull);
      expect(
        primary.style?.backgroundColor?.resolve(<WidgetState>{}),
        const Color(0xFF5268D7),
      );
    },
  );

  testWidgets(
    'disclaimer only enforces five seconds before the first completed read',
    (tester) async {
      await tester.pumpWidget(
        app(const AuthPage(initialMode: 'login', redirect: '/music')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('需阅读 5 秒'));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('disclaimer-read-confirm')));
      await tester.pumpAndSettle();

      expect(preferences.getBool(legalDocumentsReadPreferenceKey), isTrue);
      expect(preferences.getBool(disclaimerAcceptedPreferenceKey), isNot(true));
      expect(
        tester
            .widget<Checkbox>(find.byKey(const ValueKey('disclaimer-checkbox')))
            .value,
        isFalse,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        app(const AuthPage(initialMode: 'login', redirect: '/music')),
      );
      await tester.pumpAndSettle();

      expect(find.text('《用户协议》《隐私政策》'), findsOneWidget);
      expect(find.textContaining('需阅读 5 秒'), findsNothing);
      await tester.tap(find.text('《用户协议》《隐私政策》'));
      await tester.pump(const Duration(milliseconds: 350));

      final confirm = tester.widget<FilledButton>(
        find.byKey(const ValueKey('disclaimer-read-confirm')),
      );
      expect(confirm.onPressed, isNotNull);
      expect(find.text('我已阅读并理解'), findsOneWidget);
    },
  );

  testWidgets(
    'unchecked email password login also shakes instead of submitting',
    (tester) async {
      await tester.pumpWidget(
        app(const AuthPage(initialMode: 'login', redirect: '/music')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('auth-method-switch')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('email-account-field')),
        'music@example.com',
      );
      await tester.enterText(
        find.byKey(const ValueKey('email-password-field')),
        'password123',
      );
      final primary = find.byKey(const ValueKey('email-primary-action'));
      await tester.ensureVisible(primary);
      await tester.pumpAndSettle();

      final button = tester.widget<FilledButton>(primary);
      expect(button.onPressed, isNotNull);
      expect(
        button.style?.backgroundColor?.resolve(<WidgetState>{}),
        const Color(0xFF5268D7).withValues(alpha: .25),
      );

      await tester.tap(primary);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 35));

      final shake = tester.widget<Transform>(
        find.byKey(const ValueKey('disclaimer-checkbox-shake')),
      );
      expect(shake.transform.storage[12].abs(), greaterThan(.3));
      expect(find.textContaining('尚未配置'), findsNothing);
    },
  );

  testWidgets(
    'first checkbox tap opens disclaimer and accepts after five seconds',
    (tester) async {
      await tester.pumpWidget(
        app(const AuthPage(initialMode: 'login', redirect: '/music')),
      );
      await tester.pumpAndSettle();

      final checkboxFinder = find.byKey(const ValueKey('disclaimer-checkbox'));
      final agreementFinder = find.text('我已阅读并同意 ');
      expect(
        (tester.getCenter(checkboxFinder).dy -
                tester.getCenter(agreementFinder).dy)
            .abs(),
        lessThan(1),
      );

      await tester.tap(checkboxFinder);
      await tester.pump(const Duration(milliseconds: 350));
      expect(
        find.byKey(const ValueKey('disclaimer-read-confirm')),
        findsOneWidget,
      );

      Checkbox checkbox = tester.widget(checkboxFinder);
      expect(checkbox.value, isFalse);

      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('disclaimer-read-confirm')));
      await tester.pumpAndSettle();

      checkbox = tester.widget(checkboxFinder);
      expect(checkbox.value, isTrue);
      final primary = tester.widget<FilledButton>(
        find.byKey(const ValueKey('phone-primary-action')),
      );
      expect(primary.onPressed, isNotNull);
    },
  );

  testWidgets('first email registration checkbox tap also opens disclaimer', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(const AuthPage(initialMode: 'register', redirect: '/music')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('auth-method-switch')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('email-auth-form')), findsOneWidget);
    final checkboxFinder = find.byKey(const ValueKey('disclaimer-checkbox'));
    await tester.ensureVisible(checkboxFinder);
    await tester.pumpAndSettle();
    await tester.tap(checkboxFinder);
    await tester.pump(const Duration(milliseconds: 350));

    expect(
      find.byKey(const ValueKey('disclaimer-read-confirm')),
      findsOneWidget,
    );
    expect(tester.widget<Checkbox>(checkboxFinder).value, isFalse);
  });

  testWidgets('guest profile presents account identity and cloud benefits', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(app(const ProfilePage()));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('guest-profile-hero')), findsOneWidget);
    expect(find.text('访客模式'), findsOneWidget);
    expect(find.text('让喜欢的音乐，一直在身边'), findsOneWidget);
    expect(find.text('登录或创建账号'), findsOneWidget);
    expect(find.text('收藏与歌单同步'), findsOneWidget);
    expect(find.text('建立个人音乐主页'), findsOneWidget);
    expect(find.text('换设备继续使用'), findsOneWidget);
    expect(find.textContaining('Android Keystore'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.scrollUntilVisible(
      find.text('暂不登录也可以继续发现和播放音乐'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('暂不登录也可以继续发现和播放音乐'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('signed profile keeps account controls out of My', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(
            LocalPreviewAuthRepository(preferences: preferences),
          ),
          sharedPreferencesProvider.overrideWithValue(preferences),
        ],
        child: const MaterialApp(home: Scaffold(body: ProfilePage())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('local@device'), findsNothing);
    expect(find.text('账号与绑定'), findsNothing);
    expect(find.text('账号云端状态'), findsNothing);
    expect(find.text('退出登录'), findsNothing);
    expect(find.textContaining('微信'), findsNothing);
    expect(find.textContaining('QQ'), findsNothing);
    final avatar = tester.widget<Container>(
      find.byKey(const ValueKey('profile-avatar')),
    );
    expect((avatar.decoration! as BoxDecoration).shape, BoxShape.circle);
    await tester.scrollUntilVisible(
      find.text('听歌排行'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('听歌排行'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('装扮'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('装扮'), findsOneWidget);
    expect(find.text('皮肤、IP 主题、图标与启动页'), findsOneWidget);
    final dressUpGlyph = find.byKey(const ValueKey('profile-dress-up-glyph'));
    expect(dressUpGlyph, findsOneWidget);
    expect(
      find.descendant(of: dressUpGlyph, matching: find.byType(CustomPaint)),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.checkroom_rounded), findsNothing);
  });

  testWidgets('profile unread badge opens messages without visiting friends', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/profile',
      routes: [
        GoRoute(
          path: '/profile',
          builder: (context, state) => const Scaffold(body: ProfilePage()),
        ),
        GoRoute(
          path: '/social/messages',
          builder: (context, state) =>
              const Scaffold(body: Text('profile-messages-destination')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(
            LocalPreviewAuthRepository(preferences: preferences),
          ),
          sharedPreferencesProvider.overrideWithValue(preferences),
          socialAttentionControllerProvider.overrideWith(
            _ProfileUnreadAttentionController.new,
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    final badge = find.byKey(const ValueKey('profile-social-unread-badge'));
    expect(badge, findsOneWidget);

    await tester.tap(badge);
    await tester.pumpAndSettle();

    expect(find.text('profile-messages-destination'), findsOneWidget);
  });

  testWidgets('profile keeps the last status visible while remote refreshes', (
    tester,
  ) async {
    const user = AuthUser(uid: 'cached-status-user', nickname: 'Mesting');
    const cachedStatus = SocialStatus(emoji: '🌷', text: '等春天');
    await rememberSocialStatusSnapshot(preferences, user.uid, cachedStatus);
    final remoteStatus = Completer<SocialStatus>();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(
            _RestoredSessionAuthRepository(
              AuthSession(
                user: user,
                accessToken: 'access',
                refreshToken: 'refresh',
                expiresAt: DateTime.utc(2099),
              ),
            ),
          ),
          sharedPreferencesProvider.overrideWithValue(preferences),
          socialStatusProvider.overrideWith((ref) => remoteStatus.future),
        ],
        child: const MaterialApp(home: Scaffold(body: ProfilePage())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('等春天'), findsOneWidget);
    expect(find.text('添加状态'), findsNothing);
  });

  testWidgets('signed profile confines its background to the hero', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1024, 768);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(
            _RestoredSessionAuthRepository(
              AuthSession(
                user: const AuthUser(uid: 'rounded-user', nickname: 'Mesting'),
                accessToken: 'access',
                refreshToken: 'refresh',
                expiresAt: DateTime.utc(2099),
              ),
            ),
          ),
          sharedPreferencesProvider.overrideWithValue(preferences),
        ],
        child: const MaterialApp(home: Scaffold(body: ProfilePage())),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('profile-immersive-background')),
      findsNothing,
    );
    final hero = find.byKey(const ValueKey('profile-immersive-hero'));
    expect(hero, findsOneWidget);
    expect(tester.getSize(hero).height, 300);
    expect(
      find.descendant(
        of: hero,
        matching: find.byKey(const ValueKey('profile-hero-background')),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('profile-dashboard')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('profile-dashboard')),
        matching: find.byType(ProfileBackgroundVisual),
      ),
      findsNothing,
      reason: '个人主页背景只允许出现在顶部资料舞台，不得延伸到功能卡片区域',
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('profile-hero-content'))).width,
      780,
    );
    expect(
      find.byKey(const ValueKey('profile-expanded-sections')),
      findsOneWidget,
    );
    for (final id in const ['playlists', 'history', 'friends', 'dress-up']) {
      expect(
        find.byKey(ValueKey('profile-dashboard-card-$id')),
        findsOneWidget,
      );
    }
    for (final label in const ['关注', '粉丝', '歌单', '完整播放']) {
      expect(find.byKey(ValueKey('profile-stat-$label')), findsNothing);
    }
    final surface = find.byKey(
      const ValueKey('profile-dashboard-card-playlists'),
    );
    final material = tester.widget<Material>(
      find.descendant(of: surface, matching: find.byType(Material)).first,
    );
    final shape = material.shape! as RoundedRectangleBorder;
    expect(material.clipBehavior, Clip.antiAlias);
    expect(material.color, isNot(Colors.transparent));
    expect(shape.borderRadius, BorderRadius.circular(24));
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('profile-dashboard')),
        matching: find.byType(BackdropFilter),
      ),
      findsNothing,
      reason: '滚动中的功能卡片使用静态半透明表面，避免四张实时模糊卡片争抢帧预算',
    );
    final shadowSurface = tester.widget<DecoratedBox>(surface);
    final sectionShadows =
        (shadowSurface.decoration as BoxDecoration).boxShadow!;
    expect(sectionShadows, hasLength(1));
    expect(sectionShadows.first.color.a, lessThan(.25));
    expect(sectionShadows.first.blurRadius, 20);
    expect(sectionShadows.first.offset.dy, 8);

    final gesture = await tester.startGesture(tester.getCenter(surface));
    await tester.pump(const Duration(milliseconds: 80));
    expect(tester.takeException(), isNull);
    await gesture.cancel();
  });

  testWidgets('profile header opens the playlist creation drawer and editor', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(
            LocalPreviewAuthRepository(preferences: preferences),
          ),
          sharedPreferencesProvider.overrideWithValue(preferences),
          socialStatusProvider.overrideWith(
            (ref) async => const SocialStatus(emoji: '🎧', text: '今天只听很长很长的慢歌'),
          ),
          socialSummaryProvider.overrideWith(
            (ref) async => const SocialSummary(
              followingCount: 1,
              followerCount: 1,
              unreadCount: 128,
            ),
          ),
          socialAttentionControllerProvider.overrideWith(
            _ProfileUnreadAttentionController.new,
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: ProfilePage())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('我的'), findsNothing);
    expect(find.text('消息'), findsNothing);
    expect(find.byKey(const ValueKey('profile-menu-button')), findsOneWidget);
    expect(find.byKey(const ValueKey('profile-search-button')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('profile-create-menu-button')),
      findsOneWidget,
    );
    final headerStatus = find.byKey(const ValueKey('profile-header-status'));
    expect(headerStatus, findsOneWidget);
    expect(tester.widget<SocialStatusBadge>(headerStatus).plain, isTrue);
    expect(
      find.descendant(
        of: headerStatus,
        matching: find.byIcon(Icons.expand_more_rounded),
      ),
      findsNothing,
    );
    expect(
      find.descendant(of: headerStatus, matching: find.byType(DecoratedBox)),
      findsNothing,
    );
    expect(
      tester.getCenter(headerStatus).dx,
      closeTo(tester.view.physicalSize.width / 2, .01),
    );
    expect(
      tester
          .getCenter(find.byKey(const ValueKey('profile-header-center-lane')))
          .dx,
      closeTo(tester.view.physicalSize.width / 2, .01),
    );
    expect(
      tester.getCenter(headerStatus).dx,
      lessThan(
        tester
            .getCenter(find.byKey(const ValueKey('profile-create-menu-button')))
            .dx,
      ),
    );
    expect(
      tester.getCenter(headerStatus).dy,
      lessThan(
        tester.getTopLeft(find.byKey(const ValueKey('profile-avatar'))).dy,
      ),
    );
    expect(find.byType(SocialStatusBadge), findsOneWidget);
    for (final key in const [
      ValueKey('profile-menu-button'),
      ValueKey('profile-create-menu-button'),
      ValueKey('profile-search-button'),
    ]) {
      expect(tester.getSize(find.byKey(key)), const Size.square(48));
    }

    await tester.tap(find.byKey(const ValueKey('profile-menu-button')));
    await tester.pumpAndSettle();

    expect(find.text('MESTING SPACE'), findsOneWidget);
    expect(find.text('我的消息'), findsOneWidget);
    expect(find.byKey(const ValueKey('music-hub-my-messages')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('music-hub-unread-badge')),
      findsOneWidget,
    );
    final unreadBadge = tester.widget<Container>(
      find.byKey(const ValueKey('music-hub-unread-badge')),
    );
    expect(
      (unreadBadge.decoration! as BoxDecoration).color,
      MestingPalette.heart,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('music-hub-unread-badge')),
        matching: find.text('3'),
      ),
      findsOneWidget,
    );
    expect(find.text('应用设置'), findsOneWidget);
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('profile-create-menu-button')));
    await tester.pumpAndSettle();

    expect(find.text('快速创建'), findsOneWidget);
    expect(find.text('创建音乐歌单'), findsOneWidget);
    expect(find.text('自定义名称、描述和封面'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('profile-create-playlist-action')),
    );
    await tester.pumpAndSettle();

    expect(find.text('新建歌单'), findsOneWidget);
    expect(find.byKey(const ValueKey('playlist-editor-sheet')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('listening history separates ranking and recent playback', (
    tester,
  ) async {
    final now = DateTime.now();
    final ranking = [
      ListeningHistoryItem(
        track: testTracks.first,
        completedPlayCount: 3,
        totalListened: const Duration(minutes: 10),
        lastPlayedAt: now,
      ),
    ];
    final recent = [
      ListeningHistoryItem(
        track: testTracks[1],
        completedPlayCount: 0,
        totalListened: const Duration(seconds: 18),
        lastPlayedAt: now,
      ),
    ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          listeningRankingProvider.overrideWith((ref) => Stream.value(ranking)),
          recentPlaybackProvider.overrideWith((ref) => Stream.value(recent)),
        ],
        child: const MaterialApp(home: Scaffold(body: ListeningHistoryPage())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('完整听完 3 次'), findsNothing);
    expect(find.text('3次'), findsOneWidget);
    final completedCount = find.byKey(
      ValueKey('completed-play-count-${testTracks.first.id}'),
    );
    expect(completedCount, findsOneWidget);
    expect(
      find.descendant(
        of: completedCount,
        matching: find.byIcon(Icons.play_arrow_outlined),
      ),
      findsOneWidget,
    );
    final rankingCard = find.byKey(
      ValueKey('history-track-${testTracks.first.id}'),
    );
    expect(
      find.descendant(of: rankingCard, matching: find.byType(BackdropFilter)),
      findsNothing,
      reason: '听歌排行的滚动卡片不应实时模糊背景，以避免平板页面转场掉帧',
    );
    final glassDecorations = tester
        .widgetList<DecoratedBox>(
          find.descendant(of: rankingCard, matching: find.byType(DecoratedBox)),
        )
        .map((box) => box.decoration)
        .whereType<BoxDecoration>()
        .where((decoration) => decoration.boxShadow?.isNotEmpty ?? false)
        .toList();
    expect(glassDecorations, isNotEmpty);
    expect(
      glassDecorations.first.boxShadow!.first.blurRadius,
      lessThanOrEqualTo(listeningHistoryPrimaryShadowBlurRadius),
    );
    expect(
      glassDecorations.first.boxShadow!.first.color.a,
      lessThanOrEqualTo(listeningHistoryLightShadowAlpha),
    );
    expect(find.text(testTracks.first.title), findsOneWidget);

    await tester.tap(find.text('最近播放'));
    await tester.pumpAndSettle();

    expect(find.text(testTracks[1].title), findsOneWidget);
    expect(find.text('刚刚播放'), findsOneWidget);
  });

  testWidgets('settings presents bindings, CloudBase status and sign out', (
    tester,
  ) async {
    final session = AuthSession(
      user: const AuthUser(
        uid: 'cloud-user',
        nickname: 'Cloud User',
        emailMasked: 'c***@example.com',
      ),
      accessToken: 'access',
      refreshToken: 'refresh',
      expiresAt: DateTime.utc(2099),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(
            _RestoredSessionAuthRepository(session),
          ),
          authBackendKindProvider.overrideWithValue(AuthBackendKind.cloudBase),
          sharedPreferencesProvider.overrideWithValue(preferences),
        ],
        child: const MaterialApp(home: Scaffold(body: SettingsPage())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('账号云端状态'), findsOneWidget);
    expect(find.text('装扮'), findsOneWidget);
    expect(find.text('账号与绑定'), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('settings-check-update'))).dy,
      greaterThan(
        tester
            .getBottomLeft(find.byKey(const ValueKey('settings-cloud-status')))
            .dy,
      ),
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('settings-sign-out')),
      240,
    );
    expect(find.text('退出登录'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('settings-delete-account')),
      findsOneWidget,
    );
    expect(find.text('CloudBase 身份认证已连接'), findsOneWidget);
    expect(find.text('等待云端环境连接'), findsNothing);
  });

  testWidgets('settings sign out uses the branded floating notice', (
    tester,
  ) async {
    final session = AuthSession(
      user: const AuthUser(
        uid: 'sign-out-user',
        nickname: 'Mesting Listener',
        emailMasked: 'm***@example.com',
      ),
      accessToken: 'access',
      refreshToken: 'refresh',
      expiresAt: DateTime.utc(2099),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(
            _RestoredSessionAuthRepository(session),
          ),
          sharedPreferencesProvider.overrideWithValue(preferences),
        ],
        child: const MaterialApp(home: Scaffold(body: SettingsPage())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('settings-sign-out')),
      240,
    );
    await tester.tap(find.byKey(const ValueKey('settings-sign-out')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '退出登录'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));

    expect(find.text('已安全退出'), findsOneWidget);
    expect(find.text('云端数据仍为你保留'), findsNothing); // Compact status keeps the result title.
    expect(find.byIcon(Icons.logout_rounded), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('settings opens the dedicated dress-up panel', (tester) async {
    await tester.pumpWidget(app(const SettingsPage()));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.tune_rounded), findsNothing);
    await tester.tap(find.byKey(const ValueKey('settings-theme')));
    await tester.pumpAndSettle();

    expect(find.text('装扮'), findsWidgets);
    expect(find.text('品牌套装'), findsOneWidget);
    expect(find.text('播放器样式'), findsOneWidget);
    await tester.drag(
      find.byType(CustomScrollView).last,
      const Offset(0, -480),
    );
    await tester.pumpAndSettle();
    expect(find.text('皮肤'), findsOneWidget);
    expect(find.byTooltip('关闭装扮'), findsOneWidget);
  });

  testWidgets('settings back button has no dark blurred layer', (tester) async {
    await tester.pumpWidget(app(const SettingsPage()));
    await tester.pumpAndSettle();

    final back = find.byKey(const ValueKey('settings-back'));
    final decoratedContainer = tester.widget<Container>(
      find.descendant(of: back, matching: find.byType(Container)).first,
    );
    final decoration = decoratedContainer.decoration! as BoxDecoration;

    expect(decoration.borderRadius, BorderRadius.circular(17));
    expect(decoration.border, isNotNull);
    expect(decoration.boxShadow, isNull);
  });

  testWidgets('signed profile retries a newly uploaded network avatar', (
    tester,
  ) async {
    final session = AuthSession(
      user: const AuthUser(
        uid: 'avatar-user',
        nickname: 'Mesting',
        bio: '',
        avatarUrl: 'https://cdn.example/avatar.png',
      ),
      accessToken: 'access',
      refreshToken: 'refresh',
      expiresAt: DateTime.utc(2099),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(
            _RestoredSessionAuthRepository(session),
          ),
          sharedPreferencesProvider.overrideWithValue(preferences),
        ],
        child: const MaterialApp(home: Scaffold(body: ProfilePage())),
      ),
    );
    await tester.pumpAndSettle();

    final avatar = tester.widget<ArtworkImage>(find.byType(ArtworkImage));
    expect(avatar.uri, session.user.avatarUrl);
    expect(avatar.retryOnNetworkError, isTrue);
  });

  testWidgets('saving profile confirms success after returning', (
    tester,
  ) async {
    final session = AuthSession(
      user: const AuthUser(uid: 'profile-user', nickname: 'Mest', bio: ''),
      accessToken: 'access',
      refreshToken: 'refresh',
      expiresAt: DateTime.utc(2099),
    );
    final updateGate = Completer<void>();
    final repository = _ProfileUpdateAuthRepository(
      session,
      updateGate: updateGate,
    );
    final socialRepository = _ProfileDetailsSocialRepository(
      const SocialUser(uid: 'profile-user', nickname: 'Mest'),
    );
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) =>
              const Scaffold(body: Center(child: Text('个人资料入口'))),
        ),
        GoRoute(
          path: '/edit',
          builder: (_, _) => const Scaffold(body: ProfileEditPage()),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(repository),
          socialRepositoryProvider.overrideWithValue(socialRepository),
          sharedPreferencesProvider.overrideWithValue(preferences),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    router.push('/edit');
    await tester.pumpAndSettle();

    final avatar = tester.widget<Container>(
      find.byKey(const ValueKey('profile-edit-avatar')),
    );
    expect(find.byKey(liquidGlassProfileEditSurfaceKey), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(liquidGlassProfileEditSurfaceKey),
        matching: find.byType(BackdropFilter),
      ),
      findsOneWidget,
    );
    expect((avatar.decoration! as BoxDecoration).shape, BoxShape.circle);
    expect(find.text('点击预览头像'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('profile-edit-background-entry')),
      findsOneWidget,
    );
    expect(find.textContaining('JPG/PNG/WebP'), findsNothing);
    final nicknameSurface = tester.widget<AnimatedContainer>(
      find.byKey(profileEditNicknameFieldSurfaceKey),
    );
    final bioSurface = tester.widget<AnimatedContainer>(
      find.byKey(profileEditBioFieldSurfaceKey),
    );
    final nicknameDecoration = nicknameSurface.decoration! as BoxDecoration;
    final bioDecoration = bioSurface.decoration! as BoxDecoration;
    expect(nicknameDecoration.boxShadow, hasLength(2));
    expect(bioDecoration.boxShadow, hasLength(2));
    final idleNicknameShadow = nicknameDecoration.boxShadow!.first.color;

    await tester.tap(find.byType(TextFormField).first);
    await tester.pump(const Duration(milliseconds: 200));
    final focusedNicknameSurface = tester.widget<AnimatedContainer>(
      find.byKey(profileEditNicknameFieldSurfaceKey),
    );
    final focusedNicknameDecoration =
        focusedNicknameSurface.decoration! as BoxDecoration;
    expect(
      focusedNicknameDecoration.boxShadow!.first.color,
      isNot(idleNicknameShadow),
    );

    await tester.ensureVisible(find.byKey(const ValueKey('profile-edit-age')));
    await tester.tap(find.byKey(const ValueKey('profile-edit-age')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('profile-age-increase')));
    await tester.tap(find.byKey(const ValueKey('profile-age-confirm')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('profile-edit-zodiac')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('profile-zodiac-天秤座')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, 'Mest Music');
    await tester.ensureVisible(find.text('保存资料'));
    final saveButton = find.byType(FilledButton);
    await tester.tap(saveButton);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.widget<FilledButton>(saveButton).onPressed, isNull);
    await tester.tap(saveButton);
    await tester.pump();
    expect(repository.updateCalls, 1);

    updateGate.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('个人资料入口'), findsOneWidget);
    expect(find.text('资料已保存'), findsOneWidget);
    expect(find.text('头像、昵称、简介和更多资料已更新'), findsNothing);
    expect(repository.session.user.nickname, 'Mest Music');
    expect(repository.session.user.age, 19);
    expect(repository.session.user.zodiac, '天秤座');
    expect(socialRepository.savedAge, 19);
    expect(socialRepository.savedZodiac, '天秤座');
  });

  testWidgets('account binding requires current identity before new email', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(
            LocalPreviewAuthRepository(preferences: preferences),
          ),
          sharedPreferencesProvider.overrideWithValue(preferences),
        ],
        child: const MaterialApp(home: AccountBindingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('local@device'), findsOneWidget);
    final bindingCard = find.byKey(const ValueKey('manage-email-binding'));
    final bindingInkWell = tester.widget<InkWell>(bindingCard);
    expect(bindingInkWell.borderRadius, BorderRadius.circular(22));
    final bindingMaterial = tester
        .element(bindingCard)
        .findAncestorWidgetOfExactType<Material>();
    expect(bindingMaterial, isNotNull);
    expect(bindingMaterial!.clipBehavior, Clip.antiAlias);
    expect(
      (bindingMaterial.shape! as RoundedRectangleBorder).borderRadius,
      BorderRadius.circular(22),
    );

    await tester.tap(bindingCard);
    await tester.pumpAndSettle();
    expect(find.text('先确认是你本人'), findsOneWidget);
    expect(find.byKey(liquidGlassSheetSurfaceKey), findsOneWidget);
    expect(find.byKey(liquidGlassSurfaceBodyKey), findsOneWidget);
    expect(
      tester.widget(find.byKey(const ValueKey('account-binding-flow-sheet'))),
      isA<SingleChildScrollView>(),
    );
    final sendCodeAction = find.widgetWithText(FilledButton, '发送当前身份验证码');
    final sendCodeButton = tester.widget<FilledButton>(sendCodeAction);
    final sendCodeScheme = Theme.of(tester.element(sendCodeAction)).colorScheme;
    expect(
      sendCodeButton.style!.backgroundColor!.resolve(const <WidgetState>{}),
      sendCodeScheme.primary,
    );
    expect(
      sendCodeButton.style!.backgroundColor!.resolve(const <WidgetState>{}),
      isNot(const Color(0xFFC24A34)),
    );

    await tester.tap(find.text('发送当前身份验证码'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).last, '123456');
    await tester.tap(find.widgetWithText(FilledButton, '验证当前身份'));
    await tester.pumpAndSettle();

    expect(find.text('更换邮箱'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'new@example.com');
    await tester.tap(find.text('发送新邮箱验证码'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).last, '654321');
    await tester.tap(find.text('确认安全更新'));
    await tester.pumpAndSettle();

    expect(find.text('n***@example.com'), findsOneWidget);
    expect(find.text('邮箱已安全更新'), findsOneWidget);
  });

  testWidgets('account binding sheet stays above the shell mini player', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 800);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    var miniPlayerTaps = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(
            LocalPreviewAuthRepository(preferences: preferences),
          ),
          sharedPreferencesProvider.overrideWithValue(preferences),
        ],
        child: MaterialApp(
          home: Stack(
            children: [
              Positioned.fill(
                child: Navigator(
                  onGenerateRoute: (_) => MaterialPageRoute<void>(
                    builder: (_) => const Scaffold(body: AccountBindingsPage()),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 260,
                child: GestureDetector(
                  key: const ValueKey('mini-player-obstruction-probe'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => miniPlayerTaps += 1,
                  child: const ColoredBox(color: Color(0xFF17131B)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('manage-phone-binding')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('account-binding-flow-sheet')),
      findsOneWidget,
    );
    final sendCode = find.text('发送当前身份验证码');
    expect(tester.getCenter(sendCode).dy, greaterThan(540));
    await tester.tap(sendCode);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('6 位验证码'), findsOneWidget);
    expect(miniPlayerTaps, 0);
  });

  testWidgets(
    'password recovery accepts a lowercase-only password and returns a safe result',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(
              LocalPreviewAuthRepository(preferences: preferences),
            ),
            sharedPreferencesProvider.overrideWithValue(preferences),
          ],
          child: const MaterialApp(
            home: ForgotPasswordPage(redirect: '/music/recommend'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('forgot-password-back')), findsNothing);
      expect(find.byIcon(Icons.arrow_back_rounded), findsNothing);
      final sendCodeButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '发送验证码'),
      );
      expect(
        sendCodeButton.style?.backgroundColor?.resolve(const {}),
        const Color(0xFFC24A34),
      );
      expect(
        sendCodeButton.style?.foregroundColor?.resolve(const {}),
        Colors.white,
      );

      await tester.enterText(
        find.byKey(const ValueKey('password-recovery-account')),
        'listener@example.com',
      );
      await tester.tap(find.text('发送验证码'));
      await tester.pump();
      expect(find.textContaining('如果该账号存在'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('password-recovery-code')),
        '123456',
      );
      await tester.tap(find.text('验证并继续'));
      await tester.pumpAndSettle();

      final confirmField = find.byKey(
        const ValueKey('password-recovery-confirm'),
      );
      final confirmVisibility = find.byKey(
        const ValueKey('password-recovery-confirm-visibility'),
      );
      final confirmFieldRect = tester.getRect(confirmField);
      final confirmVisibilityRect = tester.getRect(confirmVisibility);
      expect(
        confirmFieldRect.right - confirmVisibilityRect.right,
        greaterThanOrEqualTo(9),
      );
      expect(tester.widget<TextField>(confirmField).obscureText, isTrue);
      await tester.tap(confirmVisibility);
      await tester.pump();
      expect(tester.widget<TextField>(confirmField).obscureText, isFalse);

      await tester.enterText(
        find.byKey(const ValueKey('password-recovery-password')),
        'short',
      );
      await tester.enterText(
        find.byKey(const ValueKey('password-recovery-confirm')),
        'short',
      );
      await tester.tap(find.text('更新密码并退出旧设备'));
      await tester.pump();
      expect(find.text('密码长度需为 8–64 位'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('password-recovery-password')),
        'lowercaseonly',
      );
      await tester.enterText(
        find.byKey(const ValueKey('password-recovery-confirm')),
        'lowercaseonly',
      );
      await tester.tap(find.text('更新密码并退出旧设备'));
      await tester.pumpAndSettle();

      expect(find.text('密码已经更新'), findsOneWidget);
      expect(find.textContaining('旧密码和旧会话均已失效'), findsOneWidget);
    },
  );

  test('password recovery never exposes an English backend error', () {
    expect(
      forgotPasswordErrorMessage(
        const AuthRequestException('Method Not Allowed', code: 'unimplemented'),
      ),
      '密码重置失败，请稍后重试',
    );
    expect(
      forgotPasswordErrorMessage(const AuthRequestException('验证码已过期，请重新获取')),
      '验证码已过期，请重新获取',
    );
  });
}

class _ProfileUnreadAttentionController extends SocialAttentionController {
  @override
  SocialAttention build() => const SocialAttention(messageUnreadCount: 3);
}

class _RestoredSessionAuthRepository extends UnconfiguredAuthRepository {
  const _RestoredSessionAuthRepository(this.session);

  final AuthSession session;

  @override
  Future<AuthSession?> restoreSession() async => session;
}

class _ProfileUpdateAuthRepository extends UnconfiguredAuthRepository {
  _ProfileUpdateAuthRepository(this.session, {this.updateGate});

  AuthSession session;
  final Completer<void>? updateGate;
  int updateCalls = 0;

  @override
  Future<AuthSession?> restoreSession() async => session;

  @override
  Future<AuthSession> updateProfile({
    required String nickname,
    required String bio,
    int? age,
    String zodiac = '',
    String? avatarPath,
  }) async {
    updateCalls += 1;
    await updateGate?.future;
    session = session.copyWith(
      user: session.user.copyWith(
        nickname: nickname,
        bio: bio,
        age: age,
        zodiac: zodiac,
      ),
    );
    return session;
  }
}

class _ProfileDetailsSocialRepository extends Fake implements SocialRepository {
  _ProfileDetailsSocialRepository(this.user);

  SocialUser user;
  int? savedAge;
  String savedZodiac = '';

  @override
  Future<SocialUser> getUser(String uid) async => user;

  @override
  Future<SocialUser> updateProfileDetails({
    required int? age,
    required String zodiac,
  }) async {
    savedAge = age;
    savedZodiac = zodiac;
    user = SocialUser(
      uid: user.uid,
      nickname: user.nickname,
      bio: user.bio,
      age: age,
      zodiac: zodiac,
    );
    return user;
  }
}
