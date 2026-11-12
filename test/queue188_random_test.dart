import 'dart:io';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/core/audio/mesting_audio_handler.dart';
import 'support/deterministic_audio_player.dart';
import 'release_148_ui_test.dart' show song148;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    final dir = await Directory.systemTemp.createTemp('mesting188queue');
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => dir.path);
    addTearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      await dir.delete(recursive: true);
    });
  });
  test(
    'random pending leaves source/order untouched and consumes without repeats',
    () async {
      final player = DeterministicAudioPlayer();
      final handler = MestingAudioHandler(
        tracks: [],
        player: player,
        random: Random(42),
      );
      addTearDown(handler.debugDispose);
      await handler.replaceQueue(List.generate(6, song148), autoplay: false);
      final order = handler.upcomingQueue.map((t) => t.id).toList();
      final loads = player.loads;
      player.at = const Duration(seconds: 37);
      await handler.setRandomUpcoming(true);
      expect(handler.upcomingQueue.map((t) => t.id), order);
      expect(handler.mediaItem.value?.id, song148(0).id);
      expect(player.loads, loads);
      expect(player.at, const Duration(seconds: 37));
      final seen = <String>{};
      for (var i = 0; i < 5; i++) {
        await handler.skipToNext();
        expect(seen.add(handler.mediaItem.value!.id), true);
        expect(order, contains(handler.mediaItem.value!.id));
      }
    },
  );
  test(
    'disable resumes original remaining order and play-next remains explicit',
    () async {
      final handler = MestingAudioHandler(
        tracks: [],
        player: DeterministicAudioPlayer(),
        random: Random(17),
      );
      addTearDown(handler.debugDispose);
      await handler.replaceQueue(List.generate(6, song148), autoplay: false);
      await handler.setRandomUpcoming(true);
      await handler.playNextInQueue(song148(4));
      await handler.skipToNext();
      expect(handler.mediaItem.value?.id, song148(4).id);
      await handler.setRandomUpcoming(false);
      await handler.skipToNext();
      expect(handler.mediaItem.value?.id, song148(1).id);
    },
  );
}
