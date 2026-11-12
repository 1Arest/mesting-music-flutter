import 'package:flutter/material.dart';

/// Static 9.6.15 player resources, identified through discHead/playDiscBg in
/// res/layout/d7d.xml. Both the actual player and gallery use these parts.
const officialTonearmAsset = 'assets/images/player/netease-tonearm-9_6_15.webp';
const officialRecordBackdropAsset =
    'assets/images/player/netease-record-backdrop-9_6_15.webp';
const officialTonearmPauseTurns = -25 / 360;
const officialTonearmDuration = Duration(milliseconds: 300);

class OfficialVinylTonearm extends StatelessWidget {
  const OfficialVinylTonearm({required this.playing, super.key});
  final bool playing;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: AnimatedRotation(
      turns: playing ? 0 : officialTonearmPauseTurns,
      // The original 528x474 image pivots at (264, 44), not its center.
      alignment: const Alignment(0, 44 / 474 * 2 - 1),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : officialTonearmDuration,
      curve: Curves.easeOutCubic,
      child: Image.asset(
        officialTonearmAsset,
        fit: BoxFit.fill,
        excludeFromSemantics: true,
        filterQuality: FilterQuality.medium,
      ),
    ),
  );
}

class OfficialRecordBackdrop extends StatelessWidget {
  const OfficialRecordBackdrop({super.key});
  @override
  Widget build(BuildContext context) => IgnorePointer(
    // The subtle alpha is already encoded in the original backdrop. Applying
    // another opacity would make its outer rim disappear on the player.
    child: Image.asset(
      officialRecordBackdropAsset,
      fit: BoxFit.contain,
      excludeFromSemantics: true,
    ),
  );
}
