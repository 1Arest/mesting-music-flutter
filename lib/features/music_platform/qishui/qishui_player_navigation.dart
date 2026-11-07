import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/widgets/beta_tab_navigation.dart';

/// Cover and lyrics are two views of the retained Music tab, sharing the one
/// audio handler. This state never creates a second playback route or player.
class QishuiMusicViewController extends Notifier<bool> {
  @override
  bool build() => false;
  void showCover() => state = false;
  void showLyrics() => state = true;
}

final qishuiMusicLyricsProvider =
    NotifierProvider<QishuiMusicViewController, bool>(
      QishuiMusicViewController.new,
    );

void openQishuiMusicTab(BuildContext context, WidgetRef ref) {
  final router = GoRouter.of(context);
  ref.read(qishuiMusicLyricsProvider.notifier).showCover();
  // Imperative playlist/settings pages can own their own pill. Return through
  // the existing root shell before selecting its retained Music branch.
  Navigator.of(context, rootNavigator: true).popUntil((route) => route.isFirst);
  ref.read(betaTabNavigationProvider).returnToRoot(1);
  router.go('/music');
}
