import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'domain/platform_session.dart';
import 'music_platform_providers.dart';
import 'presentation/platform_design.dart';

enum PlatformFeature {
  audiobooks,
  recognition,
  together,
  rewards,
  effectsCatalog,
}

/// One capability rule serves launchers and deep-link guards. Generic local
/// playback tools are intentionally outside this platform-specific allowlist.
bool supportsPlatformFeature(
  MusicPlatform? platform,
  PlatformFeature feature,
) => platform == MusicPlatform.qishui
    ? feature == PlatformFeature.effectsCatalog
    : platform == MusicPlatform.kugou || platform == null;

class PlatformFeatureGate extends ConsumerWidget {
  const PlatformFeatureGate({
    required this.feature,
    required this.child,
    super.key,
  });
  final PlatformFeature feature;
  final Widget child;
  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      supportsPlatformFeature(
        ref.watch(platformAccountProvider).value?.platform,
        feature,
      )
      ? child
      : const PlatformPageFrame(
          title: '当前平台不支持此功能',
          child: Center(child: Text('请返回并选择网易云功能')),
        );
}
