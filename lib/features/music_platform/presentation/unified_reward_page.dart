import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/beta_secondary_music_layout.dart';
import '../../../shared/widgets/beta_swipe_pages.dart';
import '../platform_backend_providers.dart';
import 'netease_reward_calendar.dart';
import 'platform_reward_calendar.dart';

// Preserve the existing import surface for callers that override this provider.
export '../netease/netease_rewards_provider.dart'
    show retainedNeteaseRewardProvider;

/// Both tabs are production reward views. TabBarView preserves independent
/// scroll state and supports gestures without switching the music platform.
class UnifiedRewardPage extends ConsumerWidget {
  const UnifiedRewardPage({super.key});
  @override
  Widget build(
    BuildContext context,
    WidgetRef ref,
  ) => BetaSecondaryMusicLayout.wrap(
    context,
    DefaultTabController(
      length: 2,
      initialIndex: ref.read(usesNeteaseProvider) ? 0 : 1,
      child: Scaffold(
        key: const ValueKey('unified-reward-page'),
        appBar: AppBar(
          title: const Text('签到与会员'),
          bottom: const TabBar(
            tabs: [
              Tab(text: '网易云'),
              Tab(text: '酷狗'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _activeRewardPage(0, const NeteaseRewardCalendar(embedded: true)),
            _activeRewardPage(1, const PlatformRewardCalendar(embedded: true)),
          ],
        ),
      ),
    ),
  );
}

/// TabBarView adds a viewport depth. Forward only the selected page's scroll
/// to the common bar, so retained hidden pages cannot take over its capsule.
Widget _activeRewardPage(int index, Widget child) => Builder(
  builder: (context) => NotificationListener<ScrollNotification>(
    onNotification: (scroll) {
      if (scroll.metrics.axis == Axis.vertical &&
          scroll.depth == 0 &&
          DefaultTabController.of(context).index == index) {
        BetaActivePageScrollNotification(scroll).dispatch(context);
      }
      return scroll.metrics.axis == Axis.vertical;
    },
    child: child,
  ),
);
