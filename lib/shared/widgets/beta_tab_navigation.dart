import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Keeps at most one root-tab route transition in flight. Repeated input is
/// coalesced to its latest destination, rather than leaving several departing
/// pages and their live backdrop filters painting beneath the new page.
///
/// The current animation still completes at its original speed. This is not a
/// debounce: the first tap navigates immediately and the final intent is kept.
class BetaTabNavigation {
  /// Route motion records the actual departure, including a coalesced tap.
  /// Increasing tab indices bring the new page from the right (1.0.27).
  final motion = ValueNotifier<BetaTabMotion?>(null);
  final progress = ValueNotifier<double>(1);
  int? _entering, _pending;
  void Function(int)? _navigate;

  void request({
    required int index,
    required int currentIndex,
    required void Function(int) navigate,
  }) {
    _navigate = navigate;
    if (_entering != null) {
      _pending = index;
    } else if (index != currentIndex) {
      _begin(currentIndex, index);
    }
  }

  void settled(int index) {
    if (_entering != index) return;
    _entering = null;
    final next = _pending;
    _pending = null;
    if (next != null && next != index) {
      _begin(index, next);
    }
  }

  /// Opening a detail, search or player page supersedes queued root input.
  /// Dropping the callback also prevents navigation through a disposed shell.
  void cancel() {
    _entering = _pending = null;
    _navigate = null;
    motion.value = null;
  }

  void _begin(int from, int to) {
    _entering = to;
    progress.value = 0;
    motion.value = BetaTabMotion(from, to);
    _navigate?.call(to);
  }

  void dispose() {
    cancel();
    motion.dispose();
    progress.dispose();
  }
}

class BetaTabMotion {
  const BetaTabMotion(this.from, this.to);
  final int from, to;
  double get direction => to > from ? -1 : 1;
}

final betaTabNavigationProvider = Provider((ref) {
  final navigation = BetaTabNavigation();
  ref.onDispose(navigation.dispose);
  return navigation;
});

/// Reports the actual entering route's animation, including reduced motion.
/// No fixed timer guesses when the navigator has finished its transition.
class BetaTabRouteReady extends ConsumerStatefulWidget {
  const BetaTabRouteReady({
    required this.index,
    required this.child,
    super.key,
  });
  final int index;
  final Widget child;

  @override
  ConsumerState<BetaTabRouteReady> createState() => _BetaTabRouteReadyState();
}

class _BetaTabRouteReadyState extends ConsumerState<BetaTabRouteReady> {
  Animation<double>? _animation;
  ModalRoute<dynamic>? _route;
  bool _scheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
    final animation = _route?.animation;
    if (_animation != animation) {
      _animation?.removeStatusListener(_status);
      _animation = animation;
      animation?.addStatusListener(_status);
    }
    _report();
  }

  void _status(AnimationStatus _) => _report();

  void _report() {
    if (_scheduled ||
        _route?.isCurrent == false ||
        (_animation != null && !_animation!.isCompleted)) {
      return;
    }
    _scheduled = true;
    // Navigator can be locked while animation listeners run. Drain the latest
    // intent after that frame, and recheck that this is still the visible route.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted &&
          _route?.isCurrent != false &&
          (_animation == null || _animation!.isCompleted)) {
        ref.read(betaTabNavigationProvider).settled(widget.index);
      }
    });
  }

  @override
  void dispose() {
    _animation?.removeStatusListener(_status);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
