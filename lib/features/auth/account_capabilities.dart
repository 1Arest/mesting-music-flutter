import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/platform/distribution_channel.dart';
import '../music_platform/music_platform_providers.dart';
import 'auth_providers.dart';

/// Shared capability boundary for menus, player actions and route guards.
/// A Kugou login grants platform features, never a fabricated Mesting identity.
final showMestingFeaturesProvider = Provider<bool>(
  (ref) =>
      !DistributionChannel.isBeta || ref.watch(currentUserProvider) != null,
);
final showPlatformFeaturesProvider = Provider<bool>(
  (ref) =>
      DistributionChannel.isBeta &&
      ref.watch(platformAccountProvider).value != null,
);
final canUseCurrentLibraryProvider = Provider<bool>(
  (ref) =>
      ref.watch(isAuthenticatedProvider) ||
      (DistributionChannel.isBeta &&
          ref.watch(platformAccountProvider).value != null),
);
