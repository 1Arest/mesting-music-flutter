import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/core/audio/pause_fade_controller.dart';

void main() {
  test('暂停淡出曲线从完整音量平滑降到静音', () {
    expect(pauseFadeRemainingVolume(0), 1);
    expect(pauseFadeRemainingVolume(1), 0);

    final samples = List<double>.generate(
      11,
      (index) => pauseFadeRemainingVolume(index / 10),
    );
    for (var index = 1; index < samples.length; index += 1) {
      expect(samples[index], lessThanOrEqualTo(samples[index - 1]));
    }
    expect(samples[5], closeTo(0.5, 0.0001));
  });

  test('逐步降低真实音量后暂停并为下次播放恢复原音量', () async {
    final delays = <Duration>[];
    final volumes = <double>[];
    final events = <String>[];
    final controller = PauseFadeController(
      duration: const Duration(milliseconds: 700),
      steps: 14,
      delay: (duration) async {
        delays.add(duration);
      },
      setVolume: (volume) async {
        volumes.add(volume);
        events.add('volume');
      },
      pause: () async {
        events.add('pause');
      },
    );

    await controller.fadeOutAndPause(0.8);

    expect(delays, hasLength(14));
    expect(
      delays.every((duration) => duration == const Duration(milliseconds: 50)),
      isTrue,
    );
    expect(volumes, hasLength(15));
    expect(volumes.first, lessThan(0.8));
    expect(volumes[13], closeTo(0, 0.0001));
    expect(volumes.last, closeTo(0.8, 0.0001));
    expect(events[events.length - 2], 'pause');
    expect(events.last, 'volume');
    expect(controller.isFading, isFalse);
  });

  test('恢复或切歌时可取消淡出且不会误暂停', () async {
    final firstStep = Completer<void>();
    final volumes = <double>[];
    var pauseCount = 0;
    var delayCount = 0;
    final controller = PauseFadeController(
      steps: 4,
      delay: (_) {
        delayCount += 1;
        return firstStep.future;
      },
      setVolume: (volume) async {
        volumes.add(volume);
      },
      pause: () async {
        pauseCount += 1;
      },
    );

    final fade = controller.fadeOutAndPause(0.65);
    await Future<void>.delayed(Duration.zero);
    expect(controller.isFading, isTrue);
    expect(delayCount, 1);

    final cancellation = controller.cancel();
    firstStep.complete();
    await cancellation;
    await fade;

    expect(pauseCount, 0);
    expect(volumes, <double>[0.65]);
    expect(controller.isFading, isFalse);
  });

  test('底层暂停失败时仍恢复音量并清理淡出状态', () async {
    final volumes = <double>[];
    final controller = PauseFadeController(
      steps: 2,
      delay: (_) async {},
      setVolume: (volume) async {
        volumes.add(volume);
      },
      pause: () async {
        throw StateError('pause failed');
      },
    );

    await expectLater(
      controller.fadeOutAndPause(0.4),
      throwsA(isA<StateError>()),
    );

    expect(volumes.last, closeTo(0.4, 0.0001));
    expect(controller.isFading, isFalse);
  });
}
