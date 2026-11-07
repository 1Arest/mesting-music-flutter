import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mesting_music/core/audio/mesting_audio_handler.dart';
import 'package:mesting_music/core/audio/music_equalizer_providers.dart';
import 'package:mesting_music/features/downloads/audio_downloads.dart';
import 'package:mesting_music/features/downloads/audio_downloads_page.dart';
import 'package:mesting_music/features/experience/presentation/beta_bottom_bar.dart';
import 'package:mesting_music/features/music_platform/data/platform_effects_repository.dart'
    as fx;
import 'package:mesting_music/shared/models/track.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/music_platform/platform_effects_providers.dart';
import 'package:mesting_music/features/music_platform/presentation/music_effects_page.dart';
import 'package:mesting_music/features/themes/app_theme.dart';
import 'package:mesting_music/features/themes/music_theme_preset.dart';
import 'package:mesting_music/shared/widgets/audio_resolving_wave.dart';
import 'release_103_audio_test.dart' show TestEqualizerBridge;
import 'support/deterministic_audio_player.dart';
import 'support/personal_profile_fixture.dart';
import 'support/pump_artwork_ready.dart';
import 'support/test_tracks.dart';

class _Account extends PlatformAccountController {
  @override
  Future<PlatformSession?> build() async =>
      const PlatformSession(userId: 'fixture', token: 'fixture');
}

class _Effects extends Fake implements fx.PlatformEffectsRepository {
  @override
  Future<fx.MusicEffectsPage> list(
    fx.MusicEffectsCatalog catalog, {
    int page = 1,
    String? brandId,
    bool newest = false,
  }) async => fx.MusicEffectsPage([
    for (var i = 0; i < 8; i++)
      fx.MusicSoundEffect(
        id: '${catalog.name}-$i',
        name:
            '${catalog.name == 'community'
                ? '社区'
                : catalog.name == 'earphone'
                ? '耳机'
                : '明星'}人声 $i',
        preset: '人声',
        author: '合成样本',
        cover: profileFixtureCover,
      ),
  ], false);
}

