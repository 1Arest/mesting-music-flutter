import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/core/audio/mesting_audio_handler.dart';
import 'support/deterministic_audio_player.dart';
import 'release_148_ui_test.dart' show song148;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    final dir = await Directory.systemTemp.createTemp('mesting150queue');
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => dir.path);
    addTearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      await dir.delete(recursive: true);
    });
  });
  for (final existing in [false, true]) {
    test(
      'play next promotes ${existing ? 'existing' : 'new'} recording without restarting current audio',
      () async {
        final player = DeterministicAudioPlayer();
        final handler = MestingAudioHandler(tracks: [], player: player);
        addTearDown(handler.debugDispose);
        await handler.replaceQueue([
          song148(0),
          song148(1),
          song148(2),
        ], autoplay: false);
        final loads = player.loads;
        player.at = const Duration(seconds: 37);
        final target = song148(existing ? 2 : 3);
        expect(await handler.playNextInQueue(target), true);
        expect(handler.mediaItem.value?.id, song148(0).id);
        expect(player.loads, loads);
        expect(player.at, const Duration(seconds: 37));
        expect(player.active, false);
        expect(handler.upcomingQueue.first.id, target.id);
        expect(
          handler.upcomingQueue.map((t) => t.id).toSet().length,
          handler.upcomingQueue.length,
        );
        await handler.skipToNext();
        expect(handler.mediaItem.value?.id, target.id);
      },
    );
  }
  test('currently playing song is not duplicated by play next', () async {
    final player = DeterministicAudioPlayer();
    final handler = MestingAudioHandler(tracks: [], player: player);
    addTearDown(handler.debugDispose);
    await handler.replaceQueue([song148(0), song148(1)], autoplay: false);
    expect(await handler.playNextInQueue(song148(0)), false);
    expect(handler.upcomingQueue.map((t) => t.id), [song148(1).id]);
  });
}
