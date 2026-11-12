import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesting_music/core/audio/mesting_audio_handler.dart';
import 'package:mesting_music/core/audio/playback_providers.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/shared/models/track.dart';
import 'package:mesting_music/features/music_platform/data/playback_quality_catalog.dart';
import 'package:mesting_music/features/music_platform/domain/platform_audio_quality.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/music_platform/platform_quality_providers.dart';
import 'support/deterministic_audio_player.dart';
import 'support/personal_profile_fixture.dart' show SyntheticProfileAccount;
import 'release_148_data_test.dart' show quality148;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  const path = MethodChannel('plugins.flutter.io/path_provider');
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('mesting148-playback-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(path, (_) async => directory.path);
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(path, null);
    await directory.delete(recursive: true);
  });
  for (final revoked in [false, true]) {
    test(
      'verified quality ${revoked ? 'revocation preserves the old stream' : 'swaps transport and preserves queue, position and pause'}',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final player = DeterministicAudioPlayer();
        final handler = MestingAudioHandler(tracks: [], player: player);
        addTearDown(handler.debugDispose);
        final original = quality148();
        final next = Track.fromJson({
          ...original.toJson(),
          'id': 'netease_8',
          'title': '下一首',
        });
        await handler.replaceQueue([original, next], autoplay: false);
        await handler.seek(const Duration(seconds: 23));
        final catalog = VerifiedPlaybackQualities(original, {
          PlatformAudioQuality.standard: quality148(code: '128'),
        }, current: () => !revoked);
        var automaticCalls = 0;
        handler.configureTrackPlaybackResolver((track) async {
          automaticCalls++;
          throw StateError(
            'a prepared selection must not choose another provider',
          );
        });
        final container = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            platformAccountProvider.overrideWith(SyntheticProfileAccount.new),
            audioHandlerProvider.overrideWithValue(handler),
          ],
        );
        addTearDown(container.dispose);
        await container.read(platformAccountProvider.future);
        final applied = await container
            .read(platformQualityProvider.notifier)
            .select(PlatformAudioQuality.standard, catalog: catalog);
        expect(applied, !revoked);
        expect(automaticCalls, 0);
        expect(
          handler.trackForId('netease_7')!.playbackQuality,
          revoked ? '320' : '128',
        );
        expect(
          handler.trackForId('netease_7')!.audioOrigin,
          original.audioOrigin,
        );
        expect(handler.mediaItem.value!.id, 'netease_7');
        expect(handler.upcomingQueue.map((item) => item.id), ['netease_8']);
        expect(player.position, const Duration(seconds: 23));
        expect(player.playing, isFalse);
      },
    );
  }
  test(
    'audio owner rejects a prepared source for a different library recording',
    () async {
      final player = DeterministicAudioPlayer();
      final handler = MestingAudioHandler(tracks: [], player: player);
      addTearDown(handler.debugDispose);
      await handler.replaceQueue([quality148()], autoplay: false);
      final calls = player.loads;
      expect(
        await handler.refreshVerifiedSource(
          (_) async => Track.fromJson({
            ...quality148(code: '128').toJson(),
            'id': 'netease_999',
          }),
        ),
        isFalse,
      );
      expect(handler.mediaItem.value!.id, 'netease_7');
      expect(player.loads, calls);
    },
  );
}
