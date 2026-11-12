import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/track.dart';
import '../../../shared/widgets/track_artwork.dart';
import '../../music_platform/netease/messages/netease_messages_page.dart';
import '../../music_platform/netease/messages/netease_messages_repository.dart';
import '../../music_platform/netease/together/netease_together_controller.dart';

/// Only this small leading island listens to room membership. Heartbeats do
/// not rebuild the glass, track labels, transport or swipe animation owner.
class PlaybackPillArtwork extends ConsumerStatefulWidget {
  const PlaybackPillArtwork({
    required this.track,
    required this.dimension,
    super.key,
  });
  final Track track;
  final double dimension;

  @override
  ConsumerState<PlaybackPillArtwork> createState() =>
      _PlaybackPillArtworkState();
}

class _PlaybackPillArtworkState extends ConsumerState<PlaybackPillArtwork> {
  NeteaseTogetherController? _room;
  NeteasePerson? _self, _peer;
  Object? _signature;

  @override
  void initState() {
    super.initState();
    ref.listenManual(neteaseTogetherControllerProvider, (_, next) {
      _room?.removeListener(_changed);
      _room = next;
      next?.addListener(_changed);
      _changed();
      // Match the full player's read-only restore on entry. The controller
      // already guards account replacement and owns its single room timer.
      if (next != null) Future<void>.microtask(next.restore);
    }, fireImmediately: true);
  }

  void _changed() {
    final room = _room;
    final active = room != null && room.current && room.active;
    final self = active
        ? room.members.where((p) => p.id == room.self.id).firstOrNull ??
              room.self
        : null;
    final peer = active ? room.peers.firstOrNull : null;
    final signature = active
        ? (
            room.roomId,
            self?.id,
            self?.name,
            self?.avatar,
            peer?.id,
            peer?.name,
            peer?.avatar,
          )
        : null;
    if (signature == _signature) return;
    _signature = signature;
    if (mounted) {
      setState(() {
        _self = self;
        _peer = peer;
      });
    }
  }

  @override
  void dispose() {
    _room?.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.dimension;
    // A queued song from another platform must not acquire this room's faces.
    final self = widget.track.source == TrackSource.netease ? _self : null;
    final peer = self == null ? null : _peer;
    final artwork = self == null
        ? SizedBox.square(
            key: const ValueKey('pill-song-artwork'),
            dimension: size,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: TrackArtwork(
                track: widget.track,
                width: size,
                height: size,
              ),
            ),
          )
        : Semantics(
            image: true,
            label: peer == null ? '一起听，等待朋友加入' : '与${peer.name}一起听',
            child: SizedBox(
              key: const ValueKey('pill-together-avatars'),
              width: peer == null ? size : size * 1.45,
              height: size,
              child: Stack(
                children: [
                  Positioned(left: 0, child: _portrait(self, size, 'self')),
                  if (peer != null)
                    Positioned(right: 0, child: _portrait(peer, size, 'peer')),
                ],
              ),
            ),
          );
    // A zero-duration AnimatedSize can notify during its own layout when
    // membership changes. Reduced motion uses the final geometry directly.
    if (MediaQuery.disableAnimationsOf(context)) return artwork;
    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      alignment: Alignment.centerLeft,
      child: artwork,
    );
  }

  Widget _portrait(NeteasePerson person, double size, String role) => Container(
    key: ValueKey('pill-together-$role-${person.id}'),
    width: size,
    height: size,
    padding: const EdgeInsets.all(1.2),
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: Theme.of(context).colorScheme.surface,
    ),
    child: NeteasePersonAvatar(person, size: size - 2.4),
  );
}
