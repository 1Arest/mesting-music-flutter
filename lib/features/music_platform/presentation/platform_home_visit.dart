import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/beta_entrance_readiness.dart';
import '../../../shared/widgets/beta_root_tab_viewport.dart';
import '../discovery_startup_cache.dart';

/// A visit is requested only by an explicit platform selection. Ordinary Tab
/// navigation retains its scroll state and never restarts this entrance.
class PlatformHomeVisit extends Notifier<int> {
  DiscoveryStartupCache? _lease;
  bool _pending = false;
  bool get pending => _pending;

  @override
  int build() {
    ref.onDispose(() => _lease?.dispose());
    return 0;
  }

  void begin(DiscoveryStartupCache lease) {
    _lease?.dispose();
    _lease = lease;
    _pending = true;
    state++;
  }

  void complete(int visit) {
    if (state != visit || !_pending) return;
    _pending = false;
    // Start optional network revalidation after the visible entrance. Disk
    // hydration and decoded cached frames have already reached the new page.
    _lease?.resume();
  }
}

final platformHomeVisitProvider = NotifierProvider<PlatformHomeVisit, int>(
  PlatformHomeVisit.new,
);

/// Presentation preparation is injectable separately from authentication and
/// navigation. Hosts exercise the real switch route without a device keystore
/// or disk/HTTP clients; production reuses its existing cache-only hydration.
final platformHomePreparationProvider =
    Provider<Future<DiscoveryStartupCache> Function(ProviderContainer)>(
      (ref) =>
          (container) =>
              DiscoveryStartupCache.prepare(container, includePlayback: false),
    );

/// One transform-driven entrance on the destination home. No opacity group or
/// screenshot surrounds live glass; hidden roots cannot start/finish the visit.
/// Its fresh PageStorage bucket also gives an explicit platform return the
/// requested default top, while Tab changes inside that visit stay retained.
class PlatformRootSurface extends ConsumerStatefulWidget {
  const PlatformRootSurface({
    required this.home,
    required this.child,
    super.key,
  });
  final bool home;
  final Widget child;
  @override
  ConsumerState<PlatformRootSurface> createState() =>
      _PlatformRootSurfaceState();
}

class _PlatformRootSurfaceState extends ConsumerState<PlatformRootSurface>
    with SingleTickerProviderStateMixin {
  final _storage = PageStorageBucket();
  late final _visit = ref.read(platformHomeVisitProvider);
  late final _visits = ref.read(platformHomeVisitProvider.notifier);
  late final _entering = widget.home && _visits.pending;
  late final _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 360),
    value: _entering ? 0 : 1,
  )..addStatusListener(_status);
  bool _scheduled = false;

  void _status(AnimationStatus status) {
    if (status == AnimationStatus.completed && mounted) {
      _visits.complete(_visit);
      setState(() {});
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_entering ||
        _motion.value == 1 ||
        _scheduled ||
        !BetaTabVisibility.of(context) ||
        ModalRoute.isCurrentOf(context) == false) {
      return;
    }
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted || !BetaTabVisibility.of(context)) return;
      if (MediaQuery.disableAnimationsOf(context)) {
        _motion.value = 1;
      } else {
        _motion.forward();
      }
    });
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PageStorage(
    bucket: _storage,
    child: BetaEntranceReadiness(
      ready: _motion.value == 1,
      child: ClipRect(
        child: SlideTransition(
          position: _motion.drive(
            Tween<Offset>(
              begin: const Offset(.06, 0),
              end: Offset.zero,
            ).chain(CurveTween(curve: Curves.easeInOutCubic)),
          ),
          child: RepaintBoundary(child: widget.child),
        ),
      ),
    ),
  );
}
