import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/core/audio/media_volume_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(MediaVolumeController.methods, null);
    messenger.setMockStreamHandler(MediaVolumeController.events, null);
  });
  test(
    'media volume reads Android, sends slider value and follows hardware events',
    () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      double nativeVolume = .4;
      MockStreamHandlerEventSink? events;
      messenger.setMockMethodCallHandler(MediaVolumeController.methods, (
        call,
      ) async {
        if (call.method == 'setVolume') {
          nativeVolume = (call.arguments as Map)['value'] as double;
        }
        return nativeVolume;
      });
      messenger.setMockStreamHandler(
        MediaVolumeController.events,
        MockStreamHandler.inline(
          onListen: (_, sink) {
            events = sink;
          },
        ),
      );
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(mediaVolumeProvider);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(mediaVolumeProvider).available, true);
      expect(container.read(mediaVolumeProvider).value, .4);
      await container.read(mediaVolumeProvider.notifier).setVolume(.7);
      expect(nativeVolume, .7);
      expect(container.read(mediaVolumeProvider).value, .7);
      events!.success(.9);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(mediaVolumeProvider).value, .9);
      nativeVolume = .2;
      await container.read(mediaVolumeProvider.notifier).refresh();
      expect(container.read(mediaVolumeProvider).value, .2);
    },
  );
  test(
    'missing native bridge leaves an honest disabled slider without event errors',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(mediaVolumeProvider);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(mediaVolumeProvider).available, false);
      await container.read(mediaVolumeProvider.notifier).setVolume(.8);
      expect(container.read(mediaVolumeProvider).value, .5);
    },
  );
}
