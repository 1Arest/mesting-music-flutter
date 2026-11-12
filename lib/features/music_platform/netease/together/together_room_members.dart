import 'package:flutter/material.dart';

import '../messages/netease_messages_page.dart';
import '../messages/netease_messages_repository.dart';
import '../../../themes/music_typography.dart';

/// One compact relationship row, using the capsule's overlapping circular
/// portraits. Text remains independent so long nicknames and large fonts wrap
/// without squeezing either avatar or losing a member's accessible identity.
class TogetherRoomMembers extends StatelessWidget {
  const TogetherRoomMembers({required this.self, this.peer, super.key});
  final NeteasePerson self;
  final NeteasePerson? peer;

  @override
  Widget build(BuildContext context) {
    const size = 52.0;
    final friend = peer;
    final names = friend == null ? self.name : '${self.name} · ${friend.name}';
    return Semantics(
      key: const ValueKey('together-room-members'),
      label: friend == null ? '$names，等待朋友加入' : '$names，正在一起听',
      child: ExcludeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: friend == null ? size : size * 1.45,
              height: size,
              child: Stack(
                children: [
                  Positioned(left: 0, child: _portrait(context, self, 'self')),
                  if (friend != null)
                    Positioned(
                      right: 0,
                      child: _portrait(context, friend, 'peer'),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                names,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: MusicTypography.calloutSize,
                  height: 1.45,
                  fontWeight: MusicTypography.bodyWeight,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _portrait(BuildContext context, NeteasePerson person, String role) =>
      Container(
        key: ValueKey('together-room-$role-avatar'),
        width: 52,
        height: 52,
        padding: const EdgeInsets.all(1.2),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Theme.of(context).colorScheme.surfaceContainerLow,
        ),
        child: NeteasePersonAvatar(person, size: 49.6),
      );
}
