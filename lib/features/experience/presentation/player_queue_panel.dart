import 'package:flutter/material.dart';
import '../../queue/presentation/beta_playback_queue.dart';

/// The sheet and expanded player share gestures and authoritative queue state.
class PlayerQueuePanel extends StatelessWidget {
  const PlayerQueuePanel({super.key});
  @override
  Widget build(BuildContext context) =>
      const BetaPlaybackQueue(immersive: true);
}
