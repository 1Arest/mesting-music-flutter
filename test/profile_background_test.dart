import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/features/auth/auth_providers.dart';
import 'package:mesting_music/features/auth/domain/auth_models.dart';
import 'package:mesting_music/features/profile/presentation/profile_background_page.dart';
import 'package:mesting_music/features/profile/profile_background_controller.dart';
import 'package:mesting_music/features/profile/data/profile_background_sync_api.dart';
import 'package:mesting_music/shared/widgets/liquid_glass_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'mesting-profile-background-test-',
    );
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    await temporaryDirectory.delete(recursive: true);
  });

  test('背景图片按账号复制并在重启后恢复', () async {
    final preferences = await SharedPreferences.getInstance();
    final source = File('${temporaryDirectory.path}/selected.png');
    await source.writeAsBytes(base64Decode(_onePixelPng));
    final container = _container(
      preferences: preferences,
      accountId: 'account-a',
      directory: temporaryDirectory,
    );
    addTearDown(container.dispose);

    await container
        .read(profileBackgroundProvider.notifier)
        .setImage(source.path);

    final saved = container.read(profileBackgroundProvider);
    expect(saved.kind, ProfileBackgroundKind.image);
    expect(saved.imagePath, isNot(source.path));
    expect(File(saved.imagePath!).existsSync(), isTrue);
    expect(File(saved.imagePath!).parent.path, contains('profile_backgrounds'));

    final restoredContainer = _container(
      preferences: preferences,
      accountId: 'account-a',
      directory: temporaryDirectory,
    );
    addTearDown(restoredContainer.dispose);
    expect(
      restoredContainer.read(profileBackgroundProvider).imagePath,
      saved.imagePath,
    );
  });

  test('不同账号的背景互不覆盖', () async {
    final preferences = await SharedPreferences.getInstance();
    final first = _container(
      preferences: preferences,
      accountId: 'account-a',
      directory: temporaryDirectory,
    );
    addTearDown(first.dispose);
    await first.read(profileBackgroundProvider.notifier).setPreset('midnight');

    final second = _container(
      preferences: preferences,
      accountId: 'account-b',
      directory: temporaryDirectory,
    );
    addTearDown(second.dispose);
    expect(second.read(profileBackgroundProvider).active, isFalse);
    await second.read(profileBackgroundProvider.notifier).setPreset('sunset');

    final firstRestored = _container(
      preferences: preferences,
      accountId: 'account-a',
      directory: temporaryDirectory,
    );
    addTearDown(firstRestored.dispose);
    expect(firstRestored.read(profileBackgroundProvider).presetId, 'midnight');
    expect(second.read(profileBackgroundProvider).presetId, 'sunset');
  });

  test('清除本地数据后登录会从账号云端恢复主页背景图片', () async {
    final preferences = await SharedPreferences.getInstance();
    final cloud = _FakeProfileBackgroundSyncApi(
      remote: const CloudProfileBackground(
        kind: 'image',
        value:
            'cloud://music/user-profile-backgrounds/account-a/background.png',
        downloadUrl: 'https://download.example/background.png',
      ),
      imageBytes: base64Decode(_onePixelPng),
    );
    final container = _container(
      preferences: preferences,
      accountId: 'account-a',
      directory: temporaryDirectory,
      syncApi: cloud,
    );
    addTearDown(container.dispose);

    expect(container.read(profileBackgroundProvider).active, isFalse);
    for (var attempt = 0; attempt < 20; attempt += 1) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      if (container.read(profileBackgroundProvider).isImage) break;
    }

    final restored = container.read(profileBackgroundProvider);
    expect(restored.isImage, isTrue);
    expect(File(restored.imagePath!).existsSync(), isTrue);
    expect(cloud.loadCalls, 1);
    expect(cloud.downloadCalls, 1);
  });

  test('无效图片返回中文错误且不写入背景', () async {
    final preferences = await SharedPreferences.getInstance();
    final invalid = File('${temporaryDirectory.path}/invalid.jpg');
    await invalid.writeAsString('not an image');
    final container = _container(
      preferences: preferences,
      accountId: 'account-a',
      directory: temporaryDirectory,
    );
    addTearDown(container.dispose);

    await expectLater(
      container.read(profileBackgroundProvider.notifier).setImage(invalid.path),
      throwsA(
        isA<ProfileBackgroundException>().having(
          (error) => error.message,
          'message',
          '仅支持真实的 JPG、PNG 或 WebP 图片',
        ),
      ),
    );
    expect(container.read(profileBackgroundProvider).active, isFalse);
  });

  testWidgets('背景预览页提供更换、风格创作和恢复默认入口', (tester) async {
    final preferences = await SharedPreferences.getInstance();
    final router = GoRouter(
      initialLocation: '/profile/background',
      routes: [
        GoRoute(
          path: '/profile/background',
          builder: (_, _) => const ProfileBackgroundPage(),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          currentUserProvider.overrideWithValue(
            const AuthUser(uid: 'widget-account', nickname: 'Mesting'),
          ),
          profileBackgroundDocumentsDirectoryProvider.overrideWithValue(
            Future.value(temporaryDirectory),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('个人主页背景'), findsOneWidget);
    expect(find.text('更换背景'), findsOneWidget);
    expect(find.text('风格创作'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('create-profile-background')));
    await tester.pumpAndSettle();
    expect(find.text('雾蓝星云'), findsOneWidget);
    expect(find.text('午夜唱片'), findsOneWidget);
    expect(
      tester
          .widget<LiquidGlassSurface>(find.byKey(liquidGlassSheetSurfaceKey))
          .showTopHighlight,
      isFalse,
    );

    await tester.tap(
      find.byKey(const ValueKey('profile-background-preset-midnight')),
    );
    await tester.pumpAndSettle();
    expect(find.text('背景风格已应用'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('profile-background-more')));
    await tester.pumpAndSettle();
    expect(find.text('恢复默认背景'), findsOneWidget);
  });
}

ProviderContainer _container({
  required SharedPreferences preferences,
  required String accountId,
  required Directory directory,
  ProfileBackgroundSyncApi? syncApi,
}) {
  return ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(preferences),
      currentUserProvider.overrideWithValue(
        AuthUser(uid: accountId, nickname: accountId),
      ),
      profileBackgroundDocumentsDirectoryProvider.overrideWithValue(
        Future.value(directory),
      ),
      if (syncApi != null)
        profileBackgroundSyncApiProvider.overrideWithValue(syncApi),
    ],
  );
}

class _FakeProfileBackgroundSyncApi implements ProfileBackgroundSyncApi {
  _FakeProfileBackgroundSyncApi({this.remote, required this.imageBytes});

  CloudProfileBackground? remote;
  final List<int> imageBytes;
  int loadCalls = 0;
  int downloadCalls = 0;

  @override
  Future<void> clear() async {
    remote = null;
  }

  @override
  Future<List<int>> downloadImage(String downloadUrl) async {
    downloadCalls += 1;
    return imageBytes;
  }

  @override
  Future<CloudProfileBackground?> load() async {
    loadCalls += 1;
    return remote;
  }

  @override
  Future<CloudProfileBackground> saveImage(String localPath) async {
    return remote = const CloudProfileBackground(
      kind: 'image',
      value: 'cloud://music/user-profile-backgrounds/account-a/background.png',
      downloadUrl: 'https://download.example/background.png',
    );
  }

  @override
  Future<CloudProfileBackground> savePreset(String presetId) async {
    return remote = CloudProfileBackground(kind: 'preset', value: presetId);
  }
}

const _onePixelPng =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';
