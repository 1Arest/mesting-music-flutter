import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../retained_kugou_scope.dart';
import '../netease_rewards_provider.dart';
import 'netease_ad_probe_repository.dart';

/// Obtaining the service only restores the saved session; inspect() is invoked
/// exclusively by the page's explicit read button. No provider runs an ad read.
final neteaseAdProbeServiceProvider =
    FutureProvider.autoDispose<NeteaseAdProbeService?>((ref) async {
      final epoch = ref.watch(retainedNeteaseEpochProvider);
      final features = await ref.watch(retainedNeteaseRewardProvider.future);
      if (!ref.mounted || features == null) return null;
      return NeteaseAdProbeRepository(
        features.music,
        stillCurrent: () =>
            ref.mounted && epoch == ref.read(retainedNeteaseEpochProvider),
      );
    }, retry: (_, _) => null);
