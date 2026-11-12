import 'package:flutter/material.dart';

import '../../themes/music_theme_preset.dart';

/// Opaque artwork bounds measured from the uploaded PNGs, with a small margin.
/// Files remain byte-for-byte original; only their layout viewport is trimmed.
const _portraits = <MusicThemeIp, (Size, Rect)>{
  MusicThemeIp.myMelody: (Size(1254, 1254), Rect.fromLTRB(119, 85, 1132, 1211)),
  MusicThemeIp.usagi: (Size(1254, 1254), Rect.fromLTRB(150, 39, 1082, 1237)),
  MusicThemeIp.chiikawa: (Size(1254, 1254), Rect.fromLTRB(86, 183, 1163, 1115)),
  MusicThemeIp.hachiware: (
    Size(1254, 1254),
    Rect.fromLTRB(68, 171, 1180, 1159),
  ),
  MusicThemeIp.puppyWhite: (
    Size(1254, 1254),
    Rect.fromLTRB(123, 345, 1113, 901),
  ),
  MusicThemeIp.puppyGray: (Size(1254, 1254), Rect.fromLTRB(57, 333, 1195, 965)),
  MusicThemeIp.cinnamoroll: (
    Size(1254, 1254),
    Rect.fromLTRB(18, 400, 1235, 908),
  ),
  MusicThemeIp.sleepingKirby: (
    Size(1383, 1137),
    Rect.fromLTRB(102, 52, 1291, 1074),
  ),
};

bool isUploadedProgressIp(MusicThemeIp ip) => _portraits.containsKey(ip);

class UploadedProgressPortrait extends StatelessWidget {
  const UploadedProgressPortrait({required this.ip, super.key});
  final MusicThemeIp ip;

  @override
  Widget build(BuildContext context) {
    final (originalSize, bounds) = _portraits[ip]!;
    return FittedBox(
      key: ValueKey('uploaded-progress-portrait-${ip.name}'),
      fit: BoxFit.contain,
      child: SizedBox(
        width: bounds.width,
        height: bounds.height,
        child: ClipRect(
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: originalSize.width,
            maxWidth: originalSize.width,
            minHeight: originalSize.height,
            maxHeight: originalSize.height,
            child: Transform.translate(
              offset: -bounds.topLeft,
              child: Image.asset(
                companionAssetForIp(ip)!,
                width: originalSize.width,
                height: originalSize.height,
                cacheWidth: 256,
                fit: BoxFit.fill,
                filterQuality: FilterQuality.medium,
                excludeFromSemantics: true,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
