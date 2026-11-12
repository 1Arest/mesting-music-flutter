import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/beta_edge_back.dart';
import '../../../shared/widgets/beta_back_state_changes.dart';
import '../../../shared/widgets/beta_root_tab_viewport.dart';
import 'qishui_player_navigation.dart';

/// The retained branch Navigator is not always represented by GoRouter's
/// imperative pop walker. Register inline lyric history on the enclosing music
/// shell route, which both the router and Android's callback can observe.
class QishuiLyricsNavigationHost extends InheritedWidget {
  const QishuiLyricsNavigationHost({
    required this.route,
    required super.child,
    super.key,
  });
  final ModalRoute<dynamic>? route;
  static ModalRoute<dynamic>? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<QishuiLyricsNavigationHost>()
      ?.route;
  @override
  bool updateShouldNotify(QishuiLyricsNavigationHost oldWidget) =>
      route != oldWidget.route;
}

/// Lyrics are a retained Music-tab view rather than a second player route.
/// A real local-history entry makes that view visible to Android's native Back
/// registration as well as GoRouter.canPop. A PopScope callback alone cannot
/// do that when the enclosing Navigator still contains only its root route.
class QishuiLyricsBackScope extends ConsumerStatefulWidget {
  const QishuiLyricsBackScope({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<QishuiLyricsBackScope> createState() =>
      _QishuiLyricsBackScopeState();
}

class _QishuiLyricsBackScopeState extends ConsumerState<QishuiLyricsBackScope> {
  ModalRoute<dynamic>? _route;
  LocalHistoryEntry? _entry;
  bool _visible = false;
  bool _scheduled = false;
  bool _removing = false;

  void _showCover() {
    if (mounted) ref.read(qishuiMusicLyricsProvider.notifier).showCover();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route =
        QishuiLyricsNavigationHost.maybeOf(context) ?? ModalRoute.of(context);
    final visible =
        BetaTabVisibility.of(context) &&
        (ModalRoute.isCurrentOf(context) ?? true);
    if (route != _route) _removeEntry();
    _route = route;
    _visible = visible;
    _schedule();
  }

  void _schedule() {
    if (_scheduled) return;
    _scheduled = true;
    // Local-history updates notify the owning route. Install after build so
    // selecting a retained tab never dirties an ancestor during its build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) return;
      if (!_visible || _route == null) {
        _removeEntry();
        return;
      }
      if (_entry != null) return;
      _entry = LocalHistoryEntry(
        impliesAppBarDismissal: false,
        onRemove: () {
          _entry = null;
          BetaBackStateChanges.shared.refresh();
          if (!_removing) _showCover();
        },
      );
      _route!.addLocalHistoryEntry(_entry!);
      // Local history mutates no GoRouter route match and an enclosing nested
      // Navigator can suppress its notification. Ask the coordinator to read
      // the live stack again; it never trusts this value as a global OR flag.
      NavigationNotification(canHandlePop: true).dispatch(context);
      BetaBackStateChanges.shared.refresh();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _removeEntry() {
    final hadEntry = _entry != null;
    _removing = true;
    _entry?.remove();
    _entry = null;
    _removing = false;
    if (hadEntry) BetaBackStateChanges.shared.refresh();
  }

  @override
  Widget build(BuildContext context) =>
      BetaEdgeBack(onBack: _showCover, child: widget.child);

  @override
  void dispose() {
    // Hiding lyrics, changing account or leaving the active tab removes only
    // this entry. It must not invoke a delayed callback against a new owner.
    _removeEntry();
    super.dispose();
  }
}
