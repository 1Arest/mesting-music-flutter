import 'dart:async';

import 'package:flutter/material.dart';
import '../../../shared/media/artwork_refresh_coordinator.dart';
import '../../../shared/models/track.dart';
import '../../../shared/widgets/beta_activity_indicator.dart';
import '../../player/player_visual_style.dart';
import '../../player/presentation/player_visual_stages.dart';
import 'player_content_transition.dart';

/// Artwork readiness belongs to the view, never to remote audio application.
/// Keep the existing stage until the incoming bitmap is decoded, then run the
/// same bounded slide/fade as ordinary cover changes. No list loading curtain
/// may paint a rectangular surface over the immersive player's background.
class PlayerArtworkTransition extends StatefulWidget {
  const PlayerArtworkTransition({
    required this.track,
    required this.style,
    required this.playing,
    this.direction = 1,
    this.prepare,
    super.key,
  });
  final Track track;
  final PlayerVisualStyle style;
  final bool playing;
  final double direction;
  final Future<bool> Function(String)? prepare;
  @override
  State<PlayerArtworkTransition> createState() =>
      _PlayerArtworkTransitionState();
}

class _PlayerArtworkTransitionState extends State<PlayerArtworkTransition> {
  late Track _shown = widget.track;
  int _generation = 0;
  bool _waiting = false, _failed = false;

  @override
  void didUpdateWidget(covariant PlayerArtworkTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.track.id != widget.track.id ||
        oldWidget.track.coverAsset != widget.track.coverAsset) {
      unawaited(_prepare());
    }
  }

  Future<void> _prepare() async {
    final generation = ++_generation, track = widget.track;
    final uri = track.coverAsset;
    if (uri == _shown.coverAsset || !uri.startsWith('http')) {
      _waiting = _failed = false;
      _shown = track;
      return;
    }
    _waiting = true;
    _failed = false;
    var ready = false;
    try {
      ready =
          await (widget.prepare ??
              artworkRefreshCoordinator.preparePlaybackArtwork)(uri);
    } on Object {
      // Source/track changes invalidate the result, and failed artwork never
      // prevents the song or a newer remote command from starting.
    }
    if (!mounted || generation != _generation) return;
    setState(() {
      _waiting = false;
      _failed = !ready;
      if (ready) _shown = track;
    });
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      PlayerContentTransition(
        direction: widget.direction,
        child: PlayerArtworkStage(
          key: ValueKey('player-ready-artwork-${_shown.id}'),
          style: widget.style,
          track: _shown,
          playing: widget.playing,
        ),
      ),
      if (_waiting) const Center(child: BetaActivityIndicator()),
      if (_failed)
        Align(
          alignment: Alignment.bottomCenter,
          child: TextButton(
            onPressed: () {
              setState(() {
                unawaited(_prepare());
              });
            },
            child: const Text('封面加载失败，点击重试'),
          ),
        ),
    ],
  );
}
