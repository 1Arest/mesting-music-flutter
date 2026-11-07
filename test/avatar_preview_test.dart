import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/core/platform/avatar_media_bridge.dart';
import 'package:mesting_music/features/auth/auth_providers.dart';
import 'package:mesting_music/features/auth/data/auth_repository.dart';
import 'package:mesting_music/features/auth/domain/auth_models.dart';
import 'package:mesting_music/features/profile/presentation/avatar_preview_page.dart';
import 'package:mesting_music/features/profile/presentation/profile_edit_page.dart';
import 'package:mesting_music/features/profile/presentation/profile_page.dart';
import 'package:mesting_music/shared/widgets/artwork_image.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.mesting.music/media_library');
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'mesting-avatar-test-',
    );
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await temporaryDirectory.delete(recursive: true);
  });

  test(
    'avatar media bridge validates and sends the original image bytes',
    () async {
      final file = File('${temporaryDirectory.path}/avatar.png');
      final bytes = base64Decode(_onePixelPng);
      await file.writeAsBytes(bytes);
      MethodCall? received;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            received = call;
            return 'content://media/avatar';
          });

      final image = await AvatarMediaBridge.load(file.path);
      final saved = await AvatarMediaBridge.saveToGallery(
        image,
        now: DateTime(2026, 7, 24, 13, 28),
      );

      expect(saved, 'content://media/avatar');
      expect(received?.method, 'saveImage');
      expect(received?.arguments['bytes'], bytes);
      expect(received?.arguments['mimeType'], 'image/png');
      expect(
        received?.arguments['fileName'],
        'mesting_avatar_20260724132800.png',
      );
    },
  );

  testWidgets('profile identity opens edit and edit avatar opens preview', (
    tester,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    final router = GoRouter(
      initialLocation: '/profile',
      routes: [
        GoRoute(
          path: '/profile',
          builder: (_, _) => const Scaffold(body: ProfilePage()),
        ),
        GoRoute(
          path: '/profile/edit',
          builder: (_, _) => const Scaffold(body: ProfileEditPage()),
        ),
        GoRoute(
          path: '/profile/avatar',
          builder: (_, _) => const Scaffold(body: AvatarPreviewPage()),
        ),
        GoRoute(
          path: '/profile/background',
          builder: (_, _) => const Scaffold(body: Center(child: Text('背景设置页'))),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(
            _RestoredSessionAuthRepository(_session()),
          ),
          sharedPreferencesProvider.overrideWithValue(preferences),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('profile-background-button')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('profile-edit-button')), findsNothing);
    expect(
      find.byKey(const ValueKey('profile-avatar-preview-entry')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('profile-edit-entry')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('profile-edit-entry')));
    await tester.pumpAndSettle();

    expect(find.text('编辑个人资料'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('profile-edit-background-entry')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('profile-edit-background-entry')),
    );
    await tester.pumpAndSettle();
    expect(find.text('背景设置页'), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();

    final sourceHero = tester.widget<Hero>(find.byType(Hero));
    expect(sourceHero.transitionOnUserGestures, isTrue);
    expect(sourceHero.createRectTween, isNotNull);

    await tester.tap(
      find.byKey(const ValueKey('profile-edit-avatar-preview-entry')),
    );
    await tester.pumpAndSettle();

    expect(find.text('当前头像'), findsOneWidget);
    final destinationHero = tester.widget<Hero>(find.byType(Hero));
    expect(destinationHero.transitionOnUserGestures, isTrue);
    expect(destinationHero.createRectTween, isNotNull);
    expect(find.byKey(const ValueKey('save-current-avatar')), findsOneWidget);
    expect(find.byKey(const ValueKey('change-current-avatar')), findsOneWidget);
    expect(find.text('当前尚未设置头像，可从相册选择一张'), findsOneWidget);
  });

  testWidgets('avatar preview keeps the original image aspect ratio', (
    tester,
  ) async {
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWithValue(
            _session(
              avatarUrl: 'assets/branding/dress-midnight-launch.png',
            ).user,
          ),
          sharedPreferencesProvider.overrideWithValue(preferences),
        ],
        child: const MaterialApp(home: Scaffold(body: AvatarPreviewPage())),
      ),
    );
    await tester.pump();

    final artwork = tester.widget<ArtworkImage>(find.byType(ArtworkImage));
    expect(artwork.fit, BoxFit.contain);
    expect(artwork.decodeWidth, isNotNull);
    expect(artwork.decodeHeight, isNull);
  });
}

AuthSession _session({String? avatarUrl}) {
  return AuthSession(
    user: AuthUser(
      uid: 'avatar-preview-user',
      nickname: 'Mesting',
      avatarUrl: avatarUrl,
    ),
    accessToken: 'access',
    refreshToken: 'refresh',
    expiresAt: DateTime.utc(2099),
  );
}

class _RestoredSessionAuthRepository extends UnconfiguredAuthRepository {
  const _RestoredSessionAuthRepository(this.session);

  final AuthSession session;

  @override
  Future<AuthSession?> restoreSession() async => session;
}

const _onePixelPng =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';
