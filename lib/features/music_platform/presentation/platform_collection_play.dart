import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/models/track.dart';
import '../../../shared/widgets/beta_glass_controls.dart';
import '../../../shared/widgets/beta_page_route_observer.dart';
import '../../../shared/widgets/beta_root_tab_viewport.dart';
import '../../player/presentation/beta_playback_actions.dart';
import '../data/platform_explore.dart';
import '../data/platform_recommendations.dart';
import '../data/platform_ranking.dart';
import '../domain/platform_session.dart';
import '../music_platform_providers.dart';
import '../platform_backend_providers.dart';
import '../platform_explore_providers.dart';
import '../platform_recommendation_providers.dart';
import 'platform_feedback.dart';

/// One selection counter plus account checks coordinate card play requests. If the
/// user taps another card while this one is loading, only the newer selection
/// may replace playback. A widget disappearing also cancels publication.
final collectionPlayIntentProvider = Provider((ref) => CollectionPlayIntent());

class CollectionPlayIntent {
  int _generation = 0;
  int begin() => ++_generation;
  bool owns(int value) => value == _generation;
}

/// A page, account and deliberate selection own each pending playback. Route
/// observers permanently revoke a covered page, so returning to it cannot
/// revive an earlier request or attach FM to another queue.
class PlatformCoverPlayLease {
  PlatformCoverPlayLease(this.ref, this.context, this.isMounted)
    : _owner = ref.read(platformAccountProvider).value,
      _intent = ref.read(collectionPlayIntentProvider) {
    _generation = _intent.begin();
    _route = ModalRoute.of(context);
    _routes = BetaPageRouteObserver.maybeOf(context);
    _routes?.addListener(_checkRoute);
    _subscription = ref.listenManual(platformAccountProvider, (previous, next) {
      if (previous?.value?.ownerId != next.value?.ownerId ||
          previous?.value?.token != next.value?.token) {
        revoke();
      }
    });
  }
  final WidgetRef ref;
  final BuildContext context;
  final bool Function() isMounted;
  final PlatformSession? _owner;
  final CollectionPlayIntent _intent;
  late final int _generation;
  late final ModalRoute<dynamic>? _route;
  late final BetaPageRouteObserver? _routes;
  late final ProviderSubscription<AsyncValue<PlatformSession?>> _subscription;
  bool _revoked = false, _disposed = false;

  void _checkRoute() {
    if (!isMounted() || !(_routes?.isTopPage(_route) ?? true)) revoke();
  }

  /// ModalRoute.of registered the widget's dependency above. In a minimal host
  /// without the production route observer, loss of current-page visibility
  /// during loading must still revoke the read permanently.
  void observePageVisibility() {
    if (!isMounted()) return revoke();
    final visible = context
        .getInheritedWidgetOfExactType<BetaTabVisibility>()
        ?.visible;
    if (visible == false ||
        _route?.isActive == false ||
        (_routes != null && !_routes.isTopPage(_route)) ||
        (_routes == null && _route?.isCurrent == false)) {
      revoke();
    }
  }

  bool get current {
    if (!isMounted() || _revoked || !_intent.owns(_generation)) return false;
    final visible = context
        .getInheritedWidgetOfExactType<BetaTabVisibility>()
        ?.visible;
    if (visible == false ||
        _route?.isActive == false ||
        !(_routes?.isTopPage(_route) ?? (_route?.isCurrent ?? true))) {
      revoke();
      return false;
    }
    final now = ref.read(platformAccountProvider).value;
    return now?.ownerId == _owner?.ownerId && now?.token == _owner?.token;
  }

  void revoke() => _revoked = true;
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    revoke();
    _routes?.removeListener(_checkRoute);
    _subscription.close();
  }
}

Future<List<Track>> completePublicCollection(
  WidgetRef ref,
  PlatformExploreItem item,
  bool Function() isCurrent,
) async {
  if (!isCurrent()) return const [];
  final owner = ref.read(platformAccountProvider).value;
  if (owner == null) throw StateError('请先登录音乐平台');
  final repository = PlatformRankingRepository(
    api: ref.read(musicPlatformApiProvider),
    owner: owner,
    isCurrent: isCurrent,
    netease: owner.platform == MusicPlatform.netease
        ? ref.read(neteaseMusicRepositoryProvider)
        : null,
  );
  var edition = item;
  if (item.kind == PlatformExploreKind.rank &&
      owner.platform == MusicPlatform.kugou) {
    final info = await repository.info(item);
    if (!isCurrent()) return const [];
    edition = PlatformExploreItem(
      id: item.id,
      title: item.title,
      cover: item.cover,
      kind: item.kind,
      rankCid: info.period,
    );
  }
  return repository.complete(
    ref.read(platformExploreRepositoryProvider),
    edition,
  );
}

