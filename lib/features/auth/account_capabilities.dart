import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../music_platform/music_platform_providers.dart';

/// Capabilities follow the selected real platform, independently of flavor.
/// Guests retain local playback; personal cloud mutations require login.
final showPlatformFeaturesProvider = Provider<bool>(
  (ref) => ref.watch(platformAccountProvider).value != null,
);
final canUseCurrentLibraryProvider = Provider<bool>(
  (ref) => ref.watch(platformAccountProvider).value != null,
);
