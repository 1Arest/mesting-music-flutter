import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:mesting_music/app/mesting_music_app.dart';
import 'package:mesting_music/core/audio/playback_providers.dart';
import 'package:mesting_music/core/platform/distribution_channel.dart';
import 'package:mesting_music/features/auth/presentation/first_launch_auth_coordinator.dart';
import 'package:mesting_music/features/legal/presentation/disclaimer_dialog.dart';
import 'package:mesting_music/features/music_platform/data/embedded_music_server.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/search/search_providers.dart';
import 'package:mesting_music/main.dart' as app;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late ProviderContainer container;

  Future<void> screenshot(WidgetTester tester, String name) async {
    await binding.convertFlutterSurfaceToImage();
    await tester.pump();
    final bytes = await binding.takeScreenshot(name);
    final directory = await getApplicationSupportDirectory();
    await File('${directory.path}/$name.png').writeAsBytes(bytes);
  }

  testWidgets('Beta Android native server and first-install guest path', (
    tester,
  ) async {
    expect(DistributionChannel.isBeta, true);
    final server = EmbeddedMusicServer();
    final addresses = await Future.wait([server.start(), server.start()]);
    expect(addresses.first, addresses.last);
    expect(addresses.first.host, '127.0.0.1');
    // An unknown local route checks the packaged ABI, startup and HTTP stack
    // independently of platform credentials and external network conditions.
    final response = await http.get(
      addresses.first.resolve('/mesting-smoke-no-route'),
    );
    expect(response.statusCode, 404);

    // Consent is an isolated automated-test fixture, never a real-user action.
    final preferences = await SharedPreferences.getInstance();
    await saveLegalDocumentConsent(preferences);
    await preferences.setBool(firstLaunchAuthCompletedPreferenceKey, false);
    await app.main();
    for (var attempt = 0; attempt < 40; attempt++) {
      await tester.pump(const Duration(milliseconds: 500));
      if (find.text('暂不登录，先体验').evaluate().isNotEmpty) break;
    }
    expect(find.text('使用音乐平台账号登录'), findsOneWidget);
    expect(find.text('Mesting 账号登录 / 注册'), findsOneWidget);
    await screenshot(tester, 'beta-first-login');
    await tester.tap(find.text('使用音乐平台账号登录'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('酷狗扫码'), findsOneWidget);
    expect(find.text('微信扫码'), findsOneWidget);
    expect(find.text('QQ 扫码'), findsOneWidget);
    await screenshot(tester, 'beta-platform-login');
    await tester.pageBack();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byKey(const ValueKey('experience-now')));
    await tester.pump(const Duration(seconds: 1));
    expect(preferences.getBool(firstLaunchAuthCompletedPreferenceKey), true);
    expect(find.text('暂不登录，先体验'), findsNothing);
    container = ProviderScope.containerOf(
      tester.element(find.byType(MestingMusicApp)),
    );
    expect(await container.read(platformAccountProvider.future), null);
    await screenshot(tester, 'beta-guest-home');
    // Continue in the same application lifetime: widget-test teardown would
    // otherwise dispose the provider container before the playback check.
    final source = container.read(kugouMusicSourceProvider);
    final tracks = await source.search('海阔天空', limit: 4);
    expect(tracks, isNotEmpty);
    final playable = tracks.where((track) => track.isPlayable).toList();
    expect(
      playable,
      isNotEmpty,
      reason: 'Live platform did not return an anonymous playable URL',
    );
    final handler = container.read(audioHandlerProvider);
    await handler.playSingleTrack(playable.first, playbackContext: playable);
    await tester.pump(const Duration(seconds: 4));
    final position = await handler.positionStream.first;
    expect(handler.mediaItem.value?.id, playable.first.id);
    expect(position.inMilliseconds, greaterThan(500));
    await handler.stop();
  });
}
