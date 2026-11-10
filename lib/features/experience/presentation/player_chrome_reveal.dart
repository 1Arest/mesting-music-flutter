import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Local animation signal: dragging the player never rebuilds the routed page
/// or all of its glass surfaces. Only the persistent chrome listens to it.
final playerChromeRevealProvider = Provider<PlayerChromeReveal>((ref) {
  final reveal = PlayerChromeReveal();
  ref.onDispose(reveal.dispose);
  return reveal;
});

/// The callbacks of a departing player may finish after another entry opens a
/// new one. Bind progress to a view owner; the old callback must not expose bars
/// over that new page. A stack also restores an underlying mounted player.
class PlayerChromeReveal extends ValueNotifier<double> {
  PlayerChromeReveal() : super(0);
  final _owners = <Object>[];
  bool _disposed = false;
  bool get hasPlayer => _owners.isNotEmpty;

  void claim(Object owner) {
    _owners.remove(owner);
    _owners.add(owner);
    // The cover's synchronous render gate hides the entry until its post-frame
    // reset. Do not notify a building shell from its child's initState.
  }

  void publish(Object owner, double progress) {
    if (!_disposed && identical(_owners.lastOrNull, owner)) {
      value = progress.clamp(0.0, 1.0);
    }
  }

  Object? release(Object owner) {
    final wasCurrent = identical(_owners.lastOrNull, owner);
    _owners.remove(owner);
    return wasCurrent ? _owners.lastOrNull : null;
  }

  @override
  void dispose() {
    _disposed = true;
    _owners.clear();
    super.dispose();
  }
}
