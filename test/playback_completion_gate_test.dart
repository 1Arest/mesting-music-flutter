import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/core/audio/playback_completion_gate.dart';

void main() {
  test('natural playback from the beginning counts as completed', () {
    final gate = PlaybackCompletionGate();

    gate.onPlay(Duration.zero);

    expect(gate.takeCompletion(), isTrue);
    expect(gate.takeCompletion(), isFalse);
  });

  test('restored or forward-seeked playback does not count as completed', () {
    final restored = PlaybackCompletionGate();
    restored.onPlay(const Duration(seconds: 40));
    expect(restored.takeCompletion(), isFalse);

    final seeked = PlaybackCompletionGate();
    seeked.onPlay(Duration.zero);
    seeked.onSeek(
      from: const Duration(seconds: 12),
      to: const Duration(minutes: 2),
    );
    expect(seeked.takeCompletion(), isFalse);
  });

  test('seeking back to zero can start a new full-play candidate', () {
    final gate = PlaybackCompletionGate();
    gate.onPlay(Duration.zero);
    gate.onSeek(from: const Duration(seconds: 30), to: Duration.zero);
    expect(gate.takeCompletion(), isFalse);

    gate.onPlay(Duration.zero);
    expect(gate.takeCompletion(), isTrue);
  });
}
