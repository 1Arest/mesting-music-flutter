import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/core/audio/media_volume_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'rapid slider samples preserve the last value with bounded native work',
    () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      var writes = 0;
      var actual = .4;
      messenger.setMockMethodCallHandler(MediaVolumeController.methods, (
        call,
      ) async {
        if (call.method == 'setVolume') {
          writes++;
          await Future<void>.delayed(const Duration(milliseconds: 2));
          actual = (call.arguments as Map)['value'] as double;
        }
        return actual;
      });
      messenger.setMockStreamHandler(
        MediaVolumeController.events,
        MockStreamHandler.inline(onListen: (_, _) {}),
      );
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(mediaVolumeProvider);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final controller = container.read(mediaVolumeProvider.notifier);
      await Future.wait([
        for (var i = 1; i <= 100; i++) controller.setVolume(i / 100),
      ]);
      expect(actual, 1);
      expect(container.read(mediaVolumeProvider).value, 1);
      expect(writes, lessThanOrEqualTo(2));
      // Captured before/after in the delivery evidence; this measures boundary
      // traffic only, never claims an Android GPU frame-rate measurement.
      // ignore: avoid_print
      print('BETA8_VOLUME_BENCH samples=100 nativeWrites=$writes last=$actual');
    },
  );
}