void main() {
  const capture = bool.fromEnvironment('EXPORT_V124_UI');
  setUpAll(() async {
    await LiquidGlassWidgets.initialize();
    if (!capture) return;
    final bytes = await File('C:/Windows/Fonts/msyh.ttc').readAsBytes();
    for (final name in [
      'Roboto',
      'Arial',
      'CupertinoSystemText',
      'CupertinoSystemDisplay',
      'Noto Sans SC',
      'Microsoft YaHei',
      'sans-serif',
    ]) {
      await (FontLoader(
        name,
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    }
    await (FontLoader('MaterialIcons')..addFont(
          File(
            'D:/flutter/mesting-beta5/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
          ).readAsBytes().then(ByteData.sublistView),
        ))
        .load();
    await (FontLoader('packages/cupertino_icons/CupertinoIcons')..addFont(
          rootBundle.load('packages/cupertino_icons/assets/CupertinoIcons.ttf'),
        ))
        .load();
  });
  for (final dark in [false, true]) {
    for (final small in [false, true]) {
      testWidgets(
        'real effects and downloads retain chrome, paging and task separation dark=$dark small=$small',
        (tester) async {
          final dependencies = (await tester.runAsync(() async {
            final handler = MestingAudioHandler(
              tracks: testTracks,
              player: DeterministicAudioPlayer(),
            );
            await handler.replaceQueue(testTracks, autoplay: false);
            final manager = AudioDownloadManager(
              client: MockClient((_) async => http.Response('', 500)),
              resolve: (_) async => '',
              publish: (_, _, _, _) async => '',
              currentOwner: () => 'kugou:fixture',
              directory: () async => Directory.systemTemp,
              persist: (_) async {},
              restored: [
                AudioDownloadTask(
                  id: 'done',
                  owner: 'kugou:fixture',
                  track: Track.fromJson({
                    ...testTracks.first.toJson(),
                    'title': '已完成曲目',
                  }),
                  phase: AudioDownloadPhase.completed,
                  uri: 'content://music/done',
                ),
                AudioDownloadTask(
                  id: 'failed',
                  owner: 'kugou:fixture',
                  track: Track.fromJson({
                    ...testTracks.first.toJson(),
                    'title': '失败可重试曲目',
                  }),
                  phase: AudioDownloadPhase.failed,
                ),
                AudioDownloadTask(
                  id: 'resolving',
                  owner: 'kugou:fixture',
                  track: Track.fromJson({
                    ...testTracks.first.toJson(),
                    'title': '解析中的曲目',
                  }),
                  phase: AudioDownloadPhase.resolving,
                ),
              ],
            );
            final fixture = await PersonalProfileFixture.create(
              audioHandler: handler,
              accountFactory: _Account.new,
              extraOverrides: [
                platformEffectsRepositoryProvider.overrideWithValue(_Effects()),
                musicEqualizerBridgeProvider.overrideWithValue(
                  TestEqualizerBridge(),
                ),
                audioDownloadManagerProvider.overrideWithValue(manager),
              ],
            );
            return (handler, manager, fixture);
          }))!;
          final (handler, manager, fixture) = dependencies;
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(small ? 320 : 390, small ? 740 : 844);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          Future<void> mount(Widget child) async {
            await tester.pumpWidget(
              UncontrolledProviderScope(
                container: fixture.container,
                child: MaterialApp(
                  theme: buildMestingTheme(
                    musicThemePresetById(dark ? 'classic-dark' : 'classic'),
                  ),
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      textScaler: TextScaler.linear(small ? 1.6 : 1),
                      disableAnimations: true,
                    ),
                    child: child!,
                  ),
                  home: RepaintBoundary(
                    key: const ValueKey('capture124'),
                    child: child,
                  ),
                ),
              ),
            );
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 700));
            await pumpArtworkReady(tester);
          }

          Future<void> save(String name) async {
            if (!capture) return;
            await tester.runAsync(() async {
              final boundary = tester.renderObject<RenderRepaintBoundary>(
                find.byKey(const ValueKey('capture124')),
              );
              final image = await boundary.toImage();
              final data = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              image.dispose();
              final out = Directory(
                '.codex-artifacts/2026-10-31-release124/screens',
              )..createSync(recursive: true);
              await File(
                '${out.path}/$name-$dark-$small.png',
              ).writeAsBytes(data!.buffer.asUint8List());
            });
          }

          await mount(const MusicEffectsPage());
          expect(find.text('社区人声 0').hitTestable(), findsOneWidget);
          expect(find.byType(BetaMusicBottomBar), findsOneWidget);
          await save('effects');
          await tester.fling(
            find.byType(ListView).first,
            const Offset(0, -2200),
            2400,
          );
          await tester.pumpAndSettle();
          expect(find.text('社区人声 7').hitTestable(), findsOneWidget);
          expect(
            tester.getRect(find.text('社区人声 7')).bottom,
            lessThan(tester.getRect(find.byType(BetaMusicBottomBar)).top),
            reason: 'The final content must scroll above the glass overlay',
          );
          await tester.tap(find.text('耳机'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          expect(find.text('耳机人声 0').hitTestable(), findsOneWidget);
          await tester.drag(find.byType(PageView), const Offset(-260, 0));
          await tester.pump();
          await tester.pumpAndSettle();
          expect(find.text('明星人声 0').hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
          await mount(const AudioDownloadsPage(downloadedOnly: true));
          expect(find.text('已完成曲目').hitTestable(), findsOneWidget);
          expect(find.text('失败可重试曲目').hitTestable(), findsNothing);
          await tester.tap(find.text('下载任务'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          expect(find.text('失败可重试曲目').hitTestable(), findsOneWidget);
          expect(find.text('已完成曲目').hitTestable(), findsNothing);
          expect(find.byType(AudioResolvingWave), findsOneWidget);
          await save('downloads');
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          manager.dispose();
          await tester.runAsync(() async {
            await fixture.dispose();
            await handler.debugDispose();
          });
        },
      );
    }
  }
}
