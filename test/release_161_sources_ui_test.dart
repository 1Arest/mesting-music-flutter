import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/features/downloads/audio_downloads.dart';
import 'package:mesting_music/features/downloads/netease_download_source_picker.dart';
import 'package:mesting_music/features/downloads/download_source_coordinator.dart';
import 'package:mesting_music/features/music_platform/domain/platform_audio_quality.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/music_platform/netease/netease_source_settings_panel.dart';
import 'package:mesting_music/features/music_platform/netease/netease_track_sources.dart';
import 'package:mesting_music/features/music_platform/netease/fallback/netease_source_picker.dart';
import 'package:mesting_music/features/music_platform/netease/netease_music_repository.dart';
import 'package:mesting_music/features/music_platform/netease/netease_api.dart';
import 'package:mesting_music/features/music_platform/platform_backend_providers.dart';
import 'package:mesting_music/features/music_platform/retained_kugou_scope.dart';
import 'netease_v112_fallback_download_test.dart' show recording;
import 'netease_v115_sources_test.dart' show TestAccount;
import 'support/release_152_qa.dart';

void main() {
  setUpAll(initialize151QA);
  final task = AudioDownloadTask(
    id: 'test161',
    owner: 'netease:7',
    track: recording(),
    phase: AudioDownloadPhase.awaitingSource,
    requestedQuality: PlatformAudioQuality.high,
  );
  Future<ProviderContainer> mount(
    WidgetTester tester,
    Widget page, {
    bool dark = false,
    bool large = false,
    bool coordinator = false,
    Completer<bool>? detect,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final manager = AudioDownloadManager(
      client: MockClient((_) async => http.Response('', 500)),
      currentOwner: () => task.owner,
      directory: () async => Directory.systemTemp,
      persist: (_) async {},
      publish: (f, t, e, m) async => 'file:///not-used',
      resolveTaskMedia: (t, abort) async =>
          throw const FormatException('test only'),
      restored: [task],
    );
    final c = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        platformAccountProvider.overrideWith(TestAccount.new),
        audioDownloadManagerProvider.overrideWithValue(manager),
        retainedKugouScopeProvider.overrideWith((ref) => null),
        savedKugouSessionProvider.overrideWith((ref) async => null),
        neteaseMusicRepositoryProvider.overrideWithValue(
          NeteaseMusicRepository(
            NeteaseApi(MockClient((_) async => http.Response('', 500))),
          ),
        ),
        downloadSourceAvailabilityProvider.overrideWithValue(
          (t, s, current, abort) async => detect != null
              ? await Future.any([detect.future, abort.then((_) => false)])
              : s == NeteaseTrackSource.lxFish ||
                    s == NeteaseTrackSource.lxHuibq,
        ),
        neteaseSourceAvailabilityProvider.overrideWithValue(
          (t, s, current, abort) async => s == NeteaseTrackSource.lxFish,
        ),
      ],
    );
    await c.read(platformAccountProvider.future);
    tester.view.physicalSize = large
        ? const Size(320, 650)
        : const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          navigatorKey: key,
          theme: theme152(dark),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(large ? 2 : 1)),
            child: capture151Builder(
              coordinator
                  ? DownloadSourceCoordinator(navigatorKey: key, child: child!)
                  : child!,
            ),
          ),
          home: Scaffold(body: Center(child: page)),
        ),
      ),
    );
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
      manager.dispose();
    });
    expect(tester.takeException(), isNull);
    return c;
  }

  for (final dark in [false, true]) {
    for (final large in [false, true]) {
      testWidgets(
        'download choices preserve cancel and validated states dark=$dark large=$large',
        (tester) async {
          await mount(
            tester,
            NeteaseDownloadSourcePicker(task: task),
            dark: dark,
            large: large,
          );
          expect(find.text('选择下载音源'), findsOneWidget);
          expect(find.text('稍后选择').hitTestable(), findsOneWidget);
          expect(
            tester
                .widget<ListTile>(
                  find.byKey(const ValueKey('download-source-lxFish')),
                )
                .enabled,
            isTrue,
          );
          expect(
            tester
                .widget<ListTile>(
                  find.byKey(const ValueKey('download-source-lxChangqing')),
                )
                .enabled,
            isFalse,
          );
          await shot151(tester, '161-download-top-$dark-$large');
          await tester.ensureVisible(
            find.byKey(const ValueKey('download-source-lxFish')),
          );
          await tester.pump(const Duration(milliseconds: 300));
          await shot151(tester, '161-download-lx-$dark-$large');
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  testWidgets(
    'foreground coordinator opens official-failure choice without starting another source',
    (tester) async {
      final c = await mount(tester, const Text('下载页面'), coordinator: true);
      expect(find.text('选择下载音源'), findsOneWidget);
      await tester.tap(find.text('稍后选择'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        c.read(audioDownloadManagerProvider).tasks.single.phase,
        AudioDownloadPhase.awaitingSource,
      );
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('选择下载音源'), findsNothing);
    },
  );
  testWidgets(
    'account change disables late availability and prevents selecting a stale download',
    (tester) async {
      final gate = Completer<bool>();
      final c = await mount(
        tester,
        NeteaseDownloadSourcePicker(task: task),
        detect: gate,
      );
      (c.read(platformAccountProvider.notifier) as TestAccount).replace(
        'other',
      );
      gate.complete(true);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('账号或下载任务已变化，请关闭后重新操作。'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('download-source-lxFish')),
        findsNothing,
      );
    },
  );
  testWidgets(
    'playback menu lists all eleven LX identities without using download state',
    (tester) async {
      await mount(tester, NeteaseSourcePicker(recording()));
      expect(
        find.byKey(const ValueKey('song-source-lxYuningxi')),
        findsOneWidget,
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('song-source-lxFish')),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await shot151(tester, '161-playback-sources');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'source settings explain official-first manual download selection',
    (tester) async {
      await mount(
        tester,
        const SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: NeteaseSourceSettingsPanel(),
          ),
        ),
      );
      expect(find.textContaining('下载独立于播放选源'), findsOneWidget);
      await tester.ensureVisible(find.text('长青 · changqing'));
      await tester.pump(const Duration(milliseconds: 300));
      await shot151(tester, '161-source-settings');
      expect(tester.takeException(), isNull);
    },
  );
}