/// This is a sibling hit target above the cover. The enclosing card continues
/// to navigate, while this control reads the entire collection before playing.
class PlatformCollectionPlayButton extends StatelessWidget {
  const PlatformCollectionPlayButton({required this.item, super.key});
  final PlatformExploreItem item;
  @override
  Widget build(BuildContext context) => PlatformSelectionPlayButton(
    selectionKey: 'cover-play-${item.kind.name}-${item.id}',
    label: '播放${item.title}全部歌曲',
    load: (ref, current) => completePublicCollection(ref, item, current),
  );
}

/// Modes and fixed collections share the exact publication/confirmation fence.
/// FM plays a starting song and adopts the existing refill session; a finite
/// collection supplies every track and never substitutes a visible preview.
class PlatformSelectionPlayButton extends ConsumerStatefulWidget {
  const PlatformSelectionPlayButton({
    required this.selectionKey,
    required this.label,
    required this.load,
    this.stream,
    super.key,
  });
  final String selectionKey, label;
  final Future<List<Track>> Function(WidgetRef, bool Function()) load;
  final PlatformRecommendationKind? stream;
  @override
  ConsumerState<PlatformSelectionPlayButton> createState() =>
      _SelectionPlayState();
}

class _SelectionPlayState extends ConsumerState<PlatformSelectionPlayButton> {
  bool _loading = false;
  PlatformCoverPlayLease? _lease;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _lease?.observePageVisibility();
    if (!BetaTabVisibility.of(context)) _lease?.revoke();
  }

  @override
  void didUpdateWidget(covariant PlatformSelectionPlayButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectionKey != widget.selectionKey) {
      _lease?.revoke();
      _loading = false;
    }
  }

  Future<void> _play() async {
    if (_loading) return;
    final lease = PlatformCoverPlayLease(ref, context, () => mounted);
    _lease = lease;
    final stream = widget.stream;
    bool current() => lease.current;
    setState(() => _loading = true);
    try {
      // Capture before the first await; an account replacement disposes this
      // session rather than allowing the new account's session to be adopted.
      final session = stream == null
          ? null
          : ref.read(platformRecommendationSessionProvider);
      final tracks = await widget.load(ref, current);
      if (mounted && current() && tracks.isNotEmpty) {
        final played = await playBetaSelection(
          context,
          ref,
          tracks.first,
          playAll: stream == null ? tracks : null,
          stillCurrent: current,
        );
        if (played && current() && stream != null) {
          session!.adoptCurrent(stream, tracks.first);
        }
      }
    } catch (error) {
      if (mounted && current()) showPlatformFailure(context, error);
    } finally {
      lease.dispose();
      if (identical(_lease, lease)) {
        _lease = null;
        if (mounted) setState(() => _loading = false);
      }
    }
  }

  @override
  void dispose() {
    _lease?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PlatformCoverPlayControl(
    key: ValueKey(widget.selectionKey),
    label: widget.label,
    loading: _loading,
    onPressed: _loading ? null : () => unawaited(_play()),
  );
}

/// Keep a 48dp hit target while painting the original premium glass at 36dp.
/// The render transform excludes hit testing, so the surrounding 6dp margin
/// remains tappable and uses the same drag-cancellation and focus behavior.
class PlatformCoverPlayControl extends StatelessWidget {
  const PlatformCoverPlayControl({
    required this.label,
    required this.onPressed,
    this.loading = false,
    super.key,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  @override
  Widget build(BuildContext context) => Theme(
    data: Theme.of(context).copyWith(
      brightness: Brightness.dark,
      colorScheme: Theme.of(context).colorScheme.copyWith(
        brightness: Brightness.dark,
        onSurface: Colors.white,
        onSurfaceVariant: Colors.white70,
      ),
    ),
    child: SizedBox(
      width: 48,
      height: 48,
      child: Transform.scale(
        scale: .75,
        transformHitTests: false,
        child: BetaGlassButton(
          label: label,
          width: 48,
          height: 48,
          loading: loading,
          onPressed: onPressed,
          child: const Icon(
            Icons.play_arrow_rounded,
            color: Colors.white,
            size: 27,
          ),
        ),
      ),
    ),
  );
}
