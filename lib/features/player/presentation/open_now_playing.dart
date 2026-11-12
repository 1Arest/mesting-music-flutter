import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/widgets/beta_music_chrome_scope.dart';
import '../../experience/presentation/player_chrome_reveal.dart';
import 'now_playing_page.dart';
import 'now_playing_route.dart';

final _entries = Expando<bool>('now-playing-entry');

/// An imperative detail must return to its exact Navigator underlay. Pushing
/// '/player' through GoRouter from a Navigator-pushed chart reconstructs the
/// declarative shell stack instead. Use one route and a synchronous lease,
/// retained until disposal, including entry/pop and repeated taps.
Future<void> openNowPlaying(
  BuildContext context,
  WidgetRef ref, {
  bool lyrics = false,
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  if (_entries[navigator] == true ||
      ref.read(playerChromeRevealProvider).hasPlayer) {
    return;
  }
  _entries[navigator] = true;
  final chrome = BetaMusicChromeScope.maybeOf(context);
  final route =
      NowPlayingTransitionPage(
            child: Builder(
              builder: (_) {
                final page = NowPlayingPage(showLyricsInitially: lyrics);
                return chrome == null
                    ? page
                    : BetaMusicChromeScope(controller: chrome, child: page);
              },
            ),
          ).createRoute(context)
          as TransitionRoute<void>;
  try {
    navigator.push(route);
    await route.completed;
  } finally {
    _entries[navigator] = false;
  }
}
