import 'dart:async';
import 'dart:math' as math;
import 'package:just_audio/just_audio.dart';
import '../../shared/models/track.dart';

class PreparedTrack {
  const PreparedTrack(this.track, this.player, this.queueKey);
  final Track track;
  final AudioPlayer player;
  final String queueKey;
}

/// At most one silent prepared decoder and one draining predecessor. Epochs
/// reject late preparation/fade work after a seek, account change or queue edit.
class PlaybackTransition {
  int epoch = 0;
  String? attemptedKey;
  PreparedTrack? ready;
  AudioPlayer? loading, tail;
  Future<void>? fading;
  StreamSubscription<ProcessingState>? tailCompletion;
  bool crossing = false;
  void invalidate() {
    epoch++;
    attemptedKey = null;
  }

  Future<void> clearPreparation() async {
    final players = <AudioPlayer>{if (ready != null) ready!.player, ?loading};
    ready = null;
    loading = null;
    for (final player in players) {
      await player.dispose().catchError((Object _) {});
    }
  }
}

/// Equal-power curves prevent a mid-transition loudness dip. Native per-track
/// loudness gain is separate, so this envelope never overwrites normalization.
(double outgoing, double incoming) crossfadeGains(double fraction) {
  final t = fraction.clamp(0.0, 1.0);
  return (math.cos(t * math.pi / 2), math.sin(t * math.pi / 2));
}
