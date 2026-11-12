import 'package:flutter/material.dart';

/// The official player's count variants have a transparent notch at the
/// upper right. The caller lays out the count separately and owns activation.
class OfficialCountHeart extends StatelessWidget {
  const OfficialCountHeart({
    required this.favorite,
    required this.size,
    this.color,
    super.key,
  });
  final bool favorite;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => Image.asset(
    favorite
        ? 'assets/images/player/netease-heart-count-filled.webp'
        : 'assets/images/player/netease-heart-count-outline.webp',
    width: size,
    height: size,
    fit: BoxFit.contain,
    color: color ?? IconTheme.of(context).color,
    colorBlendMode: BlendMode.srcIn,
    excludeFromSemantics: true,
  );
}
